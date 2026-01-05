# M4-Task01: Calendar Integration + Explicit News-Window Policy + Post-News Re-Engagement Gating

## Objective

This task implements Economic Calendar integration (CSV fallback) with explicit entry blocking during high-impact news windows and a post-news stabilization gate that prevents re-engagement until market conditions normalize. Per **finalspec.md Section 3.4 News Filter** and **prd.md Section Compliance**, the EA must:

1. Block all new entries during high-impact news windows (prebuffer + postbuffer)
2. Require explicit market stabilization (spread <= p60, volatility sigma <= p70 over configurable M1 bars) before **resuming new entries** after a news window closes
3. Log all news-related decisions for audit compliance

This addresses FundingPips rule compliance where trading during volatile news events is penalized or prohibited, and ensures the EA does not immediately jump back in when spreads/volatility remain elevated post-event.

---

## Functional Requirements

### Account Mode & Data Sources
- **FR-01**: Determine account mode via `NewsAccountMode` (AUTO uses real-account + balance threshold; non-master treated as Evaluation).
- **FR-02**: Primary data source: **MQL5 Economic Calendar**. CSV is **fallback** only.
- **FR-03**: Only **HIGH** impact events block trading; MEDIUM/LOW are logged but do not block.
- **FR-04**: Blocking window = `[event_timestamp_utc - max(prebuffer_min*60, NewsBufferS), event_timestamp_utc + max(postbuffer_min*60, NewsBufferS)]`.
- **FR-04a**: Calendar events are currency-based; block any configured symbol whose base or quote currency matches the event currency (derive via `SYMBOL_CURRENCY_BASE` and `SYMBOL_CURRENCY_PROFIT`).
- **FR-04b**: Ensure all configured symbols are `SymbolSelect`-ed on init for currency resolution; if base/quote is empty or selection fails, log once and fall back to normalized-symbol matching.

### News Window Policy (blocked/queued/allowed)
- **FR-05**: Block **new entries** (market + pending) for affected symbols/legs while in the window.
- **FR-06**: Block **non-protective modifications** inside the window (PositionModify/OrderModify, partial closes, delete/replace), except allowed risk-reducing actions.
- **FR-07**: **Queue** trailing/SL/TP optimizations during the window; apply after the window if still valid and not inside a subsequent window; drop stale items after TTL.
- **FR-08**: **Allowed exceptions** inside window: protective exits (SL/TP/kill-switch/margin), OCO sibling cancel to reduce risk, replication pair-protect close.
- **FR-09**: XAUEUR inherits blocks from both legs (XAUUSD and EURUSD); use base/quote currency matching for all configured symbols.
- **FR-10**: Evaluation mode still applies the internal `NewsBufferS` window for safety and logs as INTERNAL_BUFFER; Master mode enforces the provider window (default +/-300s).

### Post-News Stabilization Gate
- **FR-11**: After `News_IsBlocked()` transitions from `true` -> `false`, enter **stabilization phase**.
- **FR-12**: Stabilization requires `StabilizationBars` consecutive **M1** bars where spread <= p60 and volatility <= p70, computed from rolling per-bar history.
- **FR-13**: Any threshold violation resets the consecutive bar counter.
- **FR-14**: Stabilization blocks **new entries only**; it does **not** block protective exits or queued modifications once the news window has cleared.
- **FR-15**: Stabilization timeout: if not achieved within `StabilizationTimeoutMin`, force-clear and log warning.

### Data Availability & Fallback
- **FR-16**: If calendar query fails/unavailable, fall back to CSV.
- **FR-16a**: CSV schema remains `timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min`.
- **FR-17**: If both calendar and CSV are unavailable/stale, set `news_data_ok=false` and log `NEWS_DATA_UNAVAILABLE`.
  - **Master**: fail-closed for new entries and non-protective modifications.
  - **Evaluation**: fail-open for new entries and modifications (log warning).

### Audit Logging
- **FR-18**: Log `NEWS_BLOCK_START` when entering news window.
- **FR-19**: Log `NEWS_BLOCK_END` when news window closes (before stabilization).
- **FR-20**: Log `NEWS_STABILIZING` each M1 bar during stabilization with spread/vol metrics.
- **FR-21**: Log `NEWS_STABLE` when stabilization completes and trading resumes.
- **FR-22**: Log `NEWS_STABILIZATION_TIMEOUT` if stabilization times out.
- **FR-23**: Log `NEWS_DATA_UNAVAILABLE` when no usable calendar/CSV data is available.
- **FR-24**: Log `NEWS_SOURCE_FALLBACK` when calendar is unavailable and CSV is used.
- **FR-25**: Include stabilization status in `news_window_state` (e.g., `STABILIZING` or `POST_NEWS_STABILIZING`) for audit consistency.
- **FR-26**: Log `NEWS_SYMBOL_CURRENCY_MISSING` once per symbol when base/quote currency cannot be resolved and fallback matching is used.
- **FR-27**: Log `NEWS_SYMBOL_SELECT_FAIL` once per symbol when `SymbolSelect` fails during init.

---

## Files to Modify

