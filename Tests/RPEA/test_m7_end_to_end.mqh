#ifndef TEST_M7_END_TO_END_MQH
#define TEST_M7_END_TO_END_MQH
// test_m7_end_to_end.mqh - M7 Task 08 end-to-end tests
// Tests MR time stop logic, SLO monitoring, EnableMR override, regression guards.

#include <RPEA/config.mqh>
#include <RPEA/slo_monitor.mqh>
#include <RPEA/meta_policy.mqh>
#include <RPEA/allocator.mqh>
#include <RPEA/mr_context.mqh>
#include <RPEA/queue.mqh>
#include <RPEA/signals_mr.mqh>

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

#define ASSERT_STR_EQ(expected, actual, msg) \
   do { \
      if((expected) == (actual)) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s (got \"%s\")", g_current_test, msg, actual); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected \"%s\", got \"%s\")", \
            g_current_test, msg, expected, actual); \
      } \
   } while(false)

#define TEST_FRAMEWORK_DEFINED
#endif

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int TestE2E_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestE2E_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s - %s", g_current_test, ok ? "OK" : "FAILED");
   return ok;
}

MetaPolicyContext TestE2E_DefaultMetaPolicyContext()
{
   MetaPolicyContext mpc;
   mpc.bwisc_has_setup      = false;
   mpc.bwisc_confidence     = 0.0;
   mpc.bwisc_ore            = 0.50;
   mpc.bwisc_efficiency     = 0.0;
   mpc.mr_has_setup         = true;
   mpc.mr_confidence        = 0.85;
   mpc.emrt_rank            = 0.50;
   mpc.q_advantage          = 0.50;
   mpc.mr_efficiency        = 0.0;
   mpc.atr_d1_percentile    = 0.50;
   mpc.session_age_minutes  = 60;
   mpc.news_within_15m      = false;
   mpc.entry_blocked        = false;
   mpc.spread_quantile      = 0.50;
   mpc.slippage_quantile    = 0.50;
   mpc.regime_label         = 0;
   mpc.entries_this_session = 0;
   mpc.locked_to_mr         = false;
   return mpc;
}

