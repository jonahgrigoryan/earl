#ifndef TEST_ANOMALY_MQH
#define TEST_ANOMALY_MQH
// test_anomaly.mqh - Deterministic anomaly shock detector tests

#include <RPEA/anomaly.mqh>

struct AppContext;
void SignalsBWISC_Propose(const AppContext& ctx, const string symbol,
                          bool &hasSetup, string &setupType,
                          int &slPoints, int &tpPoints,
                          double &bias, double &confidence);
void SignalsMR_Propose(const AppContext& ctx, const string symbol,
                       bool &hasSetup, string &setupType,
                       int &slPoints, int &tpPoints,
                       double &bias, double &confidence);
#include <RPEA/scheduler.mqh>

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

int TestAnomaly_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestAnomaly_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s - %s", g_current_test, ok ? "OK" : "FAILED");
   return ok;
}

void TestAnomaly_ResetConfigOverrides()
{
   Config_Test_ClearEnableAnomalyOverride();
   Config_Test_ClearAnomalyShadowModeOverride();
   Config_Test_ClearAnomalySigmaOverride();
}

bool TestAnomaly_NoShockBaseline()
{
   int f = TestAnomaly_Begin("TestAnomaly_NoShockBaseline");

   TestAnomaly_ResetConfigOverrides();
   Config_Test_SetEnableAnomalyOverride(true, true);
   Anomaly_TestResetState();

   AnomalySnapshot snapshot;
   bool ok = true;
   for(int i = 0; i < 30; i++)
   {
      ok = Anomaly_TestEvaluateSample("EURUSD", 100.0, 12.0, 1.0, snapshot);
      ASSERT_TRUE(ok, "stable baseline sample accepted");
   }

   ASSERT_FALSE(snapshot.shock, "stable baseline does not trigger shock");
   ASSERT_TRUE(snapshot.action == ANOMALY_ACTION_NONE, "stable baseline keeps action at none");
   ASSERT_TRUE(StringCompare(snapshot.reason, "no_shock") == 0, "steady state ends in no_shock reason");

   TestAnomaly_ResetConfigOverrides();
   return TestAnomaly_End(f);
}

bool TestAnomaly_ShockTrigger()
{
   int f = TestAnomaly_Begin("TestAnomaly_ShockTrigger");

   TestAnomaly_ResetConfigOverrides();
   Config_Test_SetEnableAnomalyOverride(true, true);
   Config_Test_SetAnomalySigmaOverride(true, 3.0);
   Anomaly_TestResetState();

   AnomalySnapshot snapshot;
   bool ok = true;
   for(int i = 0; i < 24; i++)
      ok = Anomaly_TestEvaluateSample("EURUSD", 100.0, 10.0, 1.0, snapshot);
   ASSERT_TRUE(ok, "baseline warmup accepted");

   ok = Anomaly_TestEvaluateSample("EURUSD", 102.5, 80.0, 12.0, snapshot);
   ASSERT_TRUE(ok, "shock sample accepted");
   ASSERT_TRUE(snapshot.shock, "large discontinuity triggers shock");
   ASSERT_TRUE(snapshot.action == ANOMALY_ACTION_FLATTEN, "severe shock escalates to flatten action");

   TestAnomaly_ResetConfigOverrides();
   return TestAnomaly_End(f);
}

bool TestAnomaly_InsufficientData()
{
   int f = TestAnomaly_Begin("TestAnomaly_InsufficientData");

   TestAnomaly_ResetConfigOverrides();
   Config_Test_SetEnableAnomalyOverride(true, true);
   Config_Test_SetAnomalySigmaOverride(true, 2.5);
   Anomaly_TestResetState();

   AnomalySnapshot snapshot;
   bool ok = true;
   for(int i = 0; i < 5; i++)
      ok = Anomaly_TestEvaluateSample("GBPUSD", 150.0 + (double)i, 30.0, 8.0, snapshot);

   ASSERT_TRUE(ok, "few-sample run accepted");
   ASSERT_FALSE(snapshot.shock, "insufficient samples suppresses shock decisions");
   ASSERT_TRUE(StringCompare(snapshot.reason, "insufficient_samples") == 0,
               "insufficient sample reason returned");

   TestAnomaly_ResetConfigOverrides();
   return TestAnomaly_End(f);
}

