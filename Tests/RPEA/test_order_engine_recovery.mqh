#ifndef TEST_ORDER_ENGINE_RECOVERY_MQH
#define TEST_ORDER_ENGINE_RECOVERY_MQH
// test_order_engine_recovery.mqh - Unit tests for Task 16 (State Recovery)

#include <RPEA/persistence.mqh>
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
#endif // TEST_FRAMEWORK_DEFINED

extern OrderEngine g_order_engine;

//------------------------------------------------------------------------------
// Helpers
//------------------------------------------------------------------------------

void RecoveryTests_WriteJournal(const string payload)
{
   Persistence_EnsureFolders();
   int handle = FileOpen(FILE_INTENTS, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;
   FileWrite(handle, payload);
   FileClose(handle);
}

string RecoveryTests_BasicIntentJson(const string id)
{
   string base = "{";
   base += "\"intent_id\":\"" + id + "\",";
   base += "\"accept_once_key\":\"" + id + "\",";
   base += "\"timestamp\":\"2024-01-01T00:00:00\",";
   base += "\"symbol\":\"XAUUSD\",";
   base += "\"signal_symbol\":\"XAUUSD\",";
   base += "\"order_type\":\"ORDER_TYPE_BUY\",";
   base += "\"volume\":0.10,";
   base += "\"price\":1900.0,";
   base += "\"sl\":1895.0,";
   base += "\"tp\":1905.0,";
   base += "\"expiry\":\"2024-01-01T01:00:00\",";
   base += "\"status\":\"PENDING\",";
   base += "\"execution_mode\":\"DIRECT\",";
   base += "\"is_proxy\":false,";
   base += "\"proxy_rate\":1.0,";
   base += "\"proxy_context\":\"\",";
   base += "\"oco_sibling_id\":\"\",";
   base += "\"retry_count\":0,";
   base += "\"reasoning\":\"\",";
   base += "\"error_messages\":[],";
   base += "\"executed_tickets\":[],";
   base += "\"partial_fills\":[],";
   base += "\"gate_pass\":false,";
   base += "\"tickets_snapshot\":[]";
   base += "}";
   return base;
}

string RecoveryTests_BuildJournal(const string intents_array, const string actions_array)
{
   string payload = "{";
   payload += "\"schema_version\":3,";
   payload += "\"intents\":[" + intents_array + "],";
   payload += "\"queued_actions\":[" + actions_array + "]";
   payload += "}";
   return payload;
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

bool TestRecovery_LoadsEntries()
{
   g_current_test = "TestRecovery_LoadsEntries";
   PrintFormat("[TEST START] %s", g_current_test);

   string payload = RecoveryTests_BuildJournal(
      RecoveryTests_BasicIntentJson("rec_1") + "," + RecoveryTests_BasicIntentJson("rec_2"),
      "");
   RecoveryTests_WriteJournal(payload);

   PersistenceRecoveredState state;
   ASSERT_TRUE(Persistence_LoadRecoveredState(state), "Load succeeded");
   ASSERT_EQUALS(2, state.intents_count, "Two intents recovered");
   Persistence_FreeRecoveredState(state);

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool TestRecovery_DedupsIntents()
{
   g_current_test = "TestRecovery_DedupsIntents";
   PrintFormat("[TEST START] %s", g_current_test);

   string dup = RecoveryTests_BasicIntentJson("dup_1");
   string payload = RecoveryTests_BuildJournal(dup + "," + dup, "");
   RecoveryTests_WriteJournal(payload);

   PersistenceRecoveredState state;
   ASSERT_TRUE(Persistence_LoadRecoveredState(state), "Load succeeded");
   ASSERT_EQUALS(1, state.intents_count, "Duplicate intent dropped");
   ASSERT_TRUE(state.summary.intents_dropped >= 1, "Drop count recorded");
   Persistence_FreeRecoveredState(state);

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool TestRecovery_ReconcileCompletes()
{
   g_current_test = "TestRecovery_ReconcileCompletes";
   PrintFormat("[TEST START] %s", g_current_test);

   string payload = RecoveryTests_BuildJournal("", "");
   RecoveryTests_WriteJournal(payload);

   g_order_engine.Init();
   g_order_engine.LoadSLEnforcementState();
   bool ok = g_order_engine.ReconcileOnStartup();
   ASSERT_TRUE(ok, "Reconcile succeeded");
   ASSERT_TRUE(OE_Test_IsRecoveryComplete(), "Recovery flag set");
   ASSERT_EQUALS(0, OE_Test_GetRecoveredIntentCount(), "No intents recovered");

   PrintFormat("[TEST END] %s", g_current_test);
   return (g_test_failed == 0);
}

bool TestRecovery_RunAll()
{
   bool ok = true;
   ok = ok && TestRecovery_LoadsEntries();
   ok = ok && TestRecovery_DedupsIntents();
   ok = ok && TestRecovery_ReconcileCompletes();
   return ok;
}

#endif // TEST_ORDER_ENGINE_RECOVERY_MQH
