# M4-Task02: Server-Day Tracking + MinTradeDays/Micro-Mode + Hard-Stop

## Objective

This task implements **server-day** tracking (with CEST reporting) to comply with FundingPips' **MinTradeDaysRequired** rule, which requires trades to occur on at least N distinct calendar days before payout eligibility. Additionally, it enables **Micro-Mode** only **after the +10% target is achieved**, enforcing reduced risk to satisfy the remaining trade days. A **hard-stop** mechanism permanently disables trading once the target + min trade days are met or the overall floor is breached.

Per **finalspec.md Section 2.1 Challenge Targets** and **prd.md Section Compliance**, the EA must:
1. Track distinct **server-day** calendar days on which at least one `DEAL_ENTRY_IN` transaction occurs; map to CEST for reporting only
2. Switch to Micro-Mode **after target is reached** if `gDaysTraded < MinTradeDaysRequired`
3. Implement hard-stop that disables all trading when target achieved **and** min trade days met, or overall floor breached

---

## Functional Requirements

### Server-Day Tracking (CEST for Reporting)
- **FR-01**: Track each **server-day** (platform midnight-to-midnight) on which at least one `DEAL_ENTRY_IN` transaction occurs
- **FR-02**: Use input `ServerToCEST_OffsetMinutes` to convert server time to CEST **for reporting only**
- **FR-03**: Store `gDaysTraded` counter and `last_counted_server_date` (yyyymmdd int) in persisted `ChallengeState`
- **FR-04**: Increment `gDaysTraded` only once per server day (idempotent)
- **FR-05**: Log `TRADE_DAY_MARKED` with both server date and CEST report date string when a new trade day is counted
- **FR-06**: Expose `State_GetDaysTraded()` for governance checks

### MinTradeDays Governance
- **FR-07**: If `gDaysTraded < MinTradeDaysRequired` when profit target is hit, log `TARGET_PENDING_DAYS` and continue trading in Micro-Mode
- **FR-08**: Challenge completion requires BOTH profit target AND `gDaysTraded >= MinTradeDaysRequired`
- **FR-09**: Display warning in logs when `gDaysTraded` is within 1 day of the minimum (e.g., log `TARGET_PENDING_DAYS` at WARN)

### Micro-Mode Activation (Post-Target Only)
- **FR-10**: Micro-Mode activates **only after** profit target is hit **and** `gDaysTraded < MinTradeDaysRequired`
- **FR-11**: In Micro-Mode, override `RiskPct` with `MicroRiskPct` (default 0.10%)
- **FR-12**: In Micro-Mode, enforce `MicroTimeStopMin` (default 45 min) as maximum position hold time
- **FR-13**: In Micro-Mode, allow **one micro trade per remaining day** until `MinTradeDaysRequired` met (use per-day micro entry tracking)
- **FR-14**: Micro-Mode persists until challenge completion or overall floor breach

### Hard-Stop Mechanism
- **FR-15**: Hard-stop activates when ANY condition is met:
  - Profit target achieved AND `gDaysTraded >= MinTradeDaysRequired` (success)
  - Overall drawdown floor breached (failure)
  - User-initiated kill switch (if present)
- **FR-16**: When hard-stop activates, set `disabled_permanent=true` and `g_ctx.permanently_disabled = true`
- **FR-17**: Hard-stop closes ALL open positions and cancels ALL pending orders
- **FR-18**: Hard-stop survives EA restart (persisted flag)
- **FR-19**: Log `HARD_STOP_ACTIVATED` with reason and final equity snapshot
- **FR-20**: After hard-stop, reject all `SendIntent()` calls with `OE_ERR_HARD_STOPPED`

### Giveback Protection (Micro-Mode)
- **FR-21**: Track `day_peak_equity` (intraday peak) for giveback calculations
- **FR-22**: If intraday drawdown from peak exceeds `GivebackCapDayPct` **during Micro-Mode**, close positions and disable trading for the day
- **FR-23**: In giveback protection mode, allow protective exits only; block new entries until next server day

---

## Files to Modify

