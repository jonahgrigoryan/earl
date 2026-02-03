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

   return (ok1 && ok2 && ok3);
}

#endif // TEST_REGIME_TELEMETRY_MQH
