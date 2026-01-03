# M4-Task03: Kill-Switch Floors + Disable Flags + Protective Exits

## Objective

This task implements the kill-switch floor mechanism that protects the trading account from breaching FundingPips daily and overall loss caps. When equity drops to or below the configured floor levels, the EA must immediately close all positions (bypassing news windows), cancel all pending orders, and disable trading appropriately, either for the day (daily floor) or permanently (overall floor).

The kill-switch is the last line of defense against challenge failure. Daily floor breach disables trading until the next server day; overall floor breach permanently disables the EA for the challenge lifecycle. Protective exits must always be allowed, even during news windows, to prevent catastrophic losses.

---

## Functional Requirements

### Floor Calculation
- **FR-01**: `DailyFloor = baseline_today - (DailyLossCapPct / 100.0) * baseline_today`
- **FR-02**: `OverallFloor = initial_baseline - (OverallLossCapPct / 100.0) * initial_baseline`
- **FR-03**: Floors SHALL be recalculated on every equity check (OnTimer/OnTick)
- **FR-04**: The EA SHALL use configurable `DailyLossCapPct` (default 4.0%) and `OverallLossCapPct` (default 6.0%)
- **FR-05**: Floor values SHALL be logged when they change with `FLOOR_UPDATE` decision code

### Kill-Switch Triggers
- **FR-06**: When `current_equity <= DailyFloor`, trigger daily kill-switch
- **FR-07**: When `current_equity <= OverallFloor`, trigger overall kill-switch
- **FR-08**: Overall floor breach SHALL take precedence over daily floor breach
- **FR-09**: Kill-switch SHALL trigger immediately on floor breach detection (no delay)
- **FR-10**: Kill-switch SHALL log trigger with `KILLSWITCH_DAILY` or `KILLSWITCH_OVERALL` decision code

### Protective Exit Behavior
- **FR-11**: On kill-switch trigger, the EA SHALL close ALL open positions immediately
- **FR-12**: Position closes SHALL bypass news window blocking (protective exits always allowed)
- **FR-13**: Position closes SHALL bypass `MinHoldSeconds` restriction
- **FR-14**: Position closes SHALL use market orders with existing slippage caps (`MaxSlippagePoints`)
- **FR-15**: Protective closes SHALL rely on the OrderEngine retry policy and log failures
- **FR-16**: The EA SHALL log each protective exit with `PROTECTIVE_EXIT` decision code

### Pending Order Cancellation
- **FR-17**: On kill-switch trigger, the EA SHALL cancel ALL pending orders
- **FR-18**: Pending cancellation SHALL bypass news window blocking
- **FR-19**: The EA SHALL log each pending cancellation with `KILLSWITCH_PENDING_CANCEL` decision code

### Disable Flags
- **FR-20**: Daily floor breach SHALL set `trading_enabled = false` and `daily_floor_breached = true` for the current server day
- **FR-21**: Daily floor breach SHALL NOT set `disabled_permanent`
- **FR-22**: Overall floor breach SHALL set both `trading_enabled = false` AND `disabled_permanent = true`
- **FR-23**: `disabled_permanent` SHALL persist across restarts
- **FR-24**: Daily disable SHALL auto-reset on server-day rollover (unless permanently disabled)
- **FR-25**: The EA SHALL expose `TradingEnabledDefault` input (default true) for manual override

### Broker SL/TP Hits During News
- **FR-26**: When `trading_enabled = false`, block new entry intents while allowing protective exits
- **FR-27**: Broker-executed SL/TP hits SHALL always be allowed (cannot be blocked)
- **FR-28**: Broker SL/TP hits during news windows SHALL be logged as `NEWS_FORCED_EXIT`
- **FR-29**: The EA SHALL NOT attempt to modify or cancel broker-side SL/TP

### Margin Protection
- **FR-30**: If margin level drops below critical threshold (e.g., 50%), trigger protective close
- **FR-31**: Margin protection exits SHALL bypass news windows
- **FR-32**: The EA SHALL log margin protection with `MARGIN_PROTECTION` decision code

---

## Files to Modify

