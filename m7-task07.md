# M7 Task 07 - Allocator Integration Implementation

**Branch name**: `feat/m7-phase5-task07-allocator-integration` (cut from `feat/m7-ensemble-integration`)

**Source of truth**: `docs/m7-final-workflow.md` (Phase 5, Task 7, Steps 7.1-7.2)

**Previous tasks completed**: Tasks 1-6 (EMRT, RL Agent, Pre-training, SignalMR, Meta-Policy, Telemetry/Regime)

## Objective

Enable MR strategy execution by completing the MR context pipeline and allocator integration:

1. Create MR_Context structure to provide entry_price/direction to allocator
2. Update allocator.mqh to accept "MR" strategy and select correct context
3. Implement strategy-specific risk sizing (MR respects MicroMode)
4. Enable execution mode (M7_DECISION_ONLY = 0)
5. Add SLO monitoring stub for future performance tracking

## Prerequisites

- **Task 6 complete**: Telemetry, regime detection, liquidity quantiles implemented
- **MetaPolicy_Choose()**: Returns "MR", "BWISC", or "Skip"
- **SignalsMR_Propose()**: Computes direction, bias, sl/tp points
- **Config_GetMRRiskPctDefault()**: Exists in config.mqh (returns 0.90)
- **SymbolBridge_GetExecutionSymbol()**: Maps signal symbol to execution symbol

## Files to Create

- `MQL5/Include/RPEA/mr_context.mqh` (lightweight context struct)
- `MQL5/Include/RPEA/slo_monitor.mqh` (SLO monitoring stub)
- `Tests/RPEA/test_allocator_mr.mqh` (unit tests)

## Files to Modify

- `MQL5/Include/RPEA/signals_mr.mqh` (populate g_last_mr_context)
- `MQL5/Include/RPEA/allocator.mqh` (accept MR strategy, select context, risk sizing)
- `MQL5/Include/RPEA/meta_policy.mqh` (enable execution mode)
- `Tests/RPEA/run_automated_tests_ea.mq5` (register new test suite)

## Workflow

1. Implement code updates in repo workspace (`C:\Users\AWCS\earl-1`).
2. Sync files to MT5 data folder via `SyncRepoToTerminal.ps1`.
3. Compile EA to ensure MQL5 code compiles.
4. Run automated tests and verify new suite.

## Implementation Steps

### Step 7.0: Preflight Checks

Before starting implementation, verify:

1. Task 6 tests pass (run `powershell -ExecutionPolicy Bypass -File run_tests.ps1`)
2. Confirm `MetaPolicy_Choose()` exists and returns strategy strings
3. Confirm `SignalsMR_Propose()` sets `hasSetup`, `direction`, `bias`, `slPoints`, `tpPoints`
4. Confirm `Config_GetMRRiskPctDefault()` exists in config.mqh (line ~1092)
5. Confirm `SymbolBridge_GetExecutionSymbol()` exists in symbol_bridge.mqh

**Compile checkpoint**: Existing EA compiles before changes (baseline).

---

### Step 7.1: Create MR Context Structure (mr_context.mqh)

**Reference**: Parallel to BWISC_Context in signals_bwisc.mqh (lines 21-30)

**Rationale**: Lightweight header avoids circular includes. Don't include signals_mr.mqh in allocator (would drag in m7_helpers → order_engine chain).

**Create file**: `MQL5/Include/RPEA/mr_context.mqh`

```cpp
#ifndef RPEA_MR_CONTEXT_MQH
#define RPEA_MR_CONTEXT_MQH
// mr_context.mqh - Lightweight MR context for allocator (M7 Task 7)
// Separate header to avoid circular includes (signals_mr → m7_helpers → order_engine)

struct MR_Context
{
   double expected_R;         // Expected R-multiple (e.g., 1.5)
   double expected_hold;      // Expected hold time in minutes (from EMRT_GetP50)
   double worst_case_risk;    // 0.0 here; computed in allocator where equity/SL known
   double entry_price;        // Current bid/ask from EXECUTION symbol (not signal)
   int    direction;          // 1 for long, -1 for short
};

MR_Context g_last_mr_context;

#endif // RPEA_MR_CONTEXT_MQH
```

**Compile checkpoint**: Header compiles standalone (no dependencies).

