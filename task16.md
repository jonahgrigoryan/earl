# Task 16 State Recovery & Reconciliation Outline

## Goal & References

- **Goal**: Implement Task 16 from `.kiro/specs/rpea-m3/tasks.md` / `zen_prompts_m3.md` — restore intents + queued actions on startup, reconcile with broker positions/orders, deduplicate action state, and resume safely after interruptions.
- **Primary files**: `Include/RPEA/persistence.mqh`, `Include/RPEA/order_engine.mqh`, `Files/RPEA/state/intents.json`, `Files/RPEA/state/sl_enforcement.json` (Task 15 dependency), `Tests/RPEA/test_order_engine_recovery.mqh`.
- **Supporting refs**: Task 2 intent schema, Task 14 telemetry fields, Task 15 SL enforcement persistence, `.kiro/specs/rpea-m3/design.md` §§8.4–8.5 (state recovery), requirements §8 Resilience.

## Prerequisites Checklist

1. Tasks 1‑15 merged, tests passing via `powershell -ExecutionPolicy Bypass -File run_tests.ps1`.
2. Intent journal schema (with telemetry & gate snapshots) finalized per Task 14/15.
3. Persistence write helpers (`Persistence_FlushIntentJournal`) operational and directories pre-created.
4. Order engine exposes `ReconcileOnStartup()` stub + execution lock helpers (`SetExecutionLock`, `IsExecutionLocked`).
5. Audit logger operational for OnInit logging; JSON helper available.

## Implementation Steps

### Phase A — Persistence Loader Enhancements (`Include/RPEA/persistence.mqh`)

1. **Define recovery data structures**

- `struct PersistenceRecoverySummary` capturing counts (total/intents kept/dropped, actions kept/dropped, corrupt_entries, renamed_corrupt_file flag).
- `struct PersistenceRecoveredState { OrderIntent intents[]; int intents_count; PersistedQueuedAction queued_actions[]; int queued_count; PersistenceRecoverySummary summary; };` (stick with the repo’s existing dynamic arrays; use `ArrayResize` as needed.)

2. **Implement `Persistence_LoadIntentJournal()`**

- Open `Files/RPEA/state/intents.json`; if missing, return empty arrays.
- Parse JSON; on failure rename file to `intents.json.corrupt.<timestamp>` and return empty state with `summary.renamed_corrupt_file=true`.
- Validate entries (required keys: `intent_id`, `action_id`, status, telemetry). Drop malformed/expired entries, increment `summary.corrupt_entries` and `intents_dropped`/`actions_dropped`.
- Rehydrate `OrderIntent` + `PersistedQueuedAction` objects including telemetry fields from Task 14 and TTL metadata from Task 12.

3. **Add dedup helpers**

- Implement `bool Persistence_AttachRecoveredIntent(OrderIntent intents[], int &count, const OrderIntent &intent, PersistenceRecoverySummary &summary)` returning false when a duplicate `intent_id` is found (increment `intents_dropped`).
- Implement `bool Persistence_AttachRecoveredAction(PersistedQueuedAction actions[], int &count, const PersistedQueuedAction &action, PersistenceRecoverySummary &summary)` for queued actions.

4. **Expose API and cleanup**

- `bool Persistence_LoadRecoveredState(PersistenceRecoveredState &out_state);`
- `void Persistence_FreeRecoveredState(PersistenceRecoveredState &state);` (release arrays / reset counts).

5. **Atomic flush upgrade**

- Update `Persistence_FlushIntentJournal()` to write to a temp file and rename atomically; include a `schema_version` field (e.g., 3). Warn when loader sees a newer schema.

6. **Optional housekeeping**

- Provide `Persistence_PruneOldRecoveryBackups(int max_files)` to delete stale `.corrupt.*` backups (optional but recommended).

### Phase B — Order Engine Reconciliation (`Include/RPEA/order_engine.mqh`)

7. **Extend class state**

- Maintain simple arrays mirroring journal data: `OrderIntent m_recovered_intents[]; int m_recovered_intent_count; PersistedQueuedAction m_recovered_actions[]; int m_recovered_action_count; bool m_recovery_completed; datetime m_recovery_timestamp;` (avoid introducing new container classes).

