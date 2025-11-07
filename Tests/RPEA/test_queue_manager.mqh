#ifndef TEST_QUEUE_MANAGER_MQH
#define TEST_QUEUE_MANAGER_MQH

#include <RPEA/queue.mqh>
#include <RPEA/persistence.mqh>

int tq_passed = 0;
int tq_failed = 0;
string tq_current = "";

#define TQ_ASSERT_TRUE(cond, msg) \
   do { \
      if(cond) { \
         tq_passed++; \
         PrintFormat("[PASS] %s: %s", tq_current, msg); \
      } else { \
         tq_failed++; \
         PrintFormat("[FAIL] %s: %s", tq_current, msg); \
      } \
   } while(false)

#define TQ_ASSERT_EQUALS(exp, act, msg) \
   do { \
      if((exp) == (act)) { \
         tq_passed++; \
         PrintFormat("[PASS] %s: %s (expected=%d actual=%d)", tq_current, msg, (int)(exp), (int)(act)); \
      } else { \
         tq_failed++; \
         PrintFormat("[FAIL] %s: %s (expected=%d actual=%d)", tq_current, msg, (int)(exp), (int)(act)); \
      } \
   } while(false)

bool TestQueue_TTLDrop_AfterQueueTTLMinutes()
{
   tq_current = "Queue_TTLDrop";
   Queue_Test_Reset();
   Queue_Init(1, 5, true);

   datetime now = TimeCurrent();
   QueuedAction expired;
   expired.id = 1;
   expired.ticket = 41;
   expired.action_type = QA_SL_MODIFY;
   expired.created_at = now - 3600;
   expired.expires_at = now - 120;
   expired.priority = QP_OTHER;
   expired.symbol = "XAUUSD";
   expired.new_sl = 1000.0;
   expired.new_tp = 0.0;
   expired.context_hex = "{}";
   expired.retry_count = 0;
   Queue_Test_AddDirect(expired);
   TQ_ASSERT_EQUALS(1, Queue_Size(), "Queued action inserted");

   int dropped = Queue_CancelExpired();
   TQ_ASSERT_EQUALS(1, dropped, "Expired action dropped");
   TQ_ASSERT_EQUALS(0, Queue_Size(), "Queue empty after drop");

   Queue_Test_Reset();
   return (tq_failed == 0);
}

bool TestQueue_OverflowEnforcesPolicy()
{
   tq_current = "Queue_OverflowPolicy";
   Queue_Test_Reset();
   Queue_Init(5, 2, true);

   datetime now = TimeCurrent();
   QueuedAction base;
   base.id = 1;
   base.ticket = 1001;
   base.action_type = QA_SL_MODIFY;
   base.created_at = now;
   base.expires_at = now + 600;
   base.priority = QP_OTHER;
   base.symbol = "XAUUSD";
   base.new_sl = 1000.0;
   base.new_tp = 0.0;
   base.context_hex = "{}";
   base.retry_count = 0;
   Queue_Test_AddDirect(base);

   QueuedAction tighten = base;
   tighten.id = 2;
   tighten.ticket = 1002;
   tighten.priority = QP_TIGHTEN_SL;
   tighten.new_sl = 1005.0;
   Queue_Test_AddDirect(tighten);
   TQ_ASSERT_EQUALS(2, Queue_Size(), "Queue seeded with two actions");

   QueuedAction protective = base;
   protective.id = 3;
   protective.ticket = 1003;
   protective.priority = QP_PROTECTIVE_EXIT;
   protective.action_type = QA_CLOSE;

   string reason = "";
   long evicted_id = 0;
   int admit = Queue_AdmitOrBackpressure(protective, reason, evicted_id);
   TQ_ASSERT_EQUALS(1, admit, "Protective action evicts lower tier");
   TQ_ASSERT_TRUE(reason == "OVERFLOW_EVICT", "Overflow reason recorded");

   Queue_Test_Reset();
   return (tq_failed == 0);
}