| File | Rationale |
|------|-----------|
| `MQL5/Include/RPEA/news.mqh` | Economic calendar integration + CSV fallback, explicit policy helpers, stabilization state machine |
| `MQL5/Include/RPEA/config.mqh` | Add new inputs: stabilization thresholds + calendar lookahead/back windows |
| `MQL5/Include/RPEA/order_engine.mqh` | Gate **entries** on `News_IsEntryBlocked()` (blocked or stabilizing) and report stabilization in `news_window_state` |
| `MQL5/Include/RPEA/queue.mqh` | Ensure queued modifications apply after window even if stabilizing; enforce news-window policy |
| `MQL5/Include/RPEA/trailing.mqh` | Use `News_IsModifyBlocked()` when deciding to queue/apply trailing updates |
| `MQL5/Include/RPEA/breakeven.mqh` | Use `News_IsModifyBlocked()` when deciding to queue/apply breakeven updates |
| `MQL5/Include/RPEA/logging.mqh` | Add `NEWS_BLOCK_START/END`, stabilization, and data-unavailable events |
| `MQL5/Include/RPEA/state.mqh` | Add stabilization + per-bar history structures |
| `MQL5/Experts/FundingPips/RPEA.mq5` | Wire new inputs, init news tracking, call M1 bar updater (no static arrays) |
| `Tests/RPEA/test_news_policy.mqh` | New tests for calendar fallback, news policy, stabilization |
| `Tests/RPEA/run_automated_tests_ea.mq5` | Include and wire new test suite |

---

## Data/State Changes

### New Inputs (config.mqh / RPEA.mq5)

```cpp
input int    StabilizationBars          = 3;      // M1 bars required for stabilization
input int    StabilizationTimeoutMin    = 15;     // Max minutes to wait for stabilization
input double SpreadStabilizationPct     = 60.0;   // Percentile threshold for spread (p60)
input double VolatilityStabilizationPct = 70.0;   // Percentile threshold for M1 ATR (p70)
input int    StabilizationLookbackBars  = 60;     // Bars for percentile calculation
input int    NewsCalendarLookbackHours  = 6;      // Calendar lookback window
input int    NewsCalendarLookaheadHours = 24;     // Calendar lookahead window
input int    NewsAccountMode            = 0;      // 0=AUTO, 1=MASTER, 2=EVALUATION
```

### New Structs (state.mqh)

```cpp
struct NewsStabilizationState
{
   string   symbol;
   bool     in_stabilization;        // Currently in stabilization phase
   datetime stabilization_start;     // When stabilization phase began
   int      stable_bar_count;        // Consecutive stable M1 bars
   double   spread_p60;              // Current session spread p60 threshold
   double   vol_p70;                 // Current session M1 ATR p70 threshold
   datetime last_bar_time;           // Last M1 bar processed
   double   spread_history[];        // Rolling M1 spreads (for percentile)
   double   vol_history[];           // Rolling M1 vol proxy (for percentile)
   int      history_count;           // Count of samples in history
   int      history_index;           // Ring buffer index
};
```

### NewsEvent Additions (news.mqh)

```cpp
struct NewsEvent
{
   // Existing fields...
   bool     is_currency; // true when symbol represents event currency (calendar)
};
```

### New Module State (news.mqh)

```cpp
NewsStabilizationState g_news_stab_state[];  // Per-symbol stabilization state
bool                   g_news_stab_enabled;   // Master stabilization enable flag
int                    g_news_stab_count;     // Number of tracked symbols
bool                   g_news_data_ok;        // Calendar/CSV data availability
int                    g_news_source;         // 0=NONE, 1=CALENDAR, 2=CSV
bool                   g_news_prev_blocked[]; // Track transitions for start/end logs
bool                   g_news_calendar_override_active; // Test override active (RPEA_TEST_RUNNER)
NewsEvent              g_news_calendar_override_events[]; // Test calendar events
int                    g_news_calendar_override_count;
string                 g_news_missing_currency_symbols[]; // Log-once tracking for missing base/quote
int                    g_news_missing_currency_count;
string                 g_news_select_fail_symbols[]; // Log-once tracking for SymbolSelect failures
int                    g_news_select_fail_count;
```

### New Log Event Types (logging.mqh)

```cpp
// Add to existing event type handling
"NEWS_BLOCK_START"           // Entry blocked due to news window
"NEWS_BLOCK_END"             // News window closed, entering stabilization
"NEWS_STABILIZING"           // M1 bar during stabilization (with metrics)
"NEWS_STABLE"                // Stabilization complete, trading resumed
"NEWS_STABILIZATION_TIMEOUT" // Stabilization timed out
"NEWS_SYMBOL_CURRENCY_MISSING" // Missing base/quote currency for symbol
"NEWS_SYMBOL_SELECT_FAIL" // Failed to SymbolSelect configured symbol
```

---

## Detailed Implementation Steps

### Step 1: Extend config.mqh with New Defaults

```cpp
// In config.mqh, add after existing news defaults:
#ifndef DEFAULT_StabilizationBars
#define DEFAULT_StabilizationBars          3
#endif
#ifndef DEFAULT_StabilizationTimeoutMin
#define DEFAULT_StabilizationTimeoutMin    15
#endif
#ifndef DEFAULT_SpreadStabilizationPct
#define DEFAULT_SpreadStabilizationPct     60.0
#endif
#ifndef DEFAULT_VolatilityStabilizationPct
#define DEFAULT_VolatilityStabilizationPct 70.0
#endif
#ifndef DEFAULT_StabilizationLookbackBars
#define DEFAULT_StabilizationLookbackBars  60
#endif
#ifndef DEFAULT_NewsCalendarLookbackHours
#define DEFAULT_NewsCalendarLookbackHours  6
#endif
#ifndef DEFAULT_NewsCalendarLookaheadHours
#define DEFAULT_NewsCalendarLookaheadHours 24
#endif
#ifndef DEFAULT_NewsAccountMode
#define DEFAULT_NewsAccountMode           0
#endif
```

