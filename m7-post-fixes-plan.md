# M7 Post-Fixes Execution Plan (Full TODO Closure + Performance Hardening)

## Goal
Close all remaining `TODO[M7*]` stubs and improve live/backtest performance after M7 completion without breaking execution/risk protections delivered in Tasks 07-08.

## Branch
- Working branch: `feat/m7-post-fixes`
- Base branch: `feat/m7-ensemble-integration`

### Branch Promotion Flow
1. Run task branches under the active phase branch.
2. Merge completed phase branch into `feat/m7-post-fixes`.
3. Create the next phase branch from updated `feat/m7-post-fixes`.
4. After Phase 5 closeout and final gates, merge `feat/m7-post-fixes` into `feat/m7-ensemble-integration`.

## Task Pack
- Execution index: `post-m7-task-index.md`
- Task specs: `post-m7-task01.md` ... `post-m7-task17.md`
- Rule: each task file is the source of truth for implementation scope, checkpoints, artifacts, and handoff.

## Execution Evidence

### Phase 0 Baseline
- `MQL5/Files/RPEA/test_results/post_m7/baseline_summary.json`
- `MQL5/Files/RPEA/test_results/post_m7/todo_scan_pre.txt`

### Phase 1 Data/Policy
- `MQL5/Files/RPEA/test_results/post_m7/task02_spread_buffer_summary.json`
- `MQL5/Files/RPEA/test_results/post_m7/task03_atr_percentile_summary.json`
- `MQL5/Files/RPEA/test_results/post_m7/task04_telemetry_kpi_summary.json`
- `MQL5/Files/RPEA/test_results/post_m7/task05_metapolicy_efficiency_summary.json`
- `MQL5/Files/RPEA/test_results/post_m7/task06_phase1_validation.json`
- Targeted run decision evidence: `MQL5/Files/RPEA/test_results/post_m7/phase1_decisions_20240102.csv` .. `MQL5/Files/RPEA/test_results/post_m7/phase1_decisions_20240105.csv`

## Scope Boundaries
- In scope: telemetry/KPI realism, SLO analytics realism, adaptive risk, learning/bandit shadow path, controlled parameter tuning.
- Out of scope: removing hard guards (news block, session cap, liquidity hard blocks, kill-switch/floors), unsafe risk expansion.

## Hard Completion Condition
- Final code scan must return zero hits:
  - `rg -n "TODO\\[M7" MQL5/Include/RPEA MQL5/Experts/FundingPips`
- This includes all variants such as `TODO[M7]`, `TODO[M7-PhaseX]`, and `TODO[M7-TaskX]`.

## Current M7 TODO Inventory (must be resolved by this plan)
1. `MQL5/Include/RPEA/telemetry.mqh:11` - `TODO[M7]: compute rolling KPIs`
2. `MQL5/Include/RPEA/telemetry.mqh:16` - `TODO[M7]: SLO thresholds and auto-risk reduction`
3. `MQL5/Include/RPEA/adaptive.mqh:8` - `TODO[M7]: scale risk by regime/efficiency/room`
4. `MQL5/Include/RPEA/learning.mqh:8` - `TODO[M7]: load calibration.json and apply`
5. `MQL5/Include/RPEA/learning.mqh:13` - `TODO[M7]: apply updates; freeze on SLO breaches`
6. `MQL5/Include/RPEA/bandit.mqh:11` - `TODO[M7]: Thompson/LinUCB with posterior persistence`
7. `MQL5/Include/RPEA/m7_helpers.mqh:60` - `TODO[M7-Phase2]: rolling spread buffer`
8. `MQL5/Include/RPEA/m7_helpers.mqh:90` - `TODO[M7-Phase4]: full percentile calculation`
9. `MQL5/Include/RPEA/meta_policy.mqh:144` - `TODO[M7-Phase5]: bandit posterior readiness check`
10. `MQL5/Include/RPEA/slo_monitor.mqh:49` - `TODO[M7-Task8]: persistent MR throttle action`