| File | Rationale |
|------|-----------|
| `MQL5/Include/RPEA/state.mqh` | Extend existing day tracking and mode flags; add micro entry day tracking, hard-stop metadata, and overall peak tracking |
| `MQL5/Include/RPEA/timeutils.mqh` | Add `TimeUtils_ServerDateInt()`, `TimeUtils_ServerToCEST()`, and `TimeUtils_CestDateString()` |
| `MQL5/Include/RPEA/equity_guardian.mqh` | Add Micro-Mode checks, hard-stop trigger logic, giveback protection (Micro-Mode only) |
| `MQL5/Include/RPEA/config.mqh` | Add defaults for Micro-Mode and hard-stop inputs |
| `MQL5/Include/RPEA/order_engine.mqh` | Gate on hard-stop, Micro-Mode daily entry limit, giveback; apply Micro-Mode risk override |
| `MQL5/Include/RPEA/risk.mqh` | Add `Risk_GetEffectiveRiskPct()` that respects Micro-Mode |
| `MQL5/Include/RPEA/persistence.mqh` | Extend challenge state persistence for micro-mode activation + entry tracking, hard-stop metadata, `overall_peak_equity` |
| `MQL5/Include/RPEA/logging.mqh` | Add new event types for day tracking and mode changes |
| `MQL5/Experts/FundingPips/RPEA.mq5` | Wire CEST reporting, Micro-Mode inputs, hard-stop handling |
| `Tests/RPEA/test_day_tracking.mqh` | New test file for server-day counting + CEST reporting |
| `Tests/RPEA/test_micro_mode.mqh` | New test file for Micro-Mode activation |
| `Tests/RPEA/run_automated_tests_ea.mq5` | Include and wire new test suites |

---

## Data/State Changes

### New/Modified Inputs (config.mqh / RPEA.mq5)

```cpp
// Existing inputs (for reference)
input int    MinTradeDaysRequired       = 3;
input double MicroRiskPct               = 0.10;   // 0.05-0.20
input int    MicroTimeStopMin           = 45;     // 30-60
input double GivebackCapDayPct          = 0.50;   // 0.25-0.50
input int    ServerToCEST_OffsetMinutes = 0;

// New inputs
input double TargetProfitPct            = 10.0;   // Challenge profit target percentage
```

### New/Modified Fields in ChallengeState (state.mqh)

```cpp
struct ChallengeState
{
   // ... existing fields ...
   
   // Server-Day Tracking (M4-Task02)
   int      gDaysTraded;              // Count of distinct server days with trades (existing)
   int      last_counted_server_date; // yyyymmdd of last counted server day (existing)
   
   // Micro-Mode (M4-Task02)
   bool     micro_mode;               // Currently in Micro-Mode (existing)
   datetime micro_mode_activated_at;  // When Micro-Mode was activated (new)
   int      last_micro_entry_server_date; // yyyymmdd of last micro entry day (new)
   
   // Hard-Stop (M4-Task02)
   bool     disabled_permanent;       // Permanent trading disable flag (existing)
   string   hard_stop_reason;         // Reason for hard-stop (new)
   datetime hard_stop_time;           // When hard-stop was triggered (new)
   double   hard_stop_equity;         // Final equity at hard-stop (new)
   
   // Giveback Protection (M4-Task02)
   bool     trading_enabled;          // Day-level enable flag (existing)
   double   day_peak_equity;          // Intraday high water mark (existing)
   double   overall_peak_equity;      // Overall high water mark (new)
};
```

### New Config Defaults (config.mqh)

```cpp
#ifndef DEFAULT_TargetProfitPct
#define DEFAULT_TargetProfitPct         10.0
#endif
```

### New Log Event Types

```cpp
"TRADE_DAY_MARKED"       // New server day with trade (CEST reported in payload)
"MICRO_MODE_ACTIVATED"   // Entered Micro-Mode
"MICRO_MODE_TRADE"       // Trade executed in Micro-Mode
"MICRO_MODE_DAY_LIMIT"   // Micro-Mode entry rejected for the day
"HARD_STOP_ACTIVATED"    // Trading permanently disabled
"HARD_STOP_REJECTED"     // Intent rejected due to hard-stop
"GIVEBACK_PROTECTION"    // Entered giveback protection mode
"TARGET_PENDING_DAYS"    // Target hit but MinTradeDays not met
"CHALLENGE_COMPLETE"     // Both target and MinTradeDays achieved
"DAY_ROLLOVER_SERVER"    // Server-day rollover (daily peak reset)
```

---

## Detailed Implementation Steps

### Step 1: Add Server-Day + CEST Reporting Helpers to timeutils.mqh

```cpp
// Get server date string "YYYY.MM.DD" from server time
string TimeUtils_ServerDateString(const datetime server_time)
{
   MqlDateTime dt;
   TimeToStruct(server_time, dt);
   return StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);
}

// Get server date int yyyymmdd from server time
int TimeUtils_ServerDateInt(const datetime server_time)
{
   MqlDateTime dt;
   TimeToStruct(server_time, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

// Convert server time to CEST using configured offset (reporting only)
datetime TimeUtils_ServerToCEST(const datetime server_time)
{
   return server_time + ServerToCEST_OffsetMinutes * 60;
}

// Get CEST report date string "YYYY.MM.DD" from server time
string TimeUtils_CestDateString(const datetime server_time)
{
   datetime cest_time = TimeUtils_ServerToCEST(server_time);
   MqlDateTime dt;
   TimeToStruct(cest_time, dt);
   return StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);
}
```

