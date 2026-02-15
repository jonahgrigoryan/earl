#ifndef TEST_SLO_MONITOR_MQH
#define TEST_SLO_MONITOR_MQH
// test_slo_monitor.mqh - Post-M7 Phase 2 SLO monitor tests

#include <RPEA/slo_monitor.mqh>
#include <RPEA/telemetry.mqh>

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

int TestSLO_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestSLO_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s - %s", g_current_test, ok ? "OK" : "FAILED");
   return ok;
}

bool TestSLO_Ingestion_OncePerFinalClose()
{
   int f = TestSLO_Begin("TestSLO_Ingestion_OncePerFinalClose");

   SLO_TestResetState();
   Telemetry_TestReset();

   datetime t0 = 1704067200; // 2024-01-01 00:00:00 UTC
   ulong position_id = 9001;
   Telemetry_TestProcessPositionEntry(position_id, "MR-MR", t0);

   string strategy = "";
   double outcome = 0.0;
   int hold_minutes = 0;

   bool emitted_partial = Telemetry_TestProcessPositionExitDetailed(position_id,
                                                                    "MR-MR",
                                                                    10.0,
                                                                    t0 + 300,
                                                                    false,
                                                                    strategy,
                                                                    outcome,
                                                                    hold_minutes);
   ASSERT_FALSE(emitted_partial, "partial close does not emit final-close telemetry");

   bool emitted_final = Telemetry_TestProcessPositionExitDetailed(position_id,
                                                                  "MR-MR",
                                                                  -2.0,
                                                                  t0 + 900,
                                                                  true,
                                                                  strategy,
                                                                  outcome,
                                                                  hold_minutes);
   ASSERT_TRUE(emitted_final, "final close emits telemetry payload once");

   bool ingested = SLO_TestIngestTradeClosed(5001,
                                             position_id,
                                             strategy,
                                             outcome,
                                             hold_minutes,
                                             0.0,
                                             t0 + 900);
   ASSERT_TRUE(ingested, "SLO ingests final-close payload");
   ASSERT_TRUE(SLO_TestGetSampleCount() == 1, "exactly one SLO sample after final close");

   return TestSLO_End(f);
}

bool TestSLO_Ingestion_DuplicateCloseIdIgnored()
{
   int f = TestSLO_Begin("TestSLO_Ingestion_DuplicateCloseIdIgnored");

   SLO_TestResetState();

   datetime t0 = 1704067200;
   bool first = SLO_TestIngestTradeClosed(7001, 42, "MR", 15.0, 60, 0.05, t0);
   bool second = SLO_TestIngestTradeClosed(7001, 42, "MR", 15.0, 60, 0.05, t0 + 1);

   ASSERT_TRUE(first, "first ingest accepted");
   ASSERT_FALSE(second, "duplicate close id rejected");
   ASSERT_TRUE(SLO_TestGetSampleCount() == 1, "duplicate id does not increase sample count");
   ASSERT_TRUE(SLO_TestGetIngestedIdCount() == 1, "dedupe id table tracks one id");

   return TestSLO_End(f);
}

bool TestSLO_Ingestion_IgnoresNonMR()
{
   int f = TestSLO_Begin("TestSLO_Ingestion_IgnoresNonMR");

   SLO_TestResetState();

   bool bwisc = SLO_TestIngestTradeClosed(8101, 51, "BWISC", 8.0, 30, 0.02, 1704067200);
   bool empty = SLO_TestIngestTradeClosed(8102, 52, "", 8.0, 30, 0.02, 1704067200);

   ASSERT_FALSE(bwisc, "BWISC payload ignored by MR SLO stream");
   ASSERT_FALSE(empty, "empty strategy ignored");
   ASSERT_TRUE(SLO_TestGetSampleCount() == 0, "no MR samples recorded for non-MR payloads");

   return TestSLO_End(f);
}

