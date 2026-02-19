#ifndef TEST_REGIME_TELEMETRY_MQH
#define TEST_REGIME_TELEMETRY_MQH
// test_regime_telemetry.mqh - Unit tests for M7 Task 06 (Regime + Telemetry)

#include <RPEA/app_context.mqh>
#include <RPEA/liquidity.mqh>
#include <RPEA/regime.mqh>
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

int TestRegimeTelemetry_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestRegimeTelemetry_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s - %s", g_current_test, ok ? "OK" : "FAILED");
   return ok;
}

//+------------------------------------------------------------------+
//| Test: Regime default is RANGING with neutral ATR + no ADX        |
//+------------------------------------------------------------------+
bool TestRegime_DefaultRanging()
{
   int f = TestRegimeTelemetry_Begin("TestRegime_DefaultRanging");

   AppContext ctx;
   ZeroMemory(ctx);
   ctx.current_server_time = TimeCurrent();

   string symbol = "RPEA_INVALID_SYMBOL";
   REGIME_LABEL label = Regime_Detect(ctx, symbol);
   ASSERT_TRUE(label == REGIME_RANGING, "Regime_Detect returns RANGING by default");

   return TestRegimeTelemetry_End(f);
}

//+------------------------------------------------------------------+
//| Test: Liquidity quantiles default to 0.5 with no stats           |
//+------------------------------------------------------------------+
bool TestLiquidity_DefaultQuantiles()
{
   int f = TestRegimeTelemetry_Begin("TestLiquidity_DefaultQuantiles");

   string symbol = "RPEA_LIQ_TEST";
   double spread_q = Liquidity_GetSpreadQuantile(symbol);
   double slippage_q = Liquidity_GetSlippageQuantile(symbol);

   ASSERT_TRUE(MathAbs(spread_q - 0.5) < 1e-9, "Spread quantile defaults to 0.5");
   ASSERT_TRUE(MathAbs(slippage_q - 0.5) < 1e-9, "Slippage quantile defaults to 0.5");

   return TestRegimeTelemetry_End(f);
}

//+------------------------------------------------------------------+
//| Test: Telemetry LogMetaPolicyDecision smoke test                 |
//+------------------------------------------------------------------+
bool TestTelemetry_Smoke()
{
   int f = TestRegimeTelemetry_Begin("TestTelemetry_Smoke");

   LogMetaPolicyDecision("XAUUSD",
                         "Skip",
                         "SKIP_NO_SETUP",
                         "CLEAR",
                         0.0,
                         0.0,
                         0.0,
                         0.0,
                         0.0,
                         0.0,
                         0.0,
                         0.5,
                         0.5,
                         0.5,
                         0,
                         REGIME_UNKNOWN);

   ASSERT_TRUE(true, "LogMetaPolicyDecision executes without error");

   return TestRegimeTelemetry_End(f);
}

//+------------------------------------------------------------------+
//| Test: KPI updates respect minimum sample threshold               |
//+------------------------------------------------------------------+
bool TestTelemetry_KpiThreshold()
{
   int f = TestRegimeTelemetry_Begin("TestTelemetry_KpiThreshold");

   Telemetry_TestReset();
   Telemetry_TestSetMinSamples(3);
   Telemetry_TestRecordOutcome("BWISC", 1.0);
   Telemetry_TestRecordOutcome("BWISC", -0.5);

   ASSERT_TRUE(MathAbs(Telemetry_GetBWISCEfficiency()) < 1e-9,
               "efficiency is zero below sample threshold");
   ASSERT_TRUE(MathAbs(Telemetry_GetBWISCExpectancy()) < 1e-9,
               "expectancy is zero below sample threshold");

   Telemetry_TestRecordOutcome("BWISC", 0.5);
   ASSERT_TRUE(Telemetry_GetBWISCSamples() == 3, "sample count tracks outcomes");
   ASSERT_TRUE(MathAbs(Telemetry_GetBWISCExpectancy() - (1.0 / 3.0)) < 1e-6,
               "expectancy is computed after threshold is reached");
   ASSERT_TRUE(MathAbs(Telemetry_GetBWISCEfficiency() - 0.75) < 1e-6,
               "efficiency ratio uses positive/(positive+negative)");

   return TestRegimeTelemetry_End(f);
}

//+------------------------------------------------------------------+
//| Test: BWISC and MR KPI state remain strategy-scoped             |
//+------------------------------------------------------------------+
bool TestTelemetry_StrategyIsolation()
{
   int f = TestRegimeTelemetry_Begin("TestTelemetry_StrategyIsolation");

   Telemetry_TestReset();
   Telemetry_TestSetMinSamples(2);
   Telemetry_TestRecordOutcome("MR", 2.0);
   Telemetry_TestRecordOutcome("MR", -1.0);

   ASSERT_TRUE(Telemetry_GetBWISCSamples() == 0, "BWISC sample count unaffected by MR updates");
   ASSERT_TRUE(MathAbs(Telemetry_GetBWISCEfficiency()) < 1e-9, "BWISC efficiency stays zero");
   ASSERT_TRUE(Telemetry_GetMRSamples() == 2, "MR sample count updates independently");
   ASSERT_TRUE(MathAbs(Telemetry_GetMRExpectancy() - 0.5) < 1e-6, "MR expectancy computed correctly");
   ASSERT_TRUE(MathAbs(Telemetry_GetMREfficiency() - (2.0 / 3.0)) < 1e-6,
               "MR efficiency computed correctly");

   return TestRegimeTelemetry_End(f);
}

