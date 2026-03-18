# FundingPips HPO Implementation Outline

## Purpose

This document is the canonical end-to-end implementation outline for the FundingPips profitability workstream.
It replaces the rough planning note previously kept in `## 0) FundingPips 1-Step rule.md`.

The goal is not to maximize raw backtest profit. The goal is to make the EA produce rule-compliant, robustly profitable behavior for the FundingPips 1-Step evaluation and then carry that into a safer funded profile.

## Primary Objective

Build a staged optimization pipeline that can:

- measure FundingPips-style pass and failure conditions correctly
- run repeatable MT5 backtests headlessly
- score parameter sets against rule-constrained pass probability, not raw return alone
- detect overfitting, fragility, and regime dependence before deployment
- stage more complex MR / ensemble / Q-learning components only after the deterministic base is validated

## Source Of Truth For Rules

Do not trust public FundingPips pages blindly. Public sources conflict.

For implementation and optimization, the source of truth must be the purchased FundingPips dashboard for the active account:

- profit target
- max daily loss
- max overall loss
- minimum trading days
- daily reset clock
- leverage
- evaluation vs funded news restrictions

For the implemented repo tooling, use the current repo rule profile as the working source of truth until the purchased dashboard proves otherwise:

- target: `10%`
- max daily loss: `4%`
- max overall loss: `6%`
- minimum trading days: `3`
- daily loss baseline: higher of balance or equity at reset
- overall DD: assume static unless dashboard proves otherwise

If the dashboard later differs, update the checked-in rules profile and study specs rather than hand-editing scoring logic.

## Core Principles

1. Measurement before tuning.
The EA must report the right pass/fail and drawdown behavior before any optimization is trusted.

2. Constraint-first optimization.
Hard breaches are knockouts, not soft penalties.

3. Phased delivery.
Each phase should leave behind a stable, reviewable checkpoint.

4. Deterministic v0 first.
Q-learning and similar path-dependent components stay off until the base system proves itself.

5. Robustness over headline PnL.
A candidate that survives rolling windows, stress scenarios, and neighbor checks is more valuable than the single best curve-fit result.

## Branch Topology

This repo uses `master`, not `main`.

Use one baseline branch as the integration spine, then short-lived phase branches off that spine.

### Baseline branch

- `feat/hpo-pipeline`

### Phase branches

- `feat/hpo-phase0-metrics-exports`
- `feat/hpo-phase1-mt5-runner`
- `feat/hpo-phase2-objective-windows`
- `feat/hpo-phase3-optuna-search`
- `feat/hpo-phase4-wfo-stress`
- `codex/hpo-phase5-mr-ql-staging`

The Phase 5 branch used the `codex/` prefix in practice to satisfy the local Codex app branch-prefix rule.

### Branch flow

1. Create `feat/hpo-pipeline` from `master`.
2. Cut Phase 0 from `feat/hpo-pipeline`.
3. Merge Phase 0 back into `feat/hpo-pipeline`.
4. Cut Phase 1 from the updated `feat/hpo-pipeline`.
5. Repeat until v0 is complete.
6. Bank v0 into `master`.
7. If needed, cut a new robust baseline for v1 from updated `master`.

## Delivery Model

### v0

v0 is the minimum viable optimization system. It covers Phases 0 through 2:

- correct evaluator metrics
- Python-driven MT5 single-run orchestration
- rolling-window scoring and a small end-to-end study

v0 should be banked early if it works.

### v1

v1 adds heavier robustness and architecture work:

- parameter reduction
- walk-forward evaluation
- stress harness
- staged MR / ensemble / Q-learning evaluation

## Current Execution Status

As of `2026-03-17`, Phases 0-5 are complete through Phase 5 winner selection and merge-prep packaging on `codex/hpo-phase5-mr-ql-staging`.

Key execution outcomes:

- Phase 4 was promoted as the HPO baseline via commit `d07f1db`, keeping `anchor_mr100` as the carried-forward representative.
- Phase 5 added a dedicated harness and runtime artifact/mode controls:
  - `tools/fundingpips_phase5.py`
  - `tools/fundingpips_studies/phase5_anchor_pipeline.json`
  - explicit runtime `QLMode`, qtable/threshold path overrides, and bandit state/snapshot controls in the EA
  - baseline bundle generation plus study-root `phase5_manifest.json`, `phase5_summary.json`, and `phase5_run_rows.jsonl`