### Step 2: Add Day Tracking to state.mqh

```cpp
// Mark a trade day (called from OnTradeTransaction on DEAL_ENTRY_IN)
void State_MarkTradeDayServer(const datetime server_time)
{
   int server_date = TimeUtils_ServerDateInt(server_time);
   string server_date_str = TimeUtils_ServerDateString(server_time);
   string cest_date = TimeUtils_CestDateString(server_time);
   
   ChallengeState st = State_Get();
   
   // Check if already counted today
   if(st.last_counted_server_date == server_date)
      return;  // Already counted
   
   // New trade day
   st.gDaysTraded++;
   st.last_counted_server_date = server_date;
   State_Set(st);
   
   LogAuditRow("TRADE_DAY_MARKED", "STATE", 1,
               StringFormat("Day %d of %d", st.gDaysTraded, MinTradeDaysRequired),
               StringFormat("{\"server_date\":\"%s\",\"cest_date\":\"%s\",\"days_traded\":%d}",
                           server_date_str, cest_date, st.gDaysTraded));
}

// Get current days traded count
int State_GetDaysTraded()
{
   ChallengeState st = State_Get();
   return st.gDaysTraded;
}

// Check if MinTradeDays requirement is met
bool State_MinTradeDaysMet()
{
   return State_GetDaysTraded() >= MinTradeDaysRequired;
}

// Check if a Micro-Mode entry is allowed for the current server day
bool State_MicroEntryAllowed(const datetime server_time)
{
   int server_date = TimeUtils_ServerDateInt(server_time);
   ChallengeState st = State_Get();
   return st.last_micro_entry_server_date != server_date;
}

// Mark that a Micro-Mode entry occurred on this server day
void State_MarkMicroEntryServer(const datetime server_time)
{
   ChallengeState st = State_Get();
   st.last_micro_entry_server_date = TimeUtils_ServerDateInt(server_time);
   State_Set(st);
}
```

Replace the existing `State_MarkTradeDayOnce()` overloads to call `State_MarkTradeDayServer()` with an explicit timestamp for deterministic tests.

### Step 3: Implement Micro-Mode in equity_guardian.mqh

```cpp
// Check and activate Micro-Mode if conditions met
void Equity_CheckMicroMode(const AppContext &ctx)
{
   ChallengeState st = State_Get();
   
   // Already in Micro-Mode or permanently disabled
   if(st.micro_mode || st.disabled_permanent)
      return;
   
   // Condition 1: Profit target achieved
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double baseline = ctx.initial_baseline;
   double target_equity = baseline * (1.0 + TargetProfitPct / 100.0);

   if(current_equity < target_equity)
      return;

   // Condition 2: gDaysTraded still below requirement
   if(st.gDaysTraded >= MinTradeDaysRequired)
      return;
   
   // Activate Micro-Mode
   st.micro_mode = true;
   st.micro_mode_activated_at = TimeCurrent();
   State_Set(st);
   
   LogAuditRow("MICRO_MODE_ACTIVATED", "EQUITY", 1,
               StringFormat("Equity %.2f near target %.2f", current_equity, target_equity),
               StringFormat("{\"equity\":%.2f,\"target\":%.2f,\"days_traded\":%d,\"micro_risk_pct\":%.2f}",
                           current_equity, target_equity, st.gDaysTraded, MicroRiskPct));
}

// Check if Micro-Mode is active
bool Equity_IsMicroModeActive()
{
   ChallengeState st = State_Get();
   return st.micro_mode;
}

// Check Micro-Mode time stop
bool Equity_MicroTimeStopExceeded(const datetime entry_time)
{
   if(!Equity_IsMicroModeActive())
      return false;
   
   int elapsed_min = (int)((TimeCurrent() - entry_time) / 60);
   return elapsed_min >= MicroTimeStopMin;
}
```

In `risk.mqh`, add a helper that respects Micro-Mode:

```cpp
// Get effective risk percentage (respects Micro-Mode)
double Risk_GetEffectiveRiskPct()
{
   return Equity_IsMicroModeActive() ? MicroRiskPct : RiskPct;
}
```

### Step 4: Implement Hard-Stop in equity_guardian.mqh