bool TestAnomaly_InvalidDataFallback()
{
   int f = TestAnomaly_Begin("TestAnomaly_InvalidDataFallback");

   TestAnomaly_ResetConfigOverrides();
   Config_Test_SetEnableAnomalyOverride(true, true);
   Anomaly_TestResetState();

   AnomalySnapshot snapshot;
   bool ok = Anomaly_TestEvaluateSample("EURUSD", 0.0, -1.0, 1.0, snapshot);

   ASSERT_FALSE(ok, "invalid sample is rejected");
   ASSERT_FALSE(snapshot.shock, "invalid sample does not trigger shock");
   ASSERT_TRUE(StringCompare(snapshot.reason, "invalid_sample") == 0,
               "invalid sample reason is explicit");

   TestAnomaly_ResetConfigOverrides();
   return TestAnomaly_End(f);
}

bool TestAnomaly_ShadowVsActiveBehavior()
{
   int f = TestAnomaly_Begin("TestAnomaly_ShadowVsActiveBehavior");

   TestAnomaly_ResetConfigOverrides();

   Config_Test_SetEnableAnomalyOverride(true, true);
   Config_Test_SetAnomalyShadowModeOverride(true, true);
   ASSERT_FALSE(Anomaly_ShouldRunActiveMode(), "shadow mode keeps detector non-enforcing");

   Config_Test_SetAnomalyShadowModeOverride(true, false);
   ASSERT_TRUE(Anomaly_ShouldRunActiveMode(), "active mode enables enforcement path");

   Config_Test_SetEnableAnomalyOverride(true, false);
   ASSERT_FALSE(Anomaly_ShouldRunActiveMode(), "detector disable overrides active mode");

   TestAnomaly_ResetConfigOverrides();
   return TestAnomaly_End(f);
}

bool TestAnomaly_SchedulerActionSemantics()
{
   int f = TestAnomaly_Begin("TestAnomaly_SchedulerActionSemantics");

   ASSERT_FALSE(Scheduler_AnomalyActionHasExecutionHandler(ANOMALY_ACTION_WIDEN),
                "widen has no active execution handler");
   ASSERT_TRUE(Scheduler_AnomalyActionHasExecutionHandler(ANOMALY_ACTION_CANCEL),
               "cancel has active execution handler");
   ASSERT_TRUE(Scheduler_AnomalyActionHasExecutionHandler(ANOMALY_ACTION_FLATTEN),
               "flatten has active execution handler");

   ASSERT_FALSE(Scheduler_AnomalyShouldBlockEntries(true, true, ANOMALY_ACTION_WIDEN),
                "widen does not hard-block entries in active mode");
   ASSERT_TRUE(Scheduler_AnomalyShouldBlockEntries(true, true, ANOMALY_ACTION_CANCEL),
               "cancel blocks entries in active mode");
   ASSERT_TRUE(Scheduler_AnomalyShouldBlockEntries(true, true, ANOMALY_ACTION_FLATTEN),
               "flatten blocks entries in active mode");
   ASSERT_FALSE(Scheduler_AnomalyShouldBlockEntries(true, false, ANOMALY_ACTION_CANCEL),
                "non-shock path never blocks entries");
   ASSERT_FALSE(Scheduler_AnomalyShouldBlockEntries(false, true, ANOMALY_ACTION_CANCEL),
                "shadow mode never blocks entries");

   return TestAnomaly_End(f);
}

bool TestAnomaly_ConfigClampMinSamples()
{
   int f = TestAnomaly_Begin("TestAnomaly_ConfigClampMinSamples");

   ASSERT_TRUE(Config_ClampAnomalyMinSamples(0) == 1,
               "min samples clamp maps 0 to 1");
   ASSERT_TRUE(Config_ClampAnomalyMinSamples(-10) == 1,
               "min samples clamp maps negatives to 1");
   ASSERT_TRUE(Config_ClampAnomalyMinSamples(5001) == 5000,
               "min samples clamp caps values above 5000");
   ASSERT_TRUE(Config_ClampAnomalyMinSamples(DEFAULT_AnomalyMinSamples) == DEFAULT_AnomalyMinSamples,
               "default min samples remains unchanged");

   return TestAnomaly_End(f);
}

bool TestAnomaly_RunAll()
{
   Print("=================================================================");
   Print("Post-release - Anomaly Shock Detector Tests");
   Print("=================================================================");

   bool ok1 = TestAnomaly_NoShockBaseline();
   bool ok2 = TestAnomaly_ShockTrigger();
   bool ok3 = TestAnomaly_InsufficientData();
   bool ok4 = TestAnomaly_InvalidDataFallback();
   bool ok5 = TestAnomaly_ShadowVsActiveBehavior();
   bool ok6 = TestAnomaly_SchedulerActionSemantics();
   bool ok7 = TestAnomaly_ConfigClampMinSamples();

   return (ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7);
}

#endif // TEST_ANOMALY_MQH
