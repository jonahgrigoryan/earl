//+------------------------------------------------------------------+
//|                                           test_killswitch.mqh    |
//|                          M4-Task03: Kill-Switch Floor Tests      |
//+------------------------------------------------------------------+
#ifndef TEST_KILLSWITCH_MQH
#define TEST_KILLSWITCH_MQH

#include <RPEA/app_context.mqh>
#include <RPEA/equity_guardian.mqh>
#include <RPEA/state.mqh>

// Test counters (use global from test_reporter)
#ifndef TEST_COUNTERS_DECLARED
#define TEST_COUNTERS_DECLARED
extern int g_test_passed;
extern int g_test_failed;
extern string g_current_test;
#endif

// Test assertion macro
#ifndef ASSERT_TRUE
#define ASSERT_TRUE(cond, msg) \
   if(!(cond)) { \
      PrintFormat("[FAIL] %s: %s", g_current_test, msg); \
      g_test_failed++; \
   } else { \
      g_test_passed++; \
   }
#endif

//+------------------------------------------------------------------+
// Test: Daily floor calculation
//+------------------------------------------------------------------+
bool Test_Killswitch_DailyFloorCalculation()
{
   g_current_test = "Test_Killswitch_DailyFloorCalculation";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   
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

   // Restore state
   State_Set(orig_st);

   ASSERT_TRUE(MathAbs(floor - expected) < 0.01, 
               StringFormat("Daily floor should be baseline - DailyLossCapPct%% (got %.2f, expected %.2f)", floor, expected));
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Overall floor calculation
//+------------------------------------------------------------------+
bool Test_Killswitch_OverallFloorCalculation()
{
   g_current_test = "Test_Killswitch_OverallFloorCalculation";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   
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

   // Restore state
   State_Set(orig_st);

   ASSERT_TRUE(MathAbs(floor - expected) < 0.01, 
               StringFormat("Overall floor should be baseline - OverallLossCapPct%% (got %.2f, expected %.2f)", floor, expected));
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Overall breach sets disabled_permanent
//+------------------------------------------------------------------+
bool Test_Killswitch_OverallPrecedence()
{
   g_current_test = "Test_Killswitch_OverallPrecedence";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   
   // Setup test state
   ChallengeState st = State_Get();
   st.disabled_permanent = false;
   st.daily_floor_breached = false;
   st.trading_enabled = true;
   st.initial_baseline = 10000.0;
   st.baseline_today = 10000.0;
   State_Set(st);

   AppContext ctx;
   ZeroMemory(ctx);
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.current_server_time = TimeCurrent();

   // Force equity below both floors (overall = 9400, daily = 9600 with defaults)
   Equity_Test_SetEquityOverride(9000.0);
   Equity_CheckAndExecuteKillswitch(ctx);
   Equity_Test_ClearEquityOverride();

   st = State_Get();
   bool result = st.disabled_permanent;
   
   // Restore state
   State_Set(orig_st);

   ASSERT_TRUE(result, "Overall breach should set disabled_permanent");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Daily flags reset on server-day rollover
//+------------------------------------------------------------------+
bool Test_Killswitch_DailyReset()
{
   g_current_test = "Test_Killswitch_DailyReset";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   
   // Setup test state with daily breach
   ChallengeState st = State_Get();
   st.daily_floor_breached = true;
   st.trading_enabled = false;
   st.disabled_permanent = false;
   State_Set(st);

   // Simulate server-day rollover
   Equity_OnServerDayRollover();
   st = State_Get();

   bool daily_reset = (st.daily_floor_breached == false);
   bool trading_enabled = (st.trading_enabled == TradingEnabledDefault);
   
   // Restore state
   State_Set(orig_st);

   ASSERT_TRUE(daily_reset, "Daily breach flag should reset on rollover");
   ASSERT_TRUE(trading_enabled, "Trading should be re-enabled after rollover");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Permanent disable persists across rollover
//+------------------------------------------------------------------+
bool Test_Killswitch_PermanentNoReset()
{
   g_current_test = "Test_Killswitch_PermanentNoReset";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   
   // Setup test state with permanent disable
   ChallengeState st = State_Get();
   st.disabled_permanent = true;
   st.trading_enabled = false;
   State_Set(st);

   // Simulate server-day rollover
   Equity_OnServerDayRollover();
   st = State_Get();

   bool still_permanent = st.disabled_permanent;
   bool still_disabled = !st.trading_enabled;
   
   // Restore state
   State_Set(orig_st);

   ASSERT_TRUE(still_permanent, "Permanent disable should NOT reset on rollover");
   ASSERT_TRUE(still_disabled, "Trading should stay disabled when permanently disabled");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Daily floor breach sets correct flags
//+------------------------------------------------------------------+
bool Test_Killswitch_DailyFloorBreach()
{
   g_current_test = "Test_Killswitch_DailyFloorBreach";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   
   // Setup test state
   ChallengeState st = State_Get();
   st.disabled_permanent = false;
   st.daily_floor_breached = false;
   st.trading_enabled = true;
   st.initial_baseline = 10000.0;
   st.baseline_today = 10000.0;
   State_Set(st);

   AppContext ctx;
   ZeroMemory(ctx);
   ctx.baseline_today = 10000.0;
   ctx.initial_baseline = 10000.0;
   ctx.current_server_time = TimeCurrent();

   // Force equity below daily floor but above overall floor
   // Daily floor = 10000 - 4% = 9600
   // Overall floor = 10000 - 6% = 9400
   Equity_Test_SetEquityOverride(9500.0);
   Equity_CheckAndExecuteKillswitch(ctx);
   Equity_Test_ClearEquityOverride();

   st = State_Get();
   bool daily_breached = st.daily_floor_breached;
   bool trading_disabled = !st.trading_enabled;
   bool not_permanent = !st.disabled_permanent;
   
   // Restore state
   State_Set(orig_st);

   ASSERT_TRUE(daily_breached, "Daily floor breach should set daily_floor_breached flag");
   ASSERT_TRUE(trading_disabled, "Daily floor breach should disable trading");
   ASSERT_TRUE(not_permanent, "Daily floor breach should NOT set disabled_permanent");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Test: Daily kill-switch is active check
//+------------------------------------------------------------------+
bool Test_Killswitch_IsDailyKillswitchActive()
{
   g_current_test = "Test_Killswitch_IsDailyKillswitchActive";
   Print("Running: ", g_current_test);
   
   // Save original state
   ChallengeState orig_st = State_Get();
   
   // Test 1: Daily breached, not permanent -> active
   ChallengeState st = State_Get();
   st.daily_floor_breached = true;
   st.disabled_permanent = false;
   State_Set(st);
   bool is_active_1 = Equity_IsDailyKillswitchActive();
   
   // Test 2: Daily breached but also permanent -> not active (permanent takes precedence)
   st.disabled_permanent = true;
   State_Set(st);
   bool is_active_2 = Equity_IsDailyKillswitchActive();
   
   // Test 3: Not daily breached -> not active
   st.daily_floor_breached = false;
   st.disabled_permanent = false;
   State_Set(st);
   bool is_active_3 = Equity_IsDailyKillswitchActive();
   
   // Restore state
   State_Set(orig_st);

   ASSERT_TRUE(is_active_1, "Daily kill-switch should be active when daily_floor_breached=true and not permanent");
   ASSERT_TRUE(!is_active_2, "Daily kill-switch should NOT be active when disabled_permanent=true");
   ASSERT_TRUE(!is_active_3, "Daily kill-switch should NOT be active when daily_floor_breached=false");
   return (g_test_failed == 0);
}

//+------------------------------------------------------------------+
// Run all kill-switch tests
//+------------------------------------------------------------------+
bool TestKillswitch_RunAll()
{
   Print("==============================================================");
   Print("M4 Task03 Kill-Switch Tests");
   Print("==============================================================");

   int local_passed = 0;
   int local_failed = 0;

   bool ok = true;
   
   // Reset counters for this suite
   int start_passed = g_test_passed;
   int start_failed = g_test_failed;
   
   ok &= Test_Killswitch_DailyFloorCalculation();
   ok &= Test_Killswitch_OverallFloorCalculation();
   ok &= Test_Killswitch_OverallPrecedence();
   ok &= Test_Killswitch_DailyReset();
   ok &= Test_Killswitch_PermanentNoReset();
   ok &= Test_Killswitch_DailyFloorBreach();
   ok &= Test_Killswitch_IsDailyKillswitchActive();

   local_passed = g_test_passed - start_passed;
   local_failed = g_test_failed - start_failed;
   
   PrintFormat("Kill-Switch Test Summary: %d passed, %d failed", local_passed, local_failed);
   return (local_failed == 0);
}

#endif // TEST_KILLSWITCH_MQH