```cpp
// Trigger hard-stop with reason
void Equity_TriggerHardStop(const string reason)
{
   ChallengeState st = State_Get();
   
   if(st.disabled_permanent)
      return;  // Already stopped
   
   st.disabled_permanent = true;
   st.trading_enabled = false;
   st.hard_stop_reason = reason;
   st.hard_stop_time = TimeCurrent();
   st.hard_stop_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   State_Set(st);
   
   // Set context flag
   g_ctx.permanently_disabled = true;
   
   LogAuditRow("HARD_STOP_ACTIVATED", "EQUITY", 0, reason,
               StringFormat("{\"equity\":%.2f,\"reason\":\"%s\",\"days_traded\":%d}",
                           st.hard_stop_equity, reason, st.gDaysTraded));
   
   // Close all positions and cancel all orders
   Equity_CloseAllPositions("HARD_STOP");
   Equity_CancelAllPendingOrders("HARD_STOP");
   
   // Persist immediately
   Persistence_Flush();
}

// Check if hard-stopped
bool Equity_IsHardStopped()
{
   ChallengeState st = State_Get();
   return st.disabled_permanent;
}

// Check for hard-stop conditions
void Equity_CheckHardStopConditions(const AppContext &ctx)
{
   ChallengeState st = State_Get();
   
   if(st.disabled_permanent)
      return;
   
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double baseline = ctx.initial_baseline;
   
   // Check 1: Overall drawdown floor breach
   double overall_floor = baseline * (1.0 - OverallLossCapPct / 100.0);
   if(current_equity <= overall_floor)
   {
      Equity_TriggerHardStop(StringFormat("Overall floor breach: %.2f <= %.2f", 
                                          current_equity, overall_floor));
      return;
   }
   
   // Check 2: Challenge complete (success hard-stop)
   double target_equity = baseline * (1.0 + TargetProfitPct / 100.0);
   if(current_equity >= target_equity && st.gDaysTraded >= MinTradeDaysRequired)
   {
      LogAuditRow("CHALLENGE_COMPLETE", "EQUITY", 1,
                  StringFormat("Target %.2f achieved with %d days", target_equity, st.gDaysTraded),
                  StringFormat("{\"equity\":%.2f,\"target\":%.2f,\"days_traded\":%d}",
                              current_equity, target_equity, st.gDaysTraded));
      Equity_TriggerHardStop("Challenge completed successfully");
      return;
   }
   
   // Check 3: Target hit but MinTradeDays not met
   if(current_equity >= target_equity && st.gDaysTraded < MinTradeDaysRequired)
   {
      LogAuditRow("TARGET_PENDING_DAYS", "EQUITY", 1,
                  StringFormat("Target hit, need %d more days", 
                              MinTradeDaysRequired - st.gDaysTraded),
                  StringFormat("{\"equity\":%.2f,\"days_traded\":%d,\"required\":%d}",
                              current_equity, st.gDaysTraded, MinTradeDaysRequired));
      // Continue in Micro-Mode, don't hard-stop
   }
}

// Close all open positions
void Equity_CloseAllPositions(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_DEAL;
         request.position = ticket;
         request.symbol = symbol;
         request.volume = volume;
         request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
                        ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.price = (request.type == ORDER_TYPE_BUY) 
                         ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                         : SymbolInfoDouble(symbol, SYMBOL_BID);
         request.deviation = MaxSlippagePoints;
         request.comment = reason;
         
         if(!OrderSend(request, result))
         {
            PrintFormat("[HardStop] Failed to close position %d: %d", ticket, result.retcode);
         }
      }
   }
}

// Cancel all pending orders
void Equity_CancelAllPendingOrders(const string reason)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_REMOVE;
         request.order = ticket;
         request.comment = reason;
         
         if(!OrderSend(request, result))
         {
            PrintFormat("[HardStop] Failed to cancel order %d: %d", ticket, result.retcode);
         }
      }
   }
}
```

### Step 5: Implement Giveback Protection

```cpp
// Update peak equity tracking
void Equity_UpdatePeakTracking()
{
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   ChallengeState st = State_Get();
   
   // Update intraday peak
   if(current_equity > st.day_peak_equity)
   {
      st.day_peak_equity = current_equity;
   }
   
   // Update overall peak
   if(current_equity > st.overall_peak_equity)
   {
      st.overall_peak_equity = current_equity;
   }
   
   State_Set(st);
}

// Check and trigger giveback protection (Micro-Mode only)
bool Equity_CheckGivebackProtection()
{
   ChallengeState st = State_Get();
   
   if(!st.micro_mode)
      return false;

   if(st.day_peak_equity <= 0)
      return false;
   
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown_from_peak = (st.day_peak_equity - current_equity) / st.day_peak_equity;
   
   if(drawdown_from_peak >= GivebackCapDayPct / 100.0)
   {
      if(st.trading_enabled)
      {
         st.trading_enabled = false;
         State_Set(st);

         LogAuditRow("GIVEBACK_PROTECTION", "EQUITY", 0,
                     StringFormat("DD %.2f%% from peak %.2f", drawdown_from_peak * 100, st.day_peak_equity),
                     StringFormat("{\"equity\":%.2f,\"peak\":%.2f,\"dd_pct\":%.2f}",
                                 current_equity, st.day_peak_equity, drawdown_from_peak * 100));

         Equity_CloseAllPositions("GIVEBACK_PROTECTION");
         Equity_CancelAllPendingOrders("GIVEBACK_PROTECTION");
      }
      return true;
   }
   
   return !st.trading_enabled;
}

// Read-only gate for order engine
bool Equity_IsGivebackProtectionActive()
{
   ChallengeState st = State_Get();
   return st.micro_mode && !st.trading_enabled;
}

// Reset daily tracking on server-day rollover
void Equity_OnServerDayRollover()
{
   ChallengeState st = State_Get();
   st.day_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!st.disabled_permanent)
      st.trading_enabled = true;
   State_Set(st);
   
   LogAuditRow("DAY_ROLLOVER_SERVER", "EQUITY", 1, "Daily peak reset", "{}");
}
```

