# M6 Task 02 -- Market Closure and Broker Reject Paths

Branch name: `feat/m6-task02-market-closure` (cut from `feat/m6-hardening`)

Source of truth: `finalspec.md`, `prd.md`

## Objective
Harden order execution and error handling for market-closed, trade-disabled, invalid-price, requote, off-quotes, and reject retcodes. Behavior must be deterministic with no unsafe retries and clear gating logs.

## Scope
- `MQL5/Include/RPEA/order_engine.mqh`
- `MQL5/Include/RPEA/queue.mqh` (if queueing interacts with reject handling)
- `MQL5/Include/RPEA/logging.mqh` (audit fields and gating reasons)

## Implementation Steps
1. **Enumerate retcodes**
   - Identify retcodes already handled in `order_engine.mqh`.
   - Add missing explicit cases for market closed, trade disabled, invalid price, invalid stops, invalid volume,
     invalid expiration, off quotes, requote, too many requests, and `TRADE_RETCODE_REJECT` (generic rejects).

2. **Define deterministic policy**
   - No retry for market closed or trade disabled.
   - Fail fast for `invalid_*` parameters and `reject` retcodes (no retry, no fallback).
   - Only retry transient cases (requote/off quotes/connection/timeout/too-many-requests) if safe and bounded.
   - Never fallback to market order if market is closed or trade disabled.

3. **Implement gating reasons**
   - Tag `gating_reason` with canonical values: `market_closed`, `trade_disabled`, `invalid_price`,
     `invalid_stops`, `invalid_volume`, `invalid_expiration`, `off_quotes`, `requote`, `request_rejected`.
   - Ensure `LogDecision` and `LogAuditRow` capture these reasons consistently.

4. **Update order retry logic**
   - Update `OE_ClassifyRetcode` and `RetryManager::GetPolicyForError` to use the new retcode mapping.
   - Ensure backoff strategy is unchanged unless required.
   - Cap retries; do not retry on safety-reject cases.

5. **Queue behavior**
   - If queueing or deferred actions exist for modifications, ensure failed modify attempts due to market-closed are logged and not retried unsafely.
   - Drop or defer queued actions only when safe and consistent with news window rules.

## Tests
1. Extend `Tests/RPEA/test_order_engine_errors.mqh`:
   - Simulate each retcode and assert expected behavior (no retry, retry, or fail-fast).
   - Validate `gating_reason` logging.
2. Add scenarios in `Tests/RPEA/test_queue_manager.mqh` if queue behavior is affected.
3. Wire any new suites into `Tests/RPEA/run_automated_tests_ea.mq5` if needed.

## Deliverables
- Updated retcode handling in `order_engine.mqh`.
- Deterministic retry policy for error cases.
- Tests covering the new retcode mappings and gating reasons.

## Acceptance Checklist
- Market-closed and trade-disabled paths do not retry or fallback.
- Transient retcodes have bounded retries with clear logs.
- `gating_reason` is consistently populated in audit logs.
- Tests cover all newly handled retcodes.

## Hold Point
After tests pass locally, stop and report results before merging back into `feat/m6-hardening`.