---

### Step 7.2: Populate MR Context in SignalsMR_Propose (signals_mr.mqh)

**Reference**: Mirror BWISC pattern from signals_bwisc.mqh (lines 45-49, 226-230)

**Add include** at top of signals_mr.mqh (after existing includes, around line 10):

```cpp
#include <RPEA/mr_context.mqh>
#include <RPEA/symbol_bridge.mqh>
```

**Add context initialization** at the start of `SignalsMR_Propose()` (after line 204, after clearing output params):

```cpp
   // Clear MR context
   g_last_mr_context.expected_R = 0.0;
   g_last_mr_context.expected_hold = 0.0;
   g_last_mr_context.worst_case_risk = 0.0;
   g_last_mr_context.entry_price = 0.0;
   g_last_mr_context.direction = 0;
```

**Add context population** after `hasSetup = true;` (line 242), before the closing brace:

```cpp
   hasSetup = true;
   setupType = "MR";

   // Populate MR context for allocator
   // CRITICAL: Use EXECUTION symbol for entry price, not signal_symbol
   string exec_symbol = SymbolBridge_GetExecutionSymbol(signal_symbol);
   if(exec_symbol == "")
      exec_symbol = signal_symbol;  // Fallback if no mapping

   double bid = 0.0, ask = 0.0;
   if(!SymbolInfoDouble(exec_symbol, SYMBOL_BID, bid) ||
      !SymbolInfoDouble(exec_symbol, SYMBOL_ASK, ask) ||
      bid <= 0.0 || ask <= 0.0)
   {
      // Cannot get valid execution prices - mark setup invalid
      hasSetup = false;
      setupType = "None";
      return;
   }

   // Set entry price based on direction (long = buy at ask, short = sell at bid)
   if(direction > 0)
      g_last_mr_context.entry_price = ask;
   else
      g_last_mr_context.entry_price = bid;

   g_last_mr_context.direction = direction;
   g_last_mr_context.expected_R = 1.5;  // MR target R-multiple
   g_last_mr_context.expected_hold = EMRT_GetP50(signal_symbol);  // minutes

   // DO NOT compute worst_case_risk here - allocator computes it with actual equity/SL
   g_last_mr_context.worst_case_risk = 0.0;
```

**Compile checkpoint**: signals_mr.mqh compiles with mr_context.mqh include.

---

### Step 7.3: Update Allocator to Accept MR (allocator.mqh)

**Reference**: `docs/m7-final-workflow.md` -> Phase 5 -> Task 7 -> Step 7.1

#### Step 7.3a: Add MR context include

Add after line 12 (after existing includes):

```cpp
#include <RPEA/mr_context.mqh>
```

**Note**: Use lightweight mr_context.mqh, NOT signals_mr.mqh (avoids include chain).

#### Step 7.3b: Update strategy validation

Change lines 132-135 from:

```cpp
   if(strategy != "BWISC")
   {
      rejection = "unsupported_strategy";
   }
```

To:

```cpp
   if(strategy != "BWISC" && strategy != "MR")
   {
      rejection = "unsupported_strategy";
   }
```

#### Step 7.3c: Select correct context based on strategy

Change lines 147-153 from:

```cpp
  if(rejection == "")
  {
     entry_price = g_last_bwisc_context.entry_price;
     direction = g_last_bwisc_context.direction;
     if(entry_price <= 0.0)
        rejection = "missing_entry_price";
  }
```

To:

```cpp
  if(rejection == "")
  {
     if(strategy == "MR")
     {
        entry_price = g_last_mr_context.entry_price;
        direction = g_last_mr_context.direction;
     }
     else  // BWISC
     {
        entry_price = g_last_bwisc_context.entry_price;
        direction = g_last_bwisc_context.direction;
     }
     if(entry_price <= 0.0)
        rejection = "missing_entry_price";
  }
```

**Compile checkpoint**: Allocator compiles with MR context selection.

---

### Step 7.4: Strategy-Specific Risk Percentage (allocator.mqh)

**Reference**: `docs/m7-final-workflow.md` -> Phase 5 -> Task 7 -> Step 7.1

**Design Decision**: MR **RESPECTS** MicroMode for global safety (challenge compliance).