### Step 2: Add Stabilization State to state.mqh

```cpp
// Add struct definition after existing state structs
struct NewsStabilizationState
{
   string   symbol;
   bool     in_stabilization;
   datetime stabilization_start;
   int      stable_bar_count;
   double   spread_p60;
   double   vol_p70;
   datetime last_bar_time;
   
   void Reset()
   {
      in_stabilization = false;
      stabilization_start = 0;
      stable_bar_count = 0;
      spread_p60 = 0.0;
      vol_p70 = 0.0;
      last_bar_time = 0;
   }
};
```

### Step 3: Implement Stabilization Logic in news.mqh

```cpp
// Module-level state
NewsStabilizationState g_news_stab_state[];
int                    g_news_stab_count = 0;
bool                   g_news_stab_enabled = true;

// Calendar integration (primary) + CSV fallback
bool News_LoadCalendarEvents(const datetime from_utc,
                             const datetime to_utc,
                             NewsEvent &out_events[])
{
#ifdef RPEA_TEST_RUNNER
   if(g_news_calendar_override_active)
   {
      ArrayResize(out_events, g_news_calendar_override_count);
      for(int i = 0; i < g_news_calendar_override_count; i++)
         out_events[i] = g_news_calendar_override_events[i];
      return (g_news_calendar_override_count > 0);
   }
#endif
   // Use CalendarValueHistory + CalendarEventById to fetch HIGH-impact events
   // Populate NewsEvent.symbol = event currency code and set is_currency = true
   // Return true on success; false on API failure/unavailable
}

bool News_LoadEvents()
{
   const datetime now_utc = News_GetNowUtc();
   const datetime from_utc = now_utc - (NewsCalendarLookbackHours * 3600);
   const datetime to_utc = now_utc + (NewsCalendarLookaheadHours * 3600);

   g_news_data_ok = News_LoadCalendarEvents(from_utc, to_utc, g_news_events);
   g_news_source = (g_news_data_ok ? 1 : 0); // 1=CALENDAR

   if(!g_news_data_ok)
   {
      g_news_data_ok = News_LoadCsvFallback();
      g_news_source = (g_news_data_ok ? 2 : 0); // 2=CSV
   }

   if(!g_news_data_ok)
      LogAuditRow("NEWS_DATA_UNAVAILABLE", "News", LOG_WARN, "No calendar or CSV data", "{}");
   else if(g_news_source == 2)
      LogAuditRow("NEWS_SOURCE_FALLBACK", "News", LOG_INFO, "Calendar unavailable, using CSV", "{}");

   return g_news_data_ok;
}

#ifdef RPEA_TEST_RUNNER
void News_Test_SetCalendarEvents(const NewsEvent &events[], const int count)
{
   g_news_calendar_override_active = true;
   g_news_calendar_override_count = count;
   ArrayResize(g_news_calendar_override_events, count);
   for(int i = 0; i < count; i++)
      g_news_calendar_override_events[i] = events[i];
   News_ForceReload();
}

void News_Test_ClearCalendarEvents()
{
   g_news_calendar_override_active = false;
   g_news_calendar_override_count = 0;
   ArrayResize(g_news_calendar_override_events, 0);
   News_ForceReload();
}
#endif

// Replace News_ReloadIfChanged() to call News_LoadEvents() and cache results
// (calendar + CSV fallback) with a short refresh interval (e.g., 60s).
// Ensure CSV loader sets is_currency=false for CSV events.

// Initialize stabilization tracking for symbols
void News_InitStabilization(const string &symbols[], const int count)
{
   ArrayResize(g_news_stab_state, count);
   g_news_stab_count = count;
   for(int i = 0; i < count; i++)
   {
      g_news_stab_state[i].symbol = symbols[i];
      g_news_stab_state[i].Reset();
   }
}

int News_BuildStabilizationSymbols(const string &symbols[],
                                   const int count,
                                   string &out_symbols[])
{
   ArrayResize(out_symbols, 0);
   bool has_xaueur = false;
   bool has_xauusd = false;
   bool has_eurusd = false;
   for(int i = 0; i < count; i++)
   {
      string sym = News_NormalizeSymbol(symbols[i]);
      if(sym == "") continue;
      int idx = ArraySize(out_symbols);
      ArrayResize(out_symbols, idx + 1);
      out_symbols[idx] = sym;
      if(sym == "XAUEUR") has_xaueur = true;
      if(sym == "XAUUSD") has_xauusd = true;
      if(sym == "EURUSD") has_eurusd = true;
   }
   if(has_xaueur && !has_xauusd)
   {
      int idx = ArraySize(out_symbols);
      ArrayResize(out_symbols, idx + 1);
      out_symbols[idx] = "XAUUSD";
   }
   if(has_xaueur && !has_eurusd)
   {
      int idx = ArraySize(out_symbols);
      ArrayResize(out_symbols, idx + 1);
      out_symbols[idx] = "EURUSD";
   }
   return ArraySize(out_symbols);
}

// Find stabilization state index for symbol
int News_FindStabIndex(const string symbol)
{
   string normalized = News_NormalizeSymbol(symbol);
   for(int i = 0; i < g_news_stab_count; i++)
   {
      if(g_news_stab_state[i].symbol == normalized)
         return i;
   }
   return -1;
}

// Check if symbol is in stabilization phase
bool News_IsStabilizing(const string symbol)
{
   if(!g_news_stab_enabled)
      return false;

   string normalized = News_NormalizeSymbol(symbol);
   if(normalized == "XAUEUR")
      return (News_IsStabilizing("XAUUSD") || News_IsStabilizing("EURUSD"));

   int idx = News_FindStabIndex(symbol);
   if(idx < 0)
      return false;
      
   return g_news_stab_state[idx].in_stabilization;
}

// Determine account mode for news policy
bool News_IsMasterMode()
{
   if(NewsAccountMode == 1)
      return true;
   if(NewsAccountMode == 2)
      return false;

   // AUTO: mirror existing master detection (real account + balance threshold)
   long trade_mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(trade_mode != ACCOUNT_TRADE_MODE_REAL)
      return false;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return (MathIsValidNumber(balance) && balance >= 25000.0);
}

// Calculate percentile from array
double News_CalcPercentile(const double &values[], const int count, const double pct)
{
   if(count <= 0)
      return 0.0;
      
   double sorted[];
   ArrayResize(sorted, count);
   ArrayCopy(sorted, values, 0, 0, count);
   ArraySort(sorted);
   
   int idx = (int)MathFloor((pct / 100.0) * (count - 1));
   idx = MathMax(0, MathMin(idx, count - 1));
   return sorted[idx];
}

// Update percentile thresholds from recent M1 history
void News_UpdateStabilizationThresholds(const int stab_idx)
{
   NewsStabilizationState &state = g_news_stab_state[stab_idx];
   if(state.history_count <= 0)
      return;

   state.spread_p60 = News_CalcPercentile(state.spread_history,
                                          state.history_count,
                                          SpreadStabilizationPct);
   state.vol_p70 = News_CalcPercentile(state.vol_history,
                                       state.history_count,
                                       VolatilityStabilizationPct);
}

// Record per-bar metrics and update stabilization state
void News_RecordM1Metrics(const int idx, const string symbol, const datetime bar_time)
{
   NewsStabilizationState &state = g_news_stab_state[idx];
   double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
   double high = iHigh(symbol, PERIOD_M1, 1);
   double low = iLow(symbol, PERIOD_M1, 1);
   double vol = high - low;

   if(ArraySize(state.spread_history) < StabilizationLookbackBars)
   {
      ArrayResize(state.spread_history, StabilizationLookbackBars);
      ArrayResize(state.vol_history, StabilizationLookbackBars);
   }

   state.spread_history[state.history_index] = spread;
   state.vol_history[state.history_index] = vol;
   state.history_index = (state.history_index + 1) % StabilizationLookbackBars;
   state.history_count = MathMin(state.history_count + 1, StabilizationLookbackBars);

   News_UpdateStabilizationThresholds(idx);
}

// Called on each M1 bar close to update stabilization state
void News_OnM1Bar(const string symbol, const datetime bar_time)
{
   int idx = News_FindStabIndex(symbol);
   if(idx < 0)
      return;

   NewsStabilizationState &state = g_news_stab_state[idx];

   // Prevent duplicate processing of same bar
   if(bar_time <= state.last_bar_time)
      return;
   state.last_bar_time = bar_time;

   News_RecordM1Metrics(idx, symbol, bar_time);

   if(!state.in_stabilization)
      return;
   
   // Check timeout
   datetime now = TimeCurrent();
   int elapsed_min = (int)((now - state.stabilization_start) / 60);
   if(elapsed_min >= StabilizationTimeoutMin)
   {
      LogAuditRow("NEWS_STABILIZATION_TIMEOUT", symbol, 0, 
                  StringFormat("Timeout after %d min", elapsed_min), "{}");
      state.Reset();
      return;
   }
   
   // Get current metrics
   double current_spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * 
                           SymbolInfoDouble(symbol, SYMBOL_POINT);
   double current_vol = iHigh(symbol, PERIOD_M1, 1) - iLow(symbol, PERIOD_M1, 1);
   
   // Check if within thresholds
   bool spread_ok = (current_spread <= state.spread_p60);
   bool vol_ok = (current_vol <= state.vol_p70);
   
   string metrics = StringFormat("{\"spread\":%.5f,\"spread_p60\":%.5f,\"vol\":%.5f,\"vol_p70\":%.5f,\"bars\":%d}",
                                  current_spread, state.spread_p60, current_vol, state.vol_p70,
                                  state.stable_bar_count);
   
   if(spread_ok && vol_ok)
   {
      state.stable_bar_count++;
      LogAuditRow("NEWS_STABILIZING", symbol, 1, 
                  StringFormat("Bar %d/%d stable", state.stable_bar_count, StabilizationBars),
                  metrics);
      
      if(state.stable_bar_count >= StabilizationBars)
      {
         LogAuditRow("NEWS_STABLE", symbol, 1, "Stabilization complete", metrics);
         state.Reset();
      }
   }
   else
   {
      // Reset counter on violation
      state.stable_bar_count = 0;
      LogAuditRow("NEWS_STABILIZING", symbol, 0, 
                  StringFormat("Reset: spread_ok=%d vol_ok=%d", spread_ok, vol_ok),
                  metrics);
   }
}

// Enter stabilization phase for symbol
void News_EnterStabilization(const string symbol)
{
   int idx = News_FindStabIndex(symbol);
   if(idx < 0)
      return;
      
   g_news_stab_state[idx].in_stabilization = true;
   g_news_stab_state[idx].stabilization_start = TimeCurrent();
   g_news_stab_state[idx].stable_bar_count = 0;
   g_news_stab_state[idx].last_bar_time = 0;
   
   // Compute thresholds from recent history
   News_UpdateStabilizationThresholds(idx);
   
   LogAuditRow("NEWS_BLOCK_END", symbol, 1, "Entering stabilization phase",
               StringFormat("{\"spread_p60\":%.5f,\"vol_p70\":%.5f}",
                           g_news_stab_state[idx].spread_p60,
                           g_news_stab_state[idx].vol_p70));
}

// Entry gate: blocked by news OR in stabilization (entries only)
bool News_IsEntryBlocked(const string symbol)
{
   if(!News_LoadEvents() || !g_news_data_ok)
      return News_IsMasterMode(); // fail-closed for Master, open for Evaluation
   return News_IsBlocked(symbol) || News_IsStabilizing(symbol);
}

// Modification gate: blocked during news window; fail-closed for Master when data unavailable
bool News_IsModifyBlocked(const string symbol)
{
   if(!News_LoadEvents() || !g_news_data_ok)
      return News_IsMasterMode(); // fail-closed for Master, open for Evaluation
   return News_IsBlocked(symbol);
}
```