### Step 6: Gate Order Engine on Hard-Stop

In `order_engine.mqh`, modify `OrderEngine_SendIntent()`:

```cpp
IntentResult OrderEngine_SendIntent(const TradeIntent &intent)
{
   IntentResult result;
   result.success = false;
   result.order_ticket = 0;
   result.position_ticket = 0;
   
   // Hard-stop gate (highest priority)
   if(Equity_IsHardStopped())
   {
      result.error_code = OE_ERR_HARD_STOPPED;
      result.error_message = "Trading permanently disabled (hard-stop active)";
      LogAuditRow("HARD_STOP_REJECTED", intent.symbol, 0, result.error_message, "{}");
      return result;
   }
   
   // Giveback protection gate (entries only)
   if(Equity_IsGivebackProtectionActive() && intent.is_entry)
   {
      result.error_code = OE_ERR_GIVEBACK_PROTECTION;
      result.error_message = "New entries blocked (giveback protection)";
      LogAuditRow("GIVEBACK_REJECTED", intent.symbol, 0, result.error_message, "{}");
      return result;
   }
   
   // Micro-Mode daily entry limit
   if(Equity_IsMicroModeActive() && intent.is_entry)
   {
      if(!State_MicroEntryAllowed(TimeCurrent()))
      {
         result.error_code = OE_ERR_MICRO_DAY_LIMIT;
         result.error_message = "Micro-Mode limit: one entry per server day";
         LogAuditRow("MICRO_MODE_DAY_LIMIT", intent.symbol, 0, result.error_message, "{}");
         return result;
      }
   }
   
   // Apply Micro-Mode risk override for entries
   TradeIntent adjusted_intent = intent;
   if(Equity_IsMicroModeActive() && intent.is_entry)
   {
      // Risk will be recalculated with MicroRiskPct by Risk module
      LogAuditRow("MICRO_MODE_TRADE", intent.symbol, 1, 
                  StringFormat("Entry at %.2f%% risk", MicroRiskPct), "{}");
   }
   
   // Continue with existing validation...
}
```

After a successful entry intent (including pending orders), call `State_MarkMicroEntryServer(TimeCurrent())` when Micro-Mode is active to prevent multiple entries in the same server day. Keep the `OnTradeTransaction` hook as a safety net and add `OE_ERR_MICRO_DAY_LIMIT` to order engine error codes.

### Step 7: Wire into RPEA.mq5

```cpp
// Add inputs
input double TargetProfitPct            = DEFAULT_TargetProfitPct;

// In OnInit():
// Initialize peak tracking
ChallengeState init_st = State_Get();
if(init_st.day_peak_equity <= 0)
{
   init_st.day_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   init_st.overall_peak_equity = init_st.day_peak_equity;
   State_Set(init_st);
}

// Check if already hard-stopped from previous session
if(Equity_IsHardStopped())
{
   g_ctx.permanently_disabled = true;
   PrintFormat("[RPEA] EA is hard-stopped: %s", State_Get().hard_stop_reason);
}

// In OnTimer():
static string s_last_server_date = "";
string current_server_date = TimeUtils_ServerDateString(TimeCurrent());
if(s_last_server_date != "" && s_last_server_date != current_server_date)
{
   Equity_OnServerDayRollover();
}
s_last_server_date = current_server_date;

// Update peak tracking
Equity_UpdatePeakTracking();

// Check Micro-Mode activation
Equity_CheckMicroMode(g_ctx);

// Check giveback protection (Micro-Mode only)
Equity_CheckGivebackProtection();

// Check hard-stop conditions
Equity_CheckHardStopConditions(g_ctx);

// In OnTradeTransaction():
if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
{
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
   {
      // Mark server trade day (idempotent)
      State_MarkTradeDayServer((datetime)trans.time);

      // Track Micro-Mode entry usage per day
      if(Equity_IsMicroModeActive())
         State_MarkMicroEntryServer((datetime)trans.time);
   }
}
```