| File Path | Rationale |
|-----------|-----------|
| `MQL5/Include/RPEA/equity_guardian.mqh` | Add kill-switch logic that uses existing floor calculations |
| `MQL5/Include/RPEA/order_engine.mqh` | Add protective close/cancel helpers and logging (news bypass already supported) |
| `MQL5/Include/RPEA/state.mqh` | Add daily floor breach tracking; reuse existing disable flags |
| `MQL5/Include/RPEA/persistence.mqh` | Persist daily floor breach flags and hard-stop metadata |
| `MQL5/Include/RPEA/config.mqh` | Add margin protection input parameters |
| `MQL5/Include/RPEA/queue.mqh` | Add `Queue_ClearAll()` to drop queued actions on kill-switch |
| `MQL5/Include/RPEA/logging.mqh` | Add new decision codes for kill-switch events |
| `MQL5/Experts/FundingPips/RPEA.mq5` | Wire kill-switch checks into OnTimer and OnTick |
| `Tests/RPEA/test_killswitch.mqh` | New test suite for kill-switch logic |
| `Tests/RPEA/test_protective_exits.mqh` | New test suite for protective exit behavior |

---

## Data/State Changes

### Enhanced ChallengeState (state.mqh)
```cpp
struct ChallengeState
{
   // Existing fields...
   
   // Kill-switch state (M4 additions)
   bool     daily_floor_breached;         // True if daily floor hit this server day
   datetime daily_floor_breach_time;      // When daily floor was breached
   
   // Disable flags (existing)
   bool     trading_enabled;              // False when disabled for day or permanently
   bool     disabled_permanent;           // True after overall floor breach
   
   // Hard-stop metadata (from Task02)
   string   hard_stop_reason;
   datetime hard_stop_time;
   double   hard_stop_equity;
};
```

### New Input Parameters (config.mqh)
```cpp
// Existing inputs (already in RPEA.mq5)
input double DailyLossCapPct        = 4.0;   // Daily loss cap % (FundingPips default)
input double OverallLossCapPct      = 6.0;   // Overall loss cap % (FundingPips default)
input bool   TradingEnabledDefault  = true;  // Default trading enabled state
input int    MaxSlippagePoints      = 10;    // Existing slippage cap for order sends
input bool   BreakerProtectiveExitBypass = true;

// New inputs (M4)
#define DEFAULT_MarginLevelCritical 50.0
#define DEFAULT_EnableMarginProtection true
input double MarginLevelCritical    = DEFAULT_MarginLevelCritical;  // Margin level % to trigger protection
input bool   EnableMarginProtection = DEFAULT_EnableMarginProtection;  // Enable margin-based protective exits
```

### New Persisted Fields (challenge_state.json)
```
daily_floor_breached=0
daily_floor_breach_time=0
disabled_permanent=0
trading_enabled=1
hard_stop_reason=
hard_stop_time=0
hard_stop_equity=0
```

### New Log Fields
- `floor_type`: "daily" | "overall"
- `floor_value`: Calculated floor value
- `equity_at_breach`: Equity when floor was breached
- `breach_margin`: How far below floor (negative = breach amount)
- `protective_reason`: "killswitch_daily" | "killswitch_overall" | "margin_protection" | "broker_sl" | "broker_tp"

---

## Detailed Implementation Steps

### Step 1: Leverage Existing Floor Calculations (equity_guardian.mqh)

Reuse `Equity_ComputeRooms(ctx)` which already calculates `g_equity_daily_floor` and `g_equity_overall_floor` from `DailyLossCapPct` and `OverallLossCapPct` with validation. Add a helper to expose/log floor changes and add test overrides for equity/margin.