### Step 4: Update news.mqh Blocking Logic

Modify existing `News_IsBlocked()` to track state transitions:

```cpp
// Add tracking for previous blocked state
bool g_news_prev_blocked[];

void News_UpdateBlockState(const string symbol)
{
   int idx = News_FindStabIndex(symbol);
   if(idx < 0)
      return;
      
   bool was_blocked = (idx < ArraySize(g_news_prev_blocked)) ? g_news_prev_blocked[idx] : false;
bool now_blocked = News_IsBlocked_Internal(symbol);  // Rename existing function
// News_IsBlocked_Internal should return false when news_data_ok == false
   
   // Detect transition: not blocked -> blocked
   if(!was_blocked && now_blocked)
   {
      LogAuditRow("NEWS_BLOCK_START", symbol, 1, "News window active", "{}");
      // If a new window starts while stabilizing, reset stabilization
      g_news_stab_state[idx].Reset();
   }

   // Detect transition: blocked -> not blocked
   if(was_blocked && !now_blocked)
   {
      News_EnterStabilization(symbol);
   }
   
   // Update tracking
   if(idx >= ArraySize(g_news_prev_blocked))
      ArrayResize(g_news_prev_blocked, idx + 1);
   g_news_prev_blocked[idx] = now_blocked;
}
```

