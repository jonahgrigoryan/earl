# M4-Task04: Persistence Hardening for Compliance State

## Objective

This task hardens persistence for compliance-critical state so the EA is restart-safe, idempotent, and audit-ready. It ensures that trade-day tracking, Micro-Mode, kill-switch flags, and baseline anchors are restored correctly, without double-counting or losing disable flags. It also tightens recovery of intent journals and queued actions so no stale modifications leak across restarts.

Challenge state remains a key=value file at `FILE_CHALLENGE_STATE` (challenge_state.json), while the intent journal remains JSON at `FILE_INTENTS`.

Per **finalspec.md Section Implementation Roadmap (M4)** and **prd.md Section Equity Guardian & Persistence**, the EA must:
1. Persist and restore compliance state (trade days, disable flags, baselines, micro-mode)
2. Prevent trade-day double counting after restart
3. Recover queued actions and intent journals safely and deterministically
4. Log recovery/validation outcomes for audit

---

## Functional Requirements

### Challenge State Durability
- **FR-01**: Persist all compliance fields (baselines, trade days, disable flags, micro-mode, floor breach flags, hard-stop metadata, peak equity, anchors).
- **FR-02**: Add `state_version` and `last_state_write_time` to support schema evolution; use best-effort defaults if the version is missing or higher than expected. Define `STATE_VERSION_CURRENT = 2`.
- **FR-03**: Writes must be atomic (write temp + move into place), leaving the last known-good state intact on failure.
- **FR-04**: Validate loaded state; clamp or reset invalid values (negative baselines, NaN, invalid dates, negative gDaysTraded).
- **FR-05**: If state file is empty/unparseable, rename it to `.corrupt.TIMESTAMP`, rebuild defaults, and log `STATE_CORRUPT_RENAMED` + `STATE_RECOVERY`.
- **FR-06**: If `disabled_permanent` is true, force `trading_enabled=false` and set `g_ctx.permanently_disabled=true` on load.
- **FR-07**: Preserve `server_midnight_ts`, `baseline_today_e0`, and `baseline_today_b0` to avoid re-anchoring on restart.

### Idempotent Trade-Day Counting
- **FR-08**: Only count the first `DEAL_ENTRY_IN` per server day using `last_counted_server_date` (yyyymmdd int).
- **FR-09**: Add `last_counted_deal_time` to prevent duplicate counts if transactions replay on restart. When processing a new `DEAL_ENTRY_IN`, skip counting if `trans.time <= last_counted_deal_time`. After counting, set `last_counted_deal_time = trans.time`. Always use `trans.time` (deal time) not `TimeCurrent()`.
- **FR-10**: Persist `last_micro_entry_server_date` to enforce one micro entry per day across restarts.

### Intent Journal + Queue Recovery
- **FR-11**: Load challenge state first, then run `g_order_engine.ReconcileOnStartup()` (intents), then `OrderEngine_RestoreStateOnInit()` (queue/trailing).
- **FR-12**: Drop expired or redundant queued actions at load time via `Queue_LoadFromDiskAndReconcile()`; persist the cleaned queue.
- **FR-13**: Log recovery summaries for intents and queued actions (loaded/dropped/corrupt counts). Define "dropped" as items discarded due to expiry, redundancy, or missing intent references. Emit summary from the owning module (OrderEngine for intents, Queue for queued actions).

### Flush Policy
- **FR-14**: Coalesce non-critical writes; immediately flush on critical transitions (baseline reset, trade-day mark, micro-mode activation, kill-switch, hard-stop, giveback protection).
- **FR-15**: Track dirty state and perform a safe flush during `OnDeinit`.

### Audit Logging
- **FR-16**: Log `STATE_LOAD_OK`, `STATE_RECOVERY`, `STATE_WRITE_OK`, `STATE_WRITE_FAIL`, `STATE_CORRUPT_RENAMED` via `LogAuditRow` (component `Persistence`) for consistency.
- **FR-17**: Log `INTENT_RECOVERY_SUMMARY` and `QUEUE_RECOVERY_SUMMARY` with counts.

