#ifndef TEST_ORDER_ENGINE_OCO_MQH
#define TEST_ORDER_ENGINE_OCO_MQH

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

#endif // TEST_FRAMEWORK_DEFINED

extern OrderEngine g_order_engine;

bool OCO_EstablishStoresMetadata()
{
   g_current_test = "OCO_EstablishStoresMetadata";
   PrintFormat("[TEST START] %s", g_current_test);

   g_order_engine.Init();
   OE_Test_EnableDecisionCapture();

   // Establish using test shim
   const ulong primary = 10001;
   const ulong sibling = 10002;
   bool ok = g_order_engine.OE_Test_EstablishOCO(primary, sibling, "XAUUSD", 0.10, 0.10, TimeCurrent()+3600);
   ASSERT_TRUE(ok, "EstablishOCO returns true");

   // Verify a decision was captured
   ASSERT_TRUE(OE_Test_GetCapturedDecisionCount() > 0, "Decision captured on establish");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool OCO_ReestablishAfterCancel()
{
   g_current_test = "OCO_ReestablishAfterCancel";
   PrintFormat("[TEST START] %s", g_current_test);

   g_order_engine.Init();
   OE_Test_EnableCancelModifyOverride();
   OE_Test_EnableDecisionCapture();
   OE_Test_ForceCancelFail(false);

   const ulong p = 14001, s = 14002;
   bool ok = g_order_engine.OE_Test_EstablishOCO(p, s, "XAUUSD", 0.10, 0.10, TimeCurrent()+3600);
   ASSERT_TRUE(ok, "First establish ok");
   // Fill and cancel sibling
   ASSERT_TRUE(g_order_engine.OE_Test_ProcessOCOFill(p), "Fill cancels sibling");
   // Re-establish cleanly with different tickets
   const ulong p2 = 14011, s2 = 14012;
   ok = g_order_engine.OE_Test_EstablishOCO(p2, s2, "XAUUSD", 0.10, 0.10, TimeCurrent()+3600);
   ASSERT_TRUE(ok, "Second establish ok");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool OCO_FillCancelsSibling()
{
   g_current_test = "OCO_FillCancelsSibling";
   PrintFormat("[TEST START] %s", g_current_test);

   g_order_engine.Init();
   g_order_engine.OE_Test_SetSessionCutoff(TimeCurrent()+3600);
   OE_Test_EnableDecisionCapture();
   OE_Test_EnableCancelModifyOverride();
   OE_Test_ForceCancelFail(false); // ensure cancel path

   const ulong primary = 11001;
   const ulong sibling = 11002;
   bool ok = g_order_engine.EstablishOCO(primary, sibling, "XAUUSD", 0.10, 0.10, TimeCurrent()+3600);
   ASSERT_TRUE(ok, "EstablishOCO returns true");

   // Simulate fill of primary via test shim
   bool handled = g_order_engine.OE_Test_ProcessOCOFill(primary);
   ASSERT_TRUE(handled, "ProcessOCOFill returns true");

   ASSERT_TRUE(OE_Test_GetCapturedCancelCount() >= 1, "Sibling cancel captured");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool Test_OCO_ExpiryTriggersCancel()
{
   g_current_test = "Test_OCO_ExpiryTriggersCancel";
   PrintFormat("[TEST START] %s", g_current_test);

   g_order_engine.Init();
   OE_Test_EnableDecisionCapture();
   OE_Test_EnableCancelModifyOverride();

   // Force cutoff to now to trigger expiry on next timer tick
   g_order_engine.OE_Test_SetSessionCutoff(TimeCurrent());
   const ulong p = 12001, s = 12002;
   bool ok = g_order_engine.OE_Test_EstablishOCO(p, s, "XAUUSD", 0.10, 0.10, TimeCurrent()+3600);
   ASSERT_TRUE(ok, "EstablishOCO returns true");

   // Simulate timer tick at now
   g_order_engine.OnTimerTick(TimeCurrent());
   ASSERT_TRUE(OE_Test_GetCapturedDecisionCount() > 0, "Decision captured on expiry");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool OCO_RiskReductionResize()
{
   g_current_test = "OCO_RiskReductionResize";
   PrintFormat("[TEST START] %s", g_current_test);

   g_order_engine.Init();
   g_order_engine.OE_Test_SetSessionCutoff(TimeCurrent()+3600);
   OE_Test_EnableDecisionCapture();
   OE_Test_EnableCancelModifyOverride();
   OE_Test_ForceCancelFail(true);  // force cancel to fail to exercise resize path
   OE_Test_ForceModifyOk(true);

   const ulong primary = 13001;
   const ulong sibling = 13002;
   bool ok = g_order_engine.OE_Test_EstablishOCO(primary, sibling, "XAUUSD", 0.10, 0.20, TimeCurrent()+3600);
   ASSERT_TRUE(ok, "EstablishOCO returns true");

   // Simulate fill on primary with explicit deal volume: 40% of 0.10 = 0.04
   bool handled = g_order_engine.OE_Test_ProcessOCOFill(primary, 0.04, 0);
   ASSERT_TRUE(handled, "Resize path handled");

   // Expect sibling resize from 0.20 to 0.20*(1-0.4)=0.12
   ulong mod_ticket; double new_vol; datetime ts; string reason;
   bool got = OE_Test_GetCapturedModifyCount() > 0 && OE_Test_GetCapturedModify(0, mod_ticket, new_vol, ts, reason);
   ASSERT_TRUE(got, "Captured modify present");
   ASSERT_TRUE(MathAbs(new_vol - 0.12) < 1e-6, "Resized volume matches expected 0.12");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool TestOrderEngineOCO_RunAll()
{
   PrintFormat("=================================================================");
   PrintFormat("RPEA Order Engine Tests - Task 7 OCO Management");
   PrintFormat("=================================================================");

   g_test_passed = 0;
   g_test_failed = 0;

   bool t1 = OCO_EstablishStoresMetadata();
   bool t2 = OCO_FillCancelsSibling();
   bool t3 = OCO_RiskReductionResize();
   bool t4 = OCO_ReestablishAfterCancel();
   bool t5 = Test_OCO_ExpiryTriggersCancel();

   bool all_passed = (t1 && t2 && t3 && t4 && t5 && g_test_failed == 0);
   PrintFormat("Test Summary: %d passed, %d failed", g_test_passed, g_test_failed);
   if(all_passed)
      PrintFormat("OCO tests PASSED");
   else
      PrintFormat("OCO tests FAILED");

   PrintFormat("=================================================================");
   return all_passed;
}

#endif // TEST_ORDER_ENGINE_OCO_MQH