## Global Rules (apply to all 4 steps)
1. Implement one subtask at a time.
2. Compile after each subtask checkpoint.
3. Run full automated suites after each major step.
4. Keep defaults safe: new features must default to no behavior change unless explicitly enabled.
5. Every major step must produce durable evidence artifacts under `MQL5/Files/RPEA/test_results/post_m7/`.
6. Do not leave placeholder stubs for listed TODOs; implement or replace with finalized deterministic logic.
7. By final closeout, no `TODO[M7*]` markers may remain.

## Baseline Snapshot (must run before Step 1)
1. Sync + compile + tests:
   - `powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1`
   - `powershell -ExecutionPolicy Bypass -File run_tests.ps1 -RequiredSuite M7Task08_EndToEnd`
2. Capture baseline metrics from decisions/audit logs:
   - `EVAL`, `PLAN_REJECT`, `PLACE_OK`, `PLACE_FAIL`
   - `SLO_MR_THROTTLED` count
   - `MR_TIMESTOP` count
3. Save baseline summary:
   - `MQL5/Files/RPEA/test_results/post_m7/baseline_summary.json`
4. Save pre-implementation TODO inventory scan:
   - Command: `rg -n "TODO\\[M7" MQL5/Include/RPEA MQL5/Experts/FundingPips`
   - Artifact: `MQL5/Files/RPEA/test_results/post_m7/todo_scan_pre.txt`

---

## Step 1 - Real KPI Pipeline + Helper Data Quality (TODO closure)

### Objective
Replace placeholder efficiency inputs and close helper-data TODOs so meta-policy decisions use real rolling performance signals.

### Files
- `MQL5/Include/RPEA/telemetry.mqh`
- `MQL5/Include/RPEA/m7_helpers.mqh`
- `MQL5/Include/RPEA/meta_policy.mqh`
- `Tests/RPEA/test_regime_telemetry.mqh` (extend)
- `Tests/RPEA/test_meta_policy.mqh` (extend)
- Add new test file if needed: `Tests/RPEA/test_m7_helpers.mqh`
- `Tests/RPEA/run_automated_tests_ea.mq5` (if new tests added)

### Subtasks
1.1 Define KPI model used by policy:
- BWISC rolling expectancy proxy.
- MR rolling expectancy proxy.
- Stability factor (minimum sample threshold before non-zero efficiency).

1.2 Implement telemetry state update:
- Add rolling counters/aggregates in `telemetry.mqh`.
- Implement `Telemetry_UpdateKpis()` to update from known execution events.

1.3 Close helper TODOs:
- Implement rolling spread buffer logic in `m7_helpers.mqh`.
- Implement full percentile calculation logic in `m7_helpers.mqh` (remove approximation placeholders).

1.4 Wire policy efficiency helpers:
- Replace `MetaPolicy_GetBWISCEfficiency()` stub.
- Replace `MetaPolicy_GetMREfficiency()` stub.
- Return safe `0.0` if sample size below threshold.

1.5 Add deterministic tests:
- Efficiency returns `0.0` when insufficient samples.
- Efficiency returns expected computed values for fixed synthetic inputs.
- Meta-policy rule paths change only when thresholds are crossed.
- Helper spread/percentile outputs match deterministic expected values.

1.6 Checkpoints
- Compile checkpoint: EA compile `0 errors`.
- Test checkpoint: all suites pass.
- Evidence: `post_m7/step1_kpi_efficiency_summary.json`.

### Step 1 Acceptance
- No stubs remain for efficiency helpers.
- No `TODO[M7-Phase2]` or `TODO[M7-Phase4]` remains in `m7_helpers.mqh`.
- Policy logs show non-zero efficiency only after sample threshold.
- No regression in `M7Task05_MetaPolicy` and `M7Task08_EndToEnd`.

---