---

## Files to Modify

| File | Rationale |
|------|-----------|
| `MQL5/Include/RPEA/state.mqh` | Extend `ChallengeState` with persistence metadata and idempotency fields |
| `MQL5/Include/RPEA/persistence.mqh` | Atomic write, state validation, schema versioning, recovery logging, dirty tracking |
| `MQL5/Include/RPEA/order_engine.mqh` | Emit intent recovery summary from `ReconcileOnStartup()` |
| `MQL5/Include/RPEA/queue.mqh` | Emit queue recovery summary after reconcile and persist cleaned queue |
| `MQL5/Experts/FundingPips/RPEA.mq5` | Wire load/validate/flush order and recovery logs |
| `Tests/RPEA/test_persistence_state.mqh` | New test suite for challenge_state recovery |
| `Tests/RPEA/test_persistence_recovery.mqh` | New test suite for intent/queue recovery summaries |
| `Tests/RPEA/run_automated_tests_ea.mq5` | Include new persistence test suites |

---

## Data/State Changes

### ChallengeState Additions (state.mqh)

```cpp
struct ChallengeState
{
   // Existing fields...
   double   initial_baseline;
   double   baseline_today;
   int      gDaysTraded;
   int      last_counted_server_date;
   bool     trading_enabled;
   bool     disabled_permanent;
   bool     micro_mode;
   datetime micro_mode_activated_at;
   double   day_peak_equity;
   datetime server_midnight_ts;
   double   baseline_today_e0;
   double   baseline_today_b0;

   // M4 persistence hardening
   int      state_version;
   datetime last_state_write_time;
   datetime last_counted_deal_time;      // idempotent trade-day count
   int      last_micro_entry_server_date;
   bool     daily_floor_breached;
   datetime daily_floor_breach_time;
   string   hard_stop_reason;
   datetime hard_stop_time;
   double   hard_stop_equity;
   double   overall_peak_equity;
};
```

### New Persistence Metadata

```
state_version=2
last_state_write_time=1718123456
last_counted_deal_time=1718123400
micro_mode_activated_at=1718123000
last_micro_entry_server_date=20250615
daily_floor_breached=1
daily_floor_breach_time=1718123500
hard_stop_reason=overall_floor_breach
hard_stop_time=1718123600
hard_stop_equity=9400.00
overall_peak_equity=10850.00
```

### New Log Event Types

```
STATE_LOAD_OK
STATE_RECOVERY
STATE_WRITE_OK
STATE_WRITE_FAIL
STATE_CORRUPT_RENAMED
INTENT_RECOVERY_SUMMARY
QUEUE_RECOVERY_SUMMARY
```

---

## Detailed Implementation Steps

### Step 1: Extend State + Dirty Flagging (state.mqh / persistence.mqh)

```cpp
// Add persistence metadata + idempotency fields to ChallengeState
// Track dirty state in persistence.mqh (module-level bool, no statics)
bool g_persistence_dirty = false;

void Persistence_MarkDirty()
{
   g_persistence_dirty = true;
}

void State_MarkDirty()
{
   g_state.last_state_write_time = TimeCurrent();
   Persistence_MarkDirty();
}
```

Call `State_MarkDirty()` in state mutators: trade-day marking, micro-mode activation, daily reset, kill-switch, hard-stop, giveback.

Note: To avoid include cycles, add a forward declaration in `state.mqh`:

```cpp
void Persistence_MarkDirty();
```

### Step 2: Validate + Migrate Challenge State (persistence.mqh)

