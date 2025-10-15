#ifndef TEST_ORDER_ENGINE_LIMITS_MQH
#define TEST_ORDER_ENGINE_LIMITS_MQH
// test_order_engine_limits.mqh - Unit tests for Task 4 order placement caps
// References: .kiro/specs/rpea-m3/tasks.md (Task 4)

#include "../../MQL5/Include/RPEA/order_engine.mqh"

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

#define ASSERT_FALSE(condition, message) \
   ASSERT_TRUE(!(condition), message)

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
      double __exp = (expected); \
      double __act = (actual); \
      double __tol = (tolerance); \
      if(MathAbs(__exp - __act) <= __tol) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%.10f, actual=%.10f, tol=%.10f)", g_current_test, message, __exp, __act, __tol); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%.10f, actual=%.10f, tol=%.10f)", g_current_test, message, __exp, __act, __tol); \
      } \
   } while(false)
#endif // TEST_FRAMEWORK_DEFINED

extern OrderEngine g_order_engine;

//------------------------------------------------------------------------------
// Helpers
//------------------------------------------------------------------------------

void TestOrderEngineLimits_Reset()
{
   OE_Test_ClearOverrides();
   g_order_engine.Init();
}

void TestOrderEngineLimits_BuildRequest(OrderRequest &request,
                                        const ENUM_ORDER_TYPE order_type = ORDER_TYPE_BUY_LIMIT)
{
   request.symbol = "XAUUSD";
   request.type = order_type;
   request.volume = 0.10;
   request.price = 1900.00;
   request.sl = 1895.00;
   request.tp = 1905.00;
   request.magic = 987654321;
   request.comment = "limits-test";
   request.is_oco_primary = false;
   request.oco_sibling_ticket = 0;
   request.expiry = TimeCurrent() + 3600;
}

//------------------------------------------------------------------------------
// Test Cases
//------------------------------------------------------------------------------

bool PlaceOrder_TotalCapBlocked()
{
   g_current_test = "PlaceOrder_TotalCapBlocked";
   PrintFormat("[TEST START] %s", g_current_test);

   TestOrderEngineLimits_Reset();
   OE_Test_SetCapOverride(false, MaxOpenPositionsTotal, 0, 0);

   OrderRequest request;
   TestOrderEngineLimits_BuildRequest(request);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_FALSE(result.success, "Order rejected when total cap already reached");
   ASSERT_TRUE(StringFind(result.error_message, "MaxOpenPositionsTotal") >= 0,
               "Error message references total cap");

   OE_Test_ClearOverrides();

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool PlaceOrder_SymbolCapBlocked()
{
   g_current_test = "PlaceOrder_SymbolCapBlocked";
   PrintFormat("[TEST START] %s", g_current_test);

   TestOrderEngineLimits_Reset();
   OE_Test_SetCapOverride(false, 1, MaxOpenPerSymbol, 0);

   OrderRequest request;
   TestOrderEngineLimits_BuildRequest(request);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_FALSE(result.success, "Order rejected when per-symbol cap already reached");
   ASSERT_TRUE(StringFind(result.error_message, "MaxOpenPerSymbol") >= 0,
               "Error message references per-symbol cap");

   OE_Test_ClearOverrides();

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool PlaceOrder_PendingCapBlocked()
{
   g_current_test = "PlaceOrder_PendingCapBlocked";
   PrintFormat("[TEST START] %s", g_current_test);

   TestOrderEngineLimits_Reset();
   OE_Test_SetCapOverride(true, 1, 0, MaxPendingsPerSymbol);

   OrderRequest request;
   TestOrderEngineLimits_BuildRequest(request);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_FALSE(result.success, "Order rejected when pending cap would be exceeded");
   ASSERT_TRUE(StringFind(result.error_message, "MaxPendingsPerSymbol") >= 0,
               "Error message references pending cap");

   OE_Test_ClearOverrides();

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool PlaceOrder_SucceedsWithinCaps()
{
   g_current_test = "PlaceOrder_SucceedsWithinCaps";
   PrintFormat("[TEST START] %s", g_current_test);

   TestOrderEngineLimits_Reset();
   OE_Test_SetCapOverride(true, 0, 0, 0);
   OE_Test_SetRiskOverride(true, 25.0);

   OrderRequest request;
   TestOrderEngineLimits_BuildRequest(request);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_TRUE(result.success, "Order accepted when below all caps");
   ASSERT_TRUE(result.error_message == "", "Successful order returns empty error message");

   OE_Test_ClearOverrides();

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool PlaceOrder_LogsReason()
{
   g_current_test = "PlaceOrder_LogsReason";
   PrintFormat("[TEST START] %s", g_current_test);

   TestOrderEngineLimits_Reset();
   OE_Test_SetCapOverride(false, MaxOpenPositionsTotal, MaxOpenPerSymbol, MaxPendingsPerSymbol);

   OrderRequest request;
   TestOrderEngineLimits_BuildRequest(request);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_FALSE(result.success, "Order rejected for cap violation captures failure");
   ASSERT_TRUE(StringFind(result.error_message, "MaxOpenPositionsTotal") >= 0 ||
               StringFind(result.error_message, "MaxOpenPerSymbol") >= 0 ||
               StringFind(result.error_message, "MaxPendingsPerSymbol") >= 0,
               "Error message contains cap identifier");

   OE_Test_ClearOverrides();

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// Test Runner
//------------------------------------------------------------------------------

bool TestOrderEngineLimits_RunAll()
{
   PrintFormat("=================================================================");
   PrintFormat("RPEA Order Engine Tests - Task 4 Position Limits");
   PrintFormat("=================================================================");

   g_test_passed = 0;
   g_test_failed = 0;

   bool total_cap = PlaceOrder_TotalCapBlocked();
   bool symbol_cap = PlaceOrder_SymbolCapBlocked();
   bool pending_cap = PlaceOrder_PendingCapBlocked();
   bool success_within = PlaceOrder_SucceedsWithinCaps();
   bool reason_logged = PlaceOrder_LogsReason();

   bool all_passed = (total_cap && symbol_cap && pending_cap && success_within && reason_logged && g_test_failed == 0);
   PrintFormat("Test Summary: %d passed, %d failed", g_test_passed, g_test_failed);
   if(all_passed)
      PrintFormat("Task 4 position limit tests PASSED");
   else
      PrintFormat("Task 4 position limit tests FAILED");

   PrintFormat("=================================================================");
   return all_passed;
}

#endif // TEST_ORDER_ENGINE_LIMITS_MQH
