#ifndef TEST_ORDER_ENGINE_INTEGRATION_MQH
#define TEST_ORDER_ENGINE_INTEGRATION_MQH

#include <RPEA/symbol_bridge.mqh>

#ifndef TEST_FRAMEWORK_DEFINED
#define TEST_FRAMEWORK_DEFINED

int g_test_passed = 0;
int g_test_failed = 0;
string g_current_test = "";

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

#define ASSERT_NEAR(expected, actual, tolerance, message) \
   do { \
      double __exp = (expected); \
      double __act = (actual); \
      double __tol = (tolerance); \
      if(MathAbs(__exp - __act) <= __tol) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%.6f, actual=%.6f, tol=%.6f)", g_current_test, message, __exp, __act, __tol); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%.6f, actual=%.6f, tol=%.6f)", g_current_test, message, __exp, __act, __tol); \
      } \
   } while(false)

#define ASSERT_STRING_EQ(expected, actual, message) \
   do { \
      string __exp = (expected); \
      string __act = (actual); \
      if(__exp == __act) { \
         g_test_passed++; \
         PrintFormat("[PASS] %s: %s", g_current_test, message); \
      } else { \
         g_test_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%s, actual=%s)", g_current_test, message, __exp, __act); \
      } \
   } while(false)
#endif // TEST_FRAMEWORK_DEFINED

extern OrderEngine g_order_engine;
#ifdef RPEA_TEST_RUNNER
extern bool g_test_gate_force_fail;
#endif

void TestGate_SetForceFail(const bool should_fail)
{
#ifdef RPEA_TEST_RUNNER
   g_test_gate_force_fail = should_fail;
#else
   (void)should_fail;
#endif
}

//------------------------------------------------------------------------------
// Helpers
//------------------------------------------------------------------------------

void IntegrationTests_BuildRequest(OrderRequest &request)
{
   request.symbol = "XAUUSD";
   request.signal_symbol = request.symbol;
   request.type = ORDER_TYPE_BUY_LIMIT;
   request.volume = 0.10;
   request.price = 1900.00;
   request.sl = 1895.00;
   request.tp = 1905.00;
   request.magic = 333444;
   request.comment = "integration-test";
   request.is_oco_primary = false;
   request.oco_sibling_ticket = 0;
   request.expiry = TimeCurrent() + 3600;
   request.is_protective = false;
   request.is_proxy = false;
   request.proxy_rate = 1.0;
   request.proxy_context = "";
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

bool TestIntegration_SymbolBridge()
{
   g_current_test = "TestIntegration_SymbolBridge";
   PrintFormat("[TEST START] %s", g_current_test);

   SymbolSelect("XAUEUR", true);
   SymbolSelect("XAUUSD", true);
   SymbolSelect("EURUSD", true);

   ASSERT_STRING_EQ("XAUUSD",
                    SymbolBridge_GetExecutionSymbol("XAUEUR"),
                    "XAUEUR maps to XAUUSD");

   double eurusd_bid = 0.0;
   ASSERT_TRUE(SymbolInfoDouble("EURUSD", SYMBOL_BID, eurusd_bid) && eurusd_bid > 0.0,
               "EURUSD bid available");

   double mapped = 0.0;
   double used_rate = 0.0;
   ASSERT_TRUE(SymbolBridge_MapDistance("XAUEUR",
                                        "XAUUSD",
                                        50.0,
                                        mapped,
                                        used_rate),
               "Distance mapping succeeds");

   ASSERT_NEAR(50.0 * eurusd_bid, mapped, 0.1, "Mapped distance uses EURUSD bid");
   ASSERT_NEAR(eurusd_bid, used_rate, 1e-5, "Mapping reports EURUSD rate");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool TestIntegration_RiskGateRejects()
{
   g_current_test = "TestIntegration_RiskGateRejects";
   PrintFormat("[TEST START] %s", g_current_test);

   OrderRequest request;
   IntegrationTests_BuildRequest(request);
   g_order_engine.Init();

   TestGate_SetForceFail(true);
   OrderResult result = g_order_engine.PlaceOrder(request);
   ASSERT_FALSE(result.success, "Order rejected when budget gate fails");
   ASSERT_STRING_EQ("forced_fail", result.error_message, "Error reason propagates");

   TestGate_SetForceFail(false);

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool TestIntegration_RunAll()
{
   Print("=================================================================");
   Print("RPEA Integration Tests - Task 15");
   Print("=================================================================");
   bool ok = true;
   ok = ok && TestIntegration_SymbolBridge();
   ok = ok && TestIntegration_RiskGateRejects();
   return ok;
}

#endif // TEST_ORDER_ENGINE_INTEGRATION_MQH