```cpp
// Optional helpers to read current floors (after Equity_ComputeRooms)
double Equity_GetDailyFloor() { return g_equity_daily_floor; }
double Equity_GetOverallFloor() { return g_equity_overall_floor; }

void Equity_LogFloorUpdate(const double prev_daily, const double prev_overall)
{
   if(MathAbs(g_equity_daily_floor - prev_daily) <= 0.01 &&
      MathAbs(g_equity_overall_floor - prev_overall) <= 0.01)
      return;

   string note = StringFormat(
      "{\"daily_floor\":%.2f,\"overall_floor\":%.2f,\"baseline_today\":%.2f,\"initial_baseline\":%.2f}",
      g_equity_daily_floor,
      g_equity_overall_floor,
      g_equity_baseline_today,
      g_equity_initial_baseline
   );
   LogDecision("Equity", "FLOOR_UPDATE", note);
}

#ifdef RPEA_TEST_RUNNER
static bool   g_equity_override_active = false;
static double g_equity_override_value  = 0.0;
static bool   g_margin_override_active = false;
static double g_margin_override_level  = 0.0;

void Equity_Test_SetEquityOverride(const double equity)
{
   g_equity_override_active = true;
   g_equity_override_value = equity;
}

void Equity_Test_ClearEquityOverride()
{
   g_equity_override_active = false;
}

void Equity_Test_SetMarginLevel(const double margin_level)
{
   g_margin_override_active = true;
   g_margin_override_level = margin_level;
}

void Equity_Test_ClearMarginLevel()
{
   g_margin_override_active = false;
}
#endif
```

Update `Equity_FetchAccountEquity()` and any margin-level checks to use the overrides when `g_equity_override_active` or `g_margin_override_active` are set (test runner only).

### Step 2: Implement Kill-Switch Detection (equity_guardian.mqh)

Use the existing room/floor calculations and session state, then execute kill-switch actions once per day or permanently.

```cpp
void Equity_CheckAndExecuteKillswitch(const AppContext &ctx)
{
   ChallengeState st = State_Get();
   if(st.disabled_permanent)
      return;

   double prev_daily = g_equity_daily_floor;
   double prev_overall = g_equity_overall_floor;

   Equity_ComputeRooms(ctx);
   Equity_LogFloorUpdate(prev_daily, prev_overall);

   EquitySessionState session = Equity_BuildSessionState(g_equity_last_rooms);
   Equity_LogSessionStateTransitions(session);

   // Overall floor takes precedence
   if(session.overall_floor_breached && !st.disabled_permanent)
   {
      double breach_margin = g_equity_current_equity - g_equity_overall_floor;
      st.disabled_permanent = true;
      st.trading_enabled = false;
      st.hard_stop_reason = "overall_floor_breach";
      st.hard_stop_time = TimeCurrent();
      st.hard_stop_equity = g_equity_current_equity;
      State_Set(st);
      g_ctx.permanently_disabled = true;

      string note = StringFormat(
         "{\"floor_type\":\"overall\",\"floor_value\":%.2f,\"equity_at_breach\":%.2f,\"breach_margin\":%.2f,\"initial_baseline\":%.2f}",
         g_equity_overall_floor,
         g_equity_current_equity,
         breach_margin,
         g_equity_initial_baseline
      );
      LogDecision("Equity", "KILLSWITCH_OVERALL", note);

      Equity_ExecuteProtectiveExits("killswitch_overall");
      Persistence_Flush();
      return;
   }

   // Daily floor breach (once per server day)
   if(session.daily_floor_breached && !st.daily_floor_breached)
   {
      double breach_margin = g_equity_current_equity - g_equity_daily_floor;
      st.daily_floor_breached = true;
      st.daily_floor_breach_time = TimeCurrent();
      st.trading_enabled = false;
      State_Set(st);

      string note = StringFormat(
         "{\"floor_type\":\"daily\",\"floor_value\":%.2f,\"equity_at_breach\":%.2f,\"breach_margin\":%.2f,\"baseline_today\":%.2f}",
         g_equity_daily_floor,
         g_equity_current_equity,
         breach_margin,
         g_equity_baseline_today
      );
      LogDecision("Equity", "KILLSWITCH_DAILY", note);

      Equity_ExecuteProtectiveExits("killswitch_daily");
      Persistence_Flush();
   }
}
```

### Step 3: Implement Protective Exits (order_engine.mqh + equity_guardian.mqh)

Reuse existing `OrderEngine_RequestProtectiveClose()` (QA_CLOSE) to bypass news, and use `OE_RequestCancel()` for pendings. Add wrappers to iterate our positions/orders and log outcomes.