### Step 8: Update Persistence

In `persistence.mqh`, extend the existing key/value challenge state persistence (keep key order stable, retain existing keys like `gDaysTraded`/`last_counted_server_date`, and default new fields when missing):

```cpp
// Save (append new keys)
FileWrite(h, "micro_mode_activated_at="+(string)st.micro_mode_activated_at);
FileWrite(h, "last_micro_entry_server_date="+(string)st.last_micro_entry_server_date);
FileWrite(h, "hard_stop_reason="+st.hard_stop_reason);
FileWrite(h, "hard_stop_time="+(string)st.hard_stop_time);
FileWrite(h, "hard_stop_equity="+DoubleToString(st.hard_stop_equity,2));
FileWrite(h, "overall_peak_equity="+DoubleToString(st.overall_peak_equity,2));

// Load (parse keys)
else if(k=="micro_mode_activated_at") { st.micro_mode_activated_at = (datetime)StringToInteger(v); parsed_any=true; }
else if(k=="last_micro_entry_server_date") { st.last_micro_entry_server_date = (int)StringToInteger(v); parsed_any=true; }
else if(k=="hard_stop_reason") { st.hard_stop_reason = v; parsed_any=true; }
else if(k=="hard_stop_time") { st.hard_stop_time = (datetime)StringToInteger(v); parsed_any=true; }
else if(k=="hard_stop_equity") { st.hard_stop_equity = StringToDouble(v); parsed_any=true; }
else if(k=="overall_peak_equity") { st.overall_peak_equity = StringToDouble(v); parsed_any=true; }
```

---

## Tests

### New Test File: `Tests/RPEA/test_day_tracking.mqh`

```cpp
#ifndef TEST_DAY_TRACKING_MQH
#define TEST_DAY_TRACKING_MQH

#include <RPEA/timeutils.mqh>
#include <RPEA/state.mqh>

// Test: CEST report date string format
bool TestDay_CestReportDateFormat()
{
   // Setup: Known server time
   // Assert: TimeUtils_CestDateString returns "YYYY.MM.DD" format
}

// Test: Same server-day detection
bool TestDay_ServerSameDayDetection()
{
   // Setup: Two timestamps on same server day
   // Assert: TimeUtils_ServerDateString returns same date
}

// Test: Different server-day detection
bool TestDay_ServerDifferentDayDetection()
{
   // Setup: Two timestamps on different server days
   // Assert: TimeUtils_ServerDateString returns different dates
}

// Test: Trade day marking is idempotent
bool TestDay_TradeDayIdempotent()
{
   // Setup: Reset state, mark trade day twice with same server day
   // Assert: gDaysTraded increments only once
}

// Test: Trade day increments on new server day
bool TestDay_TradeDayIncrements()
{
   // Setup: Mark trade on day 1, then day 2
   // Assert: gDaysTraded == 2
}

// Test: CEST offset applied correctly for reporting
bool TestDay_CestOffsetApplication()
{
   // Setup: Server time 23:30, CEST offset +60 min
   // Assert: CEST report date is next day
}

bool TestDayTracking_RunAll()
{
   bool ok = true;
   ok &= TestDay_CestReportDateFormat();
   ok &= TestDay_ServerSameDayDetection();
   ok &= TestDay_ServerDifferentDayDetection();
   ok &= TestDay_TradeDayIdempotent();
   ok &= TestDay_TradeDayIncrements();
   ok &= TestDay_CestOffsetApplication();
   return ok;
}

#endif // TEST_DAY_TRACKING_MQH
```

### New Test File: `Tests/RPEA/test_micro_mode.mqh`

