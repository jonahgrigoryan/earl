# Profitability Synthesis Reset

## Purpose

This note is the deliberate reset point after the narrow-branch search sequence driven by [PLAN_main.md](C:/Users/AWCS/earl-1/docs/plans/PLAN_main.md). It records what was tried, what was proved, what remains the best known baseline, and which paths are now closed.

Use this document before opening any new profitability branch or handing the repo to a stronger research tool.

## Current Baselines

### Official Research Truth

- Pinned research truth remains `master@d0e5558`.
- Accepted champion path remains `arch_mr_deterministic -> threshold_003 -> baseline_artifacts__ql_enabled`.
- Primary deciding dataset remains the official holdout:
  `.tmp/fundingpips_official_validation/master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c/`.
- Secondary corroboration remains the contiguous official public-rule3 validation:
  `.tmp/fundingpips_official_validation/master_phase5_champion_contiguous_public_rule3_20250603_20251031__e2ac77d835c79480/`.

### Local Working Baseline

- The current local research/tooling code baseline remains `f979370`.
- `origin/master` is still `d0e5558`.
- Local `master` therefore contains merged diagnostics/tooling on top of the official promoted baseline but **no merged trading-behavior winner** beyond the original champion.
- The merged local code commits are:
  - `76f4b92` `FundingPips: add Phase A artifact-first research pipeline`
  - `a846229` `FundingPips: add wf003 spread coverage diagnostic`
  - `f9c2fb5` `FundingPips: add RL EMRT sizing diagnostic`
  - `1442efe` `FundingPips: add XAUUSD MR floor sensitivity diagnostic`
  - `f979370` `FundingPips: add XAUUSD MR floor precision telemetry`

### Preserved No-Go Branches

These branches are preserved as evidence and should remain unmerged:

- `codex/mr-timestop-validation-search` at `d339237`
- `codex/mr-confidence-validation-search` at `9571465`
- `codex/spread-liquidity-validation-search` at `58d0277`
- `codex/session-or-timing-validation-search` at `4b458c8`
- `codex/mr-threshold-validation-search` at `336799f`
- `codex/mr-emrt-weight-validation-search` at `e42e58a`
- `codex/xauusd-mr-floor-narrow-rescue-validation` at `2fd281e`

## What Was Tried

### Merged Diagnostic / Tooling Work

- `76f4b92` Phase A research pipeline:
  - Reconstructed `research_candidates`, `research_gate_intervals`, `research_trades`, and `research_daily`.
  - Reconciled holdout exactly to `107` trades and `+$78.61`.
  - Established top-ranked candidate lever classes from pinned artifacts.

- `a846229` `wf003` spread coverage diagnostic:
  - Proved the spread-tightening failure was not mainly direct policy gating.
  - Showed the core blocker was plan-stage `volume_zero` on baseline XAUUSD opportunities.

- `f9c2fb5` RL-vs-EMRT sizing diagnostic:
  - Corrected a saved report-reference mismatch in the prior `MR_EMRTWeight` interpretation.
  - Showed the live lever mostly caused XAUUSD min-lot churn rather than a durable new edge.

- `1442efe` XAUUSD floor sensitivity diagnostic:
  - Proved the destructive floor issue was real but localized, not universal.
  - Concentrated the failure in `wf003_202510`, `LO+NY`, `VOLATILE`, around ~`6101`-point stops.

- `f979370` XAUUSD floor precision telemetry:
  - Added 8-decimal sizing diagnostics and sub-cause classification without changing runtime behavior.
  - Proved the known `wf003` failure slice consisted of `25` rows, all `below_min_after_step`, all exactly `1.083815%` below `0.01` lots.

### No-Go Behavior Branches

- `d339237` MR time-stop search:
  - `75/90` and `75/105` windows did not produce a promotable winner.
  - One variant hurt moderate stress; the other improved holdout but failed robustness and coverage.

- `9571465` MR confidence-cut search:
  - Narrow `MR_ConfCut` thresholds degraded holdout sharply.
  - This closed the simple confidence-cut path.

- `58d0277` spread/liquidity tightening:
  - Tighter `SpreadMultATR` candidates created a `wf003_202510` coverage cliff.
  - This did not close the whole spread story immediately, but it ruled out that direct tightening path.

- `4b458c8` session/OR timing trim:
  - Narrow `CutoffHour` variants did not survive holdout plus report-window moderation.
  - This closed the simple session-trim path.

- `336799f` fast-threshold search:
  - `EMRT_FastThresholdPct` at `90`, `95`, and `100` was behaviorally inert in the tested neighborhood.
  - This closed that knob as a useful next search direction.

- `e42e58a` `MR_EMRTWeight` validation:
  - The lever was live, but the saved regression interpretation was later corrected by `f9c2fb5`.
  - Even after correction, the path remained fragile and low-signal, not a clear winner.

