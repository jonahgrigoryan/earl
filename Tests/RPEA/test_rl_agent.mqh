#ifndef TEST_RL_AGENT_MQH
#define TEST_RL_AGENT_MQH
// test_rl_agent.mqh - Unit tests for M7 RL agent (Task 02)

#include <RPEA/rl_agent.mqh>
#include <RPEA/config.mqh>

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
#define TEST_FRAMEWORK_DEFINED
#endif

bool TestRL_Constants()
{
   int failures_before = g_test_failed;
   g_current_test = "TestRL_Constants";
   ASSERT_EQUALS(4, RL_NUM_PERIODS, "RL_NUM_PERIODS");
   ASSERT_EQUALS(4, RL_NUM_QUANTILES, "RL_NUM_QUANTILES");
   ASSERT_EQUALS(256, RL_NUM_STATES, "RL_NUM_STATES");
   ASSERT_EQUALS(3, RL_NUM_ACTIONS, "RL_NUM_ACTIONS");
   return (g_test_failed == failures_before);
}

bool TestRL_InitQTable()
{
   int failures_before = g_test_failed;
   g_current_test = "TestRL_InitQTable";
   RL_InitQTable();
   ASSERT_TRUE(MathAbs(g_qtable[0][0]) < 1e-9, "Q-table initialized");
   ASSERT_FALSE(g_qtable_loaded, "Q-table not marked loaded");
   return (g_test_failed == failures_before);
}

bool TestRL_QuantileBin()
{
   int failures_before = g_test_failed;
   g_current_test = "TestRL_QuantileBin";
   ASSERT_EQUALS(0, RL_QuantileBin(-0.05), "large negative");
   ASSERT_EQUALS(1, RL_QuantileBin(-0.02), "small negative");
   ASSERT_EQUALS(2, RL_QuantileBin(0.01), "small positive");
   ASSERT_EQUALS(3, RL_QuantileBin(0.05), "large positive");
   return (g_test_failed == failures_before);
}

bool TestRL_StateFromSpread()
{
   int failures_before = g_test_failed;
   g_current_test = "TestRL_StateFromSpread";
   double changes[4] = {-0.05, -0.02, 0.01, 0.05};
   int state = RL_StateFromSpread(changes, 4);
   ASSERT_EQUALS(27, state, "state encoding");
   return (g_test_failed == failures_before);
}

bool TestRL_ActionDefaults()
{
   int failures_before = g_test_failed;
   g_current_test = "TestRL_ActionDefaults";
   g_qtable_loaded = false;
   ASSERT_EQUALS((int)RL_ACTION_HOLD, RL_ActionForState(0), "default hold");
   return (g_test_failed == failures_before);
}

bool TestRL_QAdvantage()
{
   int failures_before = g_test_failed;
   g_current_test = "TestRL_QAdvantage";
   RL_InitQTable();
   g_qtable_loaded = true;
   g_qtable[0][0] = 0.0;
   g_qtable[0][1] = 0.0;
   g_qtable[0][2] = 1.0;
   double adv = RL_GetQAdvantage(0);
   ASSERT_TRUE(adv > 0.5, "advantage > 0.5");
   return (g_test_failed == failures_before);
}

bool TestRL_LoadThresholds()
{
   int failures_before = g_test_failed;
   g_current_test = "TestRL_LoadThresholds";
   FolderCreate(RPEA_DIR);
   string rl_dir = RPEA_DIR + "/rl";
   FolderCreate(rl_dir);
   string path = rl_dir + "/thresholds.json";
   FileDelete(path);
   datetime now = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(now, tm);
   string date_text = StringFormat("%04d-%02d-%02d", tm.year, tm.mon, tm.day);
   string payload = StringFormat("{\"k_thresholds\":[-0.02,0.0,0.02],\"sigma_ref\":0.015,\"calibrated_at\":\"%s\"}", date_text);
   int handle = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI);
   ASSERT_TRUE(handle != INVALID_HANDLE, "thresholds file created");
   if(handle != INVALID_HANDLE)
   {
      FileWrite(handle, payload);
      FileClose(handle);
   }
   bool loaded = RL_LoadThresholds();
   ASSERT_TRUE(loaded, "thresholds loaded");
   ASSERT_TRUE(MathAbs(g_quantile_thresholds[0] + 0.02) < 1e-6, "threshold[0]");
   ASSERT_TRUE(MathAbs(g_quantile_thresholds[1] - 0.0) < 1e-6, "threshold[1]");
   ASSERT_TRUE(MathAbs(g_quantile_thresholds[2] - 0.02) < 1e-6, "threshold[2]");
   FileDelete(path);
   return (g_test_failed == failures_before);
}

bool TestRL_QTableSaveLoad()
{
   int failures_before = g_test_failed;
   g_current_test = "TestRL_QTableSaveLoad";
   FolderCreate(RPEA_DIR);
   FolderCreate(RPEA_QTABLE_DIR);

   string test_path = "RPEA/qtable/mr_qtable_test.bin";
   FileDelete(test_path);
   RL_InitQTable();
   g_qtable_loaded = true;
   g_qtable[0][0] = 1.23;

   bool saved = RL_SaveQTable(test_path);
   ASSERT_TRUE(saved, "saved");

   RL_InitQTable();
   bool loaded = RL_LoadQTable(test_path);
   ASSERT_TRUE(loaded, "loaded");
   ASSERT_TRUE(MathAbs(g_qtable[0][0] - 1.23) < 1e-6, "value restored");
   FileDelete(test_path);
   return (g_test_failed == failures_before);
}

bool TestRL_BellmanUpdate()
{
   int failures_before = g_test_failed;
   g_current_test = "TestRL_BellmanUpdate";
   RL_InitQTable();
   g_qtable_loaded = true;
   RL_BellmanUpdate(0, 2, 1.0, 1, 0.5, 0.99);
   ASSERT_TRUE(g_qtable[0][2] > 0.0, "Q updated");
   return (g_test_failed == failures_before);
}

bool TestRL_RunAll()
{
   Print("=================================================================");
   Print("M7 RL Agent Tests - Task 02");
   Print("=================================================================");
   bool ok1 = TestRL_Constants();
   bool ok2 = TestRL_InitQTable();
   bool ok3 = TestRL_QuantileBin();
   bool ok4 = TestRL_StateFromSpread();
   bool ok5 = TestRL_ActionDefaults();
   bool ok6 = TestRL_QAdvantage();
   bool ok7 = TestRL_LoadThresholds();
   bool ok8 = TestRL_QTableSaveLoad();
   bool ok9 = TestRL_BellmanUpdate();
   return (ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7 && ok8 && ok9);
}

#endif // TEST_RL_AGENT_MQH