### Step 4a: Currency-Based Blocking (news.mqh)

```cpp
bool News_SymbolMatchesEvent(const string symbol, const NewsEvent &event)
{
   string normalized = News_NormalizeSymbol(symbol);
   if(event.is_currency)
   {
      string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
      string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
      if(StringLen(base) == 0 || StringLen(quote) == 0)
      {
         News_LogMissingCurrencyOnce(normalized);
         return (normalized == event.symbol);
      }
      return (base == event.symbol || quote == event.symbol);
   }
   return (normalized == event.symbol);
}

void News_LogMissingCurrencyOnce(const string symbol)
{
   for(int i = 0; i < g_news_missing_currency_count; i++)
   {
      if(g_news_missing_currency_symbols[i] == symbol)
         return;
   }
   int idx = ArraySize(g_news_missing_currency_symbols);
   ArrayResize(g_news_missing_currency_symbols, idx + 1);
   g_news_missing_currency_symbols[idx] = symbol;
   g_news_missing_currency_count = idx + 1;
   LogAuditRow("NEWS_SYMBOL_CURRENCY_MISSING", symbol, LOG_WARN,
               "Missing base/quote for currency blocking; fallback to symbol match", "{}");
}

void News_LogSymbolSelectFailOnce(const string symbol)
{
   for(int i = 0; i < g_news_select_fail_count; i++)
   {
      if(g_news_select_fail_symbols[i] == symbol)
         return;
   }
   int idx = ArraySize(g_news_select_fail_symbols);
   ArrayResize(g_news_select_fail_symbols, idx + 1);
   g_news_select_fail_symbols[idx] = symbol;
   g_news_select_fail_count = idx + 1;
   LogAuditRow("NEWS_SYMBOL_SELECT_FAIL", symbol, LOG_WARN,
               "SymbolSelect failed; currency match may be incomplete", "{}");
}

bool News_EnsureSymbolSelected(const string symbol)
{
   if(SymbolSelect(symbol, true))
      return true;
   News_LogSymbolSelectFailOnce(symbol);
   return false;
}

bool News_IsBlocked_Internal(const string symbol)
{
   if(StringLen(symbol) == 0)
      return false;
   if(!News_LoadEvents())
      return false;
   const datetime now_utc = News_GetNowUtc();
   for(int i = 0; i < g_news_event_count; i++)
   {
      const NewsEvent event = g_news_events[i];
      if(event.impact != "HIGH")
         continue;
      if(now_utc < event.block_start_utc || now_utc > event.block_end_utc)
         continue;
      if(News_SymbolMatchesEvent(symbol, event))
         return true;
   }
   return false;
}
```