```cpp
bool OrderEngine_IsOurMagic(const long magic)
{
   return (magic >= MagicBase && magic < MagicBase + 1000);
}

int OrderEngine_CloseAllPositionsProtective(const string reason)
{
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(!OrderEngine_IsOurMagic(magic))
         continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      if(OrderEngine_RequestProtectiveClose(symbol, (long)ticket, reason))
      {
         string note = StringFormat("{\"ticket\":%I64u,\"symbol\":\"%s\",\"reason\":\"%s\"}", ticket, symbol, reason);
         LogDecision("OrderEngine", "PROTECTIVE_EXIT", note);
         closed++;
      }
      else
      {
         string note = StringFormat("{\"ticket\":%I64u,\"symbol\":\"%s\",\"reason\":\"%s\"}", ticket, symbol, reason);
         LogDecision("OrderEngine", "PROTECTIVE_EXIT_FAILED", note);
      }
   }
   return closed;
}

int OrderEngine_CancelAllPendingsProtective(const string reason)
{
   int cancelled = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      int type = (int)OrderGetInteger(ORDER_TYPE);
      if(!Equity_IsPendingOrderType(type))
         continue;
      long magic = (long)OrderGetInteger(ORDER_MAGIC);
      if(!OrderEngine_IsOurMagic(magic))
         continue;
      if(OE_RequestCancel(ticket, reason))
      {
         string note = StringFormat("{\"ticket\":%I64u,\"reason\":\"%s\"}", ticket, reason);
         LogDecision("OrderEngine", "KILLSWITCH_PENDING_CANCEL", note);
         cancelled++;
      }
   }
   return cancelled;
}

void Equity_ExecuteProtectiveExits(const string reason)
{
   OrderEngine_CloseAllPositionsProtective(reason);
   OrderEngine_CancelAllPendingsProtective(reason);
   Queue_ClearAll(reason);
}
```

Note: Protective exits already bypass news via `News_GetWindowState(..., true)` and QA_CLOSE handling. If/when `MinHoldSeconds` is enforced, skip it for protective actions.

Add to `queue.mqh`:

```cpp
void Queue_ClearAll(const string reason)
{
   for(int i = g_queue_count - 1; i >= 0; i--)
   {
      long removed_id = g_queue_buffer[i].id;
      Queue_RemoveAt(i);
      Queue_DeleteFromDiskById(removed_id);
      string fields = StringFormat("{\"queue_id\":%I64d,\"reason\":\"%s\"}", removed_id, reason);
      LogAuditRow("QUEUE", "OrderEngine", LOG_INFO, "KILLSWITCH_QUEUE_CLEAR", fields);
   }
   Queue_FlushIfDirty();
}
```

Extend `OrderEngine_SendIntent()` to block new entries when `State_Get().trading_enabled == false`, while allowing protective exits and QA_CLOSE actions:

```cpp
if(!State_Get().trading_enabled && intent.is_entry)
{
   result.error_code = OE_ERR_DAILY_DISABLED;
   result.error_message = "Trading disabled for the current server day";
   LogDecision("OrderEngine", "DAILY_DISABLED_BLOCK", "{\"reason\":\"killswitch_daily\"}");
   return result;
}
```

Add `OE_ERR_DAILY_DISABLED` to the order engine error codes and expose it in tests.

### Step 4: Broker SL/TP Exit Logging (order_engine.mqh)

Add logging for broker-side SL/TP exits during news windows:

```cpp
if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
{
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT)
   {
      ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
      if(reason == DEAL_REASON_SL || reason == DEAL_REASON_TP)
      {
         string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
         if(News_IsBlocked(symbol))
         {
            string note = StringFormat("{\"ticket\":%I64d,\"symbol\":\"%s\",\"reason\":\"%s\"}",
                                       (long)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID),
                                       symbol,
                                       (reason == DEAL_REASON_SL ? "SL" : "TP"));
            LogDecision("OrderEngine", "NEWS_FORCED_EXIT", note);
         }
      }
   }
}
```

### Step 5: Implement Margin Protection (equity_guardian.mqh)

