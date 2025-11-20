# Task 17 Error Handling & Resilience Blueprint

## References & Inputs

- `.kiro/specs/rpea-m3/tasks.md` Task 17 and linked requirements 8.1‒8.5 (retry classes, resilience, recovery expectations).
- `zen_prompts_m3.md` Phase 4 runbook (Task 17 coding/test prompts + HOLD POINT 4 checklist).
- Existing modules: `MQL5/Include/RPEA/order_engine.mqh`, `config.mqh`, `persistence.mqh`, `logging.mqh`, `news.mqh`, RetryManager (Task 5), market fallback logic (Task 6).
- Testing harness: `Tests/RPEA/test_order_engine_errors.mqh` (new), `Tests/RPEA/run_automated_tests_ea.mq5`, fake broker shims from prior tasks.

## End-to-End Implementation Steps

1. **Enumerate Failure Surfaces**  
Review every broker interaction (placement, modification, cancel, queued trailing/breakeven, reconciliation, self-heal probes) inside `order_engine.mqh`. Capture current error handling, retry usage, and available context (intent/action IDs) so each path can be migrated to the centralized handler without regressions.

2. **Add Resilience Config Knobs (`config.mqh`)**  
Introduce spec-aligned defaults: `MaxConsecutiveFailures=3`, `FailureWindowSec=900`, `CircuitBreakerCooldownSec=120`, `SelfHealRetryWindowSec=300`, `SelfHealMaxAttempts=2`, `ErrorAlertThrottleSec=60`, `BreakerProtectiveExitBypass=true`. Implement strongly typed getters with inline validation (reject ≤0 and log + clamp). Document keys inline for later Task 20 validation.

3. **Extend OrderEngine State & Persistence**  
Add private members `m_consecutive_failures`, `m_failure_window_count`, `m_failure_window_start`, `m_last_failure_time`, `m_circuit_breaker_until`, `m_breaker_reason`, `m_last_alert_time`, `m_self_heal_active`, `m_self_heal_attempts`, `m_self_heal_reason`, `m_next_self_heal_time`. Update Task 16 persistence hooks to serialize/deserialize these fields so breaker/self-heal survive restarts; ensure `Init()` loads them before enabling trading, `OnDeinit()` flushes the snapshot.

4. **Standardize Error Classification**  
Define `enum OrderErrorClass { ERRORCLASS_FAILFAST, ERRORCLASS_TRANSIENT, ERRORCLASS_RECOVERABLE, ERRORCLASS_UNKNOWN };`. Implement `OE_ClassifyRetcode(int retcode)` mapping MT5 constants (fail-fast: `TRADE_DISABLED`, `NO_MONEY`, `MARKET_CLOSED`, `NOT_ENOUGH_RIGHTS`; transient: `CONNECTION`, `SERVER_BUSY`, `TIMEOUT`; recoverable: `REQUOTE`, `PRICE_OFF`, `INVALID_PRICE`, `OFF_QUOTES`). Provide helpers `OE_ShouldFailFast`, `OE_ShouldRetry` to keep RetryManager + handler logic in sync.

5. **Define Shared Error Payload**  
Create `struct OrderError { string context; string intent_id; string action_id; ulong ticket; int retcode; OrderErrorClass cls; int attempt; double requested_price; double executed_price; double requested_volume; bool is_protective_exit; bool is_retry_candidate; }` with ctor that classifies retcode upfront. Ensure every broker-facing function populates this struct (even success paths if logging needs context) before invoking the handler.

6. **Implement Central Error Handler (`OrderEngine_HandleError`)**  