```cpp
bool Persistence_ValidateChallengeState(ChallengeState &s, string &out_reason)
{
   if(!MathIsValidNumber(s.initial_baseline) || s.initial_baseline <= 0.0)
   {
      out_reason = "invalid_initial_baseline";
      s.initial_baseline = AccountInfoDouble(ACCOUNT_EQUITY);
   }
   if(!MathIsValidNumber(s.baseline_today) || s.baseline_today <= 0.0)
      s.baseline_today = s.initial_baseline;
   if(s.gDaysTraded < 0)
      s.gDaysTraded = 0;
   if(s.last_counted_server_date < 0)
      s.last_counted_server_date = 0;
   if(s.last_counted_deal_time > TimeCurrent())
      s.last_counted_deal_time = (datetime)0;
   if(s.last_micro_entry_server_date < 0)
      s.last_micro_entry_server_date = 0;
   if(s.disabled_permanent)
      s.trading_enabled = false;
   return true;
}
```

Add `state_version` handling with defaults when missing or higher than expected; log `STATE_RECOVERY` with detected version when defaults are applied. Unknown keys are ignored on read; only known keys are written back out.

### Step 3: Atomic Challenge State Writes (persistence.mqh)

```cpp
bool Persistence_WriteChallengeStateAtomic(const string &payload)
{
   const string tmp = FILE_CHALLENGE_STATE + ".tmp";
   const string bak = FILE_CHALLENGE_STATE + ".bak";
   if(!Persistence_WriteWholeFile(tmp, payload))
      return false;
   if(FileIsExist(FILE_CHALLENGE_STATE))
   {
      FileDelete(bak);
      FileMove(FILE_CHALLENGE_STATE, 0, bak, 0); // best-effort backup
   }
   if(!FileMove(tmp, 0, FILE_CHALLENGE_STATE, 0))
   {
      if(FileIsExist(bak))
         FileMove(bak, 0, FILE_CHALLENGE_STATE, 0);
      return false;
   }
   return true;
}
```

Update `Persistence_Flush()` to build a key=value payload string, call `Persistence_WriteChallengeStateAtomic()`, and log `STATE_WRITE_OK`/`STATE_WRITE_FAIL`.

### Step 4: Load + Recover Challenge State (persistence.mqh)

```cpp
void Persistence_LoadChallengeState()
{
   // Parse key=value file (challenge_state.json)
   // If no keys parsed: rename to .corrupt.YYYYMMDD_HHMMSS and rebuild defaults
   // If state_version missing or higher than expected: set defaults and log STATE_RECOVERY
   // Always enforce disabled_permanent -> trading_enabled=false
}
```

Also enforce `state_version` upgrades by filling new keys with defaults.

### Step 5: Wire Recovery Order (RPEA.mq5)

- Load challenge state first (`Persistence_LoadChallengeState()`), log `STATE_LOAD_OK` with detected `state_version`
- Validate + repair; apply `disabled_permanent` to `g_ctx.permanently_disabled`
- Mirror into `g_ctx` (baselines, anchors)
- Initialize order engine (`g_order_engine.Init()`)
- Run `g_order_engine.ReconcileOnStartup()` (intent journal recovery)
- Restore queue/trailing state (`OrderEngine_RestoreStateOnInit()`)
- Log `INTENT_RECOVERY_SUMMARY` and `QUEUE_RECOVERY_SUMMARY`

### Step 6: Queue + Intent Recovery Summaries

In `OrderEngine::ReconcileOnStartup()` and `Queue_LoadFromDiskAndReconcile()`, emit structured recovery logs using existing counters. `Queue_LoadFromDiskAndReconcile()` should compute `loaded_count` and `dropped_count` and log `QUEUE_RECOVERY_SUMMARY` from inside the function.

