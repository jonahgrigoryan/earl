#ifndef TEST_ORDER_ENGINE_INTENT_MQH
#define TEST_ORDER_ENGINE_INTENT_MQH
// test_order_engine_intent.mqh - Unit tests for intent journal & idempotency (M3 Task 2)
// References: .kiro/specs/rpea-m3/tasks.md, design.md, requirements.md

#include <RPEA/order_engine.mqh>
#include <RPEA/persistence.mqh>

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

#ifndef ASSERT_STRING_EQ
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
#endif

//------------------------------------------------------------------------------
// Helpers
//------------------------------------------------------------------------------

void IntentTests_ResetJournal()
{
   Persistence_EnsureFolders();
   Persistence_EnsurePlaceholderFiles();
   IntentJournal journal;
   IntentJournal_Clear(journal);
   IntentJournal_Save(journal);
}

void IntentTests_ResetEngine()
{
   OE_Test_ClearOverrides();
   OE_Test_ClearOrderSendOverride();
   OE_Test_ResetRetryDelayCapture();
   // Ensure journal is empty before init
   IntentTests_ResetJournal();
   g_order_engine.Init();
}

void IntentTests_ShutdownEngine()
{
   g_order_engine.OnShutdown();
   OE_Test_ClearOverrides();
   OE_Test_ClearOrderSendOverride();
   OE_Test_ResetRetryDelayCapture();
   IntentTests_ResetJournal();
}

//------------------------------------------------------------------------------
// Test cases
//------------------------------------------------------------------------------