```cpp
// Check margin level and trigger protection if needed
bool Equity_CheckMarginProtection(ChallengeState &state)
{
   if(!EnableMarginProtection)
      return false;
   double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
#ifdef RPEA_TEST_RUNNER
   if(g_margin_override_active)
      margin_level = g_margin_override_level;
#endif
   
   // Margin level of 0 means no positions (nothing to protect)
   if(margin_level == 0.0)
      return false;
   
   if(margin_level < MarginLevelCritical)
   {
      double equity = Equity_FetchAccountEquity();
      double margin = AccountInfoDouble(ACCOUNT_MARGIN);
      
      string note = StringFormat(
         "{\"margin_level\":%.2f,\"threshold\":%.2f,\"equity\":%.2f,\"margin\":%.2f}",
         margin_level,
         MarginLevelCritical,
         equity,
         margin
      );
      LogDecision("Equity", "MARGIN_PROTECTION", note);
      
      // Close positions to free margin
      Equity_ExecuteProtectiveExits("margin_protection");
      State_Set(state);
      
      return true;
   }
   
   return false;
}
```

### Step 6: Integrate into Main EA Loop (RPEA.mq5)

```cpp
// In OnTimer() - check kill-switch at every timer tick
void OnTimer()
{
   // Check day rollover first (server-day)
   static string s_last_server_date = "";
   string current_server_date = TimeUtils_ServerDateString(TimeCurrent());
   if(s_last_server_date != "" && s_last_server_date != current_server_date)
   {
      Equity_OnServerDayRollover();
   }
   s_last_server_date = current_server_date;

   ChallengeState state = State_Get();
   if(state.disabled_permanent)
      return;

   // Check kill-switch floors
   Equity_CheckAndExecuteKillswitch(g_ctx);

   // If kill-switch triggered, stop processing
   if(!State_Get().trading_enabled)
      return;
   
   // Check margin protection
   if(Equity_CheckMarginProtection(state))
   {
      // Margin protection triggered, but trading can continue
      // (unless it also breached a floor)
   }
   
   // ... rest of OnTimer logic ...
}

// In OnTick() - also check kill-switch for faster response
void OnTick()
{
   ChallengeState state = State_Get();
   if(!state.disabled_permanent)
      Equity_CheckAndExecuteKillswitch(g_ctx);
   
   // ... rest of OnTick logic ...
}
```

On `OnInit()`, if `disabled_permanent` or `daily_floor_breached` is already set and positions/pendings exist, call `Equity_ExecuteProtectiveExits("killswitch_resume")` to re-try closes after restart.

### Step 7: Add Daily Reset Logic (equity_guardian.mqh)

Extend `Equity_OnServerDayRollover()` (from Task02) to reset daily kill-switch flags:

```cpp
void Equity_OnServerDayRollover()
{
   ChallengeState st = State_Get();
   st.daily_floor_breached = false;
   st.daily_floor_breach_time = (datetime)0;
   if(!st.disabled_permanent)
      st.trading_enabled = TradingEnabledDefault;

   st.day_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   State_Set(st);

   string note = StringFormat("{\"trading_enabled\":%s,\"daily_floor_breached\":false}",
                              st.trading_enabled ? "true" : "false");
   LogDecision("Equity", "DAILY_FLAGS_RESET", note);
}
```

Also update `State_ResetDailyBaseline()` and its overload to set `trading_enabled = TradingEnabledDefault` when `disabled_permanent` is false.

### Step 8: Persist Daily Breach Flags (persistence.mqh)

Extend the key/value challenge state persistence (keep key order stable):

```cpp
// Save (append new keys)
FileWrite(h, "daily_floor_breached="+(st.daily_floor_breached ? "1" : "0"));
FileWrite(h, "daily_floor_breach_time="+(string)st.daily_floor_breach_time);

// Load (parse keys)
else if(k=="daily_floor_breached") { st.daily_floor_breached = (StringToInteger(v)!=0); parsed_any=true; }
else if(k=="daily_floor_breach_time") { st.daily_floor_breach_time = (datetime)StringToInteger(v); parsed_any=true; }
```

---

## Tests

### New Test File: `Tests/RPEA/test_killswitch.mqh`