- Decision type: introduce `enum OrderErrorDecisionType { ERROR_DECISION_FAIL_FAST, ERROR_DECISION_RETRY, ERROR_DECISION_DROP };` and `struct OrderErrorDecision { OrderErrorDecisionType type; int retry_delay_ms; string gating_reason; };` (default `retry_delay_ms=0`, `gating_reason=""`).  
- Signature: `OrderErrorDecision OrderEngine_HandleError(const OrderError &err);`.  
- Flow: update counters + rolling window (`m_failure_window_start` resets when elapsed > `FailureWindowSec`). Fail-fast classes log critical, trip breaker via `OrderEngine_TripCircuitBreaker("fail_fast:"+err.context)` (configurable immediate trip), and return `{FAIL_FAST,0,"fail_fast"}`. If breaker already active and action not protective, log gating + return `{FAIL_FAST,0,"circuit_breaker_active"}`. Otherwise consult RetryManager; set `decision.type=ERROR_DECISION_RETRY`, `decision.retry_delay_ms = retry.delay_ms`. When counts exceed thresholds, trip breaker and enqueue self-heal. Emit structured log `[OrderEngine][ErrorHandling] context=..., retcode=..., class=..., decision=..., breaker_state=..., retry_delay=...` and throttle high-severity alerts using `ErrorAlertThrottleSec` (store `m_last_alert_time`). Return `RETRY` only if RetryManager allows and breaker inactive; otherwise `{ERROR_DECISION_DROP,0,"retry_exhausted"}`.

7. **Circuit Breaker Mechanics, Counter Resets, Protective Exit Bypass, Alert Throttling**  