```cpp
LogAuditRow("INTENT_RECOVERY_SUMMARY", "OrderEngine", LOG_INFO,
            "reconcile",
            StringFormat("{\"intents_total\":%d,\"intents_loaded\":%d,\"intents_dropped\":%d,\"actions_total\":%d,\"actions_loaded\":%d,\"actions_dropped\":%d,\"corrupt\":%d}",
                         recovered.summary.intents_total,
                         recovered.summary.intents_loaded,
                         recovered.summary.intents_dropped,
                         recovered.summary.actions_total,
                         recovered.summary.actions_loaded,
                         recovered.summary.actions_dropped,
                         recovered.summary.corrupt_entries));

LogAuditRow("QUEUE_RECOVERY_SUMMARY", "Queue", LOG_INFO,
            "reconcile",
            StringFormat("{\"queue_loaded\":%d,\"queue_dropped\":%d}", loaded_count, dropped_count));
```

### Step 7: Test Overrides for Persistence

Add test helpers in `persistence.mqh` guarded by `RPEA_TEST_RUNNER`:

```cpp
void Persistence_Test_SetStatePath(const string path);
void Persistence_Test_ResetStatePath();
bool Persistence_Test_WriteStateFile(const string &lines[], const int count);
```

### Step 8: New Tests

Create `Tests/RPEA/test_persistence_state.mqh`:
- Load defaults on missing file
- Load from partial file with missing keys
- Clamp invalid values
- Preserve `disabled_permanent` + `trading_enabled`
- Persist `last_counted_server_date` and `last_counted_deal_time`

Create `Tests/RPEA/test_persistence_recovery.mqh`:
- Corrupt state file triggers rename + recovery
- Recovery logs include intent counts
- Queue reconcile drops expired entries

Wire both suites into `Tests/RPEA/run_automated_tests_ea.mq5` with `TestPersistenceState_RunAll()` and `TestPersistenceRecovery_RunAll()` using `g_test_reporter`.

---

## Logging/Telemetry

| Event Type | Component | Description |
|------------|-----------|-------------|
| `STATE_LOAD_OK` | Persistence | Challenge state loaded successfully |
| `STATE_RECOVERY` | Persistence | State repaired or migrated |
| `STATE_WRITE_OK` | Persistence | Atomic write succeeded |
| `STATE_WRITE_FAIL` | Persistence | Atomic write failed |
| `STATE_CORRUPT_RENAMED` | Persistence | Corrupt state file moved aside |
| `INTENT_RECOVERY_SUMMARY` | OrderEngine | Intents loaded/dropped |
| `QUEUE_RECOVERY_SUMMARY` | Queue | Queue items loaded/dropped |

---

## Edge Cases & Failure Modes

| Scenario | Handling |
|----------|----------|
| **State file missing** | Initialize defaults from current equity/balance |
| **Corrupt state file** | Rename to `.corrupt.TIMESTAMP`, rebuild defaults |
| **Negative/NaN baselines** | Clamp to current equity and log recovery |
| **Future `last_counted_server_date`** | Reset to 0 and log recovery |
| **Restart mid-day** | Preserve baseline anchors and daily disable flags |
| **Restart after hard-stop** | Keep `disabled_permanent=true` and block entries |
| **Queue contains expired actions** | Drop at load time and persist cleaned queue |
| **Intent journal mismatch** | Reconcile with live positions/orders; log summary |

---

## Acceptance Criteria

| ID | Criterion | Validation |
|----|-----------|------------|
| AC-01 | Challenge state survives restart without resets | Manual restart test |
| AC-02 | Trade days are not double-counted after restart | Test: `TestPersistenceState_RunAll` |
| AC-03 | Micro-Mode and disable flags persist | Test: `TestPersistenceState_RunAll` |
| AC-04 | Corrupt file recovered and renamed | Test: `TestPersistenceRecovery_RunAll` |
| AC-05 | Queue recovery drops expired items | Test: `TestPersistenceRecovery_RunAll` |
| AC-06 | Intent recovery summary logged | Audit log inspection |
| AC-07 | Atomic write preserves last known good state | Manual: simulate write failure |

---

## Out of Scope / Follow-ups

- **Full JSON schema migration** for challenge_state (keep key=value format for now)
- **Auto-DST adjustment** (still manual via input)
- **Persisting post-news stabilization state across restart** (optional future hardening)
