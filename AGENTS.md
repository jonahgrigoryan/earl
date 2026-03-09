---
description: 
alwaysApply: true
---

# Repository Guidelines

## Project Structure & Module Organization
- `MQL5/Experts/FundingPips/RPEA.mq5` is the Expert Advisor entry point; its includes mirror modules under `MQL5/Include/RPEA`.
- Core subsystems live in `MQL5/Include/RPEA/*.mqh` (order engine, risk, synthetic manager, news, telemetry). Keep functions scoped to their modules and guard headers.
- Tests reside in `Tests/RPEA`, with CSV fixtures in `Tests/RPEA/fixtures/news`. Production news fallback data is at `Files/RPEA/news/calendar_high_impact.csv`.

## Codebase State (Living Document)

> **Rule**: After implementing any task, update **Last Updated**, the module table
> that changed, and the **Recent Changes** list at the bottom of this section.
> This keeps future agents current without a full codebase scan.

**Last Updated**: FundingPips Phase 1 MT5 runner batch/report hardening completed (2026-03-09). The HPO workstream baseline is `feat/hpo-pipeline`; Phase 0 is merged and active work is on `feat/hpo-phase1-mt5-runner` with PR `#48` open into the baseline branch.

### Module Inventory

Each row shows responsibility, current line count, and which layer it belongs to.
Agents should check this table before editing a module to understand its scope and
avoid unintended coupling.

| Module | Lines | Layer | Responsibility |
|--------|------:|-------|----------------|
| `order_engine.mqh` | ~6277 | Execution | OCO, market fallback, retries, trailing, two-leg atomic ops, partial fills. Includes ORDER_DELETE OCO cleanup, cancel/modify retry wrappers, and market fill-mode fallback for unsupported filling retcode `10030`. **Largest module; edit with care.** |
| `persistence.mqh` | ~2020 | Support | File-backed state recovery, intent queue, challenge state persistence. Ensures binary Q-table payloads are not text-initialized. |
| `equity_guardian.mqh` | ~1350 | Risk | Baseline tracking, daily/overall floors, kill-switch, MicroMode activation (+10% target), giveback protection. |
| `queue.mqh` | ~1250 | Execution | Action queueing during news windows, TTL expiry, post-news revalidation. |
| `config.mqh` | ~1508 | Support | EA inputs, validation, clamping. Includes test overrides/runtime getters for adaptive-risk, anomaly rollout/tuning inputs, and MR diagnostic RL-bypass toggle (`EnableMRBypassOnRLUnloaded`). Script/tooling compile compatibility is provided via defaults in `rl_pretrain_inputs.mqh`. |
| `news.mqh` | ~875 | Support | Calendar API + CSV fallback, T +/-300s window, `News_IsEntryBlocked`, `News_GetWindowStateDetailed`. |
| `synthetic.mqh` | ~650 | Execution | XAUEUR proxy/replication manager (XAUUSD-only or two-leg XAUUSD+EURUSD). |
| `evaluation_report.mqh` | ~548 | Support | FundingPips Phase 0 evaluation artifact writer. Tracks per-run summary metrics and per-day DD records, handles stale-vs-fresh rollover baselines, and writes deterministic `fundingpips_eval_summary.json` plus `fundingpips_eval_daily.csv` outputs for tester/HPO consumption. |
| `tools/fundingpips_mt5_runner.py` | ~801 | Tooling | FundingPips Phase 1 MT5 automation runner. Generates `.ini`/`.set` files, syncs repo code to the MT5 data folder, compiles the EA before execution, launches headless tester runs, caches runs by scenario plus EA hash and agent-mode flags, short-circuits cache hits before preflight, keeps batch sync enabled until the first uncached run, preserves merged INI encoding from `common.ini`, checks `.xml` and `.xml.htm` report candidates independently, waits for strictly fresh artifacts on reruns, and collects summary/daily/report artifacts into structured run folders under `.tmp/fundingpips_hpo_runs/`. |
| `allocator.mqh` | ~675 | Risk | Builds `OrderPlan` for **BWISC + MR**, strategy-specific risk sizing, adaptive-risk multiplier integration behind runtime toggle, proxy-distance mapping guard for MR, budget gate, and strategy-tagged comments. |
| `sessions.mqh` | ~445 | Support | Session windows (LO, NY), OR snapshot. |
| `anomaly.mqh` | ~370 | Risk | EWMA shock detector on returns/spread/tick-gap with guardrails, deterministic scoring, and staged action recommendation (`widen`/`cancel`/`flatten`) for safe rollout. |
| `logging.mqh` | ~415 | Support | CSV audit rows (`LogAuditRow`), structured `LogDecision`. |
| `indicators.mqh` | ~403 | Support | Indicator snapshots (ATR, MA, Bollinger, etc.). |
| `emrt.mqh` | ~377 | M7 Ensemble | EMRT formation (rank, P50, beta). Used by MR signals. |
| `breakeven.mqh` | ~312 | Execution | Breakeven at +0.5R. |
| `trailing.mqh` | ~288 | Execution | Trailing stop logic (ATR-based, activates at +1R). |
| `rl_pretrain_inputs.mqh` | ~306 | M7 Ensemble | Pre-training parameter defaults (MR_RiskPct_Default, TimeStopMin/Max, etc.) plus script-safe defaults for post-release runtime toggles (anomaly/adaptive/MR RL-bypass). |
| `learning.mqh` | ~337 | M7 Ensemble | File-backed calibration state loader/updater with schema validation, atomic persistence, and SLO-breach freeze gate (`Learning_LoadCalibration`, `Learning_Update`). |
| `meta_policy.mqh` | ~333 | Signal | Strategy chooser (BWISC vs MR vs Skip). Deterministic rules + optional bandit with persisted posterior readiness check and shadow delta logging. Includes deterministic SLO override helper for MR throttle fallback. **`M7_DECISION_ONLY` is 0 (execution enabled).** |
| `state.mqh` | ~237 | Support | `ChallengeState` struct, `State_Get()`/`State_Set()` accessors. |
| `signals_bwisc.mqh` | ~230 | Signal | BWISC signals (BC/MSC). Populates `g_last_bwisc_context` (`BWISC_Context`). |
| `rl_agent.mqh` | ~220 | M7 Ensemble | Q-learning table, `RL_StateFromSpread`, `RL_GetQAdvantage`. |
| `signals_mr.mqh` | ~282 | Signal | MR signals (mean reversion, EMRT + RL). Populates `g_last_mr_context` with execution-symbol entry price and direction; RL-unloaded bypass is guarded by runtime toggle for diagnostics only. |
| `liquidity.mqh` | ~220 | Support | Rolling spread/slippage stats, quantile getters, `Liquidity_SpreadOK`, plus test-only state reset helper (`Liquidity_TestResetState`) for suite isolation. |
| `risk.mqh` | ~192 | Risk | `Risk_SizingByATRDistanceForSymbol`, `Risk_GetEffectiveRiskPct` (handles MicroMode). |
| `m7_helpers.mqh` | ~497 | M7 Ensemble | Wrapper functions (ATR, spread, session helpers) plus rolling spread buffer + full ATR percentile helpers used by policy/regime paths. |
| `scheduler.mqh` | ~380 | Orchestration | Main tick handler. Evaluates anomaly detector per symbol, logs detect/no-detect + staged action telemetry, and only hard-blocks entries for active-mode actions with handlers (`cancel`/`flatten`); `widen` stays non-blocking until explicit implementation. Includes MR time-stop enforcement + SLO periodic checks. |
| `symbol_bridge.mqh` | ~85 | Support | XAUEUR -> XAUUSD mapping. `SymbolBridge_GetExecutionSymbol()`. |
| `regime.mqh` | ~95 | M7 Ensemble | Regime detection (trending/ranging/volatile). ADX + ATR percentile. |
| `telemetry.mqh` | ~743 | Support | Rolling KPI state/update pipeline + `LogMetaPolicyDecision`; includes position-level close tracking to avoid partial-close overcount, robust strategy attribution fallback, hold-minute capture, canonical friction tax in R-units using entry-side risk basis capture + final-close aggregation (`Telemetry_OnPositionExitWithTheory`), and bandit shadow delta telemetry (`Telemetry_LogBanditShadowDelta`). |
| `adaptive.mqh` | ~96 | Risk | Deterministic adaptive multiplier by regime + efficiency with strict bound clamping and invalid-input fallback to neutral risk. |
| `slo_monitor.mqh` | ~463 | M7 Ensemble | SLO closed-trade ingestion + rolling metric engine (win rate, hold median/p80, efficiency/friction medians), staged warn/throttle/disable policy, and deterministic periodic recompute hooks (`SLO_OnTradeClosed`, `SLO_CheckAndThrottle`, `SLO_IsMRThrottled`, `SLO_IsMRDisabled`). |
| `app_context.mqh` | ~27 | Support | `AppContext` struct definition. |
| `mr_context.mqh` | ~17 | Signal | Lightweight `MR_Context` struct + `g_last_mr_context` (allocator-safe include). |
| `bandit.mqh` | ~455 | M7 Ensemble | Deterministic contextual bandit with file-backed posterior load/save (schema/version validation + atomic `.tmp` writes), posterior readiness checks, and trade-outcome update path (`Bandit_RecordTradeOutcome`). |