### Step 5: Gate Order Engine on Stabilization

In `order_engine.mqh`, modify `OrderEngine_SendIntent()`:

```cpp
IntentResult OrderEngine_SendIntent(const TradeIntent &intent)
{
   IntentResult result;
   result.success = false;
   result.order_ticket = 0;
   result.position_ticket = 0;
   
   // Existing validation...
   
   // News blocking gate for new entries (news window or stabilization)
   if(News_IsEntryBlocked(intent.symbol))
   {
      result.error_code = OE_ERR_NEWS_BLOCKED;
      result.error_message = News_IsStabilizing(intent.symbol)
                             ? "Post-news stabilization in progress"
                             : "News window active";
      LogAuditRow("INTENT_REJECTED", intent.symbol, 0, result.error_message, "{}");
      return result;
   }
   
   // Continue with existing logic...
}
```

### Step 5b: Apply News Policy in Queue Manager

- In `queue.mqh`, `trailing.mqh`, `breakeven.mqh`, and `OrderEngine_RequestModifySLTP`, replace `News_IsBlocked()` checks with `News_IsModifyBlocked()` for SL/TP/trailing actions.
- Ensure queued modifications apply **after the news window clears**, even if stabilization is still active.
- Keep protective exceptions unchanged (risk-reducing closes, kill-switch actions).

### Step 5c: Include Stabilization in News Gate (news.mqh / order_engine.mqh)

Add a detailed window state helper and use it inside `OrderEngine::EvaluateNewsGate` so audit logs include stabilization:

```cpp
string News_GetWindowStateDetailed(const string symbol, const bool is_protective)
{
   News_LoadEvents();
   if(!g_news_data_ok && News_IsMasterMode())
      return "DATA_UNAVAILABLE_BLOCK";
   if(News_IsBlocked(symbol))
      return (is_protective ? "PROTECTIVE_ONLY" : "BLOCKED");
   if(News_IsStabilizing(symbol))
      return "STABILIZING";
   return "CLEAR";
}
```

Update `OrderEngine::EvaluateNewsGate` to:
- Use `News_IsEntryBlocked(signal_symbol)` for gating (entries) and allow protective exits.
- Set `out_detail` via `News_GetWindowStateDetailed` (or leg-specific detail for XAUEUR; if either leg is stabilizing, report `STABILIZING`).

Update any audit uses of `News_GetWindowState` (queue/trailing) to include stabilization, either by routing it through `News_GetWindowStateDetailed` or by extending `News_GetWindowState` directly.

### Step 6: Wire into RPEA.mq5

```cpp
// Add inputs after existing news inputs
input int    StabilizationBars          = DEFAULT_StabilizationBars;
input int    StabilizationTimeoutMin    = DEFAULT_StabilizationTimeoutMin;
input double SpreadStabilizationPct     = DEFAULT_SpreadStabilizationPct;
input double VolatilityStabilizationPct = DEFAULT_VolatilityStabilizationPct;
input int    StabilizationLookbackBars  = DEFAULT_StabilizationLookbackBars;
input int    NewsCalendarLookbackHours  = DEFAULT_NewsCalendarLookbackHours;
input int    NewsCalendarLookaheadHours = DEFAULT_NewsCalendarLookaheadHours;
input int    NewsAccountMode            = DEFAULT_NewsAccountMode;

// In OnInit(), after symbol parsing:
// Ensure all configured symbols are selected for currency resolution.
for(int i = 0; i < g_ctx.symbols_count; i++)
{
   string sym = g_ctx.symbols[i];
   if(sym != "")
      News_EnsureSymbolSelected(sym);
}
// If XAUEUR is configured, ensure stabilization tracking includes XAUUSD and EURUSD.
string news_symbols[];
int news_count = News_BuildStabilizationSymbols(g_ctx.symbols, g_ctx.symbols_count, news_symbols);
for(int i = 0; i < news_count; i++)
   News_EnsureSymbolSelected(news_symbols[i]);
News_InitStabilization(news_symbols, news_count);
// Prime news data so g_news_data_ok is up to date for entry/modify gates.
News_LoadEvents();

// In OnTimer(), add M1 bar detection and stabilization update:
// Rely on News_OnM1Bar() last_bar_time guard; avoid static arrays.
for(int i = 0; i < g_ctx.symbols_count; i++)
{
   string sym = g_ctx.symbols[i];
   datetime current_bar = iTime(sym, PERIOD_M1, 0);
   News_UpdateBlockState(sym);
   News_OnM1Bar(sym, current_bar);
}
```

### Step 7: Add Log Event Types to logging.mqh

```cpp
// In LogAuditRow() event type validation/handling, ensure these are recognized:
// NEWS_BLOCK_START, NEWS_BLOCK_END, NEWS_STABILIZING, NEWS_STABLE, NEWS_STABILIZATION_TIMEOUT,
// NEWS_DATA_UNAVAILABLE, NEWS_SOURCE_FALLBACK
// No code changes needed if using string-based event types
```

---

## Tests

### New Test File: `Tests/RPEA/test_news_policy.mqh`

