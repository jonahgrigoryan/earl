//+------------------------------------------------------------------+
//|                                     run_automated_tests_ea.mq5  |
//|                      RPEA Automated Test Runner with Reporting  |
//|                         Writes results to JSON for CI/CD        |
//+------------------------------------------------------------------+
#property copyright "RPEA"
#property version   "1.00"
#property strict

// EA mode for automated testing
#define MaxOpenPositionsTotal  2
#define MaxOpenPerSymbol       1
#define MaxPendingsPerSymbol   2
#define DailyLossCapPct        4.0
#define OverallLossCapPct      6.0
#define MinRiskDollar          10.0
#define OneAndDoneR            1.5
#define NYGatePctOfDailyCap    0.50
#define RiskPct                1.5
#define MicroRiskPct           0.10
#define GivebackCapDayPct      0.50
#define MinStopPoints          1
#define RPEA_ORDER_ENGINE_SKIP_RISK
#define RPEA_ORDER_ENGINE_SKIP_EQUITY

// Include test reporter
#include "../../MQL5/Include/RPEA/test_reporter.mqh"

// Include test files
#include "test_order_engine.mqh"
#include "test_order_engine_normalization.mqh"
#include "test_order_engine_limits.mqh"
#include "test_order_engine_retry.mqh"
#include "test_order_engine_market.mqh"
#include "test_order_engine_intent.mqh"

// Mock functions for testing
double Equity_CalcRiskDollars(const string symbol,
                              const double volume,
                              const double price_entry,
                              const double stop_price,
                              bool &ok)
{
   ok = true;
   return 50.0; // Mock risk calculation
}

bool Equity_CheckPositionCaps(const string symbol,
                              int &out_total_positions,
                              int &out_symbol_positions,
                              int &out_symbol_pending)
{
   out_total_positions = 0;
   out_symbol_positions = 0;
   out_symbol_pending = 0;
   return true;
}

bool Equity_IsPendingOrderType(const int type)
{
   switch(type)
   {
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_SELL_LIMIT:
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_SELL_STOP:
      case ORDER_TYPE_BUY_STOP_LIMIT:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         return true;
   }
   return false;
}

// Global flag to track if tests have been run
bool g_tests_executed = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("==========================================");
   Print("RPEA AUTOMATED TEST RUNNER");
   Print("==========================================");

   g_test_reporter.SetOutputPath("RPEA/test_results/test_results.json");
   g_test_reporter.SetVerbose(true);

   // Run tests on initialization
   RunAllTests();

   // Write results to file
   g_test_reporter.WriteResults();
   g_test_reporter.PrintSummary();

   // Mark as executed
   g_tests_executed = true;

   // Exit immediately if all tests passed
   if(g_test_reporter.AllTestsPassed())
   {
      Print("[SUCCESS] All tests passed. Shutting down EA...");
      ExpertRemove();
      return(INIT_SUCCEEDED);
   }
   else
   {
      Print("[FAILURE] Some tests failed. Check logs for details.");
      ExpertRemove();
      return(INIT_FAILED);
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(!g_tests_executed)
   {
      Print("[WARNING] Tests were not executed before shutdown");
   }

   Print("Test runner shutdown complete.");
}

//+------------------------------------------------------------------+
//| Run all test suites                                              |
//+------------------------------------------------------------------+
void RunAllTests()
{
   Print("Starting test execution...");

   // Task 1: Order Engine Scaffolding
   int suite1 = g_test_reporter.BeginSuite("Task1_OrderEngine_Scaffolding");
   bool task1_result = TestOrderEngine_RunAll();
   g_test_reporter.RecordTest(suite1, "TestOrderEngine_RunAll", task1_result,
                               task1_result ? "All scaffolding tests passed" : "Some scaffolding tests failed");
   g_test_reporter.EndSuite(suite1);

   // Task 2: Idempotency (Intent journal tests)
   int suite2 = g_test_reporter.BeginSuite("Task2_Idempotency_System");
   bool task2_result = TestOrderEngineIntent_RunAll();
   g_test_reporter.RecordTest(suite2, "TestOrderEngineIntent_RunAll", task2_result,
                               task2_result ? "All intent journal tests passed" : "Some intent tests failed");
   g_test_reporter.EndSuite(suite2);

   // Task 3: Volume & Price Normalization
   int suite3 = g_test_reporter.BeginSuite("Task3_Volume_Price_Normalization");
   bool task3_result = TestOrderEngineNormalization_RunAll();
   g_test_reporter.RecordTest(suite3, "TestOrderEngineNormalization_RunAll", task3_result,
                               task3_result ? "All normalization tests passed" : "Some normalization tests failed");
   g_test_reporter.EndSuite(suite3);

   // Task 4: Order Placement with Limits
   int suite4 = g_test_reporter.BeginSuite("Task4_Order_Placement_Limits");
   bool task4_result = TestOrderEngineLimits_RunAll();
   g_test_reporter.RecordTest(suite4, "TestOrderEngineLimits_RunAll", task4_result,
                               task4_result ? "All position limit tests passed" : "Some limit tests failed");
   g_test_reporter.EndSuite(suite4);

   // Task 5: Retry Policy System
   int suite5 = g_test_reporter.BeginSuite("Task5_Retry_Policy_System");
   bool task5_result = TestOrderEngineRetry_RunAll();
   g_test_reporter.RecordTest(suite5, "TestOrderEngineRetry_RunAll", task5_result,
                               task5_result ? "All retry policy tests passed" : "Some retry tests failed");
   g_test_reporter.EndSuite(suite5);

   // Task 6: Market Fallback with Slippage
   int suite6 = g_test_reporter.BeginSuite("Task6_Market_Fallback_Slippage");
   bool task6_result = TestOrderEngineMarket_RunAll();
   g_test_reporter.RecordTest(suite6, "TestOrderEngineMarket_RunAll", task6_result,
                               task6_result ? "All market fallback tests passed" : "Some market tests failed");
   g_test_reporter.EndSuite(suite6);

   Print("Test execution complete.");
}

//+------------------------------------------------------------------+
//| Expert tick function (not used for testing)                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // Empty - we run tests in OnInit only
}