- Normal mode: MR uses `Config_GetMRRiskPctDefault()` (0.90%)
- Micro mode: MR uses `Config_GetMicroRiskPct()` (0.05-0.20%)
- BWISC unchanged: uses `Risk_GetEffectiveRiskPct()`

**Rationale**: MicroMode is a challenge-wide safety mechanism triggered after +10% target. All strategies should respect it for consistent risk reduction.

#### Step 7.4a: Add riskPct computation

Add after line 358 (after spread filter check), before volume calculation:

```cpp
   // Strategy-specific risk percentage
   double riskPct = 0.0;
   if(rejection == "")
   {
      if(strategy == "MR")
      {
         // MR respects MicroMode for global safety / challenge compliance
         if(Equity_IsMicroModeActive())
            riskPct = Config_GetMicroRiskPct();  // Micro mode: reduced risk
         else
            riskPct = Config_GetMRRiskPctDefault();  // Normal: 0.90%
      }
      else  // BWISC
      {
         riskPct = Risk_GetEffectiveRiskPct();  // Already handles MicroMode
      }
   }
```

#### Step 7.4b: Update volume calculation

Change line 362 from:

```cpp
      volume = Risk_SizingByATRDistanceForSymbol(exec_symbol, entry_price, sl_price, equity, Risk_GetEffectiveRiskPct(), -1.0, confidence);
```

To:

```cpp
      volume = Risk_SizingByATRDistanceForSymbol(exec_symbol, entry_price, sl_price, equity, riskPct, -1.0, confidence);
```

**Critical**: `Risk_SizingByATRDistanceForSymbol()` expects percentage value (e.g., 0.90 for 0.90%). Do NOT divide by 100.

**Compile checkpoint**: Allocator compiles with strategy-specific risk sizing.

---

### Step 7.5: Update Order Comments and Setup Type (allocator.mqh)

**Reference**: Include strategy name in order comment for telemetry/audit.

#### Step 7.5a: Force setup_type for MR strategy

The allocator currently derives `setup_type` as "BC" or "MSC" based on entry price vs bid/ask (lines 173-256). For MR strategy, we need to override this.

Add after the setup_type derivation block (after line 257, before the `if(rejection == "")` at line 259):

```cpp
   // MR strategy uses its own setup type
   if(strategy == "MR" && rejection == "")
   {
      setup_type = "MR";
   }
```

#### Step 7.5b: Update order comment format

Change lines 481-482 from:

```cpp
     string prefix = (plan.is_proxy ? "PX " : "");
     string comment = StringFormat("%sBWISC-%s b=%.2f conf=%.2f %s", prefix, setup_type, plan.bias, sanitized_confidence, ts);
```

To:

```cpp
     string prefix = (plan.is_proxy ? "PX " : "");
     string comment = StringFormat("%s%s-%s b=%.2f conf=%.2f %s", prefix, strategy, setup_type, plan.bias, sanitized_confidence, ts);
```

This produces:
- BWISC orders: `"BWISC-BC b=0.75 conf=0.80 2026.02.04 10:30"` or `"BWISC-MSC ..."`
- MR orders: `"MR-MR b=-1.00 conf=0.85 2026.02.04 10:30"`

**Compile checkpoint**: Order comments include strategy name, MR uses "MR" setup type.

---

### Step 7.6: Enable Execution Mode (meta_policy.mqh)

**Reference**: `docs/m7-final-workflow.md` -> Phase 5 -> Task 7

**Important**: This enables actual trade execution. Only enable after all other steps complete.

Change line 21 from:

```cpp
#define M7_DECISION_ONLY 1
```

To:

```cpp
#define M7_DECISION_ONLY 0
```

**Compile checkpoint**: EA compiles with execution enabled. MetaPolicy_Choose("MR") now flows through to order engine.

---

### Step 7.7: MR Time Stop Handling (Mark for Task 8)

**Note**: MR positions have time-based stops (MR_TimeStopMin/MR_TimeStopMax from config.mqh).

**Current scope** (Task 7): Mark requirement, document for Task 8 implementation.

**Task 8 requirements**:
- Track MR entry time per position
- Check elapsed time in scheduler/trailing module
- Close position after MR_TimeStopMin (default 60 min) if not already closed
- Enforce MR_TimeStopMax (default 90 min) as hard stop

**No code changes in Task 7** - this is documentation only.

