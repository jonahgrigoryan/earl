#ifndef TEST_ORDER_ENGINE_RETRY_MQH
#define TEST_ORDER_ENGINE_RETRY_MQH
// test_order_engine_retry.mqh - Unit tests for retry policy system (M3 Task 5)
// References: .kiro/specs/rpea-m3/tasks.md, design.md, requirements.md

#include <RPEA/order_engine.mqh>

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

void RetryTests_BuildOrderRequest(OrderRequest &request,
                                  const ENUM_ORDER_TYPE order_type = ORDER_TYPE_BUY_LIMIT)
{
   request.symbol = "XAUUSD";
   request.type = order_type;
   request.volume = 0.10;
   request.price = 1900.00;
   request.sl = 1895.00;
   request.tp = 1905.00;
   request.magic = 424242;
   request.comment = "retry-test";
   request.is_oco_primary = false;
   request.oco_sibling_ticket = 0;
   request.expiry = TimeCurrent() + 3600;
   request.signal_symbol = request.symbol;
   request.is_protective = false;
   request.is_proxy = false;
   request.proxy_rate = 1.0;
   request.proxy_context = "";
}

//------------------------------------------------------------------------------
// RetryManager tests
//------------------------------------------------------------------------------

bool RetryManager_FailFastPolicy()
{
   g_current_test = "RetryManager_FailFastPolicy";
   PrintFormat("[TEST START] %s", g_current_test);

   RetryManager manager;
   manager.Configure(3, 300, 2.0);

   ASSERT_EQUALS((int)RETRY_POLICY_FAIL_FAST,
                 (int)manager.GetPolicyForError(TRADE_RETCODE_TRADE_DISABLED),
                 "TRADE_DISABLED maps to FAIL_FAST");
   ASSERT_EQUALS((int)RETRY_POLICY_FAIL_FAST,
                 (int)manager.GetPolicyForError(TRADE_RETCODE_NO_MONEY),
                 "NO_MONEY maps to FAIL_FAST");
   ASSERT_FALSE(manager.ShouldRetry(RETRY_POLICY_FAIL_FAST, 0),
                "FAIL_FAST policy does not permit retries");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool RetryManager_BackoffProfiles()
{
   g_current_test = "RetryManager_BackoffProfiles";
   PrintFormat("[TEST START] %s", g_current_test);

   RetryManager manager;
   manager.Configure(3, 300, 2.0);

   ASSERT_EQUALS(300, manager.CalculateDelayMs(1, RETRY_POLICY_EXPONENTIAL),
                 "Exponential retry #1 uses 300ms delay");
   ASSERT_EQUALS(600, manager.CalculateDelayMs(2, RETRY_POLICY_EXPONENTIAL),
                 "Exponential retry #2 doubles to 600ms");
   ASSERT_EQUALS(1200, manager.CalculateDelayMs(3, RETRY_POLICY_EXPONENTIAL),
                 "Exponential retry #3 doubles to 1200ms");
   ASSERT_EQUALS(300, manager.CalculateDelayMs(1, RETRY_POLICY_LINEAR),
                 "Linear retry #1 uses base 300ms delay");
   ASSERT_EQUALS(300, manager.CalculateDelayMs(2, RETRY_POLICY_LINEAR),
                 "Linear retry #2 remains 300ms");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// ExecuteOrderWithRetry integration tests
//------------------------------------------------------------------------------

bool ExecuteOrderWithRetry_SuccessImmediate()
{
   g_current_test = "ExecuteOrderWithRetry_SuccessImmediate";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   g_order_engine.Init();
   OE_Test_ResetIntentJournal();
   OE_Test_SetRiskOverride(true, 25.0);

   OE_Test_EnableOrderSendOverride();
   OE_Test_EnqueueOrderSendResponse(true,
                                    TRADE_RETCODE_DONE,
                                    1234567,
                                    0,
                                    1900.10,
                                    0.10,
                                    "immediate-success");
   OE_Test_BeginRetryDelayCapture(true);

   OrderRequest request;
   RetryTests_BuildOrderRequest(request);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_TRUE(result.success, "Order succeeds on first attempt");
   ASSERT_EQUALS(0, result.retry_count, "No retries recorded");
   ASSERT_EQUALS((int)TRADE_RETCODE_DONE, result.last_retcode, "Last retcode reflects success");
   ASSERT_EQUALS(1, OE_Test_GetOrderSendCallCount(), "Single OrderSend invocation");
   ASSERT_EQUALS(0, OE_Test_GetCapturedDelayCount(), "No retry delays captured");

   OE_Test_EndRetryDelayCapture();
   OE_Test_ClearOverrides();

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool ExecuteOrderWithRetry_LinearRetrySuccess()
{
   g_current_test = "ExecuteOrderWithRetry_LinearRetrySuccess";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   g_order_engine.Init();
   OE_Test_ResetIntentJournal();
   OE_Test_SetRiskOverride(true, 25.0);

   OE_Test_EnableOrderSendOverride();
   OE_Test_EnqueueOrderSendResponse(false,
                                    TRADE_RETCODE_REQUOTE,
                                    0,
                                    0,
                                    0.0,
                                    0.0,
                                    "requote");
   OE_Test_EnqueueOrderSendResponse(true,
                                    TRADE_RETCODE_DONE,
                                    7654321,
                                    0,
                                    1900.25,
                                    0.10,
                                    "filled-after-retry");
   OE_Test_BeginRetryDelayCapture(true);

   OrderRequest request;
   RetryTests_BuildOrderRequest(request);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_TRUE(result.success, "Order succeeds after retry");
   ASSERT_EQUALS(1, result.retry_count, "Exactly one retry performed");
   ASSERT_EQUALS((int)TRADE_RETCODE_DONE, result.last_retcode, "Last retcode captures success");
   ASSERT_EQUALS(2, OE_Test_GetOrderSendCallCount(), "Two OrderSend attempts executed");
   ASSERT_EQUALS(1, OE_Test_GetCapturedDelayCount(), "One retry delay captured");
   ASSERT_EQUALS(300, OE_Test_GetCapturedDelay(0), "Linear policy uses 300ms delay");

   OE_Test_EndRetryDelayCapture();
   OE_Test_ClearOverrides();

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool ExecuteOrderWithRetry_ExponentialRetriesStop()
{
   g_current_test = "ExecuteOrderWithRetry_ExponentialRetriesStop";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   g_order_engine.Init();
   OE_Test_ResetIntentJournal();
   OE_Test_SetRiskOverride(true, 25.0);

   OE_Test_EnableOrderSendOverride();
   for(int i = 0; i < 4; i++)
   {
      OE_Test_EnqueueOrderSendResponse(false,
                                       TRADE_RETCODE_TIMEOUT,
                                       0,
                                       0,
                                       0.0,
                                       0.0,
                                       "timeout");
   }
   OE_Test_BeginRetryDelayCapture(true);

   OrderRequest request;
   RetryTests_BuildOrderRequest(request);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_FALSE(result.success, "Order fails after exhausting retries");
   ASSERT_EQUALS(3, result.retry_count, "Maximum of three retries attempted");
   ASSERT_EQUALS((int)TRADE_RETCODE_TIMEOUT, result.last_retcode, "Last retcode reflects timeout");
   ASSERT_EQUALS(4, OE_Test_GetOrderSendCallCount(), "Four OrderSend attempts (initial + 3 retries)");
   ASSERT_EQUALS(3, OE_Test_GetCapturedDelayCount(), "Three retry delays captured");
   ASSERT_EQUALS(300, OE_Test_GetCapturedDelay(0), "Exponential delay #1 is 300ms");
   ASSERT_EQUALS(600, OE_Test_GetCapturedDelay(1), "Exponential delay #2 is 600ms");
   ASSERT_EQUALS(1200, OE_Test_GetCapturedDelay(2), "Exponential delay #3 is 1200ms");
   ASSERT_TRUE(StringLen(result.error_message) > 0, "Failure surfaces error message");

   OE_Test_EndRetryDelayCapture();
   OE_Test_ClearOverrides();

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool ExecuteOrderWithRetry_FailFastStopsImmediately()
{
   g_current_test = "ExecuteOrderWithRetry_FailFastStopsImmediately";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   g_order_engine.Init();
   OE_Test_ResetIntentJournal();
   OE_Test_SetRiskOverride(true, 25.0);

   OE_Test_EnableOrderSendOverride();
   OE_Test_EnqueueOrderSendResponse(false,
                                    TRADE_RETCODE_TRADE_DISABLED,
                                    0,
                                    0,
                                    0.0,
                                    0.0,
                                    "trade-disabled");
   OE_Test_BeginRetryDelayCapture(true);

   OrderRequest request;
   RetryTests_BuildOrderRequest(request);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_FALSE(result.success, "Order fails fast on trade disabled");
   ASSERT_EQUALS(0, result.retry_count, "No retries performed on fail-fast errors");
   ASSERT_EQUALS((int)TRADE_RETCODE_TRADE_DISABLED, result.last_retcode, "Last retcode reflects fail-fast condition");
   ASSERT_EQUALS(1, OE_Test_GetOrderSendCallCount(), "Only one OrderSend attempt executed");
   ASSERT_EQUALS(0, OE_Test_GetCapturedDelayCount(), "No delays scheduled for fail-fast");
   ASSERT_TRUE(StringFind(result.error_message, "OrderSend failed") >= 0,
               "Error message surfaces failure context");

   OE_Test_EndRetryDelayCapture();
   OE_Test_ClearOverrides();

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// Test runner
//------------------------------------------------------------------------------

bool TestOrderEngineRetry_RunAll()
{
   PrintFormat("=================================================================");
   PrintFormat("RPEA Order Engine Tests - Retry Policies (Task 5)");
   PrintFormat("=================================================================");

   g_test_passed = 0;
   g_test_failed = 0;

   bool fail_fast_policy = RetryManager_FailFastPolicy();
   bool backoff_profiles = RetryManager_BackoffProfiles();
   bool success_immediate = ExecuteOrderWithRetry_SuccessImmediate();
   bool linear_retry = ExecuteOrderWithRetry_LinearRetrySuccess();
   bool exponential_stop = ExecuteOrderWithRetry_ExponentialRetriesStop();
   bool fail_fast_exec = ExecuteOrderWithRetry_FailFastStopsImmediately();

   bool all_passed = (fail_fast_policy &&
                      backoff_profiles &&
                      success_immediate &&
                      linear_retry &&
                      exponential_stop &&
                      fail_fast_exec &&
                      g_test_failed == 0);

   PrintFormat("Test Summary: %d passed, %d failed", g_test_passed, g_test_failed);
   if(all_passed)
      PrintFormat("Retry policy tests PASSED");
   else
      PrintFormat("Retry policy tests FAILED - review output for details");
   PrintFormat("=================================================================");

   return all_passed;
}

#endif // TEST_ORDER_ENGINE_RETRY_MQH