bool IntentRecording_PersistsIntent()
{
   g_current_test = "IntentRecording_PersistsIntent";
   PrintFormat("[TEST START] %s", g_current_test);

   IntentTests_ResetJournal();
   IntentTests_ResetEngine();

   const string symbol = "INTENT.TEST.SYM";
   OE_Test_SetVolumeOverride(symbol, 0.01, 0.01, 10.0);
   OE_Test_SetPriceOverride(symbol, 0.01, 2, 1800.00, 1800.05, 0);
   OE_Test_SetRiskOverride(true, 50.0);

   OE_Test_EnableOrderSendOverride();
   OE_Test_EnqueueOrderSendResponse(true, TRADE_RETCODE_DONE, 1001001, 0, 1800.02, 0.10, "ok");

   OrderRequest req;
   ZeroMemory(req);
   req.symbol = symbol;
   req.type = ORDER_TYPE_BUY_LIMIT;
   req.volume = 0.10;
   req.price = 1800.01;
   req.sl = 1799.50;
   req.tp = 1801.50;
   req.magic = 12345;
   req.comment = "Intent persistence test";
   req.expiry = TimeCurrent() + 600;

   OrderResult res = g_order_engine.PlaceOrder(req);

   ASSERT_TRUE(res.intent_id != "", "Intent id assigned");
   ASSERT_TRUE(res.accept_once_key != "", "Accept-once key assigned");
   ASSERT_TRUE(res.success, "Order result success");

   IntentJournal journal;
   IntentJournal_Load(journal);
   ASSERT_EQUALS(1, ArraySize(journal.intents), "One intent persisted");
   if(ArraySize(journal.intents) == 1)
   {
      string persisted_intent_id = journal.intents[0].intent_id;
      string persisted_accept_key = journal.intents[0].accept_once_key;
      string persisted_status = journal.intents[0].status;

      ASSERT_STRING_EQ(res.intent_id, persisted_intent_id, "Persisted intent id matches result");
      ASSERT_STRING_EQ(res.accept_once_key, persisted_accept_key, "Persisted accept key matches result");
      ASSERT_STRING_EQ("EXECUTED", persisted_status, "Intent marked executed");
      ASSERT_EQUALS(1, ArraySize(journal.intents[0].executed_tickets), "Executed ticket recorded");
   }

   IntentTests_ShutdownEngine();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool IntentDeduplication_RejectsDuplicate()
{
   g_current_test = "IntentDeduplication_RejectsDuplicate";
   PrintFormat("[TEST START] %s", g_current_test);

   IntentTests_ResetJournal();
   IntentTests_ResetEngine();

   const string symbol = "INTENT.DEDUP.SYM";
   OE_Test_SetVolumeOverride(symbol, 0.01, 0.01, 5.0);
   OE_Test_SetPriceOverride(symbol, 0.01, 2, 1900.00, 1900.04, 0);
   OE_Test_SetRiskOverride(true, 40.0);

   OE_Test_EnableOrderSendOverride();
   OE_Test_EnqueueOrderSendResponse(true, TRADE_RETCODE_DONE, 2002002, 0, 1900.03, 0.20, "ok");

   OrderRequest req;
   ZeroMemory(req);
   req.symbol = symbol;
   req.type = ORDER_TYPE_SELL_LIMIT;
   req.volume = 0.20;
   req.price = 1900.02;
   req.sl = 1901.00;
   req.tp = 1898.00;
   req.magic = 54321;
   req.comment = "Dedup test request";
   req.expiry = TimeCurrent() + 900;

   OrderResult first = g_order_engine.PlaceOrder(req);
   ASSERT_TRUE(first.success, "First intent accepted");

   // Duplicate should be rejected before hitting broker
   OrderResult second = g_order_engine.PlaceOrder(req);
   ASSERT_FALSE(second.success, "Duplicate intent rejected");
   ASSERT_TRUE(StringFind(second.error_message, "Duplicate") >= 0, "Duplicate error message returned");

   string first_key = first.accept_once_key;
   string second_key = second.accept_once_key;
   ASSERT_STRING_EQ(first_key, second_key, "Duplicate shows same accept key");

   IntentJournal journal;
   IntentJournal_Load(journal);
   ASSERT_EQUALS(1, ArraySize(journal.intents), "Journal still contains one intent");

   IntentTests_ShutdownEngine();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool IntentJournal_SerializationRoundTrip()
{
   g_current_test = "IntentJournal_SerializationRoundTrip";
   PrintFormat("[TEST START] %s", g_current_test);

   IntentTests_ResetJournal();

   IntentJournal original;
   IntentJournal_Clear(original);

   ArrayResize(original.intents, 1);
   original.intents[0].intent_id = "rpea_20240101_000000_001";
   original.intents[0].accept_once_key = "intent_sample_hash";
   original.intents[0].timestamp = TimeCurrent();
   original.intents[0].symbol = "XAUUSD";
   original.intents[0].order_type = ORDER_TYPE_BUY_LIMIT;
   original.intents[0].volume = 0.12;
   original.intents[0].price = 1905.55;
   original.intents[0].sl = 1900.00;
   original.intents[0].tp = 1915.00;
   original.intents[0].expiry = TimeCurrent() + 3600;
   original.intents[0].status = "PENDING";
   original.intents[0].execution_mode = "DIRECT";
   original.intents[0].oco_sibling_id = "";
   original.intents[0].retry_count = 0;
   original.intents[0].reasoning = "Round-trip test";
   ArrayResize(original.intents[0].error_messages, 0);
   ArrayResize(original.intents[0].executed_tickets, 0);
   ArrayResize(original.intents[0].partial_fills, 0);

   ArrayResize(original.queued_actions, 1);
   original.queued_actions[0].action_id = "rpea_action_20240101_000100_001";
   original.queued_actions[0].accept_once_key = "action_sample_hash";
   original.queued_actions[0].ticket = 123456;
   original.queued_actions[0].action_type = "TRAILING_UPDATE";
   original.queued_actions[0].new_value = 1899.50;
   original.queued_actions[0].validation_threshold = 0.5;
   original.queued_actions[0].queued_time = TimeCurrent();
   original.queued_actions[0].expires_time = TimeCurrent() + 300;
   original.queued_actions[0].trigger_condition = "news_window_end";

   IntentJournal_Save(original);

   IntentJournal loaded;
   IntentJournal_Load(loaded);

   ASSERT_EQUALS(ArraySize(original.intents), ArraySize(loaded.intents), "Intent count round-trip");
   ASSERT_EQUALS(ArraySize(original.queued_actions), ArraySize(loaded.queued_actions), "Action count round-trip");
   if(ArraySize(loaded.intents) == 1)
   {
      string orig_intent_id = original.intents[0].intent_id;
      string loaded_intent_id = loaded.intents[0].intent_id;
      string orig_status = original.intents[0].status;
      string loaded_status = loaded.intents[0].status;

      ASSERT_STRING_EQ(orig_intent_id, loaded_intent_id, "Intent id preserved");
      ASSERT_STRING_EQ(orig_status, loaded_status, "Intent status preserved");
   }
   if(ArraySize(loaded.queued_actions) == 1)
   {
      string orig_action_id = original.queued_actions[0].action_id;
      string loaded_action_id = loaded.queued_actions[0].action_id;
      string orig_action_type = original.queued_actions[0].action_type;
      string loaded_action_type = loaded.queued_actions[0].action_type;

      ASSERT_STRING_EQ(orig_action_id, loaded_action_id, "Action id preserved");
      ASSERT_STRING_EQ(orig_action_type, loaded_action_type, "Action type preserved");
   }

   IntentTests_ResetJournal();
   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

//------------------------------------------------------------------------------
// Test runner
//------------------------------------------------------------------------------

bool TestOrderEngineIntent_RunAll()
{
   PrintFormat("=================================================================");
   PrintFormat("RPEA Order Engine Tests - Intent Journal & Idempotency (Task 2)");
   PrintFormat("=================================================================");

   g_test_passed = 0;
   g_test_failed = 0;

   IntentRecording_PersistsIntent();
   IntentDeduplication_RejectsDuplicate();
   IntentJournal_SerializationRoundTrip();

   PrintFormat("=================================================================");
   PrintFormat("Test Summary: %d passed, %d failed", g_test_passed, g_test_failed);
   if(g_test_failed == 0)
      PrintFormat("ALL INTENT TESTS PASSED!");
   else
      PrintFormat("INTENT TESTS FAILED - Review output for details");
   PrintFormat("=================================================================");

   IntentTests_ResetJournal();
   return (g_test_failed == 0);
}

#endif // TEST_ORDER_ENGINE_INTENT_MQH