bool TestSLO_Metrics_ComputedFromRollingWindow()
{
   int f = TestSLO_Begin("TestSLO_Metrics_ComputedFromRollingWindow");

   SLO_TestResetState();
   SLO_TestSetMinSamples(5);
   SLO_TestSetWindowDays(30);

   datetime t0 = 1704067200;
   SLO_TestIngestTradeClosed(9101, 101, "MR", 2.0,  60, 0.10, t0 + 100);
   SLO_TestIngestTradeClosed(9102, 102, "MR", -1.0, 90, 0.30, t0 + 200);
   SLO_TestIngestTradeClosed(9103, 103, "MR", 1.0,  120, 0.20, t0 + 300);
   SLO_TestIngestTradeClosed(9104, 104, "MR", -0.5, 150, 0.40, t0 + 400);
   SLO_TestIngestTradeClosed(9105, 105, "MR", 0.8,  180, 0.20, t0 + 500);

   SLO_TestRunPeriodicCheck(t0 + 4000);

   ASSERT_TRUE(g_slo_metrics.rolling_samples == 5, "rolling sample count uses ingested MR closes");
   ASSERT_TRUE(MathAbs(g_slo_metrics.mr_win_rate_30d - 0.60) < 1e-6, "win rate computed from rolling outcomes");
   ASSERT_TRUE(MathAbs(g_slo_metrics.mr_median_hold_hours - 2.0) < 1e-6, "median hold computed from rolling samples");
   ASSERT_TRUE(MathAbs(g_slo_metrics.mr_hold_p80_hours - 2.6) < 1e-6, "hold p80 computed deterministically");
   ASSERT_TRUE(MathAbs(g_slo_metrics.mr_median_efficiency - 0.8) < 1e-6, "median efficiency computed from payloads");
   ASSERT_TRUE(MathAbs(g_slo_metrics.mr_median_friction_r - 0.2) < 1e-6, "median friction computed from payloads");
   ASSERT_TRUE(g_slo_metrics.warn_only, "warn-only state can trigger without hard breach");
   ASSERT_FALSE(g_slo_metrics.slo_breached, "hard breach remains false when hard thresholds pass");

   return TestSLO_End(f);
}

bool TestSLO_Metrics_InsufficientSamplesGuard()
{
   int f = TestSLO_Begin("TestSLO_Metrics_InsufficientSamplesGuard");

   SLO_TestResetState();
   SLO_TestSetMinSamples(6);
   SLO_TestSetWindowDays(30);

   datetime t0 = 1704067200;
   SLO_TestIngestTradeClosed(9201, 201, "MR", -1.0, 300, 0.50, t0 + 60);
   SLO_TestIngestTradeClosed(9202, 202, "MR", -1.0, 300, 0.50, t0 + 120);
   SLO_TestIngestTradeClosed(9203, 203, "MR", -1.0, 300, 0.50, t0 + 180);
   SLO_TestIngestTradeClosed(9204, 204, "MR", -1.0, 300, 0.50, t0 + 240);
   SLO_TestIngestTradeClosed(9205, 205, "MR", -1.0, 300, 0.50, t0 + 300);

   SLO_TestRunPeriodicCheck(t0 + 4000);

   ASSERT_TRUE(g_slo_metrics.rolling_samples == 5, "rolling sample count reflects available data");
   ASSERT_FALSE(g_slo_metrics.warn_only, "warn flag suppressed below minimum samples");
   ASSERT_FALSE(g_slo_metrics.slo_breached, "hard breach suppressed below minimum samples");
   ASSERT_FALSE(SLO_IsMRThrottled(), "MR throttle stays off below minimum sample threshold");

   return TestSLO_End(f);
}