- `2fd281e` XAUUSD narrow floor rescue:
  - The rescue rule was implemented correctly and validated end to end.
  - It stayed within MR/XAUUSD/`below_min_after_step` gating, but the runtime-eligible rescue population was too broad:
    - `<=1.25%` rescue touched `181` rows in `wf003`, or `7.24x` the proven `25`-row slice.
    - `<=2.00%` rescue touched `314` rows in `wf003`, or `12.56x` the proven slice.
  - This closes the XAUUSD MR floor-rescue path.

## What Was Proved

### Stable Facts

- The accepted champion path did not change.
- The official holdout baseline is still weak but compliant:
  - `+0.7861%`
  - `107` trades
  - `55` trade days
  - no daily or overall breach
- The official holdout moderate-stress baseline remains slightly negative, which is why profitability work remained justified.

### Proven Negative Results

- The simple time-stop, confidence-cut, spread-tightening, session-trim, fast-threshold, scalar confidence-mix, and narrow XAUUSD floor-rescue paths did **not** produce a promotable improvement.
- Several of those levers were not just weak; they were either:
  - inert,
  - coverage-damaging,
  - robustness-damaging,
  - or broader in runtime effect than the underlying historical slice they were meant to fix.

### Proven Diagnostic Insights

- The MR book is heavily time-stop dominated, but broadening the time-stop window did not survive validation.
- The earlier `MR_EMRTWeight` "report regression" was partly a stale-reference artifact, but the corrected same-stack comparison still showed fragility rather than a clean edge.
- XAUUSD floor sensitivity is real.
- The narrow historical `wf003` failure slice was measured precisely.
- Even with that precision, the runtime-identifiable rescue rule widened beyond the truly proven slice.

## Best Baseline Stands

### Trading Baseline

- The best known trading baseline still remains the original promoted champion behavior pinned at `master@d0e5558`.
- No behavior-changing branch tested after that has produced a verified promotable winner.

### Working Repo Baseline

- Current local `master@f979370` is still the best working repo baseline because it contains the artifact-first research and the merged diagnostics needed to support future investigation.
- It is a better **research** baseline than `d0e5558`, but not a better **trading winner**.

## Closed Paths

The following paths should be treated as closed unless a future architecture-level thesis reopens them for a materially different reason:

- MR time-stop widening
- MR confidence-cut tightening
- spread/liquidity tightening
- session/OR cutoff trimming
- `EMRT_FastThresholdPct` micro-search
- scalar `MR_EMRTWeight` confidence-mix tweaking
- XAUUSD MR narrow floor rescue

## What Is Still Open

Only materially different ideas remain open.

That means:

- no more adjacent scalar tweaks around already rejected knobs
- no more nearby XAUUSD rescue-threshold variants
- no more blind branch-by-branch continuation of the same search style

If new work continues, it should start from a new architecture-level or policy-level hypothesis that explains profitability weakness better than the exhausted one-knob search sequence did.

## Recommended Reset Decision

Before any new implementation branch:

1. Treat `f979370` as the current local research/tooling baseline.
2. Treat `d0e5558` official validation artifacts as the deciding performance truth.
3. Treat the no-go branches as preserved evidence, not candidates for merge.
4. Use a stronger research workflow to propose materially different hypotheses.

## Inputs For The Next Research Cycle

Minimum source set:

- [PLAN_main.md](C:/Users/AWCS/earl-1/docs/plans/PLAN_main.md)
- [PLAN_synthesis_reset.md](C:/Users/AWCS/earl-1/docs/plans/PLAN_synthesis_reset.md)
- `.tmp/fundingpips_phase_a_research/master_d0e5558_phase_a/`
- `.tmp/fundingpips_official_validation/master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c/`
- `.tmp/fundingpips_official_validation/master_phase5_champion_contiguous_public_rule3_20250603_20251031__e2ac77d835c79480/`
- `.tmp/fundingpips_wf003_spread_coverage_diagnostic/phasea_wf003_spread_coverage/`
- `.tmp/fundingpips_rl_emrt_sizing_diagnostic/phasea_rl_emrt_sizing/`
- `.tmp/fundingpips_xauusd_mr_floor_sensitivity_diagnostic/phasea_xauusd_mr_floor_sensitivity/`
- `.tmp/fundingpips_xauusd_mr_floor_precision_telemetry/phasea_xauusd_mr_floor_precision_telemetry/`
- `.tmp/fundingpips_xauusd_mr_floor_narrow_rescue_validation/phasea_xauusd_mr_floor_narrow_rescue_validation/`

The next research consumer should assume:

- the current local master contains useful merged diagnostics
- the official holdout remains the deciding dataset
- the dead ends above are real and should not be rediscovered from scratch
