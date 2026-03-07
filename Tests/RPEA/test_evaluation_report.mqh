#ifndef TEST_EVALUATION_REPORT_MQH
#define TEST_EVALUATION_REPORT_MQH
// test_evaluation_report.mqh - Phase 0 FundingPips evaluation artifact tests

#include <RPEA/evaluation_report.mqh>

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

int TestEvaluationReport_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestEvaluationReport_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s - %s", g_current_test, ok ? "OK" : "FAILED");
   return ok;
}

ChallengeState TestEvaluationReport_MakeState(const double initial_baseline,
                                              const double baseline_today,
                                              const int days_traded,
                                              const datetime midnight)
{
   ChallengeState st;
   ZeroMemory(st);
   st.initial_baseline = initial_baseline;
   st.baseline_today = baseline_today;
   st.baseline_today_e0 = baseline_today;
   st.baseline_today_b0 = baseline_today;
   st.gDaysTraded = days_traded;
   st.server_midnight_ts = midnight;
   st.trading_enabled = true;
   st.state_version = STATE_VERSION_CURRENT;
   return st;
}

bool TestEvaluationReport_LossMath()
{
   int f = TestEvaluationReport_Begin("TestEvaluationReport_LossMath");

   ASSERT_TRUE(MathAbs(EvaluationReport_ComputeLossPct(10000.0, 9700.0) - 3.0) < 1e-9,
               "loss percent uses baseline-relative drawdown");
   ASSERT_TRUE(MathAbs(EvaluationReport_ComputeLossPct(10000.0, 10050.0)) < 1e-9,
               "loss percent clamps non-loss values to zero");
   ASSERT_TRUE(EvaluationReport_PassCondition(11050.0, 10000.0, 3, 3, false, false),
               "pass condition succeeds at target with minimum days and no breaches");
   ASSERT_FALSE(EvaluationReport_PassCondition(11050.0, 10000.0, 2, 3, false, false),
                "pass condition fails when minimum days are missing");

   return TestEvaluationReport_End(f);
}

bool TestEvaluationReport_DailyTracking()
{
   int f = TestEvaluationReport_Begin("TestEvaluationReport_DailyTracking");

   ChallengeState st = TestEvaluationReport_MakeState(10000.0, 10000.0, 1, D'2024.01.01 00:00');
   EvaluationReport_TestInitSnapshot(D'2024.01.01 00:05', 10000.0, 10000.0, 10000.0, st);
   EvaluationReport_TestUpdateSnapshot(D'2024.01.01 01:00', 9800.0, 10000.0, st);

   EvaluationReportDay day;
   ASSERT_TRUE(EvaluationReport_TestGetDayCount() == 1, "one day record created for first snapshot");
   ASSERT_TRUE(EvaluationReport_TestGetDayRecord(0, day), "day record accessible");
   ASSERT_TRUE(MathAbs(day.max_daily_dd_pct - 2.0) < 1e-6, "daily drawdown tracks min equity");
   ASSERT_FALSE(day.daily_breach, "daily breach stays false while above floor");

   st.daily_floor_breached = true;
   EvaluationReport_TestUpdateSnapshot(D'2024.01.01 02:00', 9600.0, 10000.0, st);
   ASSERT_TRUE(EvaluationReport_TestGetDayRecord(0, day), "day record remains accessible after second update");
   ASSERT_TRUE(MathAbs(day.max_daily_dd_pct - 4.0) < 1e-6, "daily drawdown updates on deeper loss");
   ASSERT_TRUE(day.daily_breach, "daily breach persists once triggered");
   ASSERT_TRUE(EvaluationReport_TestGetAnyDailyBreach(), "aggregate daily breach flag tracks per-day breach");
   ASSERT_TRUE(MathAbs(EvaluationReport_TestGetMaxOverallDdPct() - 4.0) < 1e-6,
               "overall drawdown tracks against initial baseline");

   st = TestEvaluationReport_MakeState(10000.0, 10200.0, 2, D'2024.01.01 00:00');
   EvaluationReport_TestUpdateSnapshot(D'2024.01.02 00:10', 10100.0, 10100.0, st);
   ASSERT_TRUE(EvaluationReport_TestGetDayCount() == 2, "new server day creates a second record");
   ASSERT_TRUE(EvaluationReport_TestGetDayRecord(1, day), "second day record accessible");
   ASSERT_TRUE(day.server_midnight_ts == D'2024.01.02 00:00',
               "new day record uses the observed server midnight even when rollover state is stale");
   ASSERT_TRUE(MathAbs(day.baseline_used - 10100.0) < 1e-6,
               "stale rollover state falls back to observed equity and balance");

   EvaluationReport_TestReset();
   st = TestEvaluationReport_MakeState(10000.0, 10000.0, 1, D'2024.01.01 00:00');
   EvaluationReport_TestInitSnapshot(D'2024.01.01 00:05', 10000.0, 10000.0, 10000.0, st);
   st = TestEvaluationReport_MakeState(10000.0, 10200.0, 2, D'2024.01.02 00:00');
   EvaluationReport_TestUpdateSnapshot(D'2024.01.02 00:10', 10100.0, 10100.0, st);
   ASSERT_TRUE(EvaluationReport_TestGetDayCount() == 2, "fresh rollover also creates a second day record");
   ASSERT_TRUE(EvaluationReport_TestGetDayRecord(1, day), "fresh rollover day record accessible");
   ASSERT_TRUE(MathAbs(day.baseline_used - 10200.0) < 1e-6,
               "fresh rollover state keeps the persisted rollover baseline");

   return TestEvaluationReport_End(f);
}

bool TestEvaluationReport_TargetThenPass()
{
   int f = TestEvaluationReport_Begin("TestEvaluationReport_TargetThenPass");

   ChallengeState st = TestEvaluationReport_MakeState(10000.0, 10000.0, 2, D'2024.01.01 00:00');
   EvaluationReport_TestInitSnapshot(D'2024.01.01 08:00', 10000.0, 10000.0, 10000.0, st);
   EvaluationReport_TestUpdateSnapshot(D'2024.01.01 09:00', 11020.0, 10000.0, st);

   ASSERT_TRUE(EvaluationReport_TestGetTargetHit(), "target hit is recorded as soon as equity crosses the threshold");
   ASSERT_TRUE(EvaluationReport_TestGetTargetHitDays() == 2, "target hit captures current trading-day count");
   ASSERT_FALSE(EvaluationReport_TestGetPassAchieved(), "target hit alone does not pass before minimum days");

   st.gDaysTraded = 3;
   EvaluationReport_TestUpdateSnapshot(D'2024.01.02 09:00', 11010.0, 10000.0, st);
   ASSERT_TRUE(EvaluationReport_TestGetPassAchieved(), "pass is recorded once minimum days and target are both satisfied");
   ASSERT_TRUE(EvaluationReport_TestGetPassDays() == 3, "pass capture uses the trading-day count at pass time");

   return TestEvaluationReport_End(f);
}

bool TestEvaluationReport_RunAll()
{
   Print("=================================================================");
   Print("FundingPips Phase 0 - Evaluation Report Tests");
   Print("=================================================================");

   bool ok = true;
   ok = TestEvaluationReport_LossMath() && ok;
   ok = TestEvaluationReport_DailyTracking() && ok;
   ok = TestEvaluationReport_TargetThenPass() && ok;
   return ok;
}

#endif // TEST_EVALUATION_REPORT_MQH
