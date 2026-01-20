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

//+------------------------------------------------------------------+
//| M6-Task02: Retcode Classification Tests                          |
//+------------------------------------------------------------------+

bool TestM6_ClassifyRetcode_FailFastCases()
{
   g_current_test = "M6_ClassifyRetcode_FailFastCases";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;

   // All fail-fast retcodes should return ERRORCLASS_FAILFAST
   ASSERT_EQUALS(ERRORCLASS_FAILFAST, OE_ClassifyRetcode(TRADE_RETCODE_TRADE_DISABLED), "TRADE_DISABLED -> FAILFAST");
   ASSERT_EQUALS(ERRORCLASS_FAILFAST, OE_ClassifyRetcode(TRADE_RETCODE_MARKET_CLOSED), "MARKET_CLOSED -> FAILFAST");
   ASSERT_EQUALS(ERRORCLASS_FAILFAST, OE_ClassifyRetcode(TRADE_RETCODE_NO_MONEY), "NO_MONEY -> FAILFAST");
   ASSERT_EQUALS(ERRORCLASS_FAILFAST, OE_ClassifyRetcode(TRADE_RETCODE_INVALID_PRICE), "INVALID_PRICE -> FAILFAST");
   ASSERT_EQUALS(ERRORCLASS_FAILFAST, OE_ClassifyRetcode(TRADE_RETCODE_INVALID_STOPS), "INVALID_STOPS -> FAILFAST");
   ASSERT_EQUALS(ERRORCLASS_FAILFAST, OE_ClassifyRetcode(TRADE_RETCODE_INVALID_VOLUME), "INVALID_VOLUME -> FAILFAST");
   ASSERT_EQUALS(ERRORCLASS_FAILFAST, OE_ClassifyRetcode(TRADE_RETCODE_INVALID_EXPIRATION), "INVALID_EXPIRATION -> FAILFAST");
   ASSERT_EQUALS(ERRORCLASS_FAILFAST, OE_ClassifyRetcode(TRADE_RETCODE_POSITION_CLOSED), "POSITION_CLOSED -> FAILFAST");
   ASSERT_EQUALS(ERRORCLASS_FAILFAST, OE_ClassifyRetcode(TRADE_RETCODE_REJECT), "REJECT -> FAILFAST");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestM6_ClassifyRetcode_TransientCases()
{
   g_current_test = "M6_ClassifyRetcode_TransientCases";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;

   // Transient retcodes should return ERRORCLASS_TRANSIENT
   ASSERT_EQUALS(ERRORCLASS_TRANSIENT, OE_ClassifyRetcode(TRADE_RETCODE_CONNECTION), "CONNECTION -> TRANSIENT");
   ASSERT_EQUALS(ERRORCLASS_TRANSIENT, OE_ClassifyRetcode(TRADE_RETCODE_TIMEOUT), "TIMEOUT -> TRANSIENT");
   ASSERT_EQUALS(ERRORCLASS_TRANSIENT, OE_ClassifyRetcode(TRADE_RETCODE_TOO_MANY_REQUESTS), "TOO_MANY_REQUESTS -> TRANSIENT");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestM6_ClassifyRetcode_RecoverableCases()
{
   g_current_test = "M6_ClassifyRetcode_RecoverableCases";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;

   // Recoverable retcodes should return ERRORCLASS_RECOVERABLE
   ASSERT_EQUALS(ERRORCLASS_RECOVERABLE, OE_ClassifyRetcode(TRADE_RETCODE_REQUOTE), "REQUOTE -> RECOVERABLE");
   ASSERT_EQUALS(ERRORCLASS_RECOVERABLE, OE_ClassifyRetcode(TRADE_RETCODE_PRICE_CHANGED), "PRICE_CHANGED -> RECOVERABLE");
   ASSERT_EQUALS(ERRORCLASS_RECOVERABLE, OE_ClassifyRetcode(TRADE_RETCODE_PRICE_OFF), "PRICE_OFF -> RECOVERABLE");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

//+------------------------------------------------------------------+
//| M6-Task02: Gating Reason Tests                                   |
//+------------------------------------------------------------------+

bool TestM6_GatingReason_CanonicalValues()
{
   g_current_test = "M6_GatingReason_CanonicalValues";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;

   // Verify canonical gating_reason strings
   ASSERT_TRUE(OE_GatingReasonForRetcode(TRADE_RETCODE_MARKET_CLOSED) == "market_closed", "MARKET_CLOSED reason");
   ASSERT_TRUE(OE_GatingReasonForRetcode(TRADE_RETCODE_TRADE_DISABLED) == "trade_disabled", "TRADE_DISABLED reason");
   ASSERT_TRUE(OE_GatingReasonForRetcode(TRADE_RETCODE_INVALID_PRICE) == "invalid_price", "INVALID_PRICE reason");
   ASSERT_TRUE(OE_GatingReasonForRetcode(TRADE_RETCODE_INVALID_STOPS) == "invalid_stops", "INVALID_STOPS reason");
   ASSERT_TRUE(OE_GatingReasonForRetcode(TRADE_RETCODE_INVALID_VOLUME) == "invalid_volume", "INVALID_VOLUME reason");
   ASSERT_TRUE(OE_GatingReasonForRetcode(TRADE_RETCODE_INVALID_EXPIRATION) == "invalid_expiration", "INVALID_EXPIRATION reason");
   ASSERT_TRUE(OE_GatingReasonForRetcode(TRADE_RETCODE_PRICE_OFF) == "off_quotes", "PRICE_OFF reason");
   ASSERT_TRUE(OE_GatingReasonForRetcode(TRADE_RETCODE_REQUOTE) == "requote", "REQUOTE reason");
   ASSERT_TRUE(OE_GatingReasonForRetcode(TRADE_RETCODE_REJECT) == "request_rejected", "REJECT reason");
   ASSERT_TRUE(OE_GatingReasonForRetcode(TRADE_RETCODE_TOO_MANY_REQUESTS) == "too_many_requests", "TOO_MANY_REQUESTS reason");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestM6_GatingReason_InDecision()
{
   g_current_test = "M6_GatingReason_InDecision";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;
   Errors_ResetState();

   // Test that fail-fast decisions include the canonical gating_reason
   OrderError err_market(TRADE_RETCODE_MARKET_CLOSED);
   err_market.context = "GatingTest";
   OrderErrorDecision decision_market = g_order_engine.ResilienceHandleError(err_market);
   ASSERT_EQUALS(ERROR_DECISION_FAIL_FAST, decision_market.type, "MARKET_CLOSED fail-fast");
   ASSERT_TRUE(decision_market.gating_reason == "market_closed", "MARKET_CLOSED gating_reason in decision");

   Errors_ResetState();
   OrderError err_disabled(TRADE_RETCODE_TRADE_DISABLED);
   err_disabled.context = "GatingTest";
   OrderErrorDecision decision_disabled = g_order_engine.ResilienceHandleError(err_disabled);
   ASSERT_EQUALS(ERROR_DECISION_FAIL_FAST, decision_disabled.type, "TRADE_DISABLED fail-fast");
   ASSERT_TRUE(decision_disabled.gating_reason == "trade_disabled", "TRADE_DISABLED gating_reason in decision");

   Errors_ResetState();
   OrderError err_reject(TRADE_RETCODE_REJECT);
   err_reject.context = "GatingTest";
   OrderErrorDecision decision_reject = g_order_engine.ResilienceHandleError(err_reject);
   ASSERT_EQUALS(ERROR_DECISION_FAIL_FAST, decision_reject.type, "REJECT fail-fast");
   ASSERT_TRUE(decision_reject.gating_reason == "request_rejected", "REJECT gating_reason in decision");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

//+------------------------------------------------------------------+
//| M6-Task02: Market Fallback Tests                                 |
//+------------------------------------------------------------------+

bool TestM6_MarketFallback_Blocked()
{
   g_current_test = "M6_MarketFallback_Blocked";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;

   // These retcodes should NOT allow market fallback
   ASSERT_FALSE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_MARKET_CLOSED), "MARKET_CLOSED no fallback");
   ASSERT_FALSE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_TRADE_DISABLED), "TRADE_DISABLED no fallback");
   ASSERT_FALSE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_NO_MONEY), "NO_MONEY no fallback");
   ASSERT_FALSE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_INVALID_PRICE), "INVALID_PRICE no fallback");
   ASSERT_FALSE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_INVALID_STOPS), "INVALID_STOPS no fallback");
   ASSERT_FALSE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_INVALID_VOLUME), "INVALID_VOLUME no fallback");
   ASSERT_FALSE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_INVALID_EXPIRATION), "INVALID_EXPIRATION no fallback");
   ASSERT_FALSE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_REJECT), "REJECT no fallback");
   ASSERT_FALSE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_POSITION_CLOSED), "POSITION_CLOSED no fallback");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestM6_MarketFallback_Allowed()
{
   g_current_test = "M6_MarketFallback_Allowed";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;

   // Only PRICE_OFF should allow market fallback (transient price movement)
   ASSERT_TRUE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_PRICE_OFF), "PRICE_OFF allows fallback");

   // REQUOTE and PRICE_CHANGED should NOT allow fallback (not in allow list)
   ASSERT_FALSE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_REQUOTE), "REQUOTE no fallback");
   ASSERT_FALSE(g_order_engine.TestShouldFallbackToMarket(TRADE_RETCODE_PRICE_CHANGED), "PRICE_CHANGED no fallback");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