**Files planned for Task 08**:
- No new required headers from Task 07 remain pending.

### Key Design Decisions (Locked)

1. **Context Separation**: `BWISC_Context` lives in `signals_bwisc.mqh`. Task 07 creates `MR_Context` in a dedicated lightweight `mr_context.mqh`. Allocator includes only context headers, NOT full signal modules (avoids circular includes: `signals_mr` -> `m7_helpers` -> `order_engine`).

2. **Strategy-Specific Risk**: MR will use `Config_GetMRRiskPctDefault()` (0.90%) in normal mode, `Config_GetMicroRiskPct()` in MicroMode. BWISC uses `Risk_GetEffectiveRiskPct()` (already handles MicroMode). Both respect MicroMode for challenge compliance.

3. **Entry Price Source**: MR entry price must come from the **execution symbol** (`SymbolBridge_GetExecutionSymbol(signal_symbol)`), not signal symbol. Using XAUEUR quotes directly produces invalid prices.

4. **Execution Mode Gate**: `M7_DECISION_ONLY` flag in `meta_policy.mqh` is now **0** (execution enabled).

5. **Order Comment Format**: `"{prefix}{strategy}-{setup_type} b={bias} conf={confidence} {timestamp}"`. MR uses `setup_type = "MR"` (forced in allocator, not derived from entry vs bid/ask like BC/MSC).

6. **Risk Units**: `Risk_SizingByATRDistanceForSymbol()` expects percentage directly (e.g., 0.90 for 0.90%). Do **not** divide by 100.

### Integration Flow (Current State)

```
scheduler.mqh tick loop:
  1. Floors/room checks
  2. Per-symbol anomaly evaluation (`ANOMALY_EVAL`) with staged action (`ANOMALY_SHADOW`/`ANOMALY_ACTION`)
  3. Core gates (news, spread, session, anomaly active-mode block)
  4. SignalsBWISC_Propose() -> populates g_last_bwisc_context
  5. SignalsMR_Propose()    -> populates output params + g_last_mr_context
  6. MetaPolicy_Choose()    -> returns "BWISC" | "MR" | "Skip"
  7. Allocator_BuildOrderPlan(strategy, symbol, sl, tp, conf) -> OrderPlan
  8. If plan.valid -> OrderEngine places order (execution enabled)
```

