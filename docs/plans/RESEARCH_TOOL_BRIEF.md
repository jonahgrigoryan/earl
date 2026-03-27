# Advanced Research Tool Brief

## Goal

Identify the next **materially different** change that could improve FundingPips profitability for RPEA without sacrificing pass reliability.

This brief is for a stronger research workflow, not for immediate coding. It should begin from the proven baseline and the exhausted-path evidence already recorded in the repo.

## Repo State To Assume

- Official deciding performance truth is pinned to `master@d0e5558`.
- The current local research/tooling code baseline is `f979370`.
- Local `master` contains merged artifact-first diagnostics/tooling plus any later docs-only reset metadata, but no new promoted trading-behavior winner.
- The narrow XAUUSD floor rescue branch was validated as a no-go and remains unmerged on `codex/xauusd-mr-floor-narrow-rescue-validation` at `2fd281e`.

## Must-Read Inputs

Read these first:

- [PLAN_main.md](C:/Users/AWCS/earl-1/docs/plans/PLAN_main.md)
- [PLAN_synthesis_reset.md](C:/Users/AWCS/earl-1/docs/plans/PLAN_synthesis_reset.md)
- `.tmp/fundingpips_phase_a_research/master_d0e5558_phase_a/research_attribution_summary.json`
- `.tmp/fundingpips_phase_a_research/master_d0e5558_phase_a/research_change_rankings.md`
- `.tmp/fundingpips_official_validation/master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c/collected/fundingpips_eval_summary.json`
- `.tmp/fundingpips_official_validation/master_phase5_holdout_rule3_20251101_20260228_stress_summary.json`
- `.tmp/fundingpips_official_validation/master_phase5_champion_contiguous_public_rule3_20250603_20251031__e2ac77d835c79480/collected/fundingpips_eval_summary.json`
- `.tmp/fundingpips_wf003_spread_coverage_diagnostic/phasea_wf003_spread_coverage/diagnostic_summary.json`
- `.tmp/fundingpips_rl_emrt_sizing_diagnostic/phasea_rl_emrt_sizing/diagnostic_summary.json`
- `.tmp/fundingpips_xauusd_mr_floor_sensitivity_diagnostic/phasea_xauusd_mr_floor_sensitivity/diagnostic_summary.json`
- `.tmp/fundingpips_xauusd_mr_floor_precision_telemetry/phasea_xauusd_mr_floor_precision_telemetry/precision_telemetry_summary.json`
- `.tmp/fundingpips_xauusd_mr_floor_narrow_rescue_validation/phasea_xauusd_mr_floor_narrow_rescue_validation/narrow_rescue_summary.json`

## Do Not Re-Suggest As "Next Step"

These paths are already exhausted in their narrow form:

- MR time-stop widening
- MR confidence-cut tightening
- spread/liquidity tightening
- session/OR cutoff trimming
- `EMRT_FastThresholdPct` micro-search
- scalar `MR_EMRTWeight` tweaking
- XAUUSD MR narrow floor rescue

You may only revisit one of those areas if you can show it is part of a **materially different architecture-level thesis**, not just another nearby parameter move.

## Questions To Answer

1. Given the exhausted one-knob paths, what materially different hypotheses remain plausible?
2. What is the most likely root cause of weak profitability now that direct time-stop, spread, confidence, threshold, and floor-rescue tweaks have failed?
3. Is the limiting factor more likely:
   - strategy mix,
   - entry geometry,
   - stop geometry,
   - position-cap interaction,
   - XAUUSD-specific contract behavior,
   - regime/session interaction,
   - or something else not yet isolated?
4. What is the smallest new experiment family that would falsify the best remaining hypothesis quickly?
5. Should work stop with current `master` as the best known baseline, or is there still a justified architecture-level next move?

## Constraints

- FundingPips pass reliability stays first.
- The official holdout remains the deciding dataset.
- Contiguous public-rule3 remains corroboration, not the deciding dataset.
- Broad HPO is out of scope until a new concrete hypothesis exists.
- Any proposed next experiment should be small, discriminative, and architecture-aware.

## Desired Output

Produce:

- a ranked list of remaining plausible hypotheses
- a short explanation of why each previously tried path failed
- one recommended next initiative, or a recommendation to stop
- if continuing, a minimal validation matrix
- explicit stop criteria that prevent another long sequence of adjacent micro-branches

## Copy-Ready Prompt

```md
You are reviewing a FundingPips profitability research repo for an MT5 EA.

Use these as source of truth:
- `docs/plans/PLAN_main.md`
- `docs/plans/PLAN_synthesis_reset.md`
- the official holdout and contiguous public-rule3 artifacts under `.tmp/fundingpips_official_validation/`
- the merged diagnostics under:
  - `.tmp/fundingpips_phase_a_research/master_d0e5558_phase_a/`
  - `.tmp/fundingpips_wf003_spread_coverage_diagnostic/phasea_wf003_spread_coverage/`
  - `.tmp/fundingpips_rl_emrt_sizing_diagnostic/phasea_rl_emrt_sizing/`
  - `.tmp/fundingpips_xauusd_mr_floor_sensitivity_diagnostic/phasea_xauusd_mr_floor_sensitivity/`
  - `.tmp/fundingpips_xauusd_mr_floor_precision_telemetry/phasea_xauusd_mr_floor_precision_telemetry/`
  - `.tmp/fundingpips_xauusd_mr_floor_narrow_rescue_validation/phasea_xauusd_mr_floor_narrow_rescue_validation/`

Important baseline distinction:
- official deciding performance truth is pinned to `master@d0e5558`
- the local research/tooling code baseline is `f979370`, with only docs/reset metadata expected above it on `master`

Do not re-suggest these exhausted paths unless you can justify a materially different architecture-level thesis:
- MR time-stop widening
- MR confidence-cut tightening
- spread/liquidity tightening
- session/OR cutoff trimming
- fast-threshold micro-search
- scalar `MR_EMRTWeight`
- XAUUSD MR narrow floor rescue

Your task:
1. Synthesize the current evidence.
2. Explain the most likely remaining root causes of weak profitability.
3. Propose the single best next initiative, or explicitly recommend stopping with current baseline.
4. If you recommend continuing, give a minimal validation plan and explain why it is materially different from the exhausted paths.

Optimize for:
- FundingPips pass reliability first
- high-signal evidence use
- avoiding repeated nearby experiments
- concrete, falsifiable next moves
```