bool TestQueue_NewsQueuing_AndPostRevalidation()
{
   tq_current = "Queue_NewsRevalidation";
   Queue_Test_Reset();
   Queue_Init(5, 5, true);
   Queue_Test_SetRiskOverrides(true, true, true, true, true);
   Queue_Test_SetNewsBlocked(true);
   Queue_Test_RegisterPosition(2001, true, 1010.0, 1000.0, 0.0);

   long queue_id = 0;
   bool queued = Queue_Add("XAUUSD",
                           2001,
                           QA_SL_MODIFY,
                           1005.0,
                           0.0,
                           "{\"source\":\"test\"}",
                           queue_id);
   TQ_ASSERT_TRUE(queued, "Action queued during news window");
   TQ_ASSERT_EQUALS(1, Queue_Size(), "Queue contains one action");

   QueuedAction qa;
   TQ_ASSERT_TRUE(Queue_Test_GetAction(0, qa), "Fetched queued action");
   string reason = "";
   bool skip_news = false;
   bool permanent_failure = false;
   bool ok = Queue_RevalidateItem(qa, reason, skip_news, permanent_failure);
   TQ_ASSERT_TRUE(!ok && skip_news && reason == "NEWS_WINDOW_BLOCK",
                  "Revalidation skipped while news blocked");

   Queue_Test_SetNewsBlocked(false);
   ok = Queue_RevalidateItem(qa, reason, skip_news, permanent_failure);
   TQ_ASSERT_TRUE(ok && !skip_news && reason == "OK",
                  "Revalidation succeeds once news window clears");

   Queue_Test_ClearOverrides();
   Queue_Test_Reset();
   return (tq_failed == 0);
}

bool TestQueue_RiskSemantics()
{
   tq_current = "Queue_RiskSemantics";
   Queue_Test_Reset();

   Queue_Test_SetRiskOverrides(true, true, false, true, true);
   string reason = "";
   bool permanent = false;
   bool ok = Queue_CheckRiskAndCaps("XAUUSD",
                                    0,
                                    QA_SL_MODIFY,
                                    true,
                                    reason,
                                    permanent);
   TQ_ASSERT_TRUE(!ok && permanent && reason == "FAIL_CAPS",
                  "Risk-reducing action still respects caps");

   Queue_Test_SetRiskOverrides(true, false, true, true, true);
   ok = Queue_CheckRiskAndCaps("XAUUSD",
                               0,
                               QA_SL_MODIFY,
                               true,
                               reason,
                               permanent);
   TQ_ASSERT_TRUE(ok && reason == "OK",
                  "Risk-reducing action allowed when floors breached");

   Queue_Test_SetRiskOverrides(true, true, true, false, true);
   ok = Queue_CheckRiskAndCaps("XAUUSD",
                               0,
                               QA_TP_MODIFY,
                               false,
                               reason,
                               permanent);
   TQ_ASSERT_TRUE(!ok && reason == "FAIL_BUDGET",
                  "Non risk-reducing action still respects budget gate");

   Queue_Test_ClearOverrides();
   Queue_Test_Reset();
   return (tq_failed == 0);
}

bool TestQueue_Persistence_Restore()
{
   tq_current = "Queue_Persistence";
   Queue_Test_Reset();

   FileDelete(FILE_QUEUE_ACTIONS);
   string header = "id,ticket,action_type,symbol,created_at,expires_at,priority,new_sl,new_tp,context,retry_count,intent_id,intent_key";
   int handle = FileOpen(FILE_QUEUE_ACTIONS, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle != INVALID_HANDLE)
   {
      FileWrite(handle, header);
      datetime now = TimeCurrent();
      FileWrite(handle, StringFormat("1,3001,%d,XAUUSD,%I64d,%I64d,%d,1005.0,0.0,7b7d,0,intent_valid,accept_valid",
                                     (int)QA_SL_MODIFY,
                                     (long)now,
                                     (long)(now + 600),
                                     (int)QP_TIGHTEN_SL));
      FileWrite(handle, StringFormat("2,3002,%d,XAUUSD,%I64d,%I64d,%d,1002.0,0.0,7b7d,0,intent_missing,accept_missing",
                                     (int)QA_SL_MODIFY,
                                     (long)(now - 60),
                                     (long)(now + 600),
                                     (int)QP_OTHER));
      FileClose(handle);
   }

   IntentJournal journal;
   IntentJournal_Clear(journal);
   OrderIntent intent;
   intent.intent_id = "intent_valid";
   intent.accept_once_key = "accept_valid";
   ArrayResize(intent.executed_tickets, 1);
   intent.executed_tickets[0] = 3001;
   ArrayResize(journal.intents, 1);
   journal.intents[0] = intent;
   IntentJournal_Save(journal);

   int restored = Queue_LoadFromDiskAndReconcile();
   TQ_ASSERT_EQUALS(1, restored, "Only valid queued action restored");
   TQ_ASSERT_EQUALS(1, Queue_Size(), "Queue contains restored action");

   QueuedAction restored_action;
   TQ_ASSERT_TRUE(Queue_Test_GetAction(0, restored_action), "Fetched restored action");
   TQ_ASSERT_TRUE(restored_action.intent_id == "intent_valid", "Intent ID linked");
   TQ_ASSERT_TRUE(restored_action.intent_key == "accept_valid", "Intent accept key linked");

   Queue_Test_Reset();
   return (tq_failed == 0);
}

