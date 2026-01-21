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
   // Use current time to avoid TTL cleanup during tests
   string ts_iso = Persistence_FormatIso8601(TimeCurrent());
   string expiry_iso = Persistence_FormatIso8601(TimeCurrent() + 3600);
   
   string base = "{";
   base += "\"intent_id\":\"" + id + "\",";
   base += "\"accept_once_key\":\"" + id + "\",";
   base += "\"timestamp\":\"" + ts_iso + "\",";
   base += "\"symbol\":\"XAUUSD\",";
   base += "\"signal_symbol\":\"XAUUSD\",";
   base += "\"order_type\":\"ORDER_TYPE_BUY\",";
   base += "\"volume\":0.10,";
   base += "\"price\":1900.0,";
   base += "\"sl\":1895.0,";
   base += "\"tp\":1905.0,";
   base += "\"expiry\":\"" + expiry_iso + "\",";
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

string RecoveryTests_IntentJsonWithTicket(const string id,
                                          const string status,
                                          const ulong ticket)
{
   // Use current time to avoid TTL cleanup during tests
   string ts_iso = Persistence_FormatIso8601(TimeCurrent());
   string expiry_iso = Persistence_FormatIso8601(TimeCurrent() + 3600);
   
   string base = "{";
   base += "\"intent_id\":\"" + id + "\",";
   base += "\"accept_once_key\":\"" + id + "\",";
   base += "\"timestamp\":\"" + ts_iso + "\",";
   base += "\"symbol\":\"XAUUSD\",";
   base += "\"signal_symbol\":\"XAUUSD\",";
   base += "\"order_type\":\"ORDER_TYPE_BUY\",";
   base += "\"volume\":0.10,";
   base += "\"price\":1900.0,";
   base += "\"sl\":1895.0,";
   base += "\"tp\":1905.0,";
   base += "\"expiry\":\"" + expiry_iso + "\",";
   base += "\"status\":\"" + status + "\",";
   base += "\"execution_mode\":\"DIRECT\",";
   base += "\"is_proxy\":false,";
   base += "\"proxy_rate\":1.0,";
   base += "\"proxy_context\":\"\",";
   base += "\"oco_sibling_id\":\"\",";
   base += "\"retry_count\":0,";
   base += "\"reasoning\":\"\",";
   base += "\"error_messages\":[],";
   base += "\"executed_tickets\":[" + (string)ticket + "],";
   base += "\"partial_fills\":[],";
   base += "\"gate_pass\":true,";
   base += "\"tickets_snapshot\":[]";
   base += "}";
   return base;
}