```cpp
#ifndef TEST_NEWS_POLICY_MQH
#define TEST_NEWS_POLICY_MQH

#include <RPEA/news.mqh>

// Test: Calendar is primary source when available
bool TestNewsPolicy_CalendarPrimary()
{
   // Setup: Inject calendar events via News_Test_SetCalendarEvents, ensure CSV ignored
   // Assert: g_news_source == CALENDAR and blocking uses calendar events
}

// Test: CSV fallback used when calendar unavailable
bool TestNewsPolicy_FallbackToCsv()
{
   // Setup: Clear calendar override and force calendar failure, provide CSV
   // Assert: g_news_source == CSV and blocking uses CSV events
}

// Test: Currency-based blocking applies to all configured symbols
bool TestNewsPolicy_CurrencyBlock()
{
   // Setup: Calendar event with currency=USD
   // Assert: Any configured symbol with base/quote USD is blocked
}

// Test: Data unavailable behavior differs by account mode
bool TestNewsPolicy_DataUnavailableModes()
{
   // Setup: Calendar + CSV fail
   // Assert: Master => News_IsEntryBlocked true; News_IsModifyBlocked true
   // Assert: Evaluation => News_IsEntryBlocked false; News_IsModifyBlocked false with warning log
}

// Test: Stabilization phase entered after news window closes
bool TestNewsStab_EntersStabilizationAfterBlock()
{
   // Setup: Create news event that just ended
   // Assert: News_IsStabilizing() returns true
   // Assert: NEWS_BLOCK_END logged
}

// Test: Stabilization completes after N stable bars
bool TestNewsStab_CompletesAfterStableBars()
{
   // Setup: Enter stabilization, mock N bars within thresholds
   // Assert: After StabilizationBars, News_IsStabilizing() returns false
   // Assert: NEWS_STABLE logged
}

// Test: news_window_state reports STABILIZING during stabilization
bool TestNewsStab_WindowStateStabilizing()
{
   // Setup: Calendar override with event; set time inside window -> blocked
   // Advance time just after window; call News_UpdateBlockState() to enter stabilization
   // Assert: News_GetWindowStateDetailed(symbol, false) == "STABILIZING"
}

// Test: Counter resets on threshold violation
bool TestNewsStab_ResetsOnViolation()
{
   // Setup: Enter stabilization with 2 stable bars
   // Mock: 3rd bar exceeds spread/vol threshold
   // Assert: Counter reset to 0
   // Assert: NEWS_STABILIZING logged with reset reason
}

// Test: Timeout forces stabilization exit
bool TestNewsStab_TimeoutExits()
{
   // Setup: Enter stabilization
   // Mock: Time elapsed > StabilizationTimeoutMin
   // Assert: News_IsStabilizing() returns false
   // Assert: NEWS_STABILIZATION_TIMEOUT logged
}

// Test: Percentile calculation accuracy
bool TestNewsStab_PercentileCalculation()
{
   // Setup: Known array of values
   // Assert: p60 and p70 calculated correctly
}

// Test: XAUEUR inherits stabilization from both legs
bool TestNewsStab_XAUEURInheritsBothLegs()
{
   // Setup: XAUUSD in stabilization, EURUSD not
   // Assert: XAUEUR reports stabilizing
}

// Test: Order engine rejects new entries during stabilization
bool TestNewsStab_OrderEngineGate()
{
   // Setup: Symbol in stabilization
   // Call: OrderEngine_SendIntent()
   // Assert: Returns OE_ERR_NEWS_BLOCKED
}

// Test: Queue apply not blocked by stabilization once window cleared
bool TestNewsPolicy_QueueApplyDuringStabilization()
{
   // Setup: Queue SL/TP during news, exit window, remain stabilizing
   // Assert: Queue apply proceeds (News_IsModifyBlocked == false)
}

bool TestNewsPolicy_RunAll()
{
   bool ok = true;
   ok &= TestNewsPolicy_CalendarPrimary();
   ok &= TestNewsPolicy_FallbackToCsv();
   ok &= TestNewsPolicy_CurrencyBlock();
   ok &= TestNewsPolicy_DataUnavailableModes();
   ok &= TestNewsStab_EntersStabilizationAfterBlock();
   ok &= TestNewsStab_CompletesAfterStableBars();
   ok &= TestNewsStab_WindowStateStabilizing();
   ok &= TestNewsStab_ResetsOnViolation();
   ok &= TestNewsStab_TimeoutExits();
   ok &= TestNewsStab_PercentileCalculation();
   ok &= TestNewsStab_XAUEURInheritsBothLegs();
   ok &= TestNewsStab_OrderEngineGate();
   ok &= TestNewsPolicy_QueueApplyDuringStabilization();
   return ok;
}

#endif // TEST_NEWS_POLICY_MQH
```

### Wire into Test Runner

In `Tests/RPEA/run_automated_tests_ea.mq5`:

```cpp
// Add include
#include "test_news_policy.mqh"

// In RunAllTests():
int suiteM4T1 = g_test_reporter.BeginSuite("M4Task1_News_Policy");
bool m4t1_result = TestNewsPolicy_RunAll();
g_test_reporter.RecordTest(suiteM4T1, "TestNewsPolicy_RunAll", m4t1_result,
                            m4t1_result ? "News policy tests passed" : "News policy tests failed");
g_test_reporter.EndSuite(suiteM4T1);
```

### Test Fixtures

Create `Tests/RPEA/fixtures/news/stabilization_test.csv`:
```csv
timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min
2024-06-01T14:30:00Z,XAUUSD,High,ForexFactory,NFP,5,5
2024-06-01T15:00:00Z,EURUSD,High,ECB,Rate Decision,5,5
```