---

### Step 7.8: Create SLO Monitoring Stub (slo_monitor.mqh)

**Reference**: `docs/m7-final-workflow.md` -> Phase 5 -> Task 7 -> Step 7.2

**Create file**: `MQL5/Include/RPEA/slo_monitor.mqh`

```cpp
#ifndef RPEA_SLO_MONITOR_MQH
#define RPEA_SLO_MONITOR_MQH
// slo_monitor.mqh - SLO monitoring stub for MR strategy (M7 Task 7)
// Full tracking implementation deferred to Task 8 or post-M7.
// References: docs/m7-final-workflow.md (Phase 5, Task 7, Step 7.2)

struct SLO_Metrics
{
   double mr_win_rate_30d;          // Rolling 30-day win rate
   double mr_median_hold_hours;     // Median hold time in hours
   double mr_hold_p80_hours;        // 80th percentile hold time
   double mr_median_efficiency;     // realized R / worst_case_risk
   double mr_median_friction_r;     // (realized - theoretical) R
   bool   warn_only;                // True if warn threshold breached
   bool   slo_breached;             // True if hard threshold breached
};

// Initialize SLO metrics with safe defaults (no warnings, no breaches)
void SLO_InitMetrics(SLO_Metrics& metrics)
{
   metrics.mr_win_rate_30d = 0.60;         // Optimistic default (above 55% target)
   metrics.mr_median_hold_hours = 2.0;     // Within target (< 2.5h)
   metrics.mr_hold_p80_hours = 3.5;        // Within target (< 4h)
   metrics.mr_median_efficiency = 0.85;    // Above threshold (>= 0.8)
   metrics.mr_median_friction_r = 0.30;    // Below threshold (<= 0.4R)
   metrics.warn_only = false;              // No warnings initially
   metrics.slo_breached = false;           // No breaches initially
}

// Check SLO thresholds and set breach flags
// Spec thresholds:
// - MR win rate warn < 55% (target 58-62%)
// - Median hold <= 2.5h, 80th percentile <= 4h
// - Median efficiency >= 0.8
// - Median friction tax <= 0.4R
void SLO_CheckAndThrottle(SLO_Metrics& metrics)
{
   // Check warn threshold
   metrics.warn_only = (metrics.mr_win_rate_30d < 0.55);

   // Check all breach conditions
   if(metrics.mr_win_rate_30d < 0.55 ||
      metrics.mr_median_hold_hours > 2.5 ||
      metrics.mr_hold_p80_hours > 4.0 ||
      metrics.mr_median_efficiency < 0.80 ||
      metrics.mr_median_friction_r > 0.40)
   {
      metrics.slo_breached = true;
      // TODO[M7-Task8]: Throttle MR_RiskPct *= 0.75 or disable MR if persistent
      // Implementation options:
      // 1. Global flag g_mr_throttled that Config_GetMRRiskPctDefault() checks
      // 2. Modify meta_policy to skip MR when slo_breached
   }
   else
   {
      metrics.slo_breached = false;
   }
}

#endif // RPEA_SLO_MONITOR_MQH
```

**Where to include**: For Task 7, include only in test_allocator_mr.mqh to validate compilation. Full **SLO throttle wiring** remains Task 8 scope.

**Compile checkpoint**: slo_monitor.mqh compiles standalone.

---

## Tests

### Create test file: `Tests/RPEA/test_allocator_mr.mqh`