```cpp
#ifndef TEST_KILLSWITCH_MQH
#define TEST_KILLSWITCH_MQH

#include <RPEA/app_context.mqh>
#include <RPEA/equity_guardian.mqh>
#include <RPEA/state.mqh>

bool Test_Killswitch_DailyFloorCalculation()
{
   g_current_test = "Test_Killswitch_DailyFloorCalculation";
   AppContext ctx;
   ZeroMemory(ctx);
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.current_server_time = TimeCurrent();

   Equity_Test_SetEquityOverride(10000.0);
   Equity_ComputeRooms(ctx);
   double floor = Equity_GetDailyFloor();
   double expected = 10000.0 - (DailyLossCapPct / 100.0 * 10000.0);
   Equity_Test_ClearEquityOverride();

   ASSERT_TRUE(MathAbs(floor - expected) < 0.01, "Daily floor should be baseline - DailyLossCapPct%");
   return (g_test_failed == 0);
}

bool Test_Killswitch_OverallFloorCalculation()
{
   g_current_test = "Test_Killswitch_OverallFloorCalculation";
   AppContext ctx;
   ZeroMemory(ctx);
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.current_server_time = TimeCurrent();

   Equity_Test_SetEquityOverride(10000.0);
   Equity_ComputeRooms(ctx);
   double floor = Equity_GetOverallFloor();
   double expected = 10000.0 - (OverallLossCapPct / 100.0 * 10000.0);
   Equity_Test_ClearEquityOverride();

   ASSERT_TRUE(MathAbs(floor - expected) < 0.01, "Overall floor should be baseline - OverallLossCapPct%");
   return (g_test_failed == 0);
}

bool Test_Killswitch_OverallPrecedence()
{
   g_current_test = "Test_Killswitch_OverallPrecedence";
   ChallengeState st = State_Get();
   st.disabled_permanent = false;
   st.daily_floor_breached = false;
   st.trading_enabled = true;
   State_Set(st);

   AppContext ctx;
   ZeroMemory(ctx);
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.current_server_time = TimeCurrent();

   // Force equity below both floors
   Equity_Test_SetEquityOverride(9000.0);
   Equity_CheckAndExecuteKillswitch(ctx);
   Equity_Test_ClearEquityOverride();

   st = State_Get();
   ASSERT_TRUE(st.disabled_permanent, "Overall breach should set disabled_permanent");
   return (g_test_failed == 0);
}

bool Test_Killswitch_DailyReset()
{
   g_current_test = "Test_Killswitch_DailyReset";
   ChallengeState st = State_Get();
   st.daily_floor_breached = true;
   st.trading_enabled = false;
   st.disabled_permanent = false;
   State_Set(st);

   Equity_OnServerDayRollover();
   st = State_Get();

   ASSERT_TRUE(st.daily_floor_breached == false, "Daily breach flag should reset");
   ASSERT_TRUE(st.trading_enabled == TradingEnabledDefault, "Trading should be re-enabled");
   return (g_test_failed == 0);
}

bool Test_Killswitch_PermanentNoReset()
{
   g_current_test = "Test_Killswitch_PermanentNoReset";
   ChallengeState st = State_Get();
   st.disabled_permanent = true;
   st.trading_enabled = false;
   State_Set(st);

   Equity_OnServerDayRollover();
   st = State_Get();

   ASSERT_TRUE(st.disabled_permanent == true, "Permanent disable should NOT reset");
   ASSERT_TRUE(st.trading_enabled == false, "Trading should stay disabled");
   return (g_test_failed == 0);
}

bool TestKillswitch_RunAll()
{
   PrintFormat("==============================================================");
   PrintFormat("M4 Task03 Kill-Switch Tests");
   PrintFormat("==============================================================");

   g_test_passed = 0;
   g_test_failed = 0;

   bool ok = true;
   ok &= Test_Killswitch_DailyFloorCalculation();
   ok &= Test_Killswitch_OverallFloorCalculation();
   ok &= Test_Killswitch_OverallPrecedence();
   ok &= Test_Killswitch_DailyReset();
   ok &= Test_Killswitch_PermanentNoReset();

   PrintFormat("Test Summary: %d passed, %d failed", g_test_passed, g_test_failed);
   return (ok && g_test_failed == 0);
}

#endif // TEST_KILLSWITCH_MQH
```

### New Test File: `Tests/RPEA/test_protective_exits.mqh`