**MicroMode Integration**:
- Activated by `Equity_IsMicroModeActive()` (reads `state.micro_mode` flag).
- All strategies respect it. To test: `State_Get()` / `State_Set(st)` with `st.micro_mode = true`.
- Restore original state after test: `State_Set(orig_st)`.

### Patterns for Agents

**Include Guard**: All `.mqh` files use `#ifndef RPEA_MODULE_MQH` / `#define` / `#endif`.

**Context Population** (signal modules):
```cpp
// Clear at function start, populate before hasSetup=true
g_last_bwisc_context.entry_price = 0.0;
// ... signal logic ...
g_last_bwisc_context.entry_price = ask; // or bid based on direction
```

**Test Pattern**: Unit tests in `Tests/RPEA/test_*.mqh`. Register in `run_automated_tests_ea.mq5`. Use deterministic values (manually set globals, don't rely on live broker prices). Use EURUSD for stable tester execution.

**AppContext in Tests**: Always `ZeroMemory(ctx); ArrayResize(ctx.symbols, N);` before assigning `ctx.symbols[i]`.

### Recent Changes (Newest First)

Update this list when completing a task. Helps agents understand what just changed.

- **FundingPips Phase 1 batch/report hardening (2026-03-09)**: Updated `tools/fundingpips_mt5_runner.py` so batch execution keeps `sync_before_run` enabled until the first non-cache-hit run actually happens, preventing mixed cache-hit/cache-miss batches from compiling stale terminal-side EA sources. Also changed report detection to evaluate `.xml` and `.xml.htm` candidates independently and pick the freshest valid report, so stale XML files no longer block the active HTML-wrapped MT5 report variant. Added Python regressions in `Tests/python/test_fundingpips_mt5_runner.py` for mixed-cache batch sync sequencing and stale-XML/fresh-HTML report selection. Validation: `python -m py_compile` passed; Python unit tests `14/14` passing; forced probe for `EURUSD` (`2024.01.02..2024.01.05`) completed successfully; rerunning the same spec without `--force` returned `cache_hit`; EA compile `0 errors, 2 warnings`; automated suites `42/42` passing.
- **FundingPips Phase 1 cache/preflight/INI hardening (2026-03-07)**: Updated `tools/fundingpips_mt5_runner.py` so cache keys now include `use_local`, `use_remote`, and `use_cloud`; cache hits are evaluated before sync/compile/MT5-process preflight; and merged runner INIs preserve the detected `common.ini` encoding instead of forcing ASCII. Added Python regressions in `Tests/python/test_fundingpips_mt5_runner.py` for agent-mode cache-key differentiation, cache-hit short-circuiting ahead of preflight, and non-ASCII INI round-tripping. Validation: `python -m py_compile` passed; Python unit tests `12/12` passing; forced probe for `EURUSD` (`2024.01.02..2024.01.05`) completed successfully; rerunning the same spec without `--force` returned `cache_hit`; EA compile `0 errors, 2 warnings`; automated suites `42/42` passing.
- **FundingPips Phase 1 stale-artifact mtime guard hardening (2026-03-07)**: Tightened artifact freshness checks in `tools/fundingpips_mt5_runner.py` so summary/daily/report files must have `mtime >= started_at` with no 2-second grace window. This prevents back-to-back `--force` reruns from reusing stale prior-run artifacts and terminating MT5 early. Added Python regressions in `Tests/python/test_fundingpips_mt5_runner.py` for stale-vs-fresh `locate_recent_file` behavior at run-start boundaries. Validation: `python -m py_compile` passed; Python unit tests `9/9` passing; two consecutive forced probe runs for `EURUSD` (`2024.01.02..2024.01.05`) completed successfully; EA compile `0 errors, 2 warnings`; automated suites `42/42` passing.
- **FundingPips Phase 1 MT5 runner (2026-03-07)**: Added `tools/fundingpips_mt5_runner.py` plus `tools/__init__.py` and Python regression coverage in `Tests/python/test_fundingpips_mt5_runner.py`. The runner generates per-run `.ini` and `.set` files, prepends the terminal `[Common]` config section, compiles the EA before execution, launches MT5 headlessly, caches by run spec plus the full repo-controlled EA dependency tree (`MQL5/Experts/FundingPips` and `MQL5/Include/RPEA`), and collects the FundingPips summary/daily artifacts together with the tester report, including MT5 `.xml.htm` report-name handling. Batch defaults now merge `set_overrides` correctly so per-run tweaks do not drop shared parameters. Validation: `python -m py_compile` passed; Python unit tests `7/7` passing; runner probe for `EURUSD` (`2024.01.02..2024.01.05`) completed successfully; EA compile `0 errors, 2 warnings`; automated suites `42/42` passing. Packaging state: pushed on `feat/hpo-phase1-mt5-runner`, PR `#48` open into `feat/hpo-pipeline`.
- **FundingPips Phase 0 evaluation reporting (2026-03-07)**: Added `evaluation_report.mqh` to produce deterministic FundingPips-style summary/daily artifacts, wired lifecycle updates and final report writing into `RPEA.mq5`, added `FundingPips_Phase0_EvaluationReport` coverage in `test_evaluation_report.mqh` plus runner registration, and fixed the stale-rollover expectation so tests match production fallback behavior. Validation: EA compile `0 errors, 5 warnings`; automated suites `42/42` passing; tester probe artifacts verified at `RPEA/reports/fundingpips_eval_summary.json` and `RPEA/reports/fundingpips_eval_daily.csv`.
- **FundingPips HPO implementation outline (2026-03-07)**: Added `docs/fundingpips-hpo-implementation-outline.md` as the canonical end-to-end plan for the profitability/HPO workstream. It restructures the earlier rough rule/optimization note into a phased implementation document covering branch topology, v0/v1 delivery, phase deliverables and merge gates, artifact design, validation, overfitting defenses, and first/next/last execution order.
- **FundingPips HPO handoff scaffold (2026-03-07)**: Added `docs/fundingpips-hpo-handoff.md` as the active cross-session tracker for the new profitability/HPO workstream. It records the repo-specific branch correction (`master` instead of `main`), locked planning decisions, planned phase branches, and now the active Phase 0 execution/validation state for future handoffs.
- **FundingPips profitability evidence bundle (2026-03-03)**: Recorded branch-level tuning outcomes in `docs/fundingpips-profitability-run-2026-03-03.md`, including 3-window robustness comparison (`B` vs `E`) and long-window validation of selected candidate `B` (`2025-06-03..2025-11-21`). Key outcomes: true median net for `B` beats `E` with lower worst DD; long-window run remained low-frequency (`2` trades) with modest positive net (`+23.70`), so strategy is execution-capable but still not challenge-pass ready.
- **FundingPips profitability branch runtime fix (2026-03-03)**: Fixed a non-test getter regression in `config.mqh` where macro guards caused EA runtime inputs to be ignored in live/tester runs (notably `EnableMRBypassOnRLUnloaded`, anomaly/adaptive toggles). Restored direct variable reads for non-test builds while retaining script/tooling compile compatibility through `rl_pretrain_inputs.mqh` defaults. Validation: EA compile `0 errors, 2 warnings`; `emrt_refresh.mq5` compile `0 errors, 0 warnings`; automated suites `41/41` passing. Probe reruns (`2025-06-03..2025-07-03`) now place trades again with positive net on candidate profiles.
- **OrderEngine filling-mode compatibility fallback (2026-03-02)**: Hardened market execution in `order_engine.mqh` for unsupported filling-mode retcode `10030` by introducing deterministic fill-policy rotation (`IOC`/`FOK`/`RETURN`) with explicit `FILLING_MODE_FALLBACK` decision telemetry and richer `ORDER_SEND_ATTEMPT` payloads (`filling`). Also mapped retcode `10030` into retry/error taxonomy (`RETRY_POLICY_LINEAR`, recoverable class, gating reason `unsupported_filling`) and added regression test `ExecuteOrderWithRetry_FillingModeFallbackOn10030` in `Tests/RPEA/test_order_engine_retry.mqh`. Validation: EA compile `0 errors, 2 warnings`; test-runner compile `0 errors, 2 warnings`; automated suites `41/41` passing.
- **Config/script compile fallback hardening (2026-03-03)**: Fixed non-EA compile-path breaks by adding guarded fallback branches in `config.mqh` runtime getters (`Config_GetEnableMRBypassOnRLUnloaded`, anomaly/adaptive getters) and extending `rl_pretrain_inputs.mqh` with default macros for post-release toggles used by scripts (`EnableMRBypassOnRLUnloaded`, anomaly, adaptive inputs). Validation: `emrt_refresh.mq5` compile `0 errors, 0 warnings`; EA compile `0 errors, 2 warnings`; automated suites `41/41` passing.
- **OrderEngine filling-mode compatibility fallback (2026-03-02)**: Hardened market execution in `order_engine.mqh` for unsupported filling-mode retcode `10030` by introducing deterministic fill-policy rotation (`IOC`/`FOK`/`RETURN`) with explicit `FILLING_MODE_FALLBACK` decision telemetry and richer `ORDER_SEND_ATTEMPT` payloads (`filling`). Also mapped retcode `10030` into retry/error taxonomy (`RETRY_POLICY_LINEAR`, recoverable class, gating reason `unsupported_filling`) and added regression test `ExecuteOrderWithRetry_FillingModeFallbackOn10030` in `Tests/RPEA/test_order_engine_retry.mqh`. Validation: EA compile `0 errors, 2 warnings`; test-runner compile `0 errors, 2 warnings`; automated suites `41/41` passing.
- **Post-release diagnostic rollback + MR gate hardening (2026-03-02)**: Reverted branch-only debug forcing in `allocator.mqh` and restored standard `signals_bwisc.mqh` thresholds/flow so strategy behavior is controlled by `.set` inputs rather than hardcoded diagnostics. Kept the persistence safety fix in `persistence.mqh` that prevents binary `FILE_QTABLE_BIN` from being text-initialized. Added runtime-gated MR RL bypass (`EnableMRBypassOnRLUnloaded`) through `RPEA.mq5` + `config.mqh` + `signals_mr.mqh`; default is strict (`false`), with probe `.set` files opting in (`true`) for diagnostic runs when qtable loading is unstable. Validation: EA compile `0 errors`; automated suites pass (`41/41`).
- **Post-release anomaly rollout follow-up (2026-02-23)**: Corrected scheduler active-mode semantics so `ANOMALY_ACTION_WIDEN` no longer hard-blocks entries (only `cancel`/`flatten` block and execute), added scheduler anomaly policy helpers + deterministic scheduler-level anomaly semantics assertions in `test_anomaly.mqh`, exposed runtime-configurable anomaly tuning (`AnomalyEWMAAlpha`, `AnomalyMinSamples`) via `RPEA.mq5` + `config.mqh` getters/validation, and reverted adaptive-risk EA input defaults to `DEFAULT_AdaptiveRiskMinMult`/`DEFAULT_AdaptiveRiskMaxMult`. Validation: EA compile `0 errors, 2 warnings`; test-runner compile `0 errors, 2 warnings`; automated suites `41/41` passing (`success=true`, `total_failed=0`).
- **Post-release anomaly shock rollout (2026-02-23)**: Implemented full `Anomaly_IsShockNow` engine in `anomaly.mqh` (EWMA z-scores for returns/spread/tick-gap, invalid/insufficient-sample guardrails, deterministic action selection), wired scheduler anomaly evaluation + safe shadow/active staging in `scheduler.mqh` (`ANOMALY_EVAL`, `ANOMALY_SHADOW`, `ANOMALY_ACTION` logs), added anomaly rollout inputs/getters/overrides in `config.mqh` + `RPEA.mq5`, and introduced deterministic suite `test_anomaly.mqh` registered as `PostRelease_AnomalyShockNow` in `run_automated_tests_ea.mq5`. Validation: EA compile `0 errors, 2 warnings`; test-runner compile `0 errors, 2 warnings`; automated suites `41/41` passing (`success=true`, `total_failed=0`).
- **M7 RC cleanup hardening (2026-02-16)**: Implemented OCO relationship cleanup on `TRADE_TRANSACTION_ORDER_DELETE` in `order_engine.mqh` (`OCO_CLEANUP` decision log + pending-link cleanup), added retry-capable wrappers for cancel/modify operations (`OE_RequestCancelWithRetry`, `OE_RequestModifyWithRetry`) and routed existing helpers through those paths. Removed stale dead stubs/comments in `config.mqh`, `timeutils.mqh`, and `regime.mqh`, and refreshed regression coverage in `test_order_engine_oco.mqh` (ORDER_DELETE cleanup case) and `test_order_engine_retry.mqh` (cancel/modify retry behavior). Validation: EA compile `0 errors, 5 warnings`; test-runner compile `0 errors, 2 warnings`; automated suites `40/40` passing.
- **Post-M7 Phase 5 walk-forward hardening (2026-02-15)**: Resolved Task16 report-generation reliability in `scripts/walk_forward.ps1` by enforcing clean MT5 process ownership per run, adding expected report resolution, and writing deterministic copied report artifacts into `post_m7` output. Re-ran full Task16 family configs (`confidence`, `liquidity`, `time_stop`, `adaptive`) with real execution and refreshed `step4_tuning_report.json` + `task16_walkforward_summary.json` from generated CSV/report artifacts. Final Task16 state is no longer blocked (`full_walkforward_report_generation=completed`), with explicit outcome `completed_no_eligible_candidates` for selected windows.
- **Post-M7 Phase 5 complete (2026-02-15)**: Executed tasks 16-17 on `feat/m7-postfix-phase5-tuning-closeout`: finalized `TODO[M7*]` closure by implementing deterministic `Telemetry_AutoThrottle()` final hook in `telemetry.mqh` (no placeholder markers remain), added reproducible tuning artifacts (`step4_tuning_report.json`, `task16_walkforward_summary.json`, family config/set snapshots + dry-run logs), and produced final closeout bundle (`todo_scan_post.txt` empty, `final_summary.json`). Final gates: EA compile `0 errors, 5 warnings`; test-runner compile `0 errors, 6 warnings`; automated suites `40/40` passing including `M7Task07_AllocatorMR`, `M7Task08_EndToEnd`, and post-M7 suites.
- **Post-M7 Phase 4 test isolation hardening (2026-02-15)**: Closed cross-suite state leakage in `test_bandit.mqh` and `test_learning.mqh` by adding explicit setup/teardown cleanup (posterior/calibration file cleanup + runtime state resets) and introducing `Liquidity_TestResetState()` in `liquidity.mqh` (`#ifdef RPEA_TEST_RUNNER`) to clear rolling quantile buffers between tests. Validation rerun: EA compile `0 errors, 5 warnings`; automated suites `40/40` passing with `PostM7Task14_15_Bandit` gate.
- **Post-M7 Phase 4 complete (2026-02-15)**: Executed tasks 12-15 on `feat/m7-postfix-phase4-learning-bandit`: implemented file-backed learning calibration load/update in `learning.mqh` (schema validation, missing/malformed fallback, atomic update writes, SLO freeze gate), wired runtime calls in `RPEA.mq5` (`Learning_LoadCalibration` on init, `Learning_Update` on final close), implemented deterministic contextual bandit runtime in `bandit.mqh` (posterior persistence + readiness, contextual selection, trade-outcome updates), completed meta-policy readiness + shadow integration in `meta_policy.mqh` (`MetaPolicy_BanditIsReady` delegates to posterior readiness, shadow path logs bandit-vs-deterministic deltas through `Telemetry_LogBanditShadowDelta`), and added suites/tests `test_learning.mqh`, `test_bandit.mqh`, `test_meta_policy.mqh` updates with runner registration `PostM7Task14_15_Bandit`. Validation artifacts: `task12_learning_load_summary.json`, `task13_learning_update_summary.json`, `task14_bandit_summary.json`, `task15_metapolicy_bandit_shadow.json`; compile gates `0 errors`; automated suites `40/40` passing.
- **Post-M7 Phase 3 complete (2026-02-15)**: Executed tasks 10-11 on `feat/m7-postfix-phase3-adaptive-risk`: implemented `Adaptive_RiskMultiplier` mapping with strict bounds and neutral fallback in `adaptive.mqh`, closed carry-forward friction path by wiring theoretical-vs-realized close payload (`profit` vs `net_outcome`) through `Telemetry_OnPositionExitWithTheory` into `SLO_OnTradeClosed(... friction_r ...)`, and integrated allocator adaptive sizing behind runtime toggle (`EnableAdaptiveRisk`, min/max multipliers) with MicroMode precedence preserved. Added `test_adaptive_risk.mqh`, expanded `test_allocator_mr.mqh` and `test_slo_monitor.mqh` (non-zero friction regression), wired suite `PostM7Task10_11_AdaptiveRisk`, and validated artifacts: `task10_adaptive_multiplier_summary.json`, `task11_allocator_adaptive_summary.json` with full harness green (`38/38`, `total_failed=0`) and `unsupported_strategy` regression scan clear.
- **Post-M7 Phase 3 friction hardening (2026-02-15)**: Replaced proxy friction math with canonical R-tax model in `telemetry.mqh`: entry-side risk basis capture (`worst_case_risk_money_total`, weighted `theoretical_r`) and final-close computation `friction_r = max(0, theoretical_r - realized_r)` where `realized_r = cumulative_net_outcome / worst_case_risk_money_total`. Wired `RPEA.mq5` `DEAL_ENTRY_IN` to pass entry price/SL/TP/volume into `Telemetry_OnPositionEntryDetailed`, removed close-path profit proxy dependency, and expanded `test_slo_monitor.mqh` with deterministic cases for single-entry basis, partial-close aggregation, weighted multi-entry basis, and invalid-basis fallback. Refreshed Phase 3 real-EA evidence with manifest-backed files (`phase3_real_run_manifest.json`, `phase3_decisions_20240108..20240111.csv`) to avoid reused artifact ambiguity.
- **Post-M7 Phase 2 complete (2026-02-15)**: Executed tasks 07-09 on `feat/m7-postfix-phase2-slo`: added authoritative `SLO_OnTradeClosed(...)` ingestion wired from final-close telemetry output path in `RPEA.mq5` (`Telemetry_OnPositionExit` emit -> `SLO_OnTradeClosed`), implemented rolling 30-day metric recompute in `slo_monitor.mqh` (win rate, hold median/p80, efficiency median, friction median) with insufficient-sample guards, and finalized persistent staged policy (`WARN_ONLY` -> `THROTTLE` -> `DISABLE_MR`) with configurable breach persistence checks and meta-policy gating reason split (`SLO_MR_THROTTLED` vs `SLO_MR_DISABLED`). Added `test_slo_monitor.mqh`, expanded `test_m7_end_to_end.mqh`, updated suite wiring in `run_automated_tests_ea.mq5`, and validated artifacts: `task07_slo_ingestion_summary.json`, `task08_slo_metrics_summary.json`, `task09_slo_throttle_summary.json` with full harness green (`37/37`, `total_failed=0`) and `unsupported_strategy` regression scan clear.
- **Post-M7 Phase 1 hardening (2026-02-15)**: Completed telemetry close-path robustness work before Phase 2: added final-close aggregation in `telemetry.mqh` to prevent KPI double-counting on partial exits, added position-tracked strategy attribution with resilient comment fallback (`MR-MR`, `BWISC-*`), captured real hold minutes from entry/exit timestamps, and wired `RPEA.mq5` `OnTradeTransaction` to `Telemetry_OnPositionEntry/Exit`. Added deterministic regression coverage in `test_regime_telemetry.mqh` for partial-close finalization, strategy attribution precedence, and hold-minute capture; updated Phase 2 docs (`post-m7-task07.md`, `post-m7-task08.md`, `m7-post-fixes-plan.md`) to consume the now-available hold-time payload instead of re-implementing capture.
- **Post-M7 Phase 1 complete (2026-02-14)**: Closed tasks 02-06 on `feat/m7-postfix-phase1-data-policy` with deterministic implementations for `m7_helpers` rolling spread buffer + ATR percentile, telemetry KPI state/update pipeline, and meta-policy efficiency wiring to telemetry. Added suite `PostM7Task02_03_M7Helpers` and expanded telemetry/meta-policy regression coverage. Validation artifacts written under `MQL5/Files/RPEA/test_results/post_m7/` (`task02_*`, `task03_*`, `task04_*`, `task05_*`, `task06_phase1_validation.json`) with compile (`0 errors`) and automated suites (`36/36`) passing.
- **Post-M7 workflow alignment (2026-02-14)**: Clarified active post-M7 execution stream in `Current Baseline & Workflow`, including source-of-truth docs (`m7-post-fixes-plan.md`, `post-m7-task-index.md`, `post-m7-task01..17.md`) and required branch promotion model (merge each phase into `feat/m7-post-fixes`, then cut next phase from updated base).
- **Post-M7 planning scaffold (2026-02-11)**: Added full task-pack docs for post-M7 execution flow: `post-m7-task-index.md` and `post-m7-task01.md` .. `post-m7-task17.md`, including branch topology, per-task compile/test/evidence gates, and deterministic handoff chain to drive full `TODO[M7*]` closure.
- **M7 Task 08 evidence refresh (2026-02-10)**: Validated placement-probe results from terminal log `decisions_20260210.csv` (local runtime source), refreshed committed summary artifacts `rubric_counts.txt` and `real_ea_run_summary.json` with live scheduler counts (`EVAL=62`, `PLAN_REJECT=7`, `PLACE_OK=1`, `PLACE_FAIL=8`, `unsupported_strategy=0`), and updated `m7-task08.md` rubric Check 9 from `N/A` to `PASS` with stable artifact paths.
- **M7 Task 08 acceptance hardening (2026-02-09)**: Added deterministic `MetaPolicy_ApplySLOOverride()` helper in `meta_policy.mqh` and expanded `test_m7_end_to_end.mqh` with explicit SLO regression checks (`MR -> BWISC` when BWISC qualified, `MR -> Skip` when BWISC unavailable), raising Task 08 suite coverage from 11 to 13 internal tests. Re-ran real-EA `/config` validation and copied durable evidence to `MQL5/Files/RPEA/test_results/task08_evidence/` (`decisions_20240102..20240105`, `real_ea_run_summary.json`, `rubric_counts.txt`, `journal_slo_snippet.txt`) for reproducible rubric checks 8-10. Validation: EA compile `0 errors, 5 warnings`; test-runner compile `0 errors, 6 warnings`; automated suites `35/35` pass with required `M7Task08_EndToEnd`.
- **M7 Task 08 (2026-02-09, complete)**: Added `Scheduler_IsMRPosition` + `Scheduler_CheckMRTimeStops` in `scheduler.mqh` (uses `PositionGetInteger(POSITION_TIME)`, anti-spam `Queue_FindIndexByTicketAction`, `OrderEngine_RequestProtectiveClose`, `MR_TIMESTOP` logging), wired SLO plumbing (`g_slo_metrics`, `SLO_OnInit`, `SLO_PeriodicCheck`, `SLO_IsMRThrottled`) into `slo_monitor.mqh`, `RPEA.mq5`, `scheduler.mqh`, and `meta_policy.mqh` (`SLO_MR_THROTTLED` gate), added runtime `EnableMR` test override in `config.mqh`, switched MR gate in `signals_mr.mqh` to `Config_GetEnableMR()`, added `test_m7_end_to_end.mqh` and registered `M7Task08_EndToEnd` in `run_automated_tests_ea.mq5`. Validation: EA compile `0 errors, 5 warnings`; test-runner compile `0 errors, 6 warnings`; suite results `35/35` passed (`M7Task08_EndToEnd` and `M7Task07_AllocatorMR` passing) via Strategy Tester `/config` fallback when `run_tests.ps1` stalled; real-EA tester run logged Scheduler `EVAL` and `[SLO] Metrics initialized`.
- **M7 Task 07 closeout (2026-02-08)**: Wired scheduler execution path (`OrderPlan` -> `OrderRequest` -> `g_order_engine.PlaceOrder`), added explicit skip/reject/place logging in `scheduler.mqh`, added allocator helpers `Allocator_ShouldMapProxyDistance` (prevents MR XAUEUR double-conversion) and `Allocator_ComputeBias` (MR directional bias), and extended `test_allocator_mr.mqh` with proxy-map and bias tests. Validation: EA compile `0 errors, 5 warnings`; Strategy Tester `34/34` passed including `M7Task07_AllocatorMR`.
- **M7 Task 07** (complete): Added `mr_context.mqh`, populated MR context in `signals_mr.mqh`, integrated MR strategy path in `allocator.mqh` (context selection, strategy-specific risk, MR setup type/comment format), enabled execution mode in `meta_policy.mqh` (`M7_DECISION_ONLY=0`), added `slo_monitor.mqh` stub, added `test_allocator_mr.mqh`, and wired `M7Task07_AllocatorMR` in `run_automated_tests_ea.mq5`. Validation: compile clean, tests `34/34` passed including `M7Task07_AllocatorMR`.
- **Ops Note (2026-02-07)**: During M7 Task 07 preflight, `run_tests.ps1` appeared stalled because the test runner had a compile blocker (`Tests/RPEA/run_automated_tests_ea.mq5` contained stray token at line 597). Added troubleshooting guidance in Build/Test commands: compile the test runner first, then use explicit `/config:` Strategy Tester invocation and verify latest tester-agent `test_results.json` when needed.
- **M7 Task 06** (complete): Added `Regime_Detect()` in `regime.mqh`, `LogMetaPolicyDecision()` in `telemetry.mqh`, rolling liquidity stats in `liquidity.mqh`, efficiency stubs in `meta_policy.mqh`, wired quantiles/regime into meta-policy, `Liquidity_UpdateStats` fed from scheduler + order engine. Tests: `test_regime_telemetry.mqh`.
- **M7 Task 05** (complete): Full `MetaPolicy_Choose()` with deterministic rules (Rules 0-6), `MetaPolicyContext` struct, bandit integration stub, `M7_DECISION_ONLY=1`. Tests: `test_meta_policy.mqh`.
- **M7 Task 04** (complete): `SignalsMR_Propose()` with EMRT+RL confidence, entry conditions, SL/TP calculation. Tests: `test_signals_mr.mqh`.
- **M7 Task 03** (complete): Pre-training script (`MQL5/Scripts/rl_pretrain.mq5`), Q-table file generation.
- **M7 Task 02** (complete): `rl_agent.mqh` - Q-learning table, state discretization, action policy. Tests: `test_rl_agent.mqh`.
- **M7 Task 01** (complete): `emrt.mqh` - EMRT formation, rank, P50, beta functions.
- **M7 Phase 0** (complete): Stubs, helpers (`m7_helpers.mqh`), ensemble inputs in `RPEA.mq5`.

### When Adding New Features

1. **Check the module table above** for file sizes and layer. Large modules need more care.
2. **Avoid circular includes**: Use lightweight context headers if module A needs types from module B but B already includes A's dependencies.
3. **Respect MicroMode**: All risk-sizing paths must check `Equity_IsMicroModeActive()`.
4. **After implementation**: Update this section -- bump "Last Updated", update changed module line counts, add entry to "Recent Changes".
5. **Test integration**: Verify signal -> allocator -> order engine flow. Set g_last contexts manually in tests.

## Current Baseline & Workflow
- Milestones M3-M6 complete (order engine, compliance, strategy tester, hardening).
- **M7 milestone status**: Tasks 01-08 complete. M7 core integration baseline is `feat/m7-ensemble-integration`.
- **FundingPips HPO stream**: Phase 0 is merged into `feat/hpo-pipeline`; the active branch is `feat/hpo-phase1-mt5-runner`, which contains the validated MT5 runner and is under review in PR `#48`. Do not cut Phase 2 until that PR is squash-merged and the baseline branch is updated locally.
- **Active execution stream**: Post-M7 TODO closure + hardening on `feat/m7-post-fixes`.
- **Post-M7 phase status**: Phase 0 baseline complete, Phase 1 data/policy complete, Phase 2 SLO realism complete, Phase 3 adaptive risk complete, Phase 4 learning+bandit complete, Phase 5 tuning+closeout complete.
- **Post-M7 source of truth**: `m7-post-fixes-plan.md`, `post-m7-task-index.md`, and `post-m7-task01.md` .. `post-m7-task17.md`.
- **Post-M7 task execution**: Run task docs in numeric order with per-task compile/test/evidence gates.
- **Post-M7 branch promotion model**:
  1. Complete and validate current phase branch.
  2. Merge current phase branch into `feat/m7-post-fixes`.
  3. Cut next phase branch from updated `feat/m7-post-fixes`.
  4. After Phase 5 closeout gates, merge `feat/m7-post-fixes` into `feat/m7-ensemble-integration`.

## Build, Test, and Development Commands

**Important**: Code is edited in the repo (`C:\Users\AWCS\earl-1`). Compiling must happen from the **MT5 data folder** because `/compile:` paths are relative to the working directory.

- **Sync repo to MT5**: `powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1` (run from repo root).
- **Compile EA** (from MT5 data folder):
  ```
  cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075" && "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
  ```
- **Run tests** (from repo root): `powershell -ExecutionPolicy Bypass -File run_tests.ps1` - launches Strategy Tester, writes results to `MQL5/Files/RPEA/test_results/test_results.json`.
- **FundingPips Phase 1 runner smoke test** (from repo root): `python tools\fundingpips_mt5_runner.py run --name phase1_probe --symbol EURUSD --from-date 2024.01.02 --to-date 2024.01.05 --stop-existing --force`
- Strategy Tester manual reruns: attach `Tests/RPEA/run_automated_tests_ea.mq5` to the tester to exercise suites such as `Task10_News_CSV_Fallback`.
- Troubleshooting `run_tests.ps1` stalls: first compile test runner separately (from MT5 data folder): `"C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\Tests\RPEA\run_automated_tests_ea.mq5 /log:MQL5\Experts\Tests\RPEA\compile_automated_tests.log`; if compile fails, fix runner before retrying tests.
- Fallback when script still stalls: run terminal with explicit config (`terminal64.exe /config:<ini>`) using `Expert=Tests\RPEA\run_automated_tests_ea`, `ExpertParameters=Tests\RPEA\run_automated_tests.set`, `ShutdownTerminal=1`; then verify latest tester-agent result at `%APPDATA%\MetaQuotes\Tester\...\Agent-*\MQL5\Files\RPEA\test_results\test_results.json`.

## Coding Style & Naming Conventions
- Use strict MQL5 mode, three-space indentation, and braces on new lines to match existing `.mq5/.mqh` files.
- Types use `PascalCase`; functions follow `Module_Action` (e.g., `News_ForceReload`); constants/macros are ALL_CAPS.
- Avoid wildcard includes. Reference modules explicitly via `<RPEA/...>` and keep helpers in `MQL5/Include/RPEA`.
- No `static` variables; prefer `CArrayObj` over STL; favor early returns and explicit types.

## Testing Guidelines
- Add new unit suites under `Tests/RPEA/test_*.mqh`, following `Scenario_Action_Expectation` naming.
- Mirror fixture changes between `Tests/RPEA/fixtures/news` and `Files/RPEA/news/calendar_high_impact.csv`.
- Always rerun `powershell -ExecutionPolicy Bypass -File run_tests.ps1` before submitting; include the updated JSON or key log excerpts when relevant. The runner includes Phase 5 suites (breakeven, pending expiry) by default.

## Commit & Pull Request Guidelines
- Preferred messages mirror `M3: Task <id> - summary`, `M4: Task <id> - summary`, `M5: Task <id> - summary`, `M6: Task <id> - summary`, or `M7: Task <id> - summary`, or use concise imperatives aligned with the workstream.
- Develop on task/phase branches (e.g., `feat/m3-task24` -> `feat/m3-phase5-optimization` -> `feat/m3-order-engine`). For M4 compliance polish, use `feat/m4-taskXX` -> optional `feat/m4-phaseY` -> base `feat/m4-compliance-polish` (or the current M4 base branch). For M5 Strategy Tester artifacts, use `feat/m5-taskXX` -> base `feat/m5-strategy-tester`. For M6 hardening, use `feat/m6-taskXX` -> base `feat/m6-hardening`. For M7, follow `docs/m7-final-workflow.md` phase branches (e.g., `feat/m7-phase0-scaffold` -> `feat/m7-phase1-foundation` -> `feat/m7-ensemble-integration`).
- Pull requests should summarize scope, link supporting docs (e.g., `task10.md`), and attach the latest automated test outcome or relevant compile logs.

## Agent-Specific Notes
- Respect existing worktree changes; never revert user edits unless asked.
- Use `rg` for search and keep edits ASCII unless the file already uses other encodings.
- Validate queueing, synthetic pricing, and risk behaviors against `.kiro/specs/rpea-m3/{tasks.md, design.md, requirements.md}` whenever updating those systems.
- Git Status Commands: When checking git status for task work, use PowerShell in the repo root (not WSL) and run `git status --short` (without filtering) to see all changes including both untracked (`??`) and modified (`M`) files. This ensures you see both new untracked task files (e.g., `m6-task01.md`) and any files modified during the current work session (e.g., `AGENTS.md`). When reporting or focusing, prioritize untracked milestone task markdown files (`m[0-9]-task*.md`), but do not filter out modified files entirely as they may include important changes made during the task. To see only untracked task files, use `git status --short | Select-String \"^\\?\\?.*m[0-9]-task\"`.
