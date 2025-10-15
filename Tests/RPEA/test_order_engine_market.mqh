#ifndef TEST_ORDER_ENGINE_MARKET_MQH
#define TEST_ORDER_ENGINE_MARKET_MQH
// test_order_engine_market.mqh - Unit tests for Task 6 (Market fallback & slippage)
// References: .kiro/specs/rpea-m3/tasks.md, requirements.md

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

void MarketTests_BuildRequest(OrderRequest &request,
                              const ENUM_ORDER_TYPE type,
                              const double price = 1900.00)
{
   request.symbol = "XAUUSD";
   request.type = type;
   request.volume = 0.10;
   request.price = price;
   request.sl = 1895.00;
   request.tp = 1905.00;
   request.magic = 515151;
   request.comment = "market-suite";
   request.is_oco_primary = false;
   request.oco_sibling_ticket = 0;
   request.expiry = TimeCurrent() + 3600;
}

void MarketTests_SetQuote(const double point,
                          const int digits,
                          const double bid,
                          const double ask)
{
   OE_Test_SetPriceOverride("XAUUSD", point, digits, bid, ask, 0);
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

bool MarketOrder_SlippageRejectsExcess()
{
   g_current_test = "MarketOrder_SlippageRejectsExcess";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   g_order_engine.Init();
   OE_Test_SetRiskOverride(true, 25.0);
   MarketTests_SetQuote(0.01, 2, 1900.50, 1900.60);
   OE_Test_EnableOrderSendOverride();

   OrderRequest request;
   MarketTests_BuildRequest(request, ORDER_TYPE_BUY, 1900.00);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_FALSE(result.success, "Order rejected when slippage exceeds limit");
   ASSERT_EQUALS(0, OE_Test_GetOrderSendCallCount(), "OrderSend bypassed on slippage rejection");
   ASSERT_EQUALS((int)TRADE_RETCODE_PRICE_OFF, result.last_retcode, "Slippage rejection uses PRICE_OFF retcode");
   ASSERT_TRUE(StringFind(result.error_message, "Slippage") >= 0,
               "Error message references slippage");

   OE_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool MarketOrder_AllowsWithinSlippage()
{
   g_current_test = "MarketOrder_AllowsWithinSlippage";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   g_order_engine.Init();
   OE_Test_SetRiskOverride(true, 25.0);
   MarketTests_SetQuote(0.01, 2, 1900.10, 1900.20);
   OE_Test_EnableOrderSendOverride();
   OE_Test_EnqueueOrderSendResponse(true,
                                    TRADE_RETCODE_DONE,
                                    12345,
                                    223344,
                                    1900.20,
                                    0.10,
                                    "done");

   OrderRequest request;
   MarketTests_BuildRequest(request, ORDER_TYPE_BUY, 1900.15);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_TRUE(result.success, "Order executes when slippage within limit");
   ASSERT_EQUALS(1, OE_Test_GetOrderSendCallCount(), "Exactly one OrderSend executed");
   ASSERT_EQUALS((int)TRADE_RETCODE_DONE, result.last_retcode, "Success retcode propagated");
   ASSERT_NEAR(1900.20, result.executed_price, 1e-6, "Executed price captured from broker");
   ASSERT_EQUALS(0, result.retry_count, "No retries needed for successful send");

   OE_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool PendingOrder_FallbackToMarket()
{
   g_current_test = "PendingOrder_FallbackToMarket";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   g_order_engine.Init();
   OE_Test_SetRiskOverride(true, 25.0);
   MarketTests_SetQuote(0.01, 2, 1899.95, 1900.05);
   OE_Test_EnableOrderSendOverride();
   OE_Test_EnqueueOrderSendResponse(false,
                                    TRADE_RETCODE_PRICE_OFF,
                                    0,
                                    0,
                                    0.0,
                                    0.0,
                                    "pending-price-off");
   OE_Test_EnqueueOrderSendResponse(true,
                                    TRADE_RETCODE_DONE,
                                    50001,
                                    60001,
                                    1900.05,
                                    0.10,
                                    "market-fill");

   OrderRequest request;
   MarketTests_BuildRequest(request, ORDER_TYPE_BUY_STOP, 1900.00);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_TRUE(result.success, "Fallback converts pending to market and succeeds");
   ASSERT_EQUALS((int)TRADE_RETCODE_DONE, result.last_retcode, "Fallback execution returns DONE");
   ASSERT_EQUALS(2, OE_Test_GetOrderSendCallCount(), "OrderSend called twice (pending + market)");
   ASSERT_NEAR(1900.05, result.executed_price, 1e-6, "Market execution uses current ask");
   ASSERT_EQUALS(0, result.retry_count, "Market fallback succeeded on first attempt");

   OE_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool PendingOrder_FallbackSlippageRejected()
{
   g_current_test = "PendingOrder_FallbackSlippageRejected";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   g_order_engine.Init();
   OE_Test_SetRiskOverride(true, 25.0);
   MarketTests_SetQuote(0.01, 2, 1899.40, 1900.60);
   OE_Test_EnableOrderSendOverride();
   OE_Test_EnqueueOrderSendResponse(false,
                                    TRADE_RETCODE_PRICE_OFF,
                                    0,
                                    0,
                                    0.0,
                                    0.0,
                                    "pending-reject");

   OrderRequest request;
   MarketTests_BuildRequest(request, ORDER_TYPE_BUY_STOP, 1900.00);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_FALSE(result.success, "Fallback rejected when market slippage too high");
   ASSERT_EQUALS(1, OE_Test_GetOrderSendCallCount(), "Only pending attempt reaches OrderSend");
   ASSERT_EQUALS((int)TRADE_RETCODE_PRICE_OFF, result.last_retcode, "Slippage rejection surfaced via PRICE_OFF");
   ASSERT_TRUE(StringFind(result.error_message, "Slippage") >= 0,
               "Error message indicates slippage rejection");

   OE_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool MarketOrder_FailFastStopsRetry()
{
   g_current_test = "MarketOrder_FailFastStopsRetry";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   g_order_engine.Init();
   OE_Test_SetRiskOverride(true, 25.0);
   MarketTests_SetQuote(0.01, 2, 1900.10, 1900.20);
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
   MarketTests_BuildRequest(request, ORDER_TYPE_SELL, 1900.10);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_FALSE(result.success, "Fail-fast error stops execution");
   ASSERT_EQUALS(1, OE_Test_GetOrderSendCallCount(), "Only one OrderSend attempt on fail-fast");
   ASSERT_EQUALS((int)TRADE_RETCODE_TRADE_DISABLED, result.last_retcode, "Fail-fast retcode propagated");
   ASSERT_EQUALS(0, result.retry_count, "No retries performed for fail-fast errors");
   ASSERT_EQUALS(0, OE_Test_GetCapturedDelayCount(), "Fail-fast path schedules no delays");

   OE_Test_EndRetryDelayCapture();
   OE_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool MarketOrder_RetryOnRequote()
{
   g_current_test = "MarketOrder_RetryOnRequote";
   PrintFormat("[TEST START] %s", g_current_test);

   OE_Test_ClearOverrides();
   g_order_engine.Init();
   OE_Test_SetRiskOverride(true, 25.0);
   MarketTests_SetQuote(0.01, 2, 1900.05, 1900.15);
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
                                    80001,
                                    90001,
                                    1900.15,
                                    0.10,
                                    "success");
   OE_Test_BeginRetryDelayCapture(true);

   OrderRequest request;
   MarketTests_BuildRequest(request, ORDER_TYPE_BUY, 1900.12);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_TRUE(result.success, "Order succeeds after retrying requote");
   ASSERT_EQUALS(2, OE_Test_GetOrderSendCallCount(), "Retry triggers second OrderSend");
   ASSERT_EQUALS(1, result.retry_count, "Retry count reflects single retry");
   ASSERT_EQUALS(1, OE_Test_GetCapturedDelayCount(), "One retry delay captured");
   ASSERT_EQUALS(300, OE_Test_GetCapturedDelay(0), "Linear retry uses 300ms delay");

   OE_Test_EndRetryDelayCapture();
   OE_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// Test runner
//------------------------------------------------------------------------------

bool TestOrderEngineMarket_RunAll()
{
   PrintFormat("=================================================================");
   PrintFormat("RPEA Order Engine Tests - Market & Slippage (Task 6)");
   PrintFormat("=================================================================");

   g_test_passed = 0;
   g_test_failed = 0;

   bool slippage_reject = MarketOrder_SlippageRejectsExcess();
   bool slippage_success = MarketOrder_AllowsWithinSlippage();
   bool fallback_success = PendingOrder_FallbackToMarket();
   bool fallback_slippage = PendingOrder_FallbackSlippageRejected();
   bool fail_fast = MarketOrder_FailFastStopsRetry();
   bool requote_retry = MarketOrder_RetryOnRequote();

   bool all_passed = (slippage_reject &&
                      slippage_success &&
                      fallback_success &&
                      fallback_slippage &&
                      fail_fast &&
                      requote_retry &&
                      g_test_failed == 0);

   PrintFormat("Test Summary: %d passed, %d failed", g_test_passed, g_test_failed);
   if(all_passed)
      PrintFormat("Market order tests PASSED");
   else
      PrintFormat("Market order tests FAILED - review output for details");
   PrintFormat("=================================================================");

   return all_passed;
}

#endif // TEST_ORDER_ENGINE_MARKET_MQH