## Step 2 - True SLO Analytics (replace default placeholders)

### Objective
Make `SLO_IsMRThrottled()` depend on real rolling metrics, not optimistic defaults.
Note: close-event hold-time capture is already landed in Phase 1 via telemetry position tracking; Step 2 should consume that payload, not duplicate it.

### Files
- `MQL5/Include/RPEA/slo_monitor.mqh`
- `MQL5/Include/RPEA/order_engine.mqh` (or central close-event path used for realized outcomes)
- `MQL5/Include/RPEA/scheduler.mqh` (only if integration hook needed)
- `Tests/RPEA/test_m7_end_to_end.mqh` (extend)
- Add new test file if needed: `Tests/RPEA/test_slo_monitor.mqh`

### Subtasks
2.1 Add rolling window model (30-day equivalent in tester time):
- Win/loss counts.
- Hold-time median/p80 estimators.
- Efficiency median estimator.
- Friction median estimator.

2.2 Add event ingestion API:
- Add explicit function (example: `SLO_OnTradeClosed(...)`) to feed outcomes from telemetry close payload.
- Call this API from one authoritative close/realization path (final close only).

2.3 Implement periodic recompute:
- `SLO_PeriodicCheck()` recomputes flags from rolling window.
- Preserve existing deterministic throttle behavior (MR only).
- Resolve `slo_monitor.mqh` persistent-throttle TODO with concrete logic (for example staged throttle then disable after configured persistence threshold).

2.4 Extend regression tests:
- Breach -> MR choice reroutes (`BWISC` if qualified, otherwise `Skip`).
- Recovery path clears breach after metrics improve.
- No effect on BWISC hard-gate paths.

2.5 Checkpoints
- Compile checkpoint: EA compile `0 errors`.
- Test checkpoint: all suites pass.
- Evidence: `post_m7/step2_slo_analytics_summary.json`.

### Step 2 Acceptance
- SLO metrics are derived from real outcomes.
- SLO gate behavior remains deterministic and test-covered.
- No `unsupported_strategy` regressions.
- No `TODO[M7-Task8]` remains in `slo_monitor.mqh`.

---

## Step 3 - Adaptive Risk Multiplier (guarded rollout)

### Objective
Adjust risk sizing by regime/efficiency while staying within strict safety bounds.

### Files
- `MQL5/Include/RPEA/adaptive.mqh`
- `MQL5/Include/RPEA/allocator.mqh`
- `MQL5/Include/RPEA/config.mqh` (new toggles/clamps)
- Tests: extend `Tests/RPEA/test_allocator_mr.mqh` and add `Tests/RPEA/test_adaptive_risk.mqh`

### Subtasks
3.1 Implement multiplier function:
- Inputs: regime label + efficiency.
- Output clamp: `[min_mult, max_mult]` from config.
- Default multiplier remains `1.0`.
- Remove `adaptive.mqh` placeholder TODO by shipping concrete regime/efficiency mapping.

3.2 Integrate into allocator risk path:
- Apply multiplier after strategy base risk is chosen.
- Preserve MicroMode cap precedence.
- Preserve hard budget/risk gates.

3.3 Add runtime toggle:
- `EnableAdaptiveRisk` default `false`.
- When disabled, behavior equals pre-step baseline.

3.4 Add tests:
- Clamp boundaries.
- MicroMode precedence.
- Disabled toggle returns exact baseline volume/risk.

3.5 Checkpoints
- Compile checkpoint: EA compile `0 errors`.
- Test checkpoint: all suites pass.
- Evidence: `post_m7/step3_adaptive_risk_summary.json`.

### Step 3 Acceptance
- No risk increase when feature disabled.
- With feature enabled, risk always within clamps and challenge protections.
- No `TODO[M7]` remains in `adaptive.mqh`.

---

## Step 4 - Learning + Bandit Shadow + Controlled Tuning

