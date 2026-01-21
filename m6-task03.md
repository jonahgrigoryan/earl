# M6 Task 03 -- Restart and Idempotency Hardening

Branch name: `feat/m6-task03-restart-idempotency` (cut from `feat/m6-hardening`)

Source of truth: `finalspec.md`, `prd.md`

## Objective
Ensure restart recovery is idempotent: persisted intents and queued actions reconcile safely, no duplicate orders are created, and recovery logs are explicit and consistent.

## Scope
- `MQL5/Include/RPEA/persistence.mqh`
- `MQL5/Include/RPEA/queue.mqh`
- `MQL5/Include/RPEA/order_engine.mqh`

## Implementation Steps
1. **Map recovery flow**
   - Identify where recovery currently happens (init sequence, persistence load, queue rebuild).
   - Document ordering dependencies across persistence, queue, and order engine.

2. **Add idempotency keys**
   - Use existing `intent_id` / `action_id` to prevent re-applying the same action.
   - Persist execution markers in existing state files (`FILE_INTENTS`, `FILE_QUEUE_ACTIONS`) rather than creating new formats.

3. **Reconcile before actions**
   - Ensure recovery/reconcile executes before any new order actions in `OnInit`.
   - Make reconcile safe to call multiple times without side effects.

4. **Guard duplicates**
   - If a persisted intent already exists on the broker, do not resend.
   - If a queued action was already applied, skip with a recovery log entry.

5. **Logging**
   - Add explicit recovery logs (prefix `[Recovery]` or similar consistent tag).
   - Log both the detection and the decision (replay vs skip).

## Tests
1. Extend `Tests/RPEA/test_order_engine_recovery.mqh`:
   - Simulate restart with existing open orders and verify no duplicates.
2. Extend `Tests/RPEA/test_persistence_recovery.mqh`:
   - Run recovery twice and assert second pass is a no-op.
3. Wire any new suites into `Tests/RPEA/run_automated_tests_ea.mq5` if needed.

## Deliverables
- Idempotent recovery logic across persistence, queue, and order engine.
- Recovery logs that explain replay or skip decisions.
- Tests verifying duplicate prevention on restart.

## Acceptance Checklist
- Restart can run multiple times without duplicate orders.
- Queued actions are reconciled once with explicit logs.
- Recovery order is safe and deterministic.
- Tests cover restart and re-run scenarios.

## Hold Point
After tests pass locally, stop and report results before merging back into `feat/m6-hardening`.
