#ifndef TEST_ORDER_ENGINE_ERRORS_MQH
#define TEST_ORDER_ENGINE_ERRORS_MQH
// test_order_engine_errors.mqh - Task 17 resilience & error handler tests

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

void Errors_ResetState()
{
   g_order_engine.TestResetResilienceState();
   g_order_engine.TestResetIntentJournal();
}

bool TestErrorHandling_ClassifiesFailFast()
{
   g_current_test = "ErrorHandling_ClassifiesFailFast";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;
   Errors_ResetState();

   OrderError err(TRADE_RETCODE_TRADE_DISABLED);
   err.context = "UnitTest";
   OrderErrorDecision decision = g_order_engine.ResilienceHandleError(err);
   ASSERT_EQUALS(ERROR_DECISION_FAIL_FAST, decision.type, "Fail-fast decision returned");
   ASSERT_TRUE(g_order_engine.GetBreakerUntil() > 0, "Breaker tripped");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestErrorHandling_TriggersCircuitBreaker()
{
   g_current_test = "ErrorHandling_TriggersCircuitBreaker";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;
   Errors_ResetState();

   const int threshold = Config_GetMaxConsecutiveFailures();
   OrderError err(TRADE_RETCODE_PRICE_CHANGED);
   err.context = "UnitTest";
   for(int i = 0; i < threshold; ++i)
   {
      err.attempt = i;
      g_order_engine.ResilienceHandleError(err);
   }
   ASSERT_TRUE(g_order_engine.GetBreakerUntil() > 0, "Breaker active after repeated failures");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestErrorHandling_RetriesRecoverable()
{
   g_current_test = "ErrorHandling_RetriesRecoverable";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;
   Errors_ResetState();

   OrderError err(TRADE_RETCODE_CONNECTION);
   err.context = "UnitTest";
   err.attempt = 0;
   OrderErrorDecision first = g_order_engine.ResilienceHandleError(err);
   ASSERT_EQUALS(ERROR_DECISION_RETRY, first.type, "Transient error retries");
   ASSERT_EQUALS(DEFAULT_InitialRetryDelayMs, first.retry_delay_ms, "Initial delay matches config");

   err.attempt = 1;
   OrderErrorDecision second = g_order_engine.ResilienceHandleError(err);
   ASSERT_EQUALS(ERROR_DECISION_RETRY, second.type, "Second attempt still retries");
   ASSERT_TRUE(second.retry_delay_ms > first.retry_delay_ms, "Backoff applied");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestErrorHandling_LogsAlerts()
{
   g_current_test = "ErrorHandling_LogsAlerts";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;
   Errors_ResetState();

   OE_Test_EnableDecisionCapture();
   OrderError err(TRADE_RETCODE_TRADE_DISABLED);
   err.context = "AlertTest";
   g_order_engine.ResilienceHandleError(err);
   int captured = OE_Test_GetCapturedDecisionCount();
   ASSERT_TRUE(captured > 0, "Decision capture entries recorded");
   if(captured > 0)
   {
      string event, payload;
      datetime ts;
      ASSERT_TRUE(OE_Test_GetCapturedDecision(captured - 1, event, payload, ts), "Fetched capture row");
      ASSERT_TRUE(StringFind(event, "ERROR_HANDLING") >= 0, "Error handling log emitted");
   }
   OE_Test_DisableDecisionCapture();

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestErrorHandling_ResetsAfterRecovery()
{
   g_current_test = "ErrorHandling_ResetsAfterRecovery";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;
   Errors_ResetState();

   OrderError err(TRADE_RETCODE_PRICE_OFF);
   err.context = "ResetTest";
   g_order_engine.ResilienceHandleError(err);
   ASSERT_TRUE(g_order_engine.GetConsecutiveFailures() > 0, "Failure counter incremented");
   g_order_engine.ResilienceRecordSuccess();
   ASSERT_EQUALS(0, g_order_engine.GetConsecutiveFailures(), "Counters reset after success");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestErrorHandling_ProtectiveBypass()
{
   g_current_test = "Breaker_AllowsProtectiveExit";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;
   Errors_ResetState();

   OrderError err(TRADE_RETCODE_TRADE_DISABLED);
   err.context = "BreakerTest";
   g_order_engine.ResilienceHandleError(err);
   ASSERT_TRUE(g_order_engine.BreakerBlocksAction(false), "Breaker blocks non protective");
   ASSERT_FALSE(g_order_engine.BreakerBlocksAction(true), "Protective bypass honored");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestErrorHandling_SelfHealScheduling()
{
   g_current_test = "SelfHeal_SchedulesAndResets";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;
   Errors_ResetState();

   OrderError err(TRADE_RETCODE_TRADE_DISABLED);
   err.context = "SelfHeal";
   g_order_engine.ResilienceHandleError(err);
   ASSERT_TRUE(g_order_engine.IsSelfHealActive(), "Self-heal flagged");
   ASSERT_TRUE(g_order_engine.GetSelfHealAttempts() >= 1, "Self-heal attempt recorded");

   g_order_engine.ResilienceRecordSuccess();
   ASSERT_FALSE(g_order_engine.IsSelfHealActive(), "Self-heal cleared after success");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestOrderEngineErrors_RunAll()
{
   bool ok = true;
   ok = ok && TestErrorHandling_ClassifiesFailFast();
   ok = ok && TestErrorHandling_TriggersCircuitBreaker();
   ok = ok && TestErrorHandling_RetriesRecoverable();
   ok = ok && TestErrorHandling_LogsAlerts();
   ok = ok && TestErrorHandling_ResetsAfterRecovery();
   ok = ok && TestErrorHandling_ProtectiveBypass();
   ok = ok && TestErrorHandling_SelfHealScheduling();
   return ok;
}

#endif // TEST_ORDER_ENGINE_ERRORS_MQH
