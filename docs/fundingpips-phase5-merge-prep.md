# FundingPips Phase 5 Merge Prep

Date: 2026-03-17

Status: ready for review, not merged

## Required Closures

Bandit frozen scope:

- `arch_mr_bandit_frozen` is intentionally deferred
- `15` rows were blocked
- only failure reason: `bandit_snapshot_not_ready`
- no bandit-ready snapshot path was staged for this acceptance pass
- merge acceptance does not claim any validated frozen-bandit performance

Stage 3 scope:

- confirmed intentional
- `phase5_manifest.json` records `stage3_artifact_candidate_ids` as `[]`
- the study therefore compared only the inherited baseline RL artifacts under:
  - `ql_enabled`
  - `ql_disabled`

## Champion Summary

Accepted path:

1. `stage1__arch_mr_deterministic`
2. `stage2__threshold_003`
3. `stage3__baseline_artifacts__ql_enabled`

Champion metrics:

- report objective mean: `52.34879085833333`
- objective min: `48.628524612499994`
- robustness: `no_breach=true`, `no_zero_trade=true`, mild/moderate report non-collapse true

Stage 3 enabled vs disabled:

- enabled: `52.34879085833333` mean, `48.628524612499994` min, no zero-trade windows
- disabled: `30.03640387916667` mean, `20.0` min, zero-trade in `wf001_202508` and `wf003_202510`

## Locked Artifacts

- phase5 summary: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\phase5_summary.json`
- phase5 rows: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\phase5_run_rows.jsonl`
- phase5 manifest: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\phase5_manifest.json`
- final lock: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\phase5_final_lock.json`
- completion note: `C:\Users\AWCS\earl-1\docs\fundingpips-phase5-completion-note.md`

Baseline / runtime artifact ids:

- baseline bundle: `baseline_bundle_53fb4b67246a`
- qtable: `qtable_30a624d3fc6a`
- thresholds: `thresholds_565e78dc7fa8`
- bandit snapshot: `bandit_snapshot_44136fa355b3`

## Validation State

No fresh full MT5 quality pass is required before merge preparation under the requested rule.

Reason:

- the last code changes were already validated
- after that point, only documentation and lock artifacts changed

Last successful validation covering code changes:

- `python -m py_compile tools\fundingpips_mt5_runner.py Tests\python\test_fundingpips_mt5_runner.py tools\fundingpips_phase5.py Tests\python\test_fundingpips_phase5.py`
- `python -m unittest Tests.python.test_fundingpips_mt5_runner Tests.python.test_fundingpips_phase5`
- successful real Stage 3 rerun across `wf001_202508`, `wf002_202509`, and `wf003_202510`

## Approval Boundary

Merge has not been performed.

Next step after your approval:

- prepare the branch for merge/review using the locked Phase 5 artifacts and champion rationale above