- Final Phase 5 study totals under `.tmp/fundingpips_phase5/phase5_anchor_pipeline/`:
  - `795` total rows
  - `780` valid rows
  - `15` blocked rows, all `bandit_snapshot_not_ready`
- Stage 1 winner: `stage1__arch_mr_deterministic`
- Stage 2 winner: `stage2__threshold_003`
  - accepted threshold diffs versus the Phase 4 anchor:
    - `EMRT_FastThresholdPct: 100 -> 95`
    - `MR_TimeStopMin: 60 -> 75`
- Stage 3 winner: `stage3__baseline_artifacts__ql_enabled`
  - Stage 3 scope was intentionally limited to the inherited baseline artifacts because `phase5_manifest.json` records no additional Stage 3 artifact candidates
  - `ql_enabled` preserved the Stage 2 profile at report objective mean `52.34879085833333`, worst report window `48.628524612499994`, `no_breach=true`, `no_zero_trade=true`
  - `ql_disabled` degraded to mean objective `30.03640387916667` and zero-traded in `wf001_202508` and `wf003_202510`
- Final locked artifact contract:
  - baseline bundle `baseline_bundle_53fb4b67246a`
  - qtable `qtable_30a624d3fc6a`
  - thresholds `thresholds_565e78dc7fa8`
  - bandit snapshot `bandit_snapshot_44136fa355b3` with `ready=false` and `BanditStateMode=disabled`
- Merge-prep outputs now exist:
  - `.tmp/fundingpips_phase5/phase5_anchor_pipeline/phase5_final_lock.json`
  - `docs/fundingpips-phase5-completion-note.md`
  - `docs/fundingpips-phase5-merge-prep.md`

Phase 5 is complete for the planned scope. The remaining unresolved item is intentionally deferred scope, not unfinished implementation: the frozen-bandit arm was never accepted because no bandit-ready posterior snapshot was staged for that branch.

## Implementation Phases

## Phase 0: FundingPips Metrics Export

### Goal

Make each tester run produce deterministic, machine-readable evaluation metrics aligned with FundingPips rules.

### Why this phase is first

MT5 built-in statistics are not enough. FundingPips-style daily drawdown depends on the daily reset baseline, especially the higher-of-balance/equity rule.

Without this phase, optimization results are not trustworthy.

### Deliverables

- deterministic per-run JSON and/or CSV artifact
- pass flag
- day or trading day when target was first reached
- minimum trading days met flag
- max daily drawdown percent
- max overall drawdown percent
- daily and overall breach flags
- reset-time baseline tracking per day
- daily max loss usage per day
- trade counts total and per day
- account-path summaries needed for later scoring

### Likely code areas

- `MQL5/Experts/FundingPips/RPEA.mq5`
- `MQL5/Include/RPEA/equity_guardian.mqh`
- `MQL5/Include/RPEA/telemetry.mqh`
- `MQL5/Include/RPEA/logging.mqh`
- `MQL5/Include/RPEA/config.mqh`
- tests under `Tests/RPEA`

### Merge gate

- EA compiles cleanly
- automated tests pass
- at least one controlled Strategy Tester run emits the artifact reliably
- artifact fields are sufficient for downstream scoring

## Phase 1: Python MT5 Runner

### Goal

Build a repeatable runner that launches MT5 backtests programmatically and collects artifacts into a structured output tree.

### Deliverables

- generated `.ini` files for tester runs
- generated `.set` files for parameterized runs
- headless or portable MT5 launch flow
- structured run folder per backtest
- parameter hash and scenario-aware caching
- deterministic artifact collection after terminal exit

### Required behavior

- support repeatable single backtests first
- preserve exact run inputs for reproducibility
- cache by params + date window + scenario + rules profile + MT5 build + data signature

### Merge gate

- can launch and complete 10 to 20 single backtests automatically
- outputs are collected without manual intervention
- rerunning the same input resolves to the same cache identity

## Phase 2: Objective, Windows, And Baseline Study

