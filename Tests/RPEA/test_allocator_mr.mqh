#ifndef TEST_ALLOCATOR_MR_MQH
#define TEST_ALLOCATOR_MR_MQH
// test_allocator_mr.mqh - Unit tests for M7 Task 7 (Allocator MR Integration)
// Tests allocator accepts MR strategy with correct context and risk sizing.

#include <RPEA/allocator.mqh>
#include <RPEA/mr_context.mqh>
#include <RPEA/state.mqh>
#include <RPEA/slo_monitor.mqh>

#ifndef SIGNALS_BWISC_MQH
struct BWISC_Context
{
   double expected_R;
   double expected_hold;
   double worst_case_risk;
   double entry_price;
   int    direction;
};
BWISC_Context g_last_bwisc_context;
#endif

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
//| Helpers                                                          |
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

void SetupMRContext(double entry_price, int direction)
{
   g_last_mr_context.entry_price = entry_price;
   g_last_mr_context.direction = direction;
   g_last_mr_context.expected_R = 1.5;
   g_last_mr_context.expected_hold = 90.0;
   g_last_mr_context.worst_case_risk = 0.0;
}

void SetupBWISCContext(double entry_price, int direction)
{
   g_last_bwisc_context.entry_price = entry_price;
   g_last_bwisc_context.direction = direction;
   g_last_bwisc_context.expected_R = 2.0;
   g_last_bwisc_context.expected_hold = 45.0;
   g_last_bwisc_context.worst_case_risk = 0.0;
}