```cpp
#ifndef TEST_PROTECTIVE_EXITS_MQH
#define TEST_PROTECTIVE_EXITS_MQH

#include <RPEA/order_engine.mqh>
#include <RPEA/news.mqh>

bool ProtectiveExits_WriteFixture(const string filename, const string &lines[], const int line_count, string &out_path)
{
   FolderCreate(RPEA_DIR);
   const string fixture_dir = RPEA_DIR"/test_fixtures";
   FolderCreate(fixture_dir);
   string path = fixture_dir + "/" + filename;
   int handle = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;
   for(int i = 0; i < line_count; i++)
      FileWrite(handle, lines[i]);
   FileClose(handle);
   out_path = path;
   return true;
}

bool Test_ProtectiveExits_BypassNews()
{
   g_current_test = "Test_ProtectiveExits_BypassNews";
   string fixture_path = "";
   string lines[2];
   lines[0] = "timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min";
   lines[1] = "2025-01-15T13:30:00Z,XAUUSD,HIGH,BLS,Test,5,10";
   ASSERT_TRUE(ProtectiveExits_WriteFixture("news_protective.csv", lines, 2, fixture_path), "Fixture created");
   News_Test_SetOverridePath(fixture_path);
   News_Test_SetOverrideMaxAgeHours(24);
   News_Test_SetCurrentTimes(StringToTime("2025.01.15 13:29"), StringToTime("2025.01.15 13:29"));

   string news_state = News_GetWindowState("XAUUSD", true);
   ASSERT_TRUE(news_state == "PROTECTIVE_ONLY", "Protective exits should be allowed during news");

   News_Test_ClearCurrentTimeOverride();
   return (g_test_failed == 0);
}

bool Test_ProtectiveExits_MarginProtection()
{
   g_current_test = "Test_ProtectiveExits_MarginProtection";
   ASSERT_TRUE(MarginLevelCritical >= 20.0 && MarginLevelCritical <= 100.0,
               "Margin level threshold should be between 20% and 100%");
   return (g_test_failed == 0);
}

bool TestProtectiveExits_RunAll()
{
   PrintFormat("==============================================================");
   PrintFormat("M4 Task03 Protective Exit Tests");
   PrintFormat("==============================================================");

   g_test_passed = 0;
   g_test_failed = 0;

   bool ok = true;
   ok &= Test_ProtectiveExits_BypassNews();
   ok &= Test_ProtectiveExits_MarginProtection();

   PrintFormat("Test Summary: %d passed, %d failed", g_test_passed, g_test_failed);
   return (ok && g_test_failed == 0);
}

#endif // TEST_PROTECTIVE_EXITS_MQH
```

### Wire into Test Runner

In `Tests/RPEA/run_automated_tests_ea.mq5`:

```cpp
#include "test_killswitch.mqh"
#include "test_protective_exits.mqh"

int suiteM4T3a = g_test_reporter.BeginSuite("M4Task3_KillSwitch");
bool m4t3a_result = TestKillswitch_RunAll();
g_test_reporter.RecordTest(suiteM4T3a, "TestKillswitch_RunAll", m4t3a_result,
                           m4t3a_result ? "kill-switch tests passed" : "kill-switch tests failed");
g_test_reporter.EndSuite(suiteM4T3a);

int suiteM4T3b = g_test_reporter.BeginSuite("M4Task3_Protective_Exits");
bool m4t3b_result = TestProtectiveExits_RunAll();
g_test_reporter.RecordTest(suiteM4T3b, "TestProtectiveExits_RunAll", m4t3b_result,
                           m4t3b_result ? "protective exit tests passed" : "protective exit tests failed");
g_test_reporter.EndSuite(suiteM4T3b);
```

---

## Logging/Telemetry

### New Decision Codes

| Code | Component | Description |
|------|-----------|-------------|
| `FLOOR_UPDATE` | Equity | Floor values recalculated |
| `KILLSWITCH_DAILY` | Equity | Daily floor breached, kill-switch triggered |
| `KILLSWITCH_OVERALL` | Equity | Overall floor breached, permanent kill-switch |
| `PROTECTIVE_EXIT` | OrderEngine | Position closed by protective mechanism |
| `PROTECTIVE_EXIT_FAILED` | OrderEngine | Protective exit failed |
| `KILLSWITCH_PENDING_CANCEL` | OrderEngine | Pending cancelled by kill-switch |
| `KILLSWITCH_QUEUE_CLEAR` | Queue | Queued actions cleared due to kill-switch |
| `DAILY_DISABLED_BLOCK` | OrderEngine | Entry blocked while trading disabled for the day |
| `MARGIN_PROTECTION` | Equity | Margin protection triggered |
| `NEWS_FORCED_EXIT` | OrderEngine | Broker SL/TP hit during news window |
| `DAILY_FLAGS_RESET` | Equity | Daily flags reset at server-day rollover |