### Goal

Define the optimization target correctly and prove an end-to-end baseline study works.

### Deliverables

- rolling 10-trading-day window generator
- baseline and stressed scenario definitions
- pass-probability scoring function
- deterministic aggregation across windows
- small Optuna study running end-to-end
- study resume support

### Recommended scoring shape

Use a constraint-first or pass-probability objective, not raw return maximization.

Reward:

- pass without breaches
- slack versus daily and overall loss limits
- fewer days to target

Penalize:

- any hard breach
- too many or too few trades
- reset exposure
- stress fragility

### Merge gate

- the same seed reproduces the same study path and outcome
- a stopped study can resume
- artifacts and trial table are usable for later screening

## Phase 3: Parameter Reduction And Conditional Search

### Goal

Shrink the search space before heavy optimization and model the hierarchy explicitly.

### Deliverables

- locked parameter set for non-alpha plumbing and safety
- architecture ablations
- cheap broad screening
- parameter importance analysis
- conditional search space definition
- reduced optimized core set

### Parameter policy

#### Lock

- rule mirrors
- timezone and reset alignment
- leverage overrides
- most resilience and plumbing knobs
- profiling and housekeeping knobs

#### Optimize

- core behavioral risk and trade management parameters
- session and symbol participation choices
- limited MR / ensemble thresholds after base proof
- only the highest-impact veto or anomaly thresholds

#### Conditional only

- MR child parameters only if MR is enabled
- Q-learning parameters only if Q-learning remains enabled at all

### Merge gate

- a reduced core set is documented and justified
- architecture branches that fail robustness are excluded
- search space is clean enough for meaningful optimization

## Phase 4: Walk-Forward And Stress Harness

### Goal

Prove that top candidates survive realistic variation in time, friction, and nearby parameter values.

### Deliverables

- walk-forward protocol across monthly rolls
- overlapping search windows and non-overlapping final report windows
- stress scenarios for spread, slippage, delay, and commission
- parameter neighbor checks
- regime-tagged reporting

### Stress examples

- EURUSD spread: `+25%`, `+50%`
- XAUUSD spread: `+25%`, `+50%`, `+100%`
- execution delay buckets such as `100ms`, `250ms`, `500ms`
- commission increase: `+25%`, `+50%`
- gap and Friday carry sensitivity

### Merge gate

- top candidates remain acceptable under mild and moderate stress
- neighbor perturbations degrade smoothly instead of collapsing
- walk-forward results are stable enough to rank candidates rationally

## Phase 5: MR, Ensemble, And Q-Learning Staging

### Goal

Introduce complex architecture choices in a controlled order so they earn their place instead of overfitting into the pipeline.

### Completed outcome

Phase 5 is now complete and locked.

- Architecture winner: deterministic MR-on with bandit disabled
- Threshold winner: `stage2__threshold_003`
- Stage 3 winner: `stage3__baseline_artifacts__ql_enabled`
- Accepted behavior diffs from the promoted Phase 4 anchor:
  - `EMRT_FastThresholdPct` reduced from `100` to `95`
  - `MR_TimeStopMin` increased from `60` to `75`
  - RL stays enabled using the inherited baseline qtable and thresholds artifacts
  - frozen bandit remains excluded because the staged snapshot is not ready
- Stage 3 scope confirmation: baseline artifacts only, `ql_enabled` versus `ql_disabled`

### Sequence

1. Architecture ablation with coarse toggles only.
2. Threshold tuning for the selected architecture.
3. Q-learning hyperparameter tuning last, only if still justified.

### Acceptance standard

Complexity stays only if it improves:

- out-of-sample pass score
- lower-tail robustness
- stress resilience
- stability across seeds and nearby settings

If Q-learning fails that standard, it stays fixed or off for the evaluation profile.

### Merge gate

- each complexity layer is justified against a simpler baseline
- Q-learning on/off comparisons exist under matched conditions
- the final profile is explainable and not dependent on one lucky path

Outcome: satisfied for the planned Phase 5 scope. The only excluded arm is the intentionally deferred frozen-bandit branch.

## Optimization Framework

### Recommended architecture

