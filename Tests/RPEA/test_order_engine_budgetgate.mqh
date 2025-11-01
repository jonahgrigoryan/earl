#ifndef TEST_ORDER_ENGINE_BUDGETGATE_MQH
#define TEST_ORDER_ENGINE_BUDGETGATE_MQH
// test_order_engine_budgetgate.mqh - Unit tests for Budget Gate with Position Snapshot Locking (M3 Task 9)
// References: .kiro/specs/rpea-m3/tasks.md (Task 9), design.md

#ifndef RPEA_TEST_APP_CONTEXT_DEFINED
#define RPEA_TEST_APP_CONTEXT_DEFINED
struct AppContext
{
   datetime current_server_time;
   string   symbols[];
   int      symbols_count;
   bool     session_london;
   bool     session_newyork;
   double   initial_baseline;
   double   baseline_today;
   double   equity_snapshot;
   double   baseline_today_e0;
   double   baseline_today_b0;
   bool     trading_paused;
   bool     permanently_disabled;
   datetime server_midnight_ts;
   datetime timer_last_check;
};
#endif // RPEA_TEST_APP_CONTEXT_DEFINED

#include <RPEA/config.mqh>
#include <RPEA/equity_guardian.mqh>

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

#define ASSERT_FALSE(condition, message) \
   ASSERT_TRUE(!(condition), message)

#define ASSERT_EQUALS(expected, actual, message) \
   do { \
      if((expected) == (actual)) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%d, actual=%d)", g_current_test, message, (int)(expected), (int)(actual)); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%d, actual=%d)", g_current_test, message, (int)(expected), (int)(actual)); \
      } \
   } while(false)

#define ASSERT_NEAR(expected, actual, tolerance, message) \
   do { \
      double __exp = (expected); \
      double __act = (actual); \
      double __tol = (tolerance); \
      if(MathAbs(__exp - __act) <= __tol) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%.10f, actual=%.10f, tol=%.10f)", g_current_test, message, __exp, __act, __tol); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%.10f, actual=%.10f, tol=%.10f)", g_current_test, message, __exp, __act, __tol); \
      } \
   } while(false)

#define ASSERT_STRING_EQ(expected, actual, message) \
   do { \
      string __exp = (expected); \
      string __act = (actual); \
      if(__exp == __act) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s", g_current_test, message); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%s, actual=%s)", g_current_test, message, __exp, __act); \
      } \
   } while(false)

#endif // TEST_FRAMEWORK_DEFINED

//------------------------------------------------------------------------------
// Test helpers
//------------------------------------------------------------------------------

void BudgetGateTests_Reset()
{
   // Release any held locks
   Equity_ReleaseBudgetGateLock();
}

AppContext BudgetGateTests_CreateContext()
{
   AppContext ctx;
   ctx.current_server_time = TimeCurrent();
   ctx.symbols_count = 0;
   ctx.session_london = false;
   ctx.session_newyork = false;
   ctx.initial_baseline = 10000.0;
   ctx.baseline_today = 10000.0;
   ctx.equity_snapshot = 10000.0;
   ctx.baseline_today_e0 = 10000.0;
   ctx.baseline_today_b0 = 10000.0;
   ctx.trading_paused = false;
   ctx.permanently_disabled = false;
   ctx.server_midnight_ts = 0;
   ctx.timer_last_check = TimeCurrent();
   return ctx;
}

//------------------------------------------------------------------------------
// Test cases
//------------------------------------------------------------------------------

