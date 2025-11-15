//+------------------------------------------------------------------+
//|                                     run_automated_tests_ea.mq5  |
//|                      RPEA Automated Test Runner with Reporting  |
//|                         Writes results to JSON for CI/CD        |
//+------------------------------------------------------------------+
#property copyright "RPEA"
#property version   "1.00"
#property strict

input int    BudgetGateLockMs           = 1000;
input double RiskGateHeadroom           = 0.90;

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
#define UseLondonOnly          false
#define StartHourLO            7
#define StartHourNY            12
#define ORMinutes              60
#define CutoffHour             16
#define MinStopPoints          1
#define TrailMult              0.8
#define NewsBufferS            300
#define MaxSpreadPoints        40
#define MaxSlippagePoints      10
#define NewsCSVPath            "Files/RPEA/news/calendar_high_impact.csv"
#define NewsCSVMaxAgeHours     24
#define RPEA_ORDER_ENGINE_SKIP_RISK
#define RPEA_ORDER_ENGINE_SKIP_EQUITY
#define RPEA_ORDER_ENGINE_SKIP_SESSIONS

// Include test reporter
#define RPEA_TEST_RUNNER
#include <RPEA/app_context.mqh>
#include <RPEA/test_reporter.mqh>
#include <RPEA/logging.mqh>

AppContext g_ctx;
bool g_test_gate_force_fail = false;

// Include test files
#include "test_order_engine.mqh"
#include "test_order_engine_normalization.mqh"
#include "test_order_engine_limits.mqh"
#include "test_order_engine_retry.mqh"
#include "test_order_engine_market.mqh"
#include "test_order_engine_intent.mqh"
// OCO tests (Task 7)
#include "test_order_engine_oco.mqh"
// Partial fill tests (Task 8)
#include "test_order_engine_partialfills.mqh"
// Budget gate tests (Task 9)
#include "test_order_engine_budgetgate.mqh"
// News CSV fallback tests (Task 10)
#include "test_news_csv.mqh"
// Synthetic manager tests (Task 11)
#include "test_synthetic_manager.mqh"
// Queue manager tests (Task 12)
#include "test_queue_manager.mqh"
// Trailing manager tests (Task 13)
#include "test_trailing.mqh"
// Audit logger tests (Task 14)
#include "test_logging.mqh"
// Integration tests (Task 15)
#include "test_order_engine_integration.mqh"

#ifndef EQUITY_GUARDIAN_MQH
// Mock functions for testing (only when equity guardian not included)
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

EquityBudgetGateResult Equity_EvaluateBudgetGate(const AppContext& ctx,
                                                 const double next_trade_worst_case)
{
   EquityBudgetGateResult result;
   result.approved = true;
   result.gate_pass = true;
   result.gating_reason = "test_pass";
   result.room_available = 100.0;
   result.room_today = 100.0;
   result.room_overall = 100.0;
   result.open_risk = 0.0;
   result.pending_risk = 0.0;
   result.next_worst_case = next_trade_worst_case;
   result.calculation_error = false;
   if(g_test_gate_force_fail)
   {
      result.gate_pass = false;
      result.gating_reason = "forced_fail";
      result.room_today = 10.0;
      result.room_overall = 10.0;
      result.open_risk = 5.0;
      result.pending_risk = 4.0;
   }
   return result;
}

#endif

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
   AuditLogger_Init(RPEA_LOGS_DIR, DEFAULT_LogBufferSize, true);
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
   AuditLogger_Shutdown();
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

  // Task 7: OCO Relationship Management
  int suite7 = g_test_reporter.BeginSuite("Task7_OCO_Relationship_Management");
  bool task7_result = TestOrderEngineOCO_RunAll();
  g_test_reporter.RecordTest(suite7, "TestOrderEngineOCO_RunAll", task7_result,
                              task7_result ? "All OCO tests passed" : "Some OCO tests failed");
  g_test_reporter.EndSuite(suite7);

   // Task 8: Partial Fill Handler
   int suite8 = g_test_reporter.BeginSuite("Task8_Partial_Fill_Handler");
   bool task8_result = TestOrderEnginePartialFills_RunAll();
   g_test_reporter.RecordTest(suite8, "TestOrderEnginePartialFills_RunAll", task8_result,
                               task8_result ? "All partial fill tests passed" : "Some partial fill tests failed");
   g_test_reporter.EndSuite(suite8);

   // Task 9: Budget Gate with Position Snapshot Locking
   int suite9 = g_test_reporter.BeginSuite("Task9_Budget_Gate_Snapshot_Locking");
   bool task9_result = TestOrderEngineBudgetGate_RunAll();
   g_test_reporter.RecordTest(suite9, "TestOrderEngineBudgetGate_RunAll", task9_result,
                               task9_result ? "All budget gate tests passed" : "Some budget gate tests failed");
   g_test_reporter.EndSuite(suite9);

   // Task 10: News CSV fallback
   int suite10 = g_test_reporter.BeginSuite("Task10_News_CSV_Fallback");
   bool task10_result = TestNewsCsvFallback_RunAll();
   g_test_reporter.RecordTest(suite10, "TestNewsCsvFallback_RunAll", task10_result,
                               task10_result ? "News CSV fallback tests passed" : "News CSV fallback tests failed");
   g_test_reporter.EndSuite(suite10);

   // Task 11: Synthetic Manager (XAUEUR)
   int suite11 = g_test_reporter.BeginSuite("Task11_Synthetic_Manager");
   bool task11_result = TestSyntheticManager_RunAll();
   g_test_reporter.RecordTest(suite11, "TestSyntheticManager_RunAll", task11_result,
                               task11_result ? "Synthetic manager tests passed" : "Synthetic manager tests failed");
   g_test_reporter.EndSuite(suite11);

   // Task 12: Queue Manager
   int suite12 = g_test_reporter.BeginSuite("Task12_Queue_Manager");
   bool task12_result = TestQueueManager_RunAll();
   g_test_reporter.RecordTest(suite12, "TestQueueManager_RunAll", task12_result,
                               task12_result ? "Queue manager tests passed" : "Queue manager tests failed");
   g_test_reporter.EndSuite(suite12);

   // Task 13: Trailing Manager
   int suite13 = g_test_reporter.BeginSuite("Task13_Trailing_Manager");
   bool task13_result = TestTrailing_RunAll();
   g_test_reporter.RecordTest(suite13, "TestTrailing_RunAll", task13_result,
                               task13_result ? "Trailing manager tests passed" : "Trailing manager tests failed");
   g_test_reporter.EndSuite(suite13);

   // Task 14: Audit Logger
   Print("=================================================================");
   Print("RPEA Audit Logger Tests - Task 14");
   Print("=================================================================");
   int suite14 = g_test_reporter.BeginSuite("Task14_Audit_Logger");
   bool task14_result = TestLogging_RunAll();
   g_test_reporter.RecordTest(suite14, "TestLogging_RunAll", task14_result,
                               task14_result ? "Audit logger tests passed" : "Audit logger tests failed");
   g_test_reporter.EndSuite(suite14);

   int suite15 = g_test_reporter.BeginSuite("Task15_Risk_XAUEUR");
   bool task15_result = TestIntegration_RunAll();
   g_test_reporter.RecordTest(suite15, "TestIntegration_RunAll", task15_result,
                               task15_result ? "Integration tests passed" : "Integration tests failed");
   g_test_reporter.EndSuite(suite15);

   Print("Test execution complete.");
}

//+------------------------------------------------------------------+
//| Expert tick function (not used for testing)                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // Empty - we run tests in OnInit only
}
