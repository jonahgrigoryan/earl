#ifndef TEST_ORDER_ENGINE_PENDING_EXPIRY_MQH
#define TEST_ORDER_ENGINE_PENDING_EXPIRY_MQH
// Tests for Task 24: Pending order expiry defaults and logging

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

void PendingExpiry_BuildRequest(OrderRequest &request,
                                const ENUM_ORDER_TYPE type,
                                const double price,
                                const datetime expiry_value)
{
   request.symbol = "XAUUSD";
   request.type = type;
   request.volume = 0.10;
   request.price = price;
   request.sl = price - 5.0;
   request.tp = price + 5.0;
   request.magic = 888888;
   request.comment = "pending-expiry";
   request.is_oco_primary = false;
   request.oco_sibling_ticket = 0;
   request.expiry = expiry_value;
   request.signal_symbol = request.symbol;
   request.is_protective = false;
   request.is_proxy = false;
   request.proxy_rate = 1.0;
   request.proxy_context = "";
}

void PendingExpiry_SetupEnvironment()
{
   OE_Test_ClearOverrides();
   g_order_engine.Init();
   OE_Test_ResetIntentJournal();
   OE_Test_SetRiskOverride(true, 25.0);
   OE_Test_SetPriceOverride("XAUUSD", 0.01, 2, 1900.10, 1900.20, 0);
   OE_Test_SetVolumeOverride("XAUUSD", 0.01, 0.01, 1.0);
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

bool PendingExpiry_Sets45Minutes()
{
   g_current_test = "PendingExpiry_Sets45Minutes";
   PrintFormat("[TEST START] %s", g_current_test);

   PendingExpiry_SetupEnvironment();
   OE_Test_EnableOrderSendOverride();
   OE_Test_EnqueueOrderSendResponse(true,
                                    TRADE_RETCODE_DONE,
                                    70001,
                                    0,
                                    1900.10,
                                    0.10,
                                    "pending-placed");

   datetime start = TimeCurrent();
   OrderRequest request;
   PendingExpiry_BuildRequest(request, ORDER_TYPE_BUY_LIMIT, 1899.90, 0);

   OrderResult result = g_order_engine.PlaceOrder(request);

   ASSERT_TRUE(result.intent_id != "", "Intent id assigned");

   OrderIntent intent;
   bool found = OrderEngine_FindIntentById(result.intent_id, intent);
   ASSERT_TRUE(found, "Intent stored in journal");

   datetime expected = start + DEFAULT_PendingExpirySeconds;
   ASSERT_TRUE(intent.expiry >= expected - 5 && intent.expiry <= expected + 10,
               "Expiry defaults to ~45 minutes ahead");

   OE_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool PendingExpiry_HonorsCustomExpiry()
{
   g_current_test = "PendingExpiry_HonorsCustomExpiry";
   PrintFormat("[TEST START] %s", g_current_test);

   PendingExpiry_SetupEnvironment();
   OE_Test_EnableOrderSendOverride();
   OE_Test_EnqueueOrderSendResponse(true,
                                    TRADE_RETCODE_DONE,
                                    70002,
                                    0,
                                    1900.15,
                                    0.10,
                                    "pending-custom");

   datetime custom_expiry = TimeCurrent() + 600;
   OrderRequest request;
   PendingExpiry_BuildRequest(request, ORDER_TYPE_SELL_LIMIT, 1900.50, custom_expiry);

   OrderResult result = g_order_engine.PlaceOrder(request);

   OrderIntent intent;
   bool found = OrderEngine_FindIntentById(result.intent_id, intent);
   ASSERT_TRUE(found, "Intent stored with custom expiry");
   ASSERT_TRUE(MathAbs((double)(intent.expiry - custom_expiry)) <= 1,
               "Custom expiry retained exactly");

   OE_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool PendingExpiry_AppliesToAllPendings()
{
   g_current_test = "PendingExpiry_AppliesToAllPendings";
   PrintFormat("[TEST START] %s", g_current_test);

   PendingExpiry_SetupEnvironment();
   datetime expected = g_order_engine.OE_Test_CalcPendingExpiry(0);
   g_order_engine.OE_Test_SetSessionCutoff(TimeCurrent() + 6 * 60 * 60);

   const ulong primary = 88001;
   const ulong sibling = 88002;
   bool ok = g_order_engine.OE_Test_EstablishOCO(primary, sibling, "XAUUSD", 0.10, 0.10, expected);
   ASSERT_TRUE(ok, "OCO establish succeeds");

   OCORelationship rel;
   bool got = g_order_engine.OE_Test_GetOCOState(0, rel);
   ASSERT_TRUE(got, "OCO state retrievable");
   if(got)
   {
      ASSERT_TRUE(rel.expiry == expected, "Relationship expiry stores broker value");
      ASSERT_TRUE(rel.expiry_broker == expected, "Broker expiry recorded");
      ASSERT_TRUE(rel.expiry_aligned <= expected && rel.expiry_aligned > 0,
                  "Aligned expiry not later than broker expiry");
   }

   OE_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool PendingExpiry_AutoCancelsExpired()
{
   g_current_test = "PendingExpiry_AutoCancelsExpired";
   PrintFormat("[TEST START] %s", g_current_test);

   PendingExpiry_SetupEnvironment();
   OE_Test_EnableDecisionCapture();
   OE_Test_EnableCancelModifyOverride();
   OE_Test_ForceCancelFail(false);

   datetime past_expiry = TimeCurrent() - 60;
   g_order_engine.OE_Test_SetSessionCutoff(TimeCurrent() + 3600);

   const ulong primary = 99001;
   const ulong sibling = 99002;
   bool ok = g_order_engine.OE_Test_EstablishOCO(primary, sibling, "XAUUSD", 0.10, 0.10, past_expiry);
   ASSERT_TRUE(ok, "OCO with past expiry established");

   g_order_engine.OnTimerTick(TimeCurrent());

   bool saw_expire = false;
   for(int i = 0; i < OE_Test_GetCapturedDecisionCount(); i++)
   {
      string ev, json;
      datetime ts;
      if(OE_Test_GetCapturedDecision(i, ev, json, ts) && ev == "OCO_EXPIRE")
      {
         saw_expire = true;
         break;
      }
   }
   ASSERT_TRUE(saw_expire, "Expiry decision captured");

   ulong cancel_ticket = 0;
   datetime cancel_ts = 0;
   string cancel_reason = "";
   bool cancel_logged = (OE_Test_GetCapturedCancelCount() > 0 &&
                         OE_Test_GetCapturedCancel(0, cancel_ticket, cancel_ts, cancel_reason));
   ASSERT_TRUE(cancel_logged, "Cancel issued for expired OCO");

   OE_Test_DisableDecisionCapture();
   OE_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool PendingExpiry_LogsExpirySet()
{
   g_current_test = "PendingExpiry_LogsExpirySet";
   PrintFormat("[TEST START] %s", g_current_test);

   PendingExpiry_SetupEnvironment();
   OE_Test_EnableDecisionCapture();
   OE_Test_EnableOrderSendOverride();
   OE_Test_EnqueueOrderSendResponse(false,
                                    TRADE_RETCODE_PRICE_OFF,
                                    0,
                                    0,
                                    0.0,
                                    0.0,
                                    "force-fail");

   OrderRequest request;
   PendingExpiry_BuildRequest(request, ORDER_TYPE_BUY_STOP, 1900.00, 0);

   g_order_engine.PlaceOrder(request);

   bool found = false;
   for(int i = 0; i < OE_Test_GetCapturedDecisionCount(); i++)
   {
      string ev, json;
      datetime ts;
      if(OE_Test_GetCapturedDecision(i, ev, json, ts) && ev == "PENDING_EXPIRY_SET")
      {
         found = true;
         ASSERT_TRUE(StringFind(json, "default_pending_ttl") >= 0, "Decision logs default expiry reason");
         break;
      }
   }
   ASSERT_TRUE(found, "Pending expiry decision captured");

   OE_Test_DisableDecisionCapture();
   OE_Test_ClearOverrides();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool TestOrderEnginePendingExpiry_RunAll()
{
   PrintFormat("=================================================================");
   PrintFormat("RPEA Order Engine Tests - Task 24 Pending Expiry");
   PrintFormat("=================================================================");

   g_test_passed = 0;
   g_test_failed = 0;

   bool t1 = PendingExpiry_Sets45Minutes();
   bool t2 = PendingExpiry_HonorsCustomExpiry();
   bool t3 = PendingExpiry_AppliesToAllPendings();
   bool t4 = PendingExpiry_AutoCancelsExpired();
   bool t5 = PendingExpiry_LogsExpirySet();

   bool all_passed = (t1 && t2 && t3 && t4 && t5 && g_test_failed == 0);
   PrintFormat("Test Summary: %d passed, %d failed", g_test_passed, g_test_failed);
   if(all_passed)
      PrintFormat("Pending expiry tests PASSED");
   else
      PrintFormat("Pending expiry tests FAILED");

   PrintFormat("=================================================================");
   return all_passed;
}

#endif // TEST_ORDER_ENGINE_PENDING_EXPIRY_MQH