### Objective
Introduce learning/bandit safely in shadow mode, then perform controlled parameter tuning based on evidence.

### Files
- `MQL5/Include/RPEA/learning.mqh`
- `MQL5/Include/RPEA/bandit.mqh`
- `MQL5/Include/RPEA/meta_policy.mqh`
- `MQL5/Include/RPEA/telemetry.mqh`
- New tests: `Tests/RPEA/test_learning.mqh`, `Tests/RPEA/test_bandit.mqh` (or consolidated test file)
- `Tests/RPEA/run_automated_tests_ea.mq5` (register suites)

### Subtasks
4.1 Implement learning state load/update:
- Load calibration file safely (missing file -> safe defaults).
- Persist updates atomically.
- Freeze updates when SLO is breached.

4.2 Implement bandit selector:
- Start with simple, deterministic Thompson-style scoring (or constrained equivalent).
- Persist posterior/state.
- Enforce hard blocks before bandit influence.
- Implement posterior-readiness check in `meta_policy.mqh` (remove Phase5 readiness TODO).

4.3 Shadow mode first (mandatory):
- Keep `BanditShadowMode=true`.
- Log bandit choice vs deterministic choice deltas.
- No live decision control yet.

4.4 Controlled tuning protocol:
- Tune only one family at a time:
  - confidence cuts,
  - liquidity quantile thresholds,
  - MR hold/time-stop bounds,
  - adaptive risk clamps.
- Run walk-forward windows and compare to baseline.

4.5 Promotion gate (shadow -> active)
- Promote only if all pass:
  - Out-of-sample expectancy improves vs baseline.
  - Drawdown does not worsen beyond agreed limit.
  - No increase in SLO breach rate.
  - Full harness still green.

4.6 Checkpoints
- Compile checkpoint: EA compile `0 errors`.
- Test checkpoint: all suites pass.
- Evidence:
  - `post_m7/step4_shadow_delta_summary.json`
  - `post_m7/step4_tuning_report.json`

### Step 4 Acceptance
- Learning and bandit are production-safe in shadow mode.
- Promotion criteria are explicit and evidence-backed.
- No `TODO[M7]` remains in `learning.mqh`, `bandit.mqh`, or `meta_policy.mqh`.

---

## Pass/Fail Gate (must pass before merge)
1. Compile gate: `compile_rpea.log` shows `0 errors`.
2. Test gate: `test_results.json` shows `success=true`, `total_failed=0`.
3. Required suites pass:
   - `M7Task07_AllocatorMR`
   - `M7Task08_EndToEnd`
   - any new post-M7 suites added in this plan.
4. No MR `unsupported_strategy` regressions in decisions logs.
5. Post-M7 evidence bundle exists under `MQL5/Files/RPEA/test_results/post_m7/`.
6. `rg -n "TODO\\[M7" MQL5/Include/RPEA MQL5/Experts/FundingPips` returns no matches.

## Rollback Rules
1. If compile/test fails after a subtask, stop and fix before continuing.
2. If live behavior degrades, disable new toggle flags (`EnableAdaptiveRisk`, bandit active mode) and revert to deterministic baseline.
3. Never remove existing hard risk/news/session protections.

## Final Closeout Checklist
1. Update `AGENTS.md` living section:
   - `Last Updated`
   - changed module line counts
   - new `Recent Changes` entry
2. Add/update task notes file summarizing:
   - what changed
   - what was validated
   - known residual risks
3. Re-run:
   - `powershell -ExecutionPolicy Bypass -File run_tests.ps1`
4. Store final evidence:
   - `MQL5/Files/RPEA/test_results/post_m7/final_summary.json`
5. Store final TODO scan output:
   - Command: `rg -n "TODO\\[M7" MQL5/Include/RPEA MQL5/Experts/FundingPips`
   - Artifact: `MQL5/Files/RPEA/test_results/post_m7/todo_scan_post.txt` (must be empty/no lines)
