#ifndef TEST_M7_HELPERS_MQH
#define TEST_M7_HELPERS_MQH
// test_m7_helpers.mqh - Unit tests for post-M7 helper data quality tasks

#include <RPEA/m7_helpers.mqh>

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

#define TEST_FRAMEWORK_DEFINED
#endif

int TestM7Helpers_Begin(const string name)
{
   g_current_test = name;
   PrintFormat("[TEST START] %s", g_current_test);
   return g_test_failed;
}

bool TestM7Helpers_End(const int failures_before)
{
   bool ok = (g_test_failed == failures_before);
   PrintFormat("[TEST END] %s - %s", g_current_test, ok ? "OK" : "FAILED");
   return ok;
}

bool TestM7Helpers_SpreadMean_InsufficientSamples()
{
   int f = TestM7Helpers_Begin("TestM7Helpers_SpreadMean_InsufficientSamples");

   M7_TestResetSpreadBuffer();
   M7_TestInjectSpreadSample("EURUSD", 2.0);
   M7_TestInjectSpreadSample("EURUSD", 4.0);

   double mean = M7_TestGetSpreadMeanFromBuffer("EURUSD", 5);
   ASSERT_TRUE(MathAbs(mean - 3.0) < 1e-9, "insufficient samples use available window");

   return TestM7Helpers_End(f);
}

bool TestM7Helpers_SpreadMean_WindowedAverage()
{
   int f = TestM7Helpers_Begin("TestM7Helpers_SpreadMean_WindowedAverage");

   M7_TestResetSpreadBuffer();
   M7_TestInjectSpreadSample("EURUSD", 1.0);
   M7_TestInjectSpreadSample("EURUSD", 2.0);
   M7_TestInjectSpreadSample("EURUSD", 3.0);
   M7_TestInjectSpreadSample("EURUSD", 4.0);

   double mean = M7_TestGetSpreadMeanFromBuffer("EURUSD", 3);
   ASSERT_TRUE(MathAbs(mean - 3.0) < 1e-9, "windowed mean uses most-recent samples");

   return TestM7Helpers_End(f);
}

bool TestM7Helpers_SpreadMean_Rollover()
{
   int f = TestM7Helpers_Begin("TestM7Helpers_SpreadMean_Rollover");

   M7_TestResetSpreadBuffer();
   int total = M7_SPREAD_BUFFER_SAMPLE_CAP + 8;
   for(int i = 1; i <= total; i++)
      M7_TestInjectSpreadSample("XAUUSD", (double)i);

   int count = M7_TestGetSpreadSampleCount("XAUUSD");
   ASSERT_TRUE(count == M7_SPREAD_BUFFER_SAMPLE_CAP, "buffer count capped at fixed capacity");

   double mean = M7_TestGetSpreadMeanFromBuffer("XAUUSD", 5);
   ASSERT_TRUE(MathAbs(mean - (double)(total - 2)) < 1e-9, "rollover keeps most-recent values");

   return TestM7Helpers_End(f);
}

bool TestM7Helpers_ATRPercentile_High()
{
   int f = TestM7Helpers_Begin("TestM7Helpers_ATRPercentile_High");

   AppContext ctx;
   ZeroMemory(ctx);
   ctx.symbols_count = 1;

   double series[];
   ArrayResize(series, 41);
   series[0] = 100.0;
   for(int i = 1; i < 41; i++)
      series[i] = (double)i;
   M7_TestSetATRPercentileSeries("EURUSD", series);

   double pct = M7_GetATR_D1_Percentile(ctx, "EURUSD");
   ASSERT_TRUE(MathAbs(pct - 1.0) < 1e-9, "high current ATR maps to high percentile");

   M7_TestClearATRPercentileSeries();
   return TestM7Helpers_End(f);
}

bool TestM7Helpers_ATRPercentile_Low()
{
   int f = TestM7Helpers_Begin("TestM7Helpers_ATRPercentile_Low");

   AppContext ctx;
   ZeroMemory(ctx);
   ctx.symbols_count = 1;

   double series[];
   ArrayResize(series, 41);
   series[0] = 0.25;
   for(int i = 1; i < 41; i++)
      series[i] = (double)i;
   M7_TestSetATRPercentileSeries("EURUSD", series);

   double pct = M7_GetATR_D1_Percentile(ctx, "EURUSD");
   ASSERT_TRUE(MathAbs(pct - 0.0) < 1e-9, "low current ATR maps to low percentile");

   M7_TestClearATRPercentileSeries();
   return TestM7Helpers_End(f);
}

bool TestM7Helpers_ATRPercentile_InsufficientSamples()
{
   int f = TestM7Helpers_Begin("TestM7Helpers_ATRPercentile_InsufficientSamples");

   AppContext ctx;
   ZeroMemory(ctx);
   ctx.symbols_count = 1;

   double series[];
   ArrayResize(series, 6);
   series[0] = 10.0;
   for(int i = 1; i < 6; i++)
      series[i] = (double)i;
   M7_TestSetATRPercentileSeries("EURUSD", series);

   double pct = M7_GetATR_D1_Percentile(ctx, "EURUSD");
   ASSERT_TRUE(MathAbs(pct - 0.5) < 1e-9, "insufficient lookback returns neutral percentile");

   M7_TestClearATRPercentileSeries();
   return TestM7Helpers_End(f);
}

bool TestM7Helpers_RunAll()
{
   Print("=================================================================");
   Print("Post-M7 Task02/03 - M7 Helpers Tests");
   Print("=================================================================");

   bool ok1 = TestM7Helpers_SpreadMean_InsufficientSamples();
   bool ok2 = TestM7Helpers_SpreadMean_WindowedAverage();
   bool ok3 = TestM7Helpers_SpreadMean_Rollover();
   bool ok4 = TestM7Helpers_ATRPercentile_High();
   bool ok5 = TestM7Helpers_ATRPercentile_Low();
   bool ok6 = TestM7Helpers_ATRPercentile_InsufficientSamples();

   return (ok1 && ok2 && ok3 && ok4 && ok5 && ok6);
}

#endif // TEST_M7_HELPERS_MQH