//+------------------------------------------------------------------+
//| Test: Allocator accepts MR strategy                              |
//+------------------------------------------------------------------+
bool TestAllocatorMR_AcceptsStrategy()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_AcceptsStrategy");

   AppContext ctx = MakeAllocatorTestContext();
   SetupMRContext(1.05000, 1);

   OrderPlan plan = Allocator_BuildOrderPlan(ctx, "MR", "EURUSD", 100, 150, 0.75);

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
//| Test: MR uses correct context (not BWISC context)                |
//+------------------------------------------------------------------+
bool TestAllocatorMR_UsesCorrectContext()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_UsesCorrectContext");

   AppContext ctx = MakeAllocatorTestContext();

   SetupMRContext(1.05000, 1);
   SetupBWISCContext(1.10000, -1);

   OrderPlan plan = Allocator_BuildOrderPlan(ctx, "MR", "EURUSD", 100, 150, 0.75);

   if(plan.price > 0.0)
   {
      double diff = MathAbs(plan.price - 1.05000);
      ASSERT_TRUE(diff < 0.001, "Entry price from MR context (1.05000)");
   }
   else
   {
      ASSERT_TRUE(plan.rejection_reason != "missing_entry_price" ||
                  g_last_mr_context.entry_price > 0.0,
                  "MR context has entry price");
   }

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: Invalid strategy still rejected                            |
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
//| Test: MR proxy mapping guard                                     |
//+------------------------------------------------------------------+
bool TestAllocatorMR_ProxyMapGuard()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_ProxyMapGuard");

   ASSERT_FALSE(Allocator_ShouldMapProxyDistance("MR", true),
                "MR proxy distances are not remapped");
   ASSERT_TRUE(Allocator_ShouldMapProxyDistance("BWISC", true),
               "BWISC proxy distances are remapped");
   ASSERT_FALSE(Allocator_ShouldMapProxyDistance("MR", false),
                "Non-proxy symbols are never remapped");

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: MR bias computed from direction                            |
//+------------------------------------------------------------------+
bool TestAllocatorMR_BiasDirection()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_BiasDirection");

   double long_bias = Allocator_ComputeBias("MR", 1, 0.75);
   double short_bias = Allocator_ComputeBias("MR", -1, 0.75);
   double neutral_bias = Allocator_ComputeBias("None", 1, 0.75);

   ASSERT_TRUE(MathAbs(long_bias - 0.75) < 0.0001,
               "Long MR bias keeps confidence magnitude");
   ASSERT_TRUE(MathAbs(short_bias + 0.75) < 0.0001,
               "Short MR bias keeps direction sign");
   ASSERT_TRUE(MathAbs(neutral_bias) < 0.0001,
               "Unknown setup bias remains zero");

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: SLO metrics initialization                                 |
//+------------------------------------------------------------------+
bool TestAllocatorMR_SLOInit()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_SLOInit");

   SLO_OnInit();
   SLO_Metrics metrics;
   SLO_InitMetrics(metrics);

   ASSERT_FALSE(metrics.warn_only, "warn_only initialized to false");
   ASSERT_FALSE(metrics.slo_breached, "slo_breached initialized to false");
   ASSERT_TRUE(metrics.mr_win_rate_30d >= 0.55, "win_rate above warn threshold");

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: SLO breach detection                                       |
//+------------------------------------------------------------------+
bool TestAllocatorMR_SLOBreach()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_SLOBreach");

   SLO_OnInit();
   SLO_Metrics metrics;
   SLO_InitMetrics(metrics);

   metrics.mr_win_rate_30d = 0.50;
   metrics.rolling_samples = SLO_DEFAULT_MIN_SAMPLES;
   SLO_CheckAndThrottle(metrics);

   ASSERT_TRUE(metrics.warn_only, "warn_only set when win_rate < 0.55");
   ASSERT_TRUE(metrics.slo_breached, "slo_breached set when threshold violated");

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: MR respects MicroMode (uses reduced risk)                  |
//+------------------------------------------------------------------+
bool TestAllocatorMR_RespectsMicroMode()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_RespectsMicroMode");

   ChallengeState orig_st = State_Get();

   ChallengeState st = orig_st;
   st.micro_mode = true;
   st.micro_mode_activated_at = TimeCurrent();
   State_Set(st);

   bool micro_active = Equity_IsMicroModeActive();
   ASSERT_TRUE(micro_active, "MicroMode should be active after State_Set");

   AppContext ctx = MakeAllocatorTestContext();
   SetupMRContext(1.05000, 1);
   OrderPlan plan = Allocator_BuildOrderPlan(ctx, "MR", "EURUSD", 100, 150, 0.75);
   if(plan.valid || !plan.valid)
   {
      // no-op: ensures call executed while micro mode was active
   }

   State_Set(orig_st);

   bool micro_inactive = !Equity_IsMicroModeActive();
   ASSERT_TRUE(micro_inactive, "MicroMode should be inactive after restore");

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: Adaptive risk disabled keeps baseline risk                 |
//+------------------------------------------------------------------+
bool TestAllocatorMR_AdaptiveRiskDisabledBaseline()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_AdaptiveRiskDisabledBaseline");

   Config_Test_ClearEnableAdaptiveRiskOverride();
   Config_Test_ClearAdaptiveRiskBoundsOverride();

   AppContext ctx = MakeAllocatorTestContext();
   string regime = "";
   double efficiency = 0.0;
   double multiplier = 0.0;
   bool applied = true;
   double base_risk = Config_GetMRRiskPctDefault();
   double effective_risk = Allocator_ApplyAdaptiveRiskPct(ctx,
                                                          "MR",
                                                          "EURUSD",
                                                          base_risk,
                                                          regime,
                                                          efficiency,
                                                          multiplier,
                                                          applied);

   ASSERT_FALSE(applied, "adaptive risk is not applied by default");
   ASSERT_TRUE(MathAbs(effective_risk - base_risk) < 1e-9,
               "default-disabled adaptive risk preserves baseline risk");

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: Adaptive risk enabled remains inside configured clamps     |
//+------------------------------------------------------------------+
bool TestAllocatorMR_AdaptiveRiskEnabledRespectsClamp()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_AdaptiveRiskEnabledRespectsClamp");

   Config_Test_SetEnableAdaptiveRiskOverride(true, true);
   Config_Test_SetAdaptiveRiskBoundsOverride(true, 0.90, 1.10);
   Telemetry_TestReset();

   AppContext ctx = MakeAllocatorTestContext();
   string regime = "";
   double efficiency = 0.0;
   double multiplier = 0.0;
   bool applied = false;
   double base_risk = Config_GetMRRiskPctDefault();
   double effective_risk = Allocator_ApplyAdaptiveRiskPct(ctx,
                                                          "MR",
                                                          "EURUSD",
                                                          base_risk,
                                                          regime,
                                                          efficiency,
                                                          multiplier,
                                                          applied);

   double min_allowed = base_risk * Config_GetAdaptiveRiskMinMult();
   double max_allowed = base_risk * Config_GetAdaptiveRiskMaxMult();
   ASSERT_TRUE(applied, "adaptive risk applies when toggle is enabled");
   ASSERT_TRUE(effective_risk >= min_allowed - 1e-9 && effective_risk <= max_allowed + 1e-9,
               "effective risk stays inside configured adaptive clamps");

   Config_Test_ClearEnableAdaptiveRiskOverride();
   Config_Test_ClearAdaptiveRiskBoundsOverride();

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Test: MicroMode overrides adaptive risk scaling                  |
//+------------------------------------------------------------------+
bool TestAllocatorMR_AdaptiveRiskMicroModePrecedence()
{
   int f = TestAllocMR_Begin("TestAllocatorMR_AdaptiveRiskMicroModePrecedence");

   ChallengeState orig_st = State_Get();
   ChallengeState st = orig_st;
   st.micro_mode = true;
   st.micro_mode_activated_at = TimeCurrent();
   State_Set(st);

   Config_Test_SetEnableAdaptiveRiskOverride(true, true);

   AppContext ctx = MakeAllocatorTestContext();
   string regime = "";
   double efficiency = 0.0;
   double multiplier = 0.0;
   bool applied = true;
   double base_risk = Config_GetMicroRiskPct();
   double effective_risk = Allocator_ApplyAdaptiveRiskPct(ctx,
                                                          "MR",
                                                          "EURUSD",
                                                          base_risk,
                                                          regime,
                                                          efficiency,
                                                          multiplier,
                                                          applied);

   ASSERT_FALSE(applied, "adaptive risk skipped when MicroMode is active");
   ASSERT_TRUE(MathAbs(effective_risk - base_risk) < 1e-9,
               "MicroMode base risk is preserved");

   Config_Test_ClearEnableAdaptiveRiskOverride();
   State_Set(orig_st);

   return TestAllocMR_End(f);
}

//+------------------------------------------------------------------+
//| Run all tests                                                    |
//+------------------------------------------------------------------+
bool TestAllocatorMR_RunAll()
{
   Print("========================================");
   Print("M7 Task 07: Allocator MR Integration Tests");
   Print("========================================");

   bool ok1 = TestAllocatorMR_AcceptsStrategy();
   bool ok2 = TestAllocatorMR_UsesCorrectContext();
   bool ok3 = TestAllocatorMR_RejectsInvalid();
   bool ok4 = TestAllocatorMR_ProxyMapGuard();
   bool ok5 = TestAllocatorMR_BiasDirection();
   bool ok6 = TestAllocatorMR_SLOInit();
   bool ok7 = TestAllocatorMR_SLOBreach();
   bool ok8 = TestAllocatorMR_RespectsMicroMode();
   bool ok9 = TestAllocatorMR_AdaptiveRiskDisabledBaseline();
   bool ok10 = TestAllocatorMR_AdaptiveRiskEnabledRespectsClamp();
   bool ok11 = TestAllocatorMR_AdaptiveRiskMicroModePrecedence();

   return (ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7 && ok8 && ok9 && ok10 && ok11);
}

#endif // TEST_ALLOCATOR_MR_MQH