bool TestQueue_CoalesceOnExternalChange()
{
   tq_current = "Queue_Coalesce";
   Queue_Test_Reset();
   Queue_Init(5, 5, true);

   QueuedAction qa;
   qa.id = 10;
   qa.ticket = 4001;
   qa.action_type = QA_SL_MODIFY;
   qa.created_at = TimeCurrent();
   qa.expires_at = TimeCurrent() + 600;
   qa.priority = QP_OTHER;
   qa.symbol = "XAUUSD";
   qa.new_sl = 1001.0;
   qa.new_tp = 0.0;
   qa.context_hex = "{}";
   qa.retry_count = 0;
   Queue_Test_AddDirect(qa);
   TQ_ASSERT_EQUALS(1, Queue_Size(), "Action queued");

   bool removed = Queue_CoalesceIfRedundant(4001, 1001.0, 0.0);
   TQ_ASSERT_TRUE(removed, "Coalesce removed redundant action");
   TQ_ASSERT_EQUALS(0, Queue_Size(), "Queue empty after coalesce");

   Queue_Test_Reset();
   return (tq_failed == 0);
}

bool TestQueue_AuditLogging()
{
   tq_current = "Queue_AuditLogging";
   Queue_Test_Reset();
   Queue_Init(5, 5, true);
   Queue_Test_SetRiskOverrides(true, true, true, true, true);
   Queue_Test_SetNewsBlocked(true);
   Queue_Test_RegisterPosition(5001, true, 1012.0, 1000.0, 0.0);

   string ymd;
   {
      MqlDateTime tm;
      TimeToStruct(TimeCurrent(), tm);
      ymd = StringFormat("%04d%02d%02d", tm.year, tm.mon, tm.day);
   }
   string audit_path = StringFormat("%s/audit_%s.csv", RPEA_LOGS_DIR, ymd);
   FileDelete(audit_path);

   long queued_id = 0;
   Queue_Add("XAUUSD",
             5001,
             QA_SL_MODIFY,
             1005.0,
             0.0,
             "{\"source\":\"audit\"}",
             queued_id);

   Queue_Test_SetNewsBlocked(false);
   Queue_Test_Reset();

   int handle_read = FileOpen(audit_path, FILE_READ|FILE_TXT|FILE_ANSI);
   bool found_reason = false;
   if(handle_read != INVALID_HANDLE)
   {
      while(!FileIsEnding(handle_read))
      {
         string line = FileReadString(handle_read);
         if(StringFind(line, "QUEUED_NEWS") >= 0)
         {
            found_reason = true;
            break;
         }
      }
      FileClose(handle_read);
   }
   TQ_ASSERT_TRUE(found_reason, "Audit log contains queue append entry");

   return (tq_failed == 0);
}

bool TestQueueManager_RunAll()
  {
     Print("=================================================================");
     Print("RPEA Queue Manager Tests - Task 12");
     Print("=================================================================");
     tq_passed = 0;
     tq_failed = 0;

     bool ttl_ok = TestQueue_TTLDrop_AfterQueueTTLMinutes();
   bool backpressure_ok = TestQueue_OverflowEnforcesPolicy();
   bool news_ok = TestQueue_NewsQueuing_AndPostRevalidation();
   bool risk_ok = TestQueue_RiskSemantics();
   bool persistence_ok = TestQueue_Persistence_Restore();
   bool coalesce_ok = TestQueue_CoalesceOnExternalChange();
   bool audit_ok = TestQueue_AuditLogging();

   if(!ttl_ok || !backpressure_ok || !news_ok || !risk_ok ||
      !persistence_ok || !coalesce_ok || !audit_ok)
      Print("Queue Manager tests reported failures");
   else
      Print("Queue Manager tests passed");

   return (tq_failed == 0);
}

#endif // TEST_QUEUE_MANAGER_MQH
