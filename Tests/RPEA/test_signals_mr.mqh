#ifndef TEST_SIGNALS_MR_MQH
#define TEST_SIGNALS_MR_MQH
// test_signals_mr.mqh - Unit tests for M7 SignalMR (Task 04)

#include <RPEA/app_context.mqh>
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
      double _diff = MathAbs((double)(expected) - (double)(actual)); \
      if(_diff <= (tolerance)) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%.6f, actual=%.6f)", g_current_test, message, (double)(expected), (double)(actual)); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%.6f, actual=%.6f)", g_current_test, message, (double)(expected), (double)(actual)); \
      } \
   } while(false)

#define TEST_FRAMEWORK_DEFINED
#endif

void TestSignalsMR_ResetState()
{
   g_emrt_loaded = false;
   g_qtable_loaded = false;
   g_mr_proxy_warned = false;
   Config_Test_ClearQLModeOverride();
   Config_Test_ClearEnableMRBypassOnRLUnloadedOverride();
}

int TestSignalsMR_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestSignalsMR_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s", g_current_test);
   return ok;
}

bool TestSignalsMR_SkipsNonGold()
{
   TestSignalsMR_ResetState();
   int failures_before = TestSignalsMR_Begin("TestSignalsMR_SkipsNonGold");

   AppContext ctx;
   ZeroMemory(ctx);
   bool has_setup = false;
   string setup_type = "";
   int sl_points = 0;
   int tp_points = 0;
   double bias = 0.0;
   double confidence = 0.0;

   SignalsMR_Propose(ctx, "EURUSD", has_setup, setup_type, sl_points, tp_points, bias, confidence);

   ASSERT_FALSE(has_setup, "Non-gold symbol returns no setup");
   ASSERT_TRUE(StringCompare(setup_type, "None") == 0, "setupType remains None");

   return TestSignalsMR_End(failures_before);
}

bool TestSignalsMR_GetSpreadChanges_ZeroPeriods()
{
   TestSignalsMR_ResetState();
   int failures_before = TestSignalsMR_Begin("TestSignalsMR_GetSpreadChanges_ZeroPeriods");

   double changes[];
   SignalsMR_GetSpreadChanges("XAUEUR", changes, 0);
   ASSERT_EQUALS(0, ArraySize(changes), "Zero periods yields empty changes array");

   return TestSignalsMR_End(failures_before);
}

bool TestSignalsMR_CalculateSLTP_NoATR()
{
   TestSignalsMR_ResetState();
   int failures_before = TestSignalsMR_Begin("TestSignalsMR_CalculateSLTP_NoATR");

   int sl_points = -1;
   int tp_points = -1;
   SignalsMR_CalculateSLTP("INVALID", 1, sl_points, tp_points);

   ASSERT_EQUALS(0, sl_points, "SL points default to 0 when ATR/point unavailable");
   ASSERT_EQUALS(0, tp_points, "TP points default to 0 when ATR/point unavailable");

   return TestSignalsMR_End(failures_before);
}

bool TestSignalsMR_RuntimeQLDisabled_NeutralizesGate()
{
   TestSignalsMR_ResetState();
   int failures_before = TestSignalsMR_Begin("TestSignalsMR_RuntimeQLDisabled_NeutralizesGate");

   Config_Test_SetQLModeOverride(true, "disabled");
   int action = -1;
   double q_advantage = 0.0;
   bool ok = SignalsMR_ResolveRuntimeQL("XAUEUR", TimeCurrent(), 7, action, q_advantage);

   ASSERT_TRUE(ok, "ql_mode=disabled bypasses RL entry gate");
   ASSERT_EQUALS((int)RL_ACTION_HOLD, action, "disabled RL returns neutral HOLD action");
   ASSERT_NEAR(0.5, q_advantage, 1e-9, "disabled RL returns neutral q-advantage");

   return TestSignalsMR_End(failures_before);
}

bool TestSignalsMR_RuntimeQLEnabled_UnloadedFailsWithoutBypass()
{
   TestSignalsMR_ResetState();
   int failures_before = TestSignalsMR_Begin("TestSignalsMR_RuntimeQLEnabled_UnloadedFailsWithoutBypass");

   Config_Test_SetQLModeOverride(true, "enabled");
   Config_Test_SetEnableMRBypassOnRLUnloadedOverride(true, false);
   int action = -1;
   double q_advantage = 0.0;
   bool ok = SignalsMR_ResolveRuntimeQL("XAUEUR", TimeCurrent(), 3, action, q_advantage);

   ASSERT_FALSE(ok, "enabled RL rejects unloaded q-table when bypass is off");

   return TestSignalsMR_End(failures_before);
}

bool TestSignalsMR_RunAll()
{
   Print("=================================================================");
   Print("M7 SignalMR Tests - Task 04");
   Print("=================================================================");

   bool ok1 = TestSignalsMR_SkipsNonGold();
   bool ok2 = TestSignalsMR_GetSpreadChanges_ZeroPeriods();
   bool ok3 = TestSignalsMR_CalculateSLTP_NoATR();
   bool ok4 = TestSignalsMR_RuntimeQLDisabled_NeutralizesGate();
   bool ok5 = TestSignalsMR_RuntimeQLEnabled_UnloadedFailsWithoutBypass();
   return (ok1 && ok2 && ok3 && ok4 && ok5);
}

#endif // TEST_SIGNALS_MR_MQH