```cpp
#ifndef TEST_MICRO_MODE_MQH
#define TEST_MICRO_MODE_MQH

#include <RPEA/equity_guardian.mqh>
#include <RPEA/state.mqh>

// Test: Micro-Mode does not activate when gDaysTraded too low
bool TestMicro_NotActivatedLowDays()
{
   // Setup: gDaysTraded = 0, equity at target
   // Assert: Equity_IsMicroModeActive() returns false
}

// Test: Micro-Mode does not activate when equity below threshold
bool TestMicro_NotActivatedLowEquity()
{
   // Setup: gDaysTraded = MinTradeDaysRequired - 1, equity far from target
   // Assert: Equity_IsMicroModeActive() returns false
}

// Test: Micro-Mode activates when both conditions met
bool TestMicro_ActivatesWhenConditionsMet()
{
   // Setup: gDaysTraded = MinTradeDaysRequired - 1, equity near target
   // Call: Equity_CheckMicroMode()
   // Assert: Equity_IsMicroModeActive() returns true
   // Assert: MICRO_MODE_ACTIVATED logged
}

// Test: Micro-Mode risk override
bool TestMicro_RiskOverride()
{
   // Setup: Activate Micro-Mode
   // Assert: Risk_GetEffectiveRiskPct() returns MicroRiskPct
}

// Test: Micro-Mode time stop
bool TestMicro_TimeStop()
{
   // Setup: Activate Micro-Mode, position held > MicroTimeStopMin
   // Assert: Equity_MicroTimeStopExceeded() returns true
}

// Test: Micro-Mode enforces one entry per day
bool TestMicro_OneEntryPerDay()
{
   // Setup: Micro-Mode active, last_micro_entry_server_date = today
   // Call: OrderEngine_SendIntent(entry)
   // Assert: Returns OE_ERR_MICRO_DAY_LIMIT
}

// Test: Hard-stop on overall floor breach
bool TestHardStop_OverallFloorBreach()
{
   // Setup: Equity below overall floor
   // Call: Equity_CheckHardStopConditions()
   // Assert: Equity_IsHardStopped() returns true
   // Assert: HARD_STOP_ACTIVATED logged with reason
}

// Test: Hard-stop on challenge completion
bool TestHardStop_ChallengeComplete()
{
   // Setup: Equity at target, gDaysTraded >= MinTradeDaysRequired
   // Call: Equity_CheckHardStopConditions()
   // Assert: Equity_IsHardStopped() returns true
   // Assert: CHALLENGE_COMPLETE logged
}

// Test: No hard-stop when target hit but days insufficient
bool TestHardStop_TargetPendingDays()
{
   // Setup: Equity at target, gDaysTraded < MinTradeDaysRequired
   // Call: Equity_CheckHardStopConditions()
   // Assert: Equity_IsHardStopped() returns false
   // Assert: TARGET_PENDING_DAYS logged
}

// Test: Order engine rejects when hard-stopped
bool TestHardStop_OrderEngineRejects()
{
   // Setup: Trigger hard-stop
   // Call: OrderEngine_SendIntent()
   // Assert: Returns OE_ERR_HARD_STOPPED
}

// Test: Giveback protection blocks new entries
bool TestGiveback_BlocksNewEntries()
{
   // Setup: Drawdown from peak exceeds GivebackCapDayPct
   // Call: Equity_CheckGivebackProtection()
   // Assert: Equity_IsGivebackProtectionActive() returns true
}

// Test: Peak equity tracking updates
bool TestGiveback_PeakTracking()
{
   // Setup: Equity increases
   // Call: Equity_UpdatePeakTracking()
   // Assert: day_peak_equity updated
}

bool TestMicroMode_RunAll()
{
   bool ok = true;
   ok &= TestMicro_NotActivatedLowDays();
   ok &= TestMicro_NotActivatedLowEquity();
   ok &= TestMicro_ActivatesWhenConditionsMet();
   ok &= TestMicro_RiskOverride();
   ok &= TestMicro_TimeStop();
   ok &= TestMicro_OneEntryPerDay();
   ok &= TestHardStop_OverallFloorBreach();
   ok &= TestHardStop_ChallengeComplete();
   ok &= TestHardStop_TargetPendingDays();
   ok &= TestHardStop_OrderEngineRejects();
   ok &= TestGiveback_BlocksNewEntries();
   ok &= TestGiveback_PeakTracking();
   return ok;
}

#endif // TEST_MICRO_MODE_MQH
```

### Wire into Test Runner

In `Tests/RPEA/run_automated_tests_ea.mq5`:

```cpp
// Add includes
#include "test_day_tracking.mqh"
#include "test_micro_mode.mqh"

// In RunAllTests():
int suiteM4T2a = g_test_reporter.BeginSuite("M4Task2_Day_Tracking");
bool m4t2a_result = TestDayTracking_RunAll();
g_test_reporter.RecordTest(suiteM4T2a, "TestDayTracking_RunAll", m4t2a_result,
                            m4t2a_result ? "day tracking tests passed" : "day tracking tests failed");
g_test_reporter.EndSuite(suiteM4T2a);

int suiteM4T2b = g_test_reporter.BeginSuite("M4Task2_Micro_Mode");
bool m4t2b_result = TestMicroMode_RunAll();
g_test_reporter.RecordTest(suiteM4T2b, "TestMicroMode_RunAll", m4t2b_result,
                            m4t2b_result ? "Micro-Mode tests passed" : "Micro-Mode tests failed");
g_test_reporter.EndSuite(suiteM4T2b);
```

---

## Logging/Telemetry