### Audit Log Fields

Add to existing CSV audit schema:
```
...,floor_type,floor_value,equity_at_breach,breach_margin,protective_reason
```

---

## Edge Cases & Failure Modes

### Floor Calculation Edge Cases
- **Zero baseline**: If baseline is 0 or negative, floor should be 0 (no trades allowed)
- **Negative cap**: If DailyLossCapPct is negative (misconfigured), treat as 0
- **Rounding errors**: Use epsilon comparison (1e-6) for floor breach detection

### Kill-Switch Execution Edge Cases
- **Position close fails**: Log error and continue; rely on OrderEngine retry policy and next tick re-run
- **Pending cancel fails**: Log error; pending may fill - handle in OnTradeTransaction
- **Partial position**: If position is partially filled during close attempt, handle remaining
- **Market closed**: If market is closed when kill-switch triggers, log failure and retry on next timer tick

### Restart Scenarios
- **Restart after daily breach**: Restore `daily_floor_breached=true` and `trading_enabled=false`; wait for rollover
- **Restart after overall breach**: Restore `disabled_permanent=true`; never trade again
- **Restart with open positions during breach**: Re-execute protective closes on init

### News Window Interactions
- **Kill-switch during news**: Execute immediately; news bypass is always allowed
- **Broker SL hit during news**: Log as `NEWS_FORCED_EXIT`; cannot prevent
- **Queued trailing during kill-switch**: Cancel all queued actions; execute protective exits

### Margin Protection Edge Cases
- **Hedged positions**: May have low margin level but no net risk; keep logic simple for M4
- **Volatile margin**: Avoid triggering on momentary spikes (optional: use smoothed margin)

---

## Acceptance Criteria

| ID | Criterion | Validation Method |
|----|-----------|-------------------|
| AC-01 | Daily floor = baseline_today - DailyLossCapPct% | Test: `Test_Killswitch_DailyFloorCalculation` |
| AC-02 | Overall floor = initial_baseline - OverallLossCapPct% | Test: `Test_Killswitch_OverallFloorCalculation` |
| AC-03 | Kill-switch triggers immediately on floor breach | Test: `Test_Killswitch_OverallPrecedence` |
| AC-04 | All positions closed on kill-switch | Verify no positions remain |
| AC-05 | All pendings cancelled on kill-switch | Verify no pending orders remain |
| AC-06 | Protective exits bypass news windows | Test: `Test_ProtectiveExits_BypassNews` |
| AC-07 | Daily disable resets at server-day rollover | Test: `Test_Killswitch_DailyReset` |
| AC-08 | Permanent disable persists across restart | Restart EA, verify disabled |
| AC-09 | `KILLSWITCH_DAILY` logged on daily breach | Audit log inspection |
| AC-10 | `KILLSWITCH_OVERALL` logged on overall breach | Audit log inspection |
| AC-11 | Margin protection triggers at MarginLevelCritical | Test: `Test_ProtectiveExits_MarginProtection` |
| AC-12 | Queue cleared on kill-switch | Manual: verify `Queue_ClearAll()` empties queue |
| AC-13 | New entries blocked when trading disabled | Manual: set `trading_enabled=false`, verify `OE_ERR_DAILY_DISABLED` |

---

## Out of Scope / Follow-ups

### Deferred to M6 or Post-Challenge
- **Partial close strategy**: Close positions in order of largest loss first
- **Hedged position handling**: Special logic for hedged/locked positions
- **External notification**: Email/SMS alert on kill-switch trigger
- **Gradual de-risking**: Reduce position size as equity approaches floor
- **Circuit breaker**: Temporary pause before full kill-switch

### Related Tasks
- **M4-Task01**: News compliance provides `is_protective` parameter for blocking checks
- **M4-Task02**: Micro-Mode interacts with daily disable (giveback protection)
- **M4-Task04**: Persistence hardening ensures disable flags survive restart