//+------------------------------------------------------------------+
//| M6-Task02: Transient Retry Tests                                 |
//+------------------------------------------------------------------+

bool TestM6_TransientRetry_TooManyRequests()
{
   g_current_test = "M6_TransientRetry_TooManyRequests";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;
   Errors_ResetState();

   OrderError err(TRADE_RETCODE_TOO_MANY_REQUESTS);
   err.context = "RetryTest";
   err.attempt = 0;
   OrderErrorDecision decision = g_order_engine.ResilienceHandleError(err);

   // TOO_MANY_REQUESTS should be transient and allow retry
   ASSERT_EQUALS(ERROR_DECISION_RETRY, decision.type, "TOO_MANY_REQUESTS allows retry");
   ASSERT_TRUE(decision.retry_delay_ms > 0, "Retry delay set");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestM6_TransientRetry_Timeout()
{
   g_current_test = "M6_TransientRetry_Timeout";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;
   Errors_ResetState();

   OrderError err(TRADE_RETCODE_TIMEOUT);
   err.context = "RetryTest";
   err.attempt = 0;
   OrderErrorDecision decision = g_order_engine.ResilienceHandleError(err);

   ASSERT_EQUALS(ERROR_DECISION_RETRY, decision.type, "TIMEOUT allows retry");
   ASSERT_TRUE(decision.retry_delay_ms > 0, "Retry delay set");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

//+------------------------------------------------------------------+
//| M6-Task02: Invalid Parameter Fail-Fast Tests                     |
//+------------------------------------------------------------------+

bool TestM6_InvalidParams_FailFast()
{
   g_current_test = "M6_InvalidParams_FailFast";
   PrintFormat("[TEST START] %s", g_current_test);
   int failed_before = g_test_failed;

   // Test each invalid parameter retcode triggers fail-fast
   Errors_ResetState();
   OrderError err_price(TRADE_RETCODE_INVALID_PRICE);
   err_price.context = "InvalidTest";
   OrderErrorDecision d1 = g_order_engine.ResilienceHandleError(err_price);
   ASSERT_EQUALS(ERROR_DECISION_FAIL_FAST, d1.type, "INVALID_PRICE fail-fast");

   Errors_ResetState();
   OrderError err_stops(TRADE_RETCODE_INVALID_STOPS);
   err_stops.context = "InvalidTest";
   OrderErrorDecision d2 = g_order_engine.ResilienceHandleError(err_stops);
   ASSERT_EQUALS(ERROR_DECISION_FAIL_FAST, d2.type, "INVALID_STOPS fail-fast");

   Errors_ResetState();
   OrderError err_volume(TRADE_RETCODE_INVALID_VOLUME);
   err_volume.context = "InvalidTest";
   OrderErrorDecision d3 = g_order_engine.ResilienceHandleError(err_volume);
   ASSERT_EQUALS(ERROR_DECISION_FAIL_FAST, d3.type, "INVALID_VOLUME fail-fast");

   Errors_ResetState();
   OrderError err_expiry(TRADE_RETCODE_INVALID_EXPIRATION);
   err_expiry.context = "InvalidTest";
   OrderErrorDecision d4 = g_order_engine.ResilienceHandleError(err_expiry);
   ASSERT_EQUALS(ERROR_DECISION_FAIL_FAST, d4.type, "INVALID_EXPIRATION fail-fast");

   PrintFormat("[TEST END] %s", g_current_test);
   return (failed_before == g_test_failed);
}

bool TestOrderEngineErrors_RunAll()
{
   bool ok = true;
   // Original Task 17 tests
   ok = ok && TestErrorHandling_ClassifiesFailFast();
   ok = ok && TestErrorHandling_TriggersCircuitBreaker();
   ok = ok && TestErrorHandling_RetriesRecoverable();
   ok = ok && TestErrorHandling_LogsAlerts();
   ok = ok && TestErrorHandling_ResetsAfterRecovery();
   ok = ok && TestErrorHandling_ProtectiveBypass();
   ok = ok && TestErrorHandling_SelfHealScheduling();
   // M6-Task02: Classification tests
   ok = ok && TestM6_ClassifyRetcode_FailFastCases();
   ok = ok && TestM6_ClassifyRetcode_TransientCases();
   ok = ok && TestM6_ClassifyRetcode_RecoverableCases();
   // M6-Task02: Gating reason tests
   ok = ok && TestM6_GatingReason_CanonicalValues();
   ok = ok && TestM6_GatingReason_InDecision();
   // M6-Task02: Market fallback tests
   ok = ok && TestM6_MarketFallback_Blocked();
   ok = ok && TestM6_MarketFallback_Allowed();
   // M6-Task02: Transient retry tests
   ok = ok && TestM6_TransientRetry_TooManyRequests();
   ok = ok && TestM6_TransientRetry_Timeout();
   // M6-Task02: Invalid parameter tests
   ok = ok && TestM6_InvalidParams_FailFast();
   return ok;
}

#endif // TEST_ORDER_ENGINE_ERRORS_MQH
