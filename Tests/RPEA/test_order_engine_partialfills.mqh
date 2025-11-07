#ifndef TEST_ORDER_ENGINE_PARTIALFILLS_MQH
#define TEST_ORDER_ENGINE_PARTIALFILLS_MQH
// test_order_engine_partialfills.mqh - Unit tests for partial fill handler (M3 Task 8)
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
// Test 1: PartialFill_AdjustsSiblingVolume
// Verify that a 50% partial fill shrinks the opposite leg to 50%
//------------------------------------------------------------------------------
bool PartialFill_AdjustsSiblingVolume()
{
   g_current_test = "PartialFill_AdjustsSiblingVolume";
   PrintFormat("[TEST START] %s", g_current_test);

   g_order_engine.Init();
   g_order_engine.OE_Test_SetSessionCutoff(TimeCurrent()+3600);
   OE_Test_EnableDecisionCapture();
   OE_Test_EnableCancelModifyOverride();
   OE_Test_ForceCancelFail(true);  // Force cancel to fail, trigger resize path
   OE_Test_ForceModifyOk(true);

   const ulong primary = 10001;
   const ulong sibling = 10002;
   const double initial_vol = 0.10;
   
   // Establish OCO with equal volumes
   bool ok = g_order_engine.OE_Test_EstablishOCO(primary, sibling, "XAUUSD", initial_vol, initial_vol, TimeCurrent()+3600);
   ASSERT_TRUE(ok, "EstablishOCO returns true");

   // Simulate 50% partial fill: 0.05 of 0.10
   bool handled = g_order_engine.OE_Test_ProcessOCOFill(primary, 0.05, 1001);
   ASSERT_TRUE(handled, "ProcessOCOFill returns true");

   // Verify sibling resized to 50% (0.05)
   ulong mod_ticket;
   double new_vol;
   datetime ts;
   string reason;
   bool got_modify = OE_Test_GetCapturedModifyCount() > 0 && OE_Test_GetCapturedModify(0, mod_ticket, new_vol, ts, reason);
   ASSERT_TRUE(got_modify, "Modify captured");
   ASSERT_EQUALS((int)sibling, (int)mod_ticket, "Modified sibling ticket");
   ASSERT_NEAR(0.05, new_vol, 1e-6, "Sibling volume reduced to 50%");

   // Verify PARTIAL_FILL_ADJUST decision captured
   int decision_count = OE_Test_GetCapturedDecisionCount();
   bool found_adjust = false;
   datetime decision_ts = 0;
   for(int i = 0; i < decision_count; i++)
   {
      string decision, data;
      OE_Test_GetCapturedDecision(i, decision, data, decision_ts);
      if(decision == "PARTIAL_FILL_ADJUST")
         found_adjust = true;
   }
   ASSERT_TRUE(found_adjust, "PARTIAL_FILL_ADJUST decision captured");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// Test 2: PartialFill_AggregatesMultipleEvents
// Verify multiple partial fills aggregate correctly: 30% + 40% + 30% = 100%
//------------------------------------------------------------------------------
bool PartialFill_AggregatesMultipleEvents()
{
   g_current_test = "PartialFill_AggregatesMultipleEvents";
   PrintFormat("[TEST START] %s", g_current_test);

   g_order_engine.Init();
   g_order_engine.OE_Test_SetSessionCutoff(TimeCurrent()+3600);
   OE_Test_EnableDecisionCapture();
   OE_Test_EnableCancelModifyOverride();
   OE_Test_ForceCancelFail(true);
   OE_Test_ForceModifyOk(true);

   const ulong primary = 11001;
   const ulong sibling = 11002;
   const double initial_vol = 0.10;
   
   bool ok = g_order_engine.OE_Test_EstablishOCO(primary, sibling, "XAUUSD", initial_vol, initial_vol, TimeCurrent()+3600);
   ASSERT_TRUE(ok, "EstablishOCO returns true");

   // First partial: 30% (0.03 of 0.10)
   g_order_engine.OE_Test_ProcessOCOFill(primary, 0.03, 2001);
   
   // After first fill: sibling should be 0.07 (70% of 0.10)
   ulong mod_ticket1;
   double new_vol1;
   datetime ts1;
   string reason1;
   OE_Test_GetCapturedModify(0, mod_ticket1, new_vol1, ts1, reason1);
   ASSERT_NEAR(0.07, new_vol1, 1e-6, "After 30% fill: sibling = 70%");

   // Second partial: 40% more (0.04 of 0.10) → cumulative 70%
   g_order_engine.OE_Test_ProcessOCOFill(primary, 0.04, 2002);
   
   // After second fill: sibling should be 0.03 (30% of original 0.10)
   ulong mod_ticket2;
   double new_vol2;
   datetime ts2;
   string reason2;
   OE_Test_GetCapturedModify(1, mod_ticket2, new_vol2, ts2, reason2);
   ASSERT_NEAR(0.03, new_vol2, 1e-6, "After 70% cumulative fill: sibling = 30%");

   // Third partial: 30% more (0.03 of 0.10) → cumulative 100% complete
   g_order_engine.OE_Test_ProcessOCOFill(primary, 0.03, 2003);

   // Verify PARTIAL_FILL_COMPLETE decision
   int decision_count = OE_Test_GetCapturedDecisionCount();
   bool found_complete = false;
   datetime decision_ts = 0;
   for(int i = 0; i < decision_count; i++)
   {
      string decision, data;
      OE_Test_GetCapturedDecision(i, decision, data, decision_ts);
      if(decision == "PARTIAL_FILL_COMPLETE")
         found_complete = true;
   }
   ASSERT_TRUE(found_complete, "PARTIAL_FILL_COMPLETE decision captured");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// Test 3: PartialFill_CompletesOnLastShare
// Verify final fill triggers completion and clears state + OCO
//------------------------------------------------------------------------------
bool PartialFill_CompletesOnLastShare()
{
   g_current_test = "PartialFill_CompletesOnLastShare";
   PrintFormat("[TEST START] %s", g_current_test);

   g_order_engine.Init();
   g_order_engine.OE_Test_SetSessionCutoff(TimeCurrent()+3600);
   OE_Test_EnableDecisionCapture();
   OE_Test_EnableCancelModifyOverride();
   OE_Test_ForceCancelFail(true);
   OE_Test_ForceModifyOk(true);

   const ulong primary = 12001;
   const ulong sibling = 12002;
   const double initial_vol = 0.10;
   
   bool ok = g_order_engine.OE_Test_EstablishOCO(primary, sibling, "XAUUSD", initial_vol, initial_vol, TimeCurrent()+3600);
   ASSERT_TRUE(ok, "EstablishOCO returns true");

   // First partial: 90% (0.09 of 0.10), leaving 0.01 remaining
   g_order_engine.OE_Test_ProcessOCOFill(primary, 0.09, 3001);
   
   // Verify partial state exists
   ASSERT_TRUE(OE_Test_GetCapturedDecisionCount() > 0, "Partial fill logged");

   // Final partial: 10% (0.01 of 0.10) → complete
   g_order_engine.OE_Test_ProcessOCOFill(primary, 0.01, 3002);

   // Verify PARTIAL_FILL_COMPLETE decision
   int decision_count = OE_Test_GetCapturedDecisionCount();
   bool found_complete = false;
   datetime decision_ts = 0;
   for(int i = 0; i < decision_count; i++)
   {
      string decision, data;
      OE_Test_GetCapturedDecision(i, decision, data, decision_ts);
      if(decision == "PARTIAL_FILL_COMPLETE")
      {
         found_complete = true;
         PrintFormat("[INFO] Completion data: %s", data);
      }
   }
   ASSERT_TRUE(found_complete, "PARTIAL_FILL_COMPLETE on last share");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// Test 4: PartialFill_RejectedIfNoSibling
// Verify handler logs warning but continues when opposite leg is missing
//------------------------------------------------------------------------------
bool PartialFill_RejectedIfNoSibling()
{
   g_current_test = "PartialFill_RejectedIfNoSibling";
   PrintFormat("[TEST START] %s", g_current_test);

   g_order_engine.Init();
   g_order_engine.OE_Test_SetSessionCutoff(TimeCurrent()+3600);
   OE_Test_EnableDecisionCapture();
   OE_Test_EnableCancelModifyOverride();
   OE_Test_ForceCancelFail(true);
   OE_Test_ForceModifyOk(true);

   const ulong primary = 13001;
   const ulong sibling = 0;  // Invalid sibling ticket
   const double initial_vol = 0.10;
   
   bool ok = g_order_engine.OE_Test_EstablishOCO(primary, sibling, "XAUUSD", initial_vol, initial_vol, TimeCurrent()+3600);
   ASSERT_TRUE(ok, "EstablishOCO returns true");

   // Attempt partial fill with missing sibling
   bool handled = g_order_engine.OE_Test_ProcessOCOFill(primary, 0.05, 4001);
   
   // Should continue processing (not crash), but log warning
   int decision_count = OE_Test_GetCapturedDecisionCount();
   bool found_missing = false;
   datetime decision_ts = 0;
   for(int i = 0; i < decision_count; i++)
   {
      string decision, data;
      OE_Test_GetCapturedDecision(i, decision, data, decision_ts);
      if(decision == "OCO_SIBLING_MISSING")
         found_missing = true;
   }
   ASSERT_TRUE(found_missing, "OCO_SIBLING_MISSING decision logged");
   ASSERT_TRUE(handled, "Handler continues despite missing sibling");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// Test 5: PartialFill_LogsAdjustments
// Verify every partial fill logs PARTIAL_FILL_ADJUST with complete details
//------------------------------------------------------------------------------
bool PartialFill_LogsAdjustments()
{
   g_current_test = "PartialFill_LogsAdjustments";
   PrintFormat("[TEST START] %s", g_current_test);

   g_order_engine.Init();
   g_order_engine.OE_Test_SetSessionCutoff(TimeCurrent()+3600);
   OE_Test_EnableDecisionCapture();
   OE_Test_EnableCancelModifyOverride();
   OE_Test_ForceCancelFail(true);
   OE_Test_ForceModifyOk(true);

   const ulong primary = 14001;
   const ulong sibling = 14002;
   const double initial_vol = 0.10;
   
   bool ok = g_order_engine.OE_Test_EstablishOCO(primary, sibling, "XAUUSD", initial_vol, initial_vol, TimeCurrent()+3600);
   ASSERT_TRUE(ok, "EstablishOCO returns true");

   // First partial: 40% (0.04 of 0.10)
   g_order_engine.OE_Test_ProcessOCOFill(primary, 0.04, 5001);
   
   // Second partial: 60% more (0.06 of 0.10) → complete
   g_order_engine.OE_Test_ProcessOCOFill(primary, 0.06, 5002);

   // Verify 2 PARTIAL_FILL_ADJUST decisions captured
   int decision_count = OE_Test_GetCapturedDecisionCount();
   int adjust_count = 0;
   int complete_count = 0;
   datetime decision_ts = 0;
   
   for(int i = 0; i < decision_count; i++)
   {
      string decision, data;
      OE_Test_GetCapturedDecision(i, decision, data, decision_ts);
      if(decision == "PARTIAL_FILL_ADJUST")
      {
         adjust_count++;
         // Verify data contains required fields
         ASSERT_TRUE(StringFind(data, "fill_vol") >= 0, "Log contains fill_vol");
         ASSERT_TRUE(StringFind(data, "total_filled") >= 0, "Log contains total_filled");
         ASSERT_TRUE(StringFind(data, "remaining") >= 0, "Log contains remaining");
         ASSERT_TRUE(StringFind(data, "fill_count") >= 0, "Log contains fill_count");
         ASSERT_TRUE(StringFind(data, "opposite") >= 0, "Log contains opposite");
         ASSERT_TRUE(StringFind(data, "opposite_new_vol") >= 0, "Log contains opposite_new_vol");
         PrintFormat("[INFO] Adjust %d: %s", adjust_count, data);
      }
      else if(decision == "PARTIAL_FILL_COMPLETE")
      {
         complete_count++;
         PrintFormat("[INFO] Complete: %s", data);
      }
   }
   
   ASSERT_EQUALS(2, adjust_count, "2 PARTIAL_FILL_ADJUST decisions");
   ASSERT_EQUALS(1, complete_count, "1 PARTIAL_FILL_COMPLETE decision");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// Test Runner
//------------------------------------------------------------------------------
bool TestOrderEnginePartialFills_RunAll()
{
   PrintFormat("=================================================================");
   PrintFormat("RPEA Order Engine Tests - Task 8 Partial Fill Handler");
   PrintFormat("=================================================================");

   g_test_passed = 0;
   g_test_failed = 0;

   bool t1 = PartialFill_AdjustsSiblingVolume();
   bool t2 = PartialFill_AggregatesMultipleEvents();
   bool t3 = PartialFill_CompletesOnLastShare();
   bool t4 = PartialFill_RejectedIfNoSibling();
   bool t5 = PartialFill_LogsAdjustments();

   bool all_passed = (t1 && t2 && t3 && t4 && t5 && g_test_failed == 0);
   
   PrintFormat("=================================================================");
   PrintFormat("Test Summary: %d passed, %d failed", g_test_passed, g_test_failed);
   
   if(all_passed)
      PrintFormat("Partial Fill tests PASSED");
   else
      PrintFormat("Partial Fill tests FAILED");
   
   PrintFormat("=================================================================");
   return all_passed;
}

#endif // TEST_ORDER_ENGINE_PARTIALFILLS_MQH