8. **Implement `OrderEngine::ReconcileOnStartup()` sequence**
9. Guard: if `m_recovery_completed` already true, log `[OrderEngine] Recovery already completed at ...` and return.
10. Call `Persistence_LoadRecoveredState()`; copy arrays into `m_recovered_*` members.
11. Acquire execution lock via existing signature (`SetExecutionLock(true);`) and ensure release with `SetExecutionLock(false);` in `cleanup`.
12. Enumerate broker positions (`PositionsTotal()`) and pendings (`OrdersTotal()`), building temporary arrays of `BrokerPositionSnapshot` / `BrokerOrderSnapshot` structs.
13. For each recovered intent, verify associated tickets still exist; update `remaining_volume` accordingly or mark as closed if absent.
14. For each broker ticket lacking an intent, synthesize an `OrderIntent` with origin `"broker_recovery"`, append to `m_recovered_intents`, and log `[OrderEngine] Reattached orphan ticket ...`.
15. Validate recovered queued actions: drop ones whose parent intent missing, TTL expired, or positions closed; log drop reason.
16. Reload SL enforcement queue from `sl_enforcement.json` (Task 15) and prune entries whose tickets are gone.
17. Persist the reconciled state (`m_recovered_*` arrays) via `Persistence_FlushIntentJournal()`.
18. Set `m_recovery_completed=true`, `m_recovery_timestamp=TimeCurrent()`.
19. **Helper APIs to add**

- `bool OrderEngine_FindIntentById(const string id, OrderIntent &out_intent);`
- `bool OrderEngine_FindIntentByTicket(const ulong ticket, OrderIntent &out_intent);`
- `int OrderEngine_FindIntentIndexById(const string id);` (array search helpers, not map-based).

10. **Logging & metrics**

 - Emit summary log: `[OrderEngine] Recovery summary intents_loaded=.., intents_dropped=.., actions_loaded=.., orphans_attached=.., sl_queue_resumed=..`.
 - If `SetExecutionLock(true)` fails or recovery aborts, log error and propagate failure so `OnInit` can abort.

### Phase C — Integration Hooks

11. **RPEA.mq5 OnInit**

 - After `g_order_engine.Init()` invoke `if(!g_order_engine.ReconcileOnStartup()) return INIT_FAILED;` before signals start.

12. **OnDeinit**

 - Ensure any final flush or backup pruning occurs prior to shutdown (no new APIs assumed).

## Testing Plan (`Tests/RPEA/test_order_engine_recovery.mqh`)

1. **Recovery_RestoresIntents** — fixture with 2 intents/1 action; run reconciliation; assert `m_recovered_intent_count==2`, `m_recovery_completed=true`.
2. **Recovery_DedupsQueuedActions** — duplicate `action_id` in JSON; loader keeps one, summary reflects drop.
3. **Recovery_ReconcilesBrokerPositions** — mock broker API returning orphan ticket; expect synthetic intent appended and persisted.
4. **Recovery_HandlesCorruptIntent** — malformed JSON triggers rename to `.corrupt.*` and empty recovery; summary flags `renamed_corrupt_file`.
5. **Recovery_LogsSummary** — verify log buffer contains summary message with counts.
6. **Recovery_SLEnforcementResume** (optional) — ensure persisted SL enforcement entries reload and remain pending.
7. Register suite in `Tests/RPEA/run_automated_tests_ea.mq5`; add fixtures under `Tests/RPEA/fixtures/state/`.

## Acceptance Checklist (per tasks.md / zen prompts)

- [ ] Startup loads/deduplicates intents and queued actions using existing array patterns.
- [ ] Broker reconciliation attaches orphan tickets and purges stale journal entries.
- [ ] Queued actions validated before resuming (TTL, parent intent, position state).
- [ ] Recovery summary logged with counts + corruption handling.
- [ ] SL enforcement persistence resumes seamlessly.
- [ ] Persistence flush is atomic/versioned.
- [ ] Unit tests above pass; Strategy Tester restart scenario verified.

## Todos

- recovery-load: Implement persistence loader + dedup helpers.
- recovery-engine: Extend `OrderEngine::ReconcileOnStartup()` with broker reconciliation.
- recovery-tests: Add `test_order_engine_recovery.mqh` cases covering load/dedup/reconciliation.
- recovery-logging: Add log summaries + corruption handling hooks.