//+------------------------------------------------------------------+
//| Test: Partial exits are aggregated and counted once on close     |
//+------------------------------------------------------------------+
bool TestTelemetry_PositionExitFinalization()
{
   int f = TestRegimeTelemetry_Begin("TestTelemetry_PositionExitFinalization");

   Telemetry_TestReset();
   Telemetry_TestSetMinSamples(1);

   datetime t0 = D'2024.01.01 00:00';
   Telemetry_TestProcessPositionEntry(10001, "PX MR-MR b=0.70", t0);
   ASSERT_TRUE(Telemetry_TestGetTrackedPositionCount() == 1,
               "position tracker created on entry");

   bool emitted_partial = Telemetry_TestProcessPositionExit(10001, "PX MR-MR", -0.25, t0 + 600, false);
   ASSERT_FALSE(emitted_partial, "partial close does not emit KPI sample");
   ASSERT_TRUE(Telemetry_GetMRSamples() == 0, "MR samples remain unchanged on partial close");

   bool emitted_final = Telemetry_TestProcessPositionExit(10001, "PX MR-MR", 0.75, t0 + 1200, true);
   ASSERT_TRUE(emitted_final, "final close emits KPI sample");
   ASSERT_TRUE(Telemetry_GetMRSamples() == 1, "MR samples increment exactly once");
   ASSERT_TRUE(MathAbs(Telemetry_GetMRExpectancy() - 0.50) < 1e-6,
               "aggregated outcome across partial+final close is used");
   ASSERT_TRUE(Telemetry_TestGetTrackedPositionCount() == 0,
               "position tracker removed after final close");

   return TestRegimeTelemetry_End(f);
}

//+------------------------------------------------------------------+
//| Test: Entry strategy tracking wins over ambiguous exit comment    |
//+------------------------------------------------------------------+
bool TestTelemetry_PositionExitStrategyAttribution()
{
   int f = TestRegimeTelemetry_Begin("TestTelemetry_PositionExitStrategyAttribution");

   Telemetry_TestReset();
   Telemetry_TestSetMinSamples(1);

   datetime t0 = D'2024.01.01 01:00';
   Telemetry_TestProcessPositionEntry(20002, "PX BWISC-BC b=0.60", t0);

   string out_strategy = "";
   double out_total_outcome = 0.0;
   int out_hold_minutes = 0;
   bool emitted = Telemetry_TestProcessPositionExitDetailed(20002,
                                                            "PX MR-MR b=0.80",
                                                            -0.40,
                                                            t0 + 300,
                                                            true,
                                                            out_strategy,
                                                            out_total_outcome,
                                                            out_hold_minutes);

   ASSERT_TRUE(emitted, "final close emits KPI sample");
   ASSERT_TRUE(out_strategy == "BWISC", "tracked entry strategy overrides conflicting exit hint");
   ASSERT_TRUE(Telemetry_GetBWISCSamples() == 1, "BWISC sample incremented");
   ASSERT_TRUE(Telemetry_GetMRSamples() == 0, "MR sample not incremented");

   return TestRegimeTelemetry_End(f);
}

//+------------------------------------------------------------------+
//| Test: Hold minutes are captured from entry and final exit times   |
//+------------------------------------------------------------------+
bool TestTelemetry_PositionExitHoldMinutes()
{
   int f = TestRegimeTelemetry_Begin("TestTelemetry_PositionExitHoldMinutes");

   Telemetry_TestReset();
   Telemetry_TestSetMinSamples(1);

   datetime t0 = D'2024.01.01 02:00';
   Telemetry_TestProcessPositionEntry(30003, "PX MR-MR b=0.90", t0);

   string out_strategy = "";
   double out_total_outcome = 0.0;
   int out_hold_minutes = 0;
   bool emitted = Telemetry_TestProcessPositionExitDetailed(30003,
                                                            "PX MR-MR b=0.90",
                                                            0.30,
                                                            t0 + (61 * 60),
                                                            true,
                                                            out_strategy,
                                                            out_total_outcome,
                                                            out_hold_minutes);

   ASSERT_TRUE(emitted, "final close emits KPI sample");
   ASSERT_TRUE(out_strategy == "MR", "MR strategy preserved");
   ASSERT_TRUE(MathAbs(out_total_outcome - 0.30) < 1e-6, "outcome forwarded unchanged on single-close trade");
   ASSERT_TRUE(out_hold_minutes == 61, "hold minutes derived from entry and exit timestamps");

   return TestRegimeTelemetry_End(f);
}

//+------------------------------------------------------------------+
//| Suite runner                                                     |
//+------------------------------------------------------------------+
bool TestRegimeTelemetry_RunAll()
{
   Print("=================================================================");
   Print("M7 Task 06 - Regime + Telemetry Tests");
   Print("=================================================================");

   bool ok1 = TestRegime_DefaultRanging();
   bool ok2 = TestLiquidity_DefaultQuantiles();
   bool ok3 = TestTelemetry_Smoke();
   bool ok4 = TestTelemetry_KpiThreshold();
   bool ok5 = TestTelemetry_StrategyIsolation();
   bool ok6 = TestTelemetry_PositionExitFinalization();
   bool ok7 = TestTelemetry_PositionExitStrategyAttribution();
   bool ok8 = TestTelemetry_PositionExitHoldMinutes();

   return (ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7 && ok8);
}

#endif // TEST_REGIME_TELEMETRY_MQH