bool TestSLO_PersistentThrottle_DisablesAfterConfiguredChecks()
{
   int f = TestSLO_Begin("TestSLO_PersistentThrottle_DisablesAfterConfiguredChecks");

   SLO_TestResetState();
   SLO_TestSetMinSamples(5);
   SLO_TestSetWindowDays(30);
   SLO_TestSetDisableAfterBreachChecks(2);

   datetime t0 = 1704067200;
   for(int i = 0; i < 5; i++)
      SLO_TestIngestTradeClosed((ulong)(9500 + i), (ulong)(4500 + i), "MR", -1.0, 300, 0.50, t0 + (i * 60));

   SLO_TestRunPeriodicCheck(t0 + 7200);
   ASSERT_TRUE(g_slo_metrics.slo_breached, "first hard breach check is active");
   ASSERT_TRUE(SLO_IsMRThrottled(), "MR is throttled on hard breach");
   ASSERT_FALSE(SLO_IsMRDisabled(), "MR is not disabled before persistence threshold");
   ASSERT_TRUE(SLO_TestGetConsecutiveBreachChecks() == 1, "breach streak increments to 1");

   SLO_TestRunPeriodicCheck(t0 + 7261);
   ASSERT_TRUE(g_slo_metrics.slo_breached, "hard breach persists on next check");
   ASSERT_TRUE(SLO_IsMRDisabled(), "MR is disabled after configured persistence checks");
   ASSERT_TRUE(SLO_TestGetConsecutiveBreachChecks() == 2, "breach streak increments to configured threshold");

   return TestSLO_End(f);
}

bool TestSLO_PersistentThrottle_RecoveryClearsDisable()
{
   int f = TestSLO_Begin("TestSLO_PersistentThrottle_RecoveryClearsDisable");

   SLO_TestResetState();
   SLO_TestSetMinSamples(5);
   SLO_TestSetWindowDays(1);
   SLO_TestSetDisableAfterBreachChecks(2);

   datetime t0 = 1704067200;
   for(int i = 0; i < 5; i++)
      SLO_TestIngestTradeClosed((ulong)(9600 + i), (ulong)(4600 + i), "MR", -1.0, 300, 0.50, t0 + (i * 60));

   SLO_TestRunPeriodicCheck(t0 + 3600);
   SLO_TestRunPeriodicCheck(t0 + 3661);
   ASSERT_TRUE(SLO_IsMRDisabled(), "MR disable state reached before recovery");

   datetime t1 = t0 + (3 * 24 * 60 * 60);
   for(int i = 0; i < 5; i++)
      SLO_TestIngestTradeClosed((ulong)(9700 + i), (ulong)(4700 + i), "MR", 1.5, 90, 0.10, t1 + (i * 60));

   SLO_TestRunPeriodicCheck(t1 + 7200);
   ASSERT_FALSE(g_slo_metrics.slo_breached, "hard breach clears after healthy window replaces stale bad samples");
   ASSERT_FALSE(SLO_IsMRDisabled(), "MR disable clears on recovery");
   ASSERT_FALSE(SLO_IsMRThrottled(), "MR throttle clears on recovery");
   ASSERT_TRUE(SLO_TestGetConsecutiveBreachChecks() == 0, "breach streak resets after recovery");

   return TestSLO_End(f);
}

bool TestSLOMonitor_RunAll()
{
   Print("=================================================================");
   Print("Post-M7 Task07/08/09 - SLO Monitor Tests");
   Print("=================================================================");

   bool ok1 = TestSLO_Ingestion_OncePerFinalClose();
   bool ok2 = TestSLO_Ingestion_DuplicateCloseIdIgnored();
   bool ok3 = TestSLO_Ingestion_IgnoresNonMR();
   bool ok4 = TestSLO_Metrics_ComputedFromRollingWindow();
   bool ok5 = TestSLO_Metrics_InsufficientSamplesGuard();
   bool ok6 = TestSLO_PersistentThrottle_DisablesAfterConfiguredChecks();
   bool ok7 = TestSLO_PersistentThrottle_RecoveryClearsDisable();

   return (ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7);
}

#endif // TEST_SLO_MONITOR_MQH