---

## Logging/Telemetry

| Event Type | Symbol | OK | Description | Extra JSON |
|------------|--------|----|-----------|----|
| `NEWS_BLOCK_START` | XAUUSD | 0 | "NFP window active" | `{"event":"NFP","ends_utc":"..."}` |
| `NEWS_BLOCK_END` | XAUUSD | 1 | "Entering stabilization phase" | `{"spread_p60":0.00025,"vol_p70":0.0015}` |
| `NEWS_STABILIZING` | XAUUSD | 1 | "Bar 2/3 stable" | `{"spread":0.00020,"spread_p60":0.00025,"vol":0.0012,"vol_p70":0.0015,"bars":2}` |
| `NEWS_STABILIZING` | XAUUSD | 0 | "Reset: spread_ok=0 vol_ok=1" | `{"spread":0.00030,...}` |
| `NEWS_STABLE` | XAUUSD | 1 | "Stabilization complete" | `{"elapsed_min":4}` |
| `NEWS_STABILIZATION_TIMEOUT` | XAUUSD | 0 | "Timeout after 15 min" | `{}` |
| `INTENT_REJECTED` | XAUUSD | 0 | "Post-news stabilization in progress" | `{}` |
| `NEWS_DATA_UNAVAILABLE` | (global) | 0 | "No calendar or CSV data" | `{}` |
| `NEWS_SOURCE_FALLBACK` | (global) | 1 | "Calendar unavailable, using CSV" | `{}` |
| `NEWS_SYMBOL_CURRENCY_MISSING` | XAUUSD | 0 | "Missing base/quote; fallback match" | `{}` |
| `NEWS_SYMBOL_SELECT_FAIL` | EURUSD | 0 | "SymbolSelect failed; currency match may be incomplete" | `{}` |

`news_window_state` should report `STABILIZING` (or `DATA_UNAVAILABLE_BLOCK` for Master) when applicable to keep audit logs consistent.

---

## Edge Cases & Failure Modes

| Scenario | Handling |
|----------|----------|
| **Calendar unavailable** | Fall back to CSV; log `NEWS_SOURCE_FALLBACK` |
| **CSV missing/stale and calendar unavailable** | `news_data_ok=false`, log `NEWS_DATA_UNAVAILABLE`; Master blocks new entries, Evaluation allows (warn) |
| **EA restart mid-stabilization** | Stabilization state not persisted; re-evaluate on next news check |
| **Back-to-back news events** | Second event resets stabilization; new window takes precedence |
| **No historical bars for percentile** | Use fallback: spread_p60 = current spread * 1.5, vol_p70 = ATR(14) * 0.5 |
| **Symbol not in stabilization array** | Return `false` for `News_IsStabilizing()` |
| **XAUEUR synthetic** | Check both XAUUSD and EURUSD stabilization states |
| **DST transition during stabilization** | Use UTC timestamps exclusively in news.mqh |
| **Spread data unavailable** | Skip stabilization check for that bar, log warning |
| **SymbolSelect failure** | Log `NEWS_SYMBOL_SELECT_FAIL` once; fallback to normalized symbol match |
| **Base/quote missing** | Log `NEWS_SYMBOL_CURRENCY_MISSING` once; fallback to normalized symbol match |

---

## Acceptance Criteria

| ID | Criterion | Validation |
|----|-----------|------------|
| AC-01 | No orders placed during active news window | Test: `TestNewsStab_OrderEngineGate` |
| AC-02 | Stabilization phase entered after news window closes | Test: `TestNewsStab_EntersStabilizationAfterBlock` |
| AC-03 | Stabilization requires N consecutive stable M1 bars | Test: `TestNewsStab_CompletesAfterStableBars` |
| AC-04 | Threshold violation resets stable bar counter | Test: `TestNewsStab_ResetsOnViolation` |
| AC-05 | Stabilization timeout exits after configurable minutes | Test: `TestNewsStab_TimeoutExits` |
| AC-06 | All news decisions logged with metrics | Audit log review |
| AC-07 | XAUEUR blocks if either XAUUSD or EURUSD stabilizing | Test: `TestNewsStab_XAUEURInheritsBothLegs` |
| AC-08 | Percentile thresholds calculated from rolling window | Test: `TestNewsStab_PercentileCalculation` |
| AC-09 | Inputs configurable: bars, timeout, percentiles, lookback | Input validation in OnInit |
| AC-10 | Calendar is primary; CSV used only on calendar failure | Test: `TestNewsPolicy_CalendarPrimary` / `TestNewsPolicy_FallbackToCsv` |
| AC-11 | Data unavailable handling differs by account mode (entries + modifications) | Test: `TestNewsPolicy_DataUnavailableModes` |
| AC-12 | Currency-based blocking applies to base/quote matches | Test: `TestNewsPolicy_CurrencyBlock` |
| AC-13 | Queued modifications apply after window even if stabilizing | Test: `TestNewsPolicy_QueueApplyDuringStabilization` |
| AC-14 | Stabilization state appears in news_window_state | Test: `TestNewsStab_WindowStateStabilizing` |

---

## Out of Scope / Follow-ups

- **Per-event custom stabilization**: All events use same thresholds; event-specific config deferred
- **Stabilization persistence across restart**: State is transient; could be added in Task 04
- **Calendar/CSV multi-source merging**: Use calendar primary with CSV fallback; multi-source merging deferred