- Functions: `OrderEngine_TripCircuitBreaker(const string reason)` (set `m_circuit_breaker_until = TimeCurrent() + Config_GetCircuitBreakerCooldownSec(); m_breaker_reason = reason; m_consecutive_failures = 0; persist + log), `bool OrderEngine_IsCircuitBreakerActive() const`, `void OrderEngine_ResetCircuitBreaker(const string source)` (clear breaker, counters, self-heal flags, persist, log resume).  
- Protective exit bypass: helper `bool OrderEngine_ShouldBypassBreaker(const OrderError &err)` honoring `BreakerProtectiveExitBypass`. All entry points (ExecuteOrderWithRetry, ModifyOrder, CancelOrder, queue processors, trailing/breakeven) wrap broker work with breaker check; protective exits skip breaker but still record failures.  
- Counter hygiene: `OrderEngine_ResetErrorCounters()` called after successful broker ops to zero `m_consecutive_failures` and shrink sliding window counts.  
- Alert throttling: `OrderEngine_MaybeSendBreakerAlert(const string message)` compares `TimeCurrent()` vs `m_last_alert_time`; only escalate once per throttle window, else log at DEBUG level to prevent log spam.

8. **Self-Heal Scheduling & Execution**  

- Trigger `OrderEngine_RequestSelfHeal(reason)` when breaker trips, failure window exceeds threshold, or RetryManager exhausts retries on transient codes. Set `m_self_heal_active=true`, `m_self_heal_reason=reason`, `m_self_heal_attempts=0`, `m_next_self_heal_time=TimeCurrent()`.  
- In `OnTimerTick()`, when `m_self_heal_active` and current time ≥ `m_next_self_heal_time`, call `OrderEngine_PerformSelfHeal()`: reload symbol properties, refresh spreads/ATR caches, rerun lightweight reconciliation (`OrderEngine_ReconcilePositions()`), drop stale queued actions, revalidate intent journal, and perform an `OrderCheck` probe (encapsulate via helper `OrderEngine_ProbeTradeChannel()` to send a tiny `MqlTradeRequest`). Success resets breaker (`OrderEngine_ResetCircuitBreaker("self_heal_success"`), counters, and disables self-heal; failure increments attempts, schedules next attempt after `Config_GetSelfHealRetryWindowSec()`, and if attempts exceed `SelfHealMaxAttempts`, logs critical alert instructing manual action while keeping breaker engaged. Persist state after every attempt so restarts continue schedule.

9. **Integrate Handler Across Execution Paths**  

- `OrderEngine_ExecuteOrderWithRetry`: pre-check breaker and short-circuit when active (unless protective). After each broker failure, build `OrderError` (context `"ExecuteOrderWithRetry"`), call the handler, and if `decision.type==ERROR_DECISION_RETRY`, use `decision.retry_delay_ms` (already computed via RetryManager) to schedule the next attempt; success clears counters.  
- Queue actions (`ProcessQueuedActions`, trailing/breakeven managers): mark protective adjustments (`is_protective_exit=true`) so they bypass breaker; non-protective updates honor breaker gating. Each broker rejection funnels through handler with action-specific context + action_id for dedup logging.  
- Reconciliation (`OrderEngine_ReconcileOnStartup`, Task 16 flows): wrap broker queries/modifications with handler context `"Reconcile"`; repeated failures now count toward breaker/self-heal, ensuring startup issues don’t silently loop.

10. **Logging & Audit Integration**  
Ensure every handler invocation writes structured logs (intent/action IDs, context, retcode, classification, decision, retry_count, breaker state, self-heal state). Update audit logger (Task 14) to emit rows with `decision="error"`, `gating_reason` describing breaker/fail-fast cause, and the usual budget gate metrics; errors triggered by protective exits should note `news_window_state` + `is_protective_exit`. Maintain existing formatting (3-space indent, braces on own lines).

11. **Config & Documentation Updates**  

- `config.mqh`: inline comments for each new key, mention relationship to breaker/self-heal; ensure defaults align with design.  
- `task17.md` (or project journal): describe operational workflow (what trips breaker, how self-heal runs, log prefixes to watch, manual override steps).  
- `README`/config reference placeholder: list new keys, indicate protective exit bypass behavior, persistence of breaker state, and recommended values for funded vs. demo accounts until Task 20 adds full validation.

12. **Testing (`Tests/RPEA/test_order_engine_errors.mqh`) & Runner Wiring**  

- Implement test cases per `zen_prompts_m3.md` plus extras:  

1. `ErrorHandling_ClassifiesFailFast` (TRADE_DISABLED triggers immediate breaker, no retry).  
2. `ErrorHandling_TriggersCircuitBreaker` (three recoverable failures trip breaker, gating subsequent placements).  
3. `ErrorHandling_RetriesRecoverable` (CONNECTION errors schedule ≤3 retries with 300→600→1200ms delays).  
4. `ErrorHandling_LogsAlerts` (capture log buffer to assert structured fields + throttle).  
5. `ErrorHandling_ResetsAfterRecovery` (successful order clears counters).  
6. `Breaker_AllowsProtectiveExit` (protective SL modification executes while breaker active).  
7. `SelfHeal_SchedulesAndResets` (forced breaker triggers self-heal; mock OrderCheck success resets breaker).  

- Use fake broker hooks/stubs to simulate retcodes.  
- Register suite in `Tests/RPEA/run_automated_tests_ea.mq5` (add include + `TestOrderEngineErrors_RunAll(results);`). Ensure `run_tests.ps1` picks up the suite.

13. **Validation, Acceptance Criteria & Operator Notes**  

- Acceptance: all broker errors flow through classifier/handler; breaker trips/resets per config; protective exits bypass breaker; error counters reset after success; self-heal attempts logged/persisted; alerts throttled; state survives restart; new unit suite passes alongside existing tests.  
- Testing instructions: run `powershell -ExecutionPolicy Bypass -File run_tests.ps1` and review `MQL5/Files/RPEA/test_results/test_results.json`; capture Strategy Tester runs demonstrating fail-fast trip, protective exit bypass, self-heal success (with MTOrderCheck probe). Provide log excerpts for HOLD POINT 4 review.  
- Operator notes (update `task17.md`): steps to clear breaker manually, interpretation of `[OrderEngine][Breaker]`, `[OrderEngine][SelfHeal]`, `[OrderEngine][ErrorHandling]` logs, and guidance on adjusting config knobs if broker conditions change.

## Implementation TODOs

- `resilience-config`: Add Task 17 config keys + getters + inline validation in `config.mqh`.
- `engine-state`: Extend `OrderEngine` state/persistence with breaker/self-heal fields.
- `error-handler`: Implement classifier, central handler, breaker, self-heal, and integrate across execution flows in `order_engine.mqh`.
- `error-tests`: Create `Tests/RPEA/test_order_engine_errors.mqh`, register in harness, and ensure `run_tests.ps1` covers new cases.