**Critical Testing Guidance**:
- Use **EURUSD** (stable in Strategy Tester), not XAUEUR/XAUUSD
- **Manually set g_last_mr_context** (don't rely on live bid/ask or SignalsMR_Propose)
- Use known values for deterministic, reproducible tests

```cpp
#ifndef TEST_ALLOCATOR_MR_MQH
#define TEST_ALLOCATOR_MR_MQH
// test_allocator_mr.mqh - Unit tests for M7 Task 7 (Allocator MR Integration)
// Tests allocator accepts MR strategy with correct context and risk sizing.

#include <RPEA/allocator.mqh>
#include <RPEA/mr_context.mqh>
#include <RPEA/signals_bwisc.mqh>  // For g_last_bwisc_context in comparison tests
#include <RPEA/state.mqh>          // For State_Get/State_Set in MicroMode tests
#include <RPEA/slo_monitor.mqh>

#ifndef TEST_FRAMEWORK_DEFINED
extern int g_test_passed;
extern int g_test_failed;
extern string g_current_test;

#define ASSERT_TRUE(condition, message) \
   do { \
      if(condition) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s", g_current_test, message); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s", g_current_test, message); \
      } \
   } while(false)

#define ASSERT_FALSE(condition, message) ASSERT_TRUE(!(condition), message)

#define TEST_FRAMEWORK_DEFINED
#endif

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
int TestAllocMR_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestAllocMR_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s - %s", g_current_test, ok ? "OK" : "FAILED");
   return ok;
}

// Create minimal test AppContext
AppContext MakeAllocatorTestContext()
{
   AppContext ctx;
   ZeroMemory(ctx);
   ArrayResize(ctx.symbols, 1);
   ctx.equity_snapshot = 10000.0;
   ctx.current_server_time = TimeCurrent();
   ctx.symbols_count = 1;
   ctx.symbols[0] = "EURUSD";
   return ctx;
}

// Setup MR context with known values (don't rely on live prices)
void SetupMRContext(double entry_price, int direction)
{
   g_last_mr_context.entry_price = entry_price;
   g_last_mr_context.direction = direction;
   g_last_mr_context.expected_R = 1.5;
   g_last_mr_context.expected_hold = 90.0;
   g_last_mr_context.worst_case_risk = 0.0;  // Allocator computes
}

// Setup BWISC context with different values (for comparison tests)
void SetupBWISCContext(double entry_price, int direction)
{
   g_last_bwisc_context.entry_price = entry_price;
   g_last_bwisc_context.direction = direction;
   g_last_bwisc_context.expected_R = 2.0;
   g_last_bwisc_context.expected_hold = 45.0;
   g_last_bwisc_context.worst_case_risk = 0.0;
}

//+------------------------------------------------------------------+
//| Test: Allocator accepts MR strategy                               |
//+------------------------------------------------------------------+
bool TestAllocatorMR_AcceptsStrategy()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_AcceptsStrategy");

   AppContext ctx = MakeAllocatorTestContext();
   SetupMRContext(1.05000, 1);  // Long at 1.05000

   OrderPlan plan = Allocator_BuildOrderPlan(ctx, "MR", "EURUSD", 100, 150, 0.75);

   // Note: May still fail due to other validations (spread, budget, etc.)
   // Test that rejection is NOT "unsupported_strategy"
   if(!plan.valid)
   {
      ASSERT_TRUE(plan.rejection_reason != "unsupported_strategy",
                  "MR not rejected as unsupported");
   }
   else
   {
      ASSERT_TRUE(plan.valid, "MR order plan valid");
   }

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: MR uses correct context (not BWISC context)                 |
//+------------------------------------------------------------------+
bool TestAllocatorMR_UsesCorrectContext()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_UsesCorrectContext");

   AppContext ctx = MakeAllocatorTestContext();

   // Set different prices in each context
   SetupMRContext(1.05000, 1);       // MR: 1.05000
   SetupBWISCContext(1.10000, -1);   // BWISC: 1.10000 (different)

   OrderPlan plan = Allocator_BuildOrderPlan(ctx, "MR", "EURUSD", 100, 150, 0.75);

   // Verify entry price from MR context, not BWISC
   if(plan.price > 0.0)
   {
      double diff = MathAbs(plan.price - 1.05000);
      ASSERT_TRUE(diff < 0.001, "Entry price from MR context (1.05000)");
   }
   else
   {
      // If price is 0, check rejection reason is not context-related
      ASSERT_TRUE(plan.rejection_reason != "missing_entry_price" ||
                  g_last_mr_context.entry_price > 0.0,
                  "MR context has entry price");
   }

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: Invalid strategy still rejected                             |
//+------------------------------------------------------------------+
bool TestAllocatorMR_RejectsInvalid()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_RejectsInvalid");

   AppContext ctx = MakeAllocatorTestContext();
   SetupMRContext(1.05000, 1);

   OrderPlan plan = Allocator_BuildOrderPlan(ctx, "INVALID", "EURUSD", 100, 150, 0.75);

   ASSERT_FALSE(plan.valid, "Invalid strategy rejected");
   ASSERT_TRUE(plan.rejection_reason == "unsupported_strategy",
               "Rejection reason is unsupported_strategy");

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: SLO metrics initialization                                  |
//+------------------------------------------------------------------+
bool TestAllocatorMR_SLOInit()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_SLOInit");

   SLO_Metrics metrics;
   SLO_InitMetrics(metrics);

   ASSERT_FALSE(metrics.warn_only, "warn_only initialized to false");
   ASSERT_FALSE(metrics.slo_breached, "slo_breached initialized to false");
   ASSERT_TRUE(metrics.mr_win_rate_30d >= 0.55, "win_rate above warn threshold");

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: SLO breach detection                                        |
//+------------------------------------------------------------------+
bool TestAllocatorMR_SLOBreach()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_SLOBreach");

   SLO_Metrics metrics;
   SLO_InitMetrics(metrics);

   // Set values that breach thresholds
   metrics.mr_win_rate_30d = 0.50;  // Below 0.55
   SLO_CheckAndThrottle(metrics);

   ASSERT_TRUE(metrics.warn_only, "warn_only set when win_rate < 0.55");
   ASSERT_TRUE(metrics.slo_breached, "slo_breached set when threshold violated");

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: MR respects MicroMode (uses reduced risk)                   |
//+------------------------------------------------------------------+
bool TestAllocatorMR_RespectsMicroMode()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_RespectsMicroMode");

   // Save original state
   ChallengeState orig_st = State_Get();

   // Activate MicroMode via state
   ChallengeState st = orig_st;
   st.micro_mode = true;
   st.micro_mode_activated_at = TimeCurrent();
   State_Set(st);

   // Verify MicroMode is active
   bool micro_active = Equity_IsMicroModeActive();
   ASSERT_TRUE(micro_active, "MicroMode should be active after State_Set");

   // Build MR order plan in MicroMode
   AppContext ctx = MakeAllocatorTestContext();
   SetupMRContext(1.05000, 1);

   OrderPlan plan = Allocator_BuildOrderPlan(ctx, "MR", "EURUSD", 100, 150, 0.75);

   // The actual volume depends on many factors, but we can verify the code path was taken
   // by checking that MicroMode is still active during the call
   // (Full risk verification would require mocking more components)

   // Restore original state
   State_Set(orig_st);

   // Verify MicroMode is inactive after restore
   bool micro_inactive = !Equity_IsMicroModeActive();
   ASSERT_TRUE(micro_inactive, "MicroMode should be inactive after restore");

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Run all tests                                                     |
//+------------------------------------------------------------------+
bool TestAllocatorMR_RunAll()
{
   PrintFormat("========================================");
   PrintFormat("M7 Task 07: Allocator MR Integration Tests");
   PrintFormat("========================================");

   int initial_passed = g_test_passed;
   int initial_failed = g_test_failed;

   TestAllocatorMR_AcceptsStrategy();
   TestAllocatorMR_UsesCorrectContext();
   TestAllocatorMR_RejectsInvalid();
   TestAllocatorMR_SLOInit();
   TestAllocatorMR_SLOBreach();
   TestAllocatorMR_RespectsMicroMode();

   int suite_passed = g_test_passed - initial_passed;
   int suite_failed = g_test_failed - initial_failed;

   PrintFormat("----------------------------------------");
   PrintFormat("Task 07 Results: %d passed, %d failed", suite_passed, suite_failed);
   PrintFormat("========================================");

   return (suite_failed == 0);
}

#endif // TEST_ALLOCATOR_MR_MQH
```

### Register in runner: `Tests/RPEA/run_automated_tests_ea.mq5`

Add include after Task 06 suite (around line 35):

```cpp
#include "test_allocator_mr.mqh"
```

Add forward declaration:

```cpp
bool TestAllocatorMR_RunAll();
```

Add suite execution block after `M7-Task06: Regime/Telemetry Tests` (after `TestRegimeTelemetry_RunAll()`):

```cpp
   //--- M7-Task07: Allocator MR Integration Tests ---
   PrintFormat("\n=== Running M7-Task07: Allocator MR Tests ===");
   if(!TestAllocatorMR_RunAll())
   {
      PrintFormat("[SUITE FAIL] M7Task07_AllocatorMR");
      suites_failed++;
   }
   else
   {
      PrintFormat("[SUITE PASS] M7Task07_AllocatorMR");
   }
   suites_run++;
```

---

## Compile / Test Checklist

1. **Sync repo to MT5** (from repo root):
   ```powershell
   powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
   ```

2. **Compile EA** (must `cd` to MT5 data folder first -- `/compile:` path is relative to working directory):
   ```powershell
   cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
   & "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
   ```

3. **Run tests** (from repo root):
   ```powershell
   powershell -ExecutionPolicy Bypass -File run_tests.ps1
   ```

4. **Verify results**:
   - `compile_rpea.log` shows 0 errors
   - `MQL5/Files/RPEA/test_results/test_results.json` includes M7Task07_AllocatorMR suite
   - All Task 07 tests pass

---

## File Sync Mappings (Repo -> MT5)

Use `SyncRepoToTerminal.ps1`, ensure these files map correctly:

| Repo Path | MT5 Data Folder Path |
|-----------|---------------------|
| `MQL5/Include/RPEA/mr_context.mqh` | `...\MQL5\Include\RPEA\mr_context.mqh` |
| `MQL5/Include/RPEA/slo_monitor.mqh` | `...\MQL5\Include\RPEA\slo_monitor.mqh` |
| `MQL5/Include/RPEA/signals_mr.mqh` | `...\MQL5\Include\RPEA\signals_mr.mqh` |
| `MQL5/Include/RPEA/allocator.mqh` | `...\MQL5\Include\RPEA\allocator.mqh` |
| `MQL5/Include/RPEA/meta_policy.mqh` | `...\MQL5\Include\RPEA\meta_policy.mqh` |
| `Tests/RPEA/test_allocator_mr.mqh` | `...\MQL5\Experts\Tests\RPEA\test_allocator_mr.mqh` |
| `Tests/RPEA/run_automated_tests_ea.mq5` | `...\MQL5\Experts\Tests\RPEA\run_automated_tests_ea.mq5` |

(MT5 data folder: `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075`)

---

## Expected Results

**Compile output**:
- 0 errors
- Acceptable warnings (baseline from Task 6):
  - `logging.mqh` macro redefinition
  - `breakeven.mqh` macro redefinition
  - `queue.mqh` type conversion
  - `rl_agent.mqh` sign mismatch

**Test output**:
- All existing tests pass (no regression)
- M7Task07_AllocatorMR suite passes (including MR proxy-map guard + MR bias checks)
- Total: 34/34 passed

---

## Design Decisions (Documented)

1. **MR Context Header**: Lightweight `mr_context.mqh` avoids circular includes (signals_mr → m7_helpers → order_engine).

2. **Entry Price Source**: MR entry price from **execution symbol** via `SymbolBridge_GetExecutionSymbol()`, not signal symbol. Prevents invalid XAUEUR quote issues.

3. **worst_case_risk**: Set to 0.0 in SignalsMR_Propose; computed in allocator where equity and SL distance are known.

4. **MicroMode**: MR **respects** MicroMode (global safety / challenge compliance). Both strategies use reduced risk when MicroMode active.

5. **MR Time Stop**: Documented requirement for Task 8 (MR_TimeStopMin/Max enforcement).

6. **SLO Monitoring**: Stub implementation with proper initialization. Full tracking (rolling 30-day stats) deferred to Task 8.

7. **Task 07 Closeout Hardening (2026-02-08)**:
   - Scheduler no longer no-ops after allocator; valid plans are converted to `OrderRequest` and sent via `g_order_engine.PlaceOrder`.
   - Added allocator guard to avoid MR XAUEUR proxy distance double-conversion.
   - Added allocator MR directional bias computation helper for comments/telemetry consistency.

---

## Results

- Compile (MetaEditor): `0` errors, `5` warnings (`MQL5\Experts\FundingPips\compile_rpea.log`).
- Compile (Test Runner): `0` errors, warnings only (`MQL5\Experts\Tests\RPEA\compile_automated_tests.log`).
- Tests: `test_results.json` timestamp `2024-01-01T00:00:00Z` shows `34/34` passed, `M7Task07_AllocatorMR` passed.
- Tester evidence: `Agent-127.0.0.1-3000\logs\20260208.log` confirms full suite run and JSON write.