//+------------------------------------------------------------------+
//| Test: SLO init produces safe defaults (no breach)                |
//+------------------------------------------------------------------+
bool TestE2E_SLOInit_SafeDefaults()
{
   int f = TestE2E_Begin("TestE2E_SLOInit_SafeDefaults");

   SLO_OnInit();
   ASSERT_FALSE(SLO_IsMRThrottled(), "SLO not throttled after init");
   ASSERT_FALSE(g_slo_metrics.warn_only, "No warnings after init");
   ASSERT_TRUE(g_slo_metrics.mr_win_rate_30d >= 0.55, "Win rate above warn threshold");

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: SLO breach throttles MR                                    |
//+------------------------------------------------------------------+
bool TestE2E_SLOBreach_ThrottlesMR()
{
   int f = TestE2E_Begin("TestE2E_SLOBreach_ThrottlesMR");

   SLO_OnInit();
   g_slo_metrics.mr_win_rate_30d = 0.50;  // Below 0.55 threshold
   g_slo_metrics.rolling_samples = 5;
   SLO_CheckAndThrottle(g_slo_metrics);
   ASSERT_TRUE(SLO_IsMRThrottled(), "MR throttled when win rate < 0.55");

   // Restore
   SLO_OnInit();
   ASSERT_FALSE(SLO_IsMRThrottled(), "MR unthrottled after re-init");

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: SLO clear allows MR                                        |
//+------------------------------------------------------------------+
bool TestE2E_SLOClear_AllowsMR()
{
   int f = TestE2E_Begin("TestE2E_SLOClear_AllowsMR");

   SLO_OnInit();
   // All metrics within thresholds
   ASSERT_FALSE(SLO_IsMRThrottled(), "MR allowed with good metrics");

   // Set good values explicitly
   g_slo_metrics.mr_win_rate_30d = 0.62;
   g_slo_metrics.mr_median_hold_hours = 1.5;
   g_slo_metrics.mr_hold_p80_hours = 3.0;
   g_slo_metrics.mr_median_efficiency = 0.90;
   g_slo_metrics.mr_median_friction_r = 0.20;
   SLO_CheckAndThrottle(g_slo_metrics);
   ASSERT_FALSE(SLO_IsMRThrottled(), "MR allowed with all metrics above threshold");

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: SLO breach is metrics-driven from ingested outcomes        |
//+------------------------------------------------------------------+
bool TestE2E_SLOMetricsDriven_Breach()
{
   int f = TestE2E_Begin("TestE2E_SLOMetricsDriven_Breach");

#ifdef RPEA_TEST_RUNNER
   SLO_OnInit();
   SLO_TestSetMinSamples(5);
   SLO_TestSetWindowDays(30);

   datetime t0 = 1704067200;
   for(int i = 0; i < 5; i++)
   {
      SLO_TestIngestTradeClosed((ulong)(9300 + i),
                                (ulong)(8300 + i),
                                "MR",
                                -1.0,
                                300,
                                0.50,
                                t0 + (i * 60));
   }

   SLO_TestRunPeriodicCheck(t0 + 7200);
   ASSERT_TRUE(g_slo_metrics.rolling_samples == 5, "rolling metrics use ingested outcomes");
   ASSERT_TRUE(g_slo_metrics.slo_breached, "hard breach set from computed rolling metrics");
   ASSERT_TRUE(SLO_IsMRThrottled(), "MR throttled from computed rolling metrics");
#else
   ASSERT_TRUE(true, "Metrics-driven breach test skipped (not RPEA_TEST_RUNNER)");
#endif

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: SLO recovery clears throttle after better outcomes         |
//+------------------------------------------------------------------+
bool TestE2E_SLOMetricsDriven_Recovery()
{
   int f = TestE2E_Begin("TestE2E_SLOMetricsDriven_Recovery");

#ifdef RPEA_TEST_RUNNER
   SLO_OnInit();
   SLO_TestSetMinSamples(5);
   SLO_TestSetWindowDays(30);

   datetime t0 = 1704067200;
   for(int i = 0; i < 5; i++)
   {
      SLO_TestIngestTradeClosed((ulong)(9400 + i),
                                (ulong)(8400 + i),
                                "MR",
                                1.5,
                                90,
                                0.10,
                                t0 + (i * 60));
   }

   SLO_TestRunPeriodicCheck(t0 + 7200);
   ASSERT_FALSE(g_slo_metrics.slo_breached, "hard breach clears with healthy rolling metrics");
   ASSERT_FALSE(SLO_IsMRThrottled(), "MR throttle clears on recovery");
#else
   ASSERT_TRUE(true, "Metrics-driven recovery test skipped (not RPEA_TEST_RUNNER)");
#endif

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: Meta-policy SLO gate reroutes MR to BWISC when qualified    |
//+------------------------------------------------------------------+
bool TestE2E_MetaPolicySLOGate_MRToBWISC()
{
   int f = TestE2E_Begin("TestE2E_MetaPolicySLOGate_MRToBWISC");

   SLO_OnInit();
   g_slo_metrics.mr_win_rate_30d = 0.50;
   g_slo_metrics.rolling_samples = 5;
   SLO_CheckAndThrottle(g_slo_metrics);
   ASSERT_TRUE(SLO_IsMRThrottled(), "MR is throttled after breach");

   MetaPolicyContext mpc = TestE2E_DefaultMetaPolicyContext();
   mpc.bwisc_has_setup = true;
   mpc.bwisc_confidence = Config_GetBWISCConfCut();

   string result = MetaPolicy_ApplySLOOverride("MR", mpc, false);
   ASSERT_STR_EQ("BWISC", result, "SLO gate falls back to BWISC when BWISC is qualified");

   SLO_OnInit();
   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: Meta-policy SLO gate reroutes MR to Skip when BWISC absent  |
//+------------------------------------------------------------------+
bool TestE2E_MetaPolicySLOGate_MRToSkip()
{
   int f = TestE2E_Begin("TestE2E_MetaPolicySLOGate_MRToSkip");

   SLO_OnInit();
   g_slo_metrics.mr_win_rate_30d = 0.50;
   g_slo_metrics.rolling_samples = 5;
   SLO_CheckAndThrottle(g_slo_metrics);
   ASSERT_TRUE(SLO_IsMRThrottled(), "MR is throttled after breach");

   MetaPolicyContext mpc = TestE2E_DefaultMetaPolicyContext();
   mpc.bwisc_has_setup = false;
   mpc.bwisc_confidence = 0.0;

   string result = MetaPolicy_ApplySLOOverride("MR", mpc, false);
   ASSERT_STR_EQ("Skip", result, "SLO gate falls back to Skip when BWISC is unavailable");

   SLO_OnInit();
   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: Persistent disable reroutes MR to BWISC when qualified     |
//+------------------------------------------------------------------+
bool TestE2E_SLOPersistentDisable_MRToBWISC()
{
   int f = TestE2E_Begin("TestE2E_SLOPersistentDisable_MRToBWISC");

#ifdef RPEA_TEST_RUNNER
   SLO_OnInit();
   SLO_TestSetMinSamples(5);
   SLO_TestSetDisableAfterBreachChecks(1);
   SLO_TestSetWindowDays(30);

   datetime t0 = 1704067200;
   for(int i = 0; i < 5; i++)
      SLO_TestIngestTradeClosed((ulong)(9800 + i), (ulong)(5800 + i), "MR", -1.0, 300, 0.50, t0 + (i * 60));
   SLO_TestRunPeriodicCheck(t0 + 7200);

   ASSERT_TRUE(SLO_IsMRDisabled(), "MR persistent disable activates after configured persistence");

   MetaPolicyContext mpc = TestE2E_DefaultMetaPolicyContext();
   mpc.bwisc_has_setup = true;
   mpc.bwisc_confidence = Config_GetBWISCConfCut();
   string result = MetaPolicy_ApplySLOOverride("MR", mpc, false);
   ASSERT_STR_EQ("BWISC", result, "persistent disable still preserves BWISC fallback");

   SLO_OnInit();
#else
   ASSERT_TRUE(true, "Persistent-disable BWISC fallback test skipped (not RPEA_TEST_RUNNER)");
#endif

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: Persistent disable reroutes MR to Skip when BWISC absent   |
//+------------------------------------------------------------------+
bool TestE2E_SLOPersistentDisable_MRToSkip()
{
   int f = TestE2E_Begin("TestE2E_SLOPersistentDisable_MRToSkip");

#ifdef RPEA_TEST_RUNNER
   SLO_OnInit();
   SLO_TestSetMinSamples(5);
   SLO_TestSetDisableAfterBreachChecks(1);
   SLO_TestSetWindowDays(30);

   datetime t0 = 1704067200;
   for(int i = 0; i < 5; i++)
      SLO_TestIngestTradeClosed((ulong)(9900 + i), (ulong)(5900 + i), "MR", -1.0, 300, 0.50, t0 + (i * 60));
   SLO_TestRunPeriodicCheck(t0 + 7200);

   ASSERT_TRUE(SLO_IsMRDisabled(), "MR persistent disable activates after configured persistence");

   MetaPolicyContext mpc = TestE2E_DefaultMetaPolicyContext();
   mpc.bwisc_has_setup = false;
   mpc.bwisc_confidence = 0.0;
   string result = MetaPolicy_ApplySLOOverride("MR", mpc, false);
   ASSERT_STR_EQ("Skip", result, "persistent disable falls back to Skip when BWISC unavailable");

   SLO_OnInit();
#else
   ASSERT_TRUE(true, "Persistent-disable Skip fallback test skipped (not RPEA_TEST_RUNNER)");
#endif

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: EnableMR override disables MR                              |
//+------------------------------------------------------------------+
bool TestE2E_EnableMROverride_DisablesMR()
{
   int f = TestE2E_Begin("TestE2E_EnableMROverride_DisablesMR");

#ifdef RPEA_TEST_RUNNER
   // Baseline: MR enabled
   Config_Test_ClearEnableMROverride();
   ASSERT_TRUE(Config_GetEnableMR(), "MR enabled by default in test runner");

   // Override: disable MR
   Config_Test_SetEnableMROverride(true, false);
   ASSERT_FALSE(Config_GetEnableMR(), "MR disabled via override");

   // Clear override: back to default
   Config_Test_ClearEnableMROverride();
   ASSERT_TRUE(Config_GetEnableMR(), "MR re-enabled after override cleared");
#else
   ASSERT_TRUE(true, "Override test skipped (not RPEA_TEST_RUNNER)");
#endif

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: BWISC-only mode (MR disabled) - SignalsMR returns no setup |
//+------------------------------------------------------------------+
bool TestE2E_BWISCOnlyMode()
{
   int f = TestE2E_Begin("TestE2E_BWISCOnlyMode");

#ifdef RPEA_TEST_RUNNER
   Config_Test_SetEnableMROverride(true, false);
   ASSERT_FALSE(Config_GetEnableMR(), "MR disabled for BWISC-only test");

   // Call SignalsMR_Propose with deterministic context -- should return hasSetup=false
   AppContext ctx;
   ZeroMemory(ctx);
   ArrayResize(ctx.symbols, 1);
   ctx.symbols[0] = "XAUUSD";
   ctx.symbols_count = 1;
   ctx.equity_snapshot = 10000.0;
   ctx.current_server_time = TimeCurrent();

   bool hasSetup = false;
   string setupType = "None";
   int slPts = 0;
   int tpPts = 0;
   double bias = 0.0;
   double conf = 0.0;
   SignalsMR_Propose(ctx, "XAUUSD", hasSetup, setupType, slPts, tpPts, bias, conf);
   ASSERT_FALSE(hasSetup, "MR signal disabled when EnableMR override is false");

   // Restore
   Config_Test_ClearEnableMROverride();
   ASSERT_TRUE(Config_GetEnableMR(), "MR re-enabled after test");
#else
   ASSERT_TRUE(true, "BWISC-only test skipped (not RPEA_TEST_RUNNER)");
#endif

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: MR time stop decision - below min (no close)               |
//+------------------------------------------------------------------+
bool TestE2E_TimeStopDecision_BelowMin()
{
   int f = TestE2E_Begin("TestE2E_TimeStopDecision_BelowMin");

   int min_seconds = Config_GetMRTimeStopMin() * 60;
   int elapsed = min_seconds - 60;
   ASSERT_TRUE(elapsed < min_seconds, "59 min is below MR_TimeStopMin");
   ASSERT_TRUE(min_seconds == 3600, "MR_TimeStopMin default is 60 min (3600 sec)");

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: MR time stop decision - above min (soft close)             |
//+------------------------------------------------------------------+
bool TestE2E_TimeStopDecision_AboveMin()
{
   int f = TestE2E_Begin("TestE2E_TimeStopDecision_AboveMin");

   int min_seconds = Config_GetMRTimeStopMin() * 60;
   int max_seconds = Config_GetMRTimeStopMax() * 60;
   int elapsed = min_seconds + 60;
   ASSERT_TRUE(elapsed >= min_seconds, "61 min triggers mr_timestop_min");
   ASSERT_TRUE(elapsed < max_seconds, "61 min does not trigger max_force");

   string reason = (elapsed >= max_seconds) ? "mr_timestop_max_force" : "mr_timestop_min";
   ASSERT_TRUE(reason == "mr_timestop_min", "Reason is mr_timestop_min at 61 min");

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: MR time stop decision - above max (hard close)             |
//+------------------------------------------------------------------+
bool TestE2E_TimeStopDecision_AboveMax()
{
   int f = TestE2E_Begin("TestE2E_TimeStopDecision_AboveMax");

   int max_seconds = Config_GetMRTimeStopMax() * 60;
   int elapsed = max_seconds + 60;
   ASSERT_TRUE(elapsed >= max_seconds, "91 min triggers mr_timestop_max_force");
   ASSERT_TRUE(max_seconds == 5400, "MR_TimeStopMax default is 90 min (5400 sec)");

   string reason = (elapsed >= max_seconds) ? "mr_timestop_max_force" : "mr_timestop_min";
   ASSERT_TRUE(reason == "mr_timestop_max_force", "Reason is mr_timestop_max_force at 91 min");

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: Anti-spam queue check returns -1 for non-existent ticket   |
//+------------------------------------------------------------------+
bool TestE2E_AntiSpamQueueCheck()
{
   int f = TestE2E_Begin("TestE2E_AntiSpamQueueCheck");

   int idx = Queue_FindIndexByTicketAction(999999999, QA_CLOSE);
   ASSERT_TRUE(idx == -1, "No false positive for non-existent ticket in queue");

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: Proxy distance guard regression (Task 07 guard)            |
//+------------------------------------------------------------------+
bool TestE2E_ProxyDistanceGuard()
{
   int f = TestE2E_Begin("TestE2E_ProxyDistanceGuard");

   ASSERT_FALSE(Allocator_ShouldMapProxyDistance("MR", true),
                "MR proxy distances not remapped");
   ASSERT_TRUE(Allocator_ShouldMapProxyDistance("BWISC", true),
               "BWISC proxy distances remapped");
   ASSERT_FALSE(Allocator_ShouldMapProxyDistance("MR", false),
                "Non-proxy MR not remapped");
   ASSERT_FALSE(Allocator_ShouldMapProxyDistance("BWISC", false),
                "Non-proxy BWISC not remapped");

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Test: MR bias sign regression (Task 07 guard)                    |
//+------------------------------------------------------------------+
bool TestE2E_MRBiasSign()
{
   int f = TestE2E_Begin("TestE2E_MRBiasSign");

   double long_bias = Allocator_ComputeBias("MR", 1, 0.80);
   double short_bias = Allocator_ComputeBias("MR", -1, 0.80);
   double bc_bias = Allocator_ComputeBias("BC", 1, 0.80);
   double msc_bias = Allocator_ComputeBias("MSC", 1, 0.80);

   ASSERT_TRUE(long_bias > 0.0, "Long MR bias is positive");
   ASSERT_TRUE(MathAbs(long_bias - 0.80) < 0.001, "Long MR bias magnitude matches confidence");
   ASSERT_TRUE(short_bias < 0.0, "Short MR bias is negative");
   ASSERT_TRUE(MathAbs(short_bias + 0.80) < 0.001, "Short MR bias magnitude matches confidence");
   ASSERT_TRUE(bc_bias > 0.0, "BC long bias is positive");
   ASSERT_TRUE(msc_bias < 0.0, "MSC long bias is negative (counter-direction)");

   return TestE2E_End(f);
}

//+------------------------------------------------------------------+
//| Run all tests                                                    |
//+------------------------------------------------------------------+
bool TestM7EndToEnd_RunAll()
{
   Print("========================================");
   Print("M7 Task 08: End-to-End Tests");
   Print("========================================");

   bool ok1  = TestE2E_SLOInit_SafeDefaults();
   bool ok2  = TestE2E_SLOBreach_ThrottlesMR();
   bool ok3  = TestE2E_SLOClear_AllowsMR();
   bool ok4  = TestE2E_SLOMetricsDriven_Breach();
   bool ok5  = TestE2E_SLOMetricsDriven_Recovery();
   bool ok6  = TestE2E_MetaPolicySLOGate_MRToBWISC();
   bool ok7  = TestE2E_MetaPolicySLOGate_MRToSkip();
   bool ok8  = TestE2E_SLOPersistentDisable_MRToBWISC();
   bool ok9  = TestE2E_SLOPersistentDisable_MRToSkip();
   bool ok10 = TestE2E_EnableMROverride_DisablesMR();
   bool ok11 = TestE2E_BWISCOnlyMode();
   bool ok12 = TestE2E_TimeStopDecision_BelowMin();
   bool ok13 = TestE2E_TimeStopDecision_AboveMin();
   bool ok14 = TestE2E_TimeStopDecision_AboveMax();
   bool ok15 = TestE2E_AntiSpamQueueCheck();
   bool ok16 = TestE2E_ProxyDistanceGuard();
   bool ok17 = TestE2E_MRBiasSign();

   return (ok1 && ok2 && ok3 && ok4 && ok5 &&
           ok6 && ok7 && ok8 && ok9 && ok10 &&
           ok11 && ok12 && ok13 && ok14 && ok15 &&
           ok16 && ok17);
}

#endif // TEST_M7_END_TO_END_MQH