string RecoveryTests_ActionJson(const string id,
                                const datetime queued_time,
                                const datetime expires_time)
{
   string queued_iso = Persistence_FormatIso8601(queued_time);
   string expires_iso = Persistence_FormatIso8601(expires_time);

   string base = "{";
   base += "\"action_id\":\"" + id + "\",";
   base += "\"accept_once_key\":\"" + id + "\",";
   base += "\"ticket\":0,";
   base += "\"action_type\":\"MODIFY_SL\",";
   base += "\"new_value\":0.0,";
   base += "\"validation_threshold\":0.0,";
   base += "\"queued_time\":\"" + queued_iso + "\",";
   base += "\"expires_time\":\"" + expires_iso + "\",";
   base += "\"trigger_condition\":\"\",";
   base += "\"intent_id\":\"\",";
   base += "\"intent_key\":\"\",";
   base += "\"queued_confidence\":0.0,";
   base += "\"queued_efficiency\":0.0,";
   base += "\"rho_est\":0.0,";
   base += "\"est_value\":0.0,";
   base += "\"gate_open_risk\":0.0,";
   base += "\"gate_pending_risk\":0.0,";
   base += "\"gate_next_risk\":0.0,";
   base += "\"room_today\":0.0,";
   base += "\"room_overall\":0.0,";
   base += "\"gate_pass\":false,";
   base += "\"gating_reason\":\"\",";
   base += "\"news_window_state\":\"\"";
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

//------------------------------------------------------------------------------
// M6-Task03: Idempotency Tests
//------------------------------------------------------------------------------

bool TestRecovery_IdempotentSecondCall()
{
   g_current_test = "TestRecovery_IdempotentSecondCall";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;

   // Setup: write empty journal
   string payload = RecoveryTests_BuildJournal("", "");
   RecoveryTests_WriteJournal(payload);

   // First recovery call
   g_order_engine.Init();
   g_order_engine.LoadSLEnforcementState();
   bool first_ok = g_order_engine.ReconcileOnStartup();
   ASSERT_TRUE(first_ok, "First reconcile succeeded");
   ASSERT_TRUE(OE_Test_IsRecoveryComplete(), "Recovery flag set after first call");

   // Second recovery call should be idempotent no-op
   bool second_ok = g_order_engine.ReconcileOnStartup();
   ASSERT_TRUE(second_ok, "Second reconcile returns true (no-op)");
   ASSERT_TRUE(OE_Test_IsRecoveryComplete(), "Recovery flag still set after second call");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestRecovery_SkipsDuplicateIntent()
{
   g_current_test = "TestRecovery_SkipsDuplicateIntent";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;

   const ulong ticket = 12345678;
   // Create intent with executed_tickets - simulates order already on broker
   string intent_with_ticket = RecoveryTests_IntentJsonWithTicket("dup_check_1", "PENDING", ticket);
   string payload = RecoveryTests_BuildJournal(intent_with_ticket, "");
   RecoveryTests_WriteJournal(payload);

   g_order_engine.Init();
   g_order_engine.LoadSLEnforcementState();

   ulong positions[];
   ArrayResize(positions, 1);
   positions[0] = ticket;
   ulong pendings[];
   ArrayResize(pendings, 0);
   OE_Test_SetRecoveryBrokerState(positions, pendings);

   bool ok = g_order_engine.ReconcileOnStartup();
   ASSERT_TRUE(ok, "Reconcile succeeded");
   OE_Test_ClearRecoveryBrokerState();

   PersistenceRecoveredState state;
   ASSERT_TRUE(Persistence_LoadRecoveredState(state), "Load succeeded");
   ASSERT_EQUALS(1, state.intents_count, "One intent recovered");
   if(state.intents_count > 0)
      ASSERT_TRUE(state.intents[0].status == "EXECUTED", "Intent marked EXECUTED");
   Persistence_FreeRecoveredState(state);

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestRecovery_DropsExpiredActions()
{
   g_current_test = "TestRecovery_DropsExpiredActions";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;

   g_order_engine.Init();
   g_order_engine.LoadSLEnforcementState();

   // Create action with past expiry
   datetime now = TimeCurrent();
   string expired_action = RecoveryTests_ActionJson("expired_1", now, now - 60);
   string payload = RecoveryTests_BuildJournal("", expired_action);
   RecoveryTests_WriteJournal(payload);

   bool ok = g_order_engine.ReconcileOnStartup();
   ASSERT_TRUE(ok, "Reconcile succeeded");

   PersistenceRecoveredState state;
   ASSERT_TRUE(Persistence_LoadRecoveredState(state), "Load succeeded");
   ASSERT_EQUALS(0, state.queued_count, "Expired actions dropped");
   Persistence_FreeRecoveredState(state);

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestRecovery_RunAll()
{
   bool ok = true;
   ok = ok && TestRecovery_LoadsEntries();
   ok = ok && TestRecovery_DedupsIntents();
   ok = ok && TestRecovery_ReconcileCompletes();
   // M6-Task03: Idempotency tests
   ok = ok && TestRecovery_IdempotentSecondCall();
   ok = ok && TestRecovery_SkipsDuplicateIntent();
   ok = ok && TestRecovery_DropsExpiredActions();
   return ok;
}

#endif // TEST_ORDER_ENGINE_RECOVERY_MQH