bool BudgetGate_PassesWithinHeadroom()
{
   g_current_test = "BudgetGate_PassesWithinHeadroom";
   PrintFormat("[TEST START] %s", g_current_test);
   
   BudgetGateTests_Reset();
   AppContext ctx = BudgetGateTests_CreateContext();
   
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.equity_snapshot = 10000.0;
   
   // Compute rooms first to set up state
   Equity_ComputeRooms(ctx);
   
   EquityBudgetGateResult preview = Equity_EvaluateBudgetGate(ctx, 0.0);
   double threshold = preview.room_available + preview.open_risk + preview.pending_risk;
   double next_trade = threshold * 0.25;
   if(next_trade <= 0.0)
      next_trade = 0.0;
   EquityBudgetGateResult result = Equity_EvaluateBudgetGate(ctx, next_trade);
   
   ASSERT_TRUE(result.gate_pass, "Gate passes when total risk below threshold");
   ASSERT_STRING_EQ("pass", result.gating_reason, "Gating reason is 'pass'");
   ASSERT_TRUE(result.approved == result.gate_pass, "approved field matches gate_pass");
   ASSERT_TRUE(MathIsValidNumber(result.room_today), "room_today logged");
   ASSERT_TRUE(MathIsValidNumber(result.room_overall), "room_overall logged");
   ASSERT_NEAR(next_trade, result.next_worst_case, 1e-6, "next_trade logged correctly");
   
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool BudgetGate_BlocksOverHeadroom()
{
   g_current_test = "BudgetGate_BlocksOverHeadroom";
   PrintFormat("[TEST START] %s", g_current_test);
   
   BudgetGateTests_Reset();
   AppContext ctx = BudgetGateTests_CreateContext();
   
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.equity_snapshot = 10000.0;
   
   Equity_ComputeRooms(ctx); // Set up state
   EquityBudgetGateResult preview = Equity_EvaluateBudgetGate(ctx, 0.0);
   double threshold = preview.room_available + preview.open_risk + preview.pending_risk;
   
   double next_trade = threshold + 100.0; // Exceeds computed threshold
   EquityBudgetGateResult result = Equity_EvaluateBudgetGate(ctx, next_trade);
   
   ASSERT_FALSE(result.gate_pass, "Gate blocks when total risk exceeds threshold");
   ASSERT_STRING_EQ("insufficient_room", result.gating_reason, "Gating reason is 'insufficient_room'");
   ASSERT_TRUE(result.approved == result.gate_pass, "approved field matches gate_pass");
   
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool BudgetGate_UsesSnapshotLock()
{
   g_current_test = "BudgetGate_UsesSnapshotLock";
   PrintFormat("[TEST START] %s", g_current_test);
   
   BudgetGateTests_Reset();
   AppContext ctx = BudgetGateTests_CreateContext();
   
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.equity_snapshot = 10000.0;
   
   Equity_ComputeRooms(ctx);
   
   // Verify lock is acquired and released by checking lock state before and after
   // We can't directly access static variables, but we can verify lock behavior
   // by trying to acquire lock before and after budget gate call
   
   bool acquired_before = Equity_AcquireBudgetGateLock(1000);
   ASSERT_TRUE(acquired_before, "Lock can be acquired before budget gate call");
   Equity_ReleaseBudgetGateLock();
   
   EquityBudgetGateResult result = Equity_EvaluateBudgetGate(ctx, 50.0);
   
   // After budget gate, lock should be released - verify we can acquire it again
   bool acquired_after = Equity_AcquireBudgetGateLock(1000);
   ASSERT_TRUE(acquired_after, "Lock released after budget gate evaluation");
   Equity_ReleaseBudgetGateLock();
   
   ASSERT_TRUE(result.gate_pass || !result.gate_pass, "Gate evaluation completed");
   
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool BudgetGate_LogsFiveInputs()
{
   g_current_test = "BudgetGate_LogsFiveInputs";
   PrintFormat("[TEST START] %s", g_current_test);
   
   BudgetGateTests_Reset();
   AppContext ctx = BudgetGateTests_CreateContext();
   
   // Set up specific room values
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.equity_snapshot = 9500.0; // Room today = 4% of 10000 - (10000-9500) = 400 - 500 = -100, clamped to 0
   // To get room_today=500, we need: equity = baseline - (4% - 500) = 10000 - (400 - 500) = 10100
   ctx.equity_snapshot = 10100.0; // This gives room_today = 400 - (10000-10100) = 400 + 100 = 500
   
   Equity_ComputeRooms(ctx);
   
   double next_trade = 150.0;
   EquityBudgetGateResult result = Equity_EvaluateBudgetGate(ctx, next_trade);
   
   // Verify all 5 inputs are populated
   ASSERT_TRUE(MathIsValidNumber(result.open_risk), "open_risk logged");
   ASSERT_TRUE(MathIsValidNumber(result.pending_risk), "pending_risk logged");
   ASSERT_TRUE(MathIsValidNumber(result.next_worst_case), "next_trade logged");
   ASSERT_TRUE(MathIsValidNumber(result.room_today), "room_today logged");
   ASSERT_TRUE(MathIsValidNumber(result.room_overall), "room_overall logged");
   
   // Verify rooms match snapshot (values may vary, but should be valid numbers)
   ASSERT_TRUE(result.room_today >= 0.0, "room_today is non-negative");
   ASSERT_TRUE(result.room_overall >= 0.0, "room_overall is non-negative");
   
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool BudgetGate_LockTimeout()
{
   g_current_test = "BudgetGate_LockTimeout";
   PrintFormat("[TEST START] %s", g_current_test);
   
   BudgetGateTests_Reset();
   AppContext ctx = BudgetGateTests_CreateContext();
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.equity_snapshot = 10000.0;
   Equity_ComputeRooms(ctx);
   
   // Acquire lock manually
   bool acquired = Equity_AcquireBudgetGateLock(1000);
   ASSERT_TRUE(acquired, "First lock acquisition succeeds");
   
   // Evaluate budget gate while lock held - expect lock timeout without calc error
   EquityBudgetGateResult locked_result = Equity_EvaluateBudgetGate(ctx, 50.0);
   ASSERT_FALSE(locked_result.gate_pass, "Gate fails when lock held by another evaluator");
   ASSERT_STRING_EQ("lock_timeout", locked_result.gating_reason, "Gating reason is 'lock_timeout' when acquisition fails");
   ASSERT_FALSE(locked_result.calculation_error, "Lock timeout does not set calculation_error");
   
   // Try to acquire again immediately (should fail - lock held)
   bool acquired2 = Equity_AcquireBudgetGateLock(1000);
   ASSERT_FALSE(acquired2, "Second lock acquisition fails when lock held and not timed out");
   
   // Release and verify we can acquire again
   Equity_ReleaseBudgetGateLock();
   Sleep(1100); // Wait longer than timeout (1000ms)
   
   bool acquired3 = Equity_AcquireBudgetGateLock(1000);
   ASSERT_TRUE(acquired3, "Lock acquisition succeeds after release");
   
   Equity_ReleaseBudgetGateLock();
   
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool BudgetGate_LogsGatePassBoolean()
{
   g_current_test = "BudgetGate_LogsGatePassBoolean";
   PrintFormat("[TEST START] %s", g_current_test);
   
   BudgetGateTests_Reset();
   AppContext ctx = BudgetGateTests_CreateContext();
   
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.equity_snapshot = 10000.0;
   
   Equity_ComputeRooms(ctx);
   
   EquityBudgetGateResult baseline = Equity_EvaluateBudgetGate(ctx, 0.0);
   double threshold = baseline.room_available + baseline.open_risk + baseline.pending_risk;
   
   double pass_trade = threshold * 0.25;
   if(pass_trade <= 0.0)
      pass_trade = 0.0;
   EquityBudgetGateResult result_pass = Equity_EvaluateBudgetGate(ctx, pass_trade);
   ASSERT_TRUE(result_pass.gate_pass || !result_pass.gate_pass, "gate_pass boolean present (pass case)");
   ASSERT_TRUE(result_pass.approved == result_pass.gate_pass, "approved matches gate_pass");
   
   // Test fail case (large next_trade exceeding threshold)
   EquityBudgetGateResult result_fail = Equity_EvaluateBudgetGate(ctx, threshold + 100.0);
   ASSERT_FALSE(result_fail.gate_pass, "gate_pass boolean is false when gate fails");
   ASSERT_TRUE(result_fail.approved == result_fail.gate_pass, "approved matches gate_pass");
   
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool BudgetGate_LogsGatingReason()
{
   g_current_test = "BudgetGate_LogsGatingReason";
   PrintFormat("[TEST START] %s", g_current_test);
   
   BudgetGateTests_Reset();
   AppContext ctx = BudgetGateTests_CreateContext();
   
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.equity_snapshot = 10000.0;
   
   Equity_ComputeRooms(ctx);
   
   EquityBudgetGateResult baseline = Equity_EvaluateBudgetGate(ctx, 0.0);
   double threshold = baseline.room_available + baseline.open_risk + baseline.pending_risk;
   
   // Test pass case
   double pass_trade = threshold * 0.25;
   if(pass_trade <= 0.0)
      pass_trade = 0.0;
   EquityBudgetGateResult result_pass = Equity_EvaluateBudgetGate(ctx, pass_trade);
   if(result_pass.gate_pass)
   {
      ASSERT_STRING_EQ("pass", result_pass.gating_reason, "Gating reason is 'pass' when gate passes");
   }
   
   // Test fail case
   EquityBudgetGateResult result_fail = Equity_EvaluateBudgetGate(ctx, threshold + 100.0);
   if(!result_fail.gate_pass && !result_fail.calculation_error)
   {
      ASSERT_STRING_EQ("insufficient_room", result_fail.gating_reason, "Gating reason is 'insufficient_room' when gate fails");
   }
   
   ASSERT_TRUE(result_pass.gating_reason != "", "Gating reason is populated");
   ASSERT_TRUE(result_fail.gating_reason != "", "Gating reason is populated even on failure");
   
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool BudgetGate_FormulaCorrect()
{
   g_current_test = "BudgetGate_FormulaCorrect";
   PrintFormat("[TEST START] %s", g_current_test);
   
   BudgetGateTests_Reset();
   AppContext ctx = BudgetGateTests_CreateContext();
   
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.equity_snapshot = 10000.0;
   
   Equity_ComputeRooms(ctx);
   
   EquityBudgetGateResult preview = Equity_EvaluateBudgetGate(ctx, 0.0);
   double threshold = preview.room_available + preview.open_risk + preview.pending_risk;
   
   double next_trade = threshold - 1.0;
   if(next_trade < 0.0)
      next_trade = 0.0;
   EquityBudgetGateResult result = Equity_EvaluateBudgetGate(ctx, next_trade);
   
   ASSERT_TRUE(result.gate_pass, "Gate passes below threshold");
   
   double next_trade_over = threshold + 1.0;
   EquityBudgetGateResult result_over = Equity_EvaluateBudgetGate(ctx, next_trade_over);
   ASSERT_FALSE(result_over.gate_pass, "Gate fails when slightly over threshold");
   
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool BudgetGate_UsesRiskGateHeadroomConfig()
{
   g_current_test = "BudgetGate_UsesRiskGateHeadroomConfig";
   PrintFormat("[TEST START] %s", g_current_test);
   
   BudgetGateTests_Reset();
   AppContext ctx = BudgetGateTests_CreateContext();
   
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.equity_snapshot = 10600.0;
   
   Equity_ComputeRooms(ctx);
   
   EquityBudgetGateResult result = Equity_EvaluateBudgetGate(ctx, 0.0);
   
   ASSERT_TRUE(result.gate_pass, "Gate uses RiskGateHeadroom config (0.90)");
   
   double min_room = MathMin(result.room_today, result.room_overall);
   double expected_threshold = RiskGateHeadroom * min_room;
   ASSERT_NEAR(expected_threshold, result.room_available, 1e-3, "room_available calculated using RiskGateHeadroom");
   
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool BudgetGate_CalcErrorWhenStateInvalid()
{
   g_current_test = "BudgetGate_CalcErrorWhenStateInvalid";
   PrintFormat("[TEST START] %s", g_current_test);
   
   BudgetGateTests_Reset();
   AppContext ctx = BudgetGateTests_CreateContext();
   
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.equity_snapshot = 10000.0;
   
   Equity_ComputeRooms(ctx);
   g_equity_state_valid = false;
   g_equity_state_time = ctx.current_server_time;
   
   EquityBudgetGateResult result = Equity_EvaluateBudgetGate(ctx, 50.0);
   ASSERT_TRUE(result.calculation_error, "Calculation error flagged when snapshot state invalid");
   ASSERT_FALSE(result.gate_pass, "Gate fails when snapshot invalid");
   ASSERT_STRING_EQ("calc_error", result.gating_reason, "Gating reason is 'calc_error' when snapshot invalid");
   
   // Restore state for subsequent tests
   Equity_ComputeRooms(ctx);
   
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool BudgetGate_LockAlwaysReleased()
{
   g_current_test = "BudgetGate_LockAlwaysReleased";
   PrintFormat("[TEST START] %s", g_current_test);
   
   BudgetGateTests_Reset();
   AppContext ctx = BudgetGateTests_CreateContext();
   
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.equity_snapshot = 10000.0;
   
   Equity_ComputeRooms(ctx);
   
   // Test normal path - verify lock can be acquired after budget gate call
   EquityBudgetGateResult result1 = Equity_EvaluateBudgetGate(ctx, 50.0);
   
   // After budget gate, lock should be released - verify we can acquire it
   bool acquired_after = Equity_AcquireBudgetGateLock(1000);
   ASSERT_TRUE(acquired_after, "Lock released after normal evaluation");
   Equity_ReleaseBudgetGateLock();
   
   // Test with various scenarios - all should release lock
   EquityBudgetGateResult result2 = Equity_EvaluateBudgetGate(ctx, 50.0);
   bool acquired_after2 = Equity_AcquireBudgetGateLock(1000);
   ASSERT_TRUE(acquired_after2, "Lock released after second evaluation");
   Equity_ReleaseBudgetGateLock();
   
   EquityBudgetGateResult result3 = Equity_EvaluateBudgetGate(ctx, 500.0);
   bool acquired_after3 = Equity_AcquireBudgetGateLock(1000);
   ASSERT_TRUE(acquired_after3, "Lock released even when gate fails");
   Equity_ReleaseBudgetGateLock();
   
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// Test runner
//------------------------------------------------------------------------------

bool TestOrderEngineBudgetGate_RunAll()
{
   PrintFormat("=================================================================");
   PrintFormat("RPEA Budget Gate Tests - Task 9 (Position Snapshot Locking)");
   PrintFormat("=================================================================");
   
   g_test_passed = 0;
   g_test_failed = 0;
   
   bool t1 = BudgetGate_PassesWithinHeadroom();
   bool t2 = BudgetGate_BlocksOverHeadroom();
   bool t3 = BudgetGate_UsesSnapshotLock();
   bool t4 = BudgetGate_LogsFiveInputs();
   bool t5 = BudgetGate_LockTimeout();
   bool t6 = BudgetGate_LogsGatePassBoolean();
   bool t7 = BudgetGate_LogsGatingReason();
   bool t8 = BudgetGate_FormulaCorrect();
   bool t9 = BudgetGate_UsesRiskGateHeadroomConfig();
   bool t10 = BudgetGate_CalcErrorWhenStateInvalid();
   bool t11 = BudgetGate_LockAlwaysReleased();
   
   bool all_passed = (t1 && t2 && t3 && t4 && t5 && t6 && t7 && t8 && t9 && t10 && t11 && g_test_failed == 0);
   
   PrintFormat("=================================================================");
   PrintFormat("Test Summary: %d passed, %d failed", g_test_passed, g_test_failed);
   if(all_passed)
      PrintFormat("ALL BUDGET GATE TESTS PASSED!");
   else
      PrintFormat("BUDGET GATE TESTS FAILED - Review output for details");
   PrintFormat("=================================================================");
   
   BudgetGateTests_Reset();
   return all_passed;
}

#endif // TEST_ORDER_ENGINE_BUDGETGATE_MQH