- Python orchestrator as the source of truth
- MT5 single-run backtests as the evaluation engine
- Optuna TPE for the main mixed conditional search
- CMA-ES only later for small continuous subproblems
- NSGA-II or NSGA-III only for final frontier selection if multi-objective selection is needed
- MT5 genetic optimization only for narrow subproblems where it is genuinely faster and simpler

### Why this is preferred

MT5 is strong as a backtest engine but awkward for conditional spaces and multi-window orchestration. External orchestration is cleaner and more reproducible for this workflow.

## Data And Artifact Design

### Minimum per-run artifact fields

- `trial_id`
- `params_hash`
- `window_id`
- `scenario_id`
- `rules_profile_id`
- `from_date`
- `to_date`
- `pass`
- `day_of_target_hit`
- `minimum_trading_days_met`
- `max_daily_dd_pct`
- `max_overall_dd_pct`
- `daily_breach`
- `overall_breach`
- `daily_reset_baselines`
- `daily_max_loss_usage`
- `trades_total`
- `trades_per_day`
- `profit_factor`
- `recovery_factor`
- `sharpe`
- `min_margin_level`
- component usage counts such as MR gates, anomaly vetoes, QL overrides

### Storage model

- raw run artifact per run in JSON
- aggregate trial table in SQLite or Parquet
- preserve `.ini` and `.set` inputs per run
- keep enough metadata to reproduce the run exactly

## Validation Framework

Every phase must leave behind a concrete validation record.

### Minimum validation types

- EA compile
- relevant script compile where needed
- automated test suite pass
- at least one targeted tester run or study proving the new phase works

### Preferred evidence

- log path
- report path
- output artifact path
- branch name
- commit hash
- short summary of result

## Overfitting Defenses

Use these throughout the pipeline, not just at the end:

- rolling 10-trading-day windows
- non-overlapping holdout reporting
- regime tagging
- spread/slippage/delay stress
- neighbor perturbation checks
- cluster selection instead of selecting the single top trial
- architecture simplification bias

## Common Failure Modes

1. Curve fit peak instead of plateau.
2. Regime-specific success only.
3. Spread or slippage fragility.
4. Too few trades to trust the sample.
5. One lucky evaluation window dominating the result.
6. Reset-time blindness causing false confidence.
7. Q-learning instability across seeds or training episodes.
8. Cross-symbol correlation spikes destroying diversification.
9. Compliance leakage around news or grouped trade risk.

## First, Next, Last

### Do first

1. Confirm the live FundingPips dashboard rules.
2. Implement Phase 0 metrics export.
3. Freeze the lock set and define:
   - `evaluation_profile`
   - `funded_safe_profile`

### Do next

4. Keep Q-learning off for v0 unless proven necessary.
5. Build the Python MT5 runner.
6. Implement rolling-window scoring and baseline Optuna orchestration.
7. Reduce the search space before broader optimization.

### Do last

8. Stress test the strongest candidates.
9. Run walk-forward verification.
10. Promote only a stable cluster solution and keep one fallback set.
11. Build the funded-safe profile after the evaluation profile is proven.

## Current Status

- Phase 0 is complete and squash-merged into `feat/hpo-pipeline`.
- Phase 1 is complete and provides the MT5 runner/library base used by Phase 2.
- Phase 2, Phase 3, and Phase 4 are complete and promoted into the current Phase 5 baseline.
- Phase 5 is complete locally on `codex/hpo-phase5-mr-ql-staging`.
- The accepted evaluation profile after Phase 5 is:
  - architecture: deterministic MR-on with bandit disabled
  - thresholds: `EMRT_FastThresholdPct=95`, `MR_TimeStopMin=75`
  - RL runtime mode: enabled with the inherited baseline artifacts
- Final Phase 5 lock and review artifacts:
  - `.tmp/fundingpips_phase5/phase5_anchor_pipeline/phase5_final_lock.json`
  - `docs/fundingpips-phase5-completion-note.md`
  - `docs/fundingpips-phase5-merge-prep.md`
- Next execution step: merge/review preparation only. Do not rerun or merge unless reproducibility is newly required or user approval is explicitly given.

Use `docs/fundingpips-hpo-handoff.md` as the session-by-session execution tracker.