| Event Type | Symbol | OK | Description | Extra JSON |
|------------|--------|----|-------------|------------|
| `TRADE_DAY_MARKED` | STATE | 1 | "Day 2 of 3" | `{"server_date":"2024.06.15","cest_date":"2024.06.15","days_traded":2}` |
| `MICRO_MODE_ACTIVATED` | EQUITY | 1 | "Equity 10800 near target 10800" | `{"equity":10800,"target":10800,"days_traded":2,"micro_risk_pct":0.10}` |
| `MICRO_MODE_TRADE` | XAUUSD | 1 | "Entry at 0.10% risk" | `{}` |
| `MICRO_MODE_DAY_LIMIT` | XAUUSD | 0 | "Micro-Mode limit: one entry per server day" | `{}` |
| `HARD_STOP_ACTIVATED` | EQUITY | 0 | "Overall floor breach" | `{"equity":9400,"reason":"...","days_traded":2}` |
| `HARD_STOP_REJECTED` | XAUUSD | 0 | "Trading permanently disabled" | `{}` |
| `GIVEBACK_PROTECTION` | EQUITY | 0 | "DD 0.55% from peak 10500" | `{"equity":10442,"peak":10500,"dd_pct":0.55}` |
| `TARGET_PENDING_DAYS` | EQUITY | 1 | "Target hit, need 1 more day" | `{"equity":10800,"days_traded":2,"required":3}` |
| `CHALLENGE_COMPLETE` | EQUITY | 1 | "Target 10800 achieved with 3 days" | `{"equity":10850,"target":10800,"days_traded":3}` |
| `DAY_ROLLOVER_SERVER` | EQUITY | 1 | "Daily peak reset" | `{}` |

---

## Edge Cases & Failure Modes

| Scenario | Handling |
|----------|----------|
| **DST transition** | `ServerToCEST_OffsetMinutes` is user-configured; user must adjust for DST changes manually |
| **Broker server time zone unknown** | User must determine offset empirically; log warning if offset seems wrong |
| **Trade at server midnight boundary** | Use `>=` and `<` comparisons; 00:00:00 belongs to new server day |
| **Multiple trades same day** | Idempotent counting; only first trade increments `gDaysTraded` |
| **EA restart mid-day** | Load persisted `last_counted_server_date`; continue counting correctly |
| **EA restart after hard-stop** | Load `disabled_permanent=true`; immediately disable trading |
| **Micro-Mode with pending orders** | Apply `MicroTimeStopMin` to positions only; pending orders use normal expiry; one-entry-per-day still enforced |
| **Hard-stop during active trade** | Close position immediately regardless of P/L |
| **Giveback during news window** | Giveback protection supersedes news blocking for closes |
| **Weekend gap moves equity** | Update peak on first tick of new session; may trigger giveback |
| **gDaysTraded persistence corruption** | Validate on load; if invalid, set to 0 and log warning |

---

## Acceptance Criteria

| ID | Criterion | Validation |
|----|-----------|------------|
| AC-01 | CEST report date calculated correctly with offset | Test: `TestDay_CestOffsetApplication` |
| AC-02 | Trade days counted idempotently per server day | Test: `TestDay_TradeDayIdempotent` |
| AC-03 | `TRADE_DAY_MARKED` logged on new trade day | Audit log inspection |
| AC-04 | Micro-Mode activates at correct conditions | Test: `TestMicro_ActivatesWhenConditionsMet` |
| AC-05 | Micro-Mode applies `MicroRiskPct` | Test: `TestMicro_RiskOverride` |
| AC-06 | Micro-Mode time stop enforced | Test: `TestMicro_TimeStop` |
| AC-07 | Hard-stop triggers on overall floor breach | Test: `TestHardStop_OverallFloorBreach` |
| AC-08 | Hard-stop triggers on challenge completion | Test: `TestHardStop_ChallengeComplete` |
| AC-09 | Hard-stop persists across restart | Manual test: restart EA after hard-stop |
| AC-10 | Order engine rejects after hard-stop | Test: `TestHardStop_OrderEngineRejects` |
| AC-11 | Giveback protection blocks new entries | Test: `TestGiveback_BlocksNewEntries` |
| AC-12 | Target-pending-days continues in Micro-Mode | Test: `TestHardStop_TargetPendingDays` |
| AC-13 | Micro-Mode enforces one entry per server day | Test: `TestMicro_OneEntryPerDay` |

---

## Out of Scope / Follow-ups

- **Automatic DST detection**: User must configure `ServerToCEST_OffsetMinutes` manually
- **Calendar day visualization**: No UI for displaying trade day calendar
- **Partial day counting**: Only full entry trades count; no partial credit
- **Micro-Mode deactivation**: Once activated, persists until hard-stop (could add equity threshold to deactivate)
- **Hard-stop reversal**: No mechanism to reverse hard-stop; requires manual intervention
- **Broker-specific time zone detection**: Would require broker API integration
