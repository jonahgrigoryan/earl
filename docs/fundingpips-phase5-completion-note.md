# FundingPips Phase 5 Completion Note

Date: 2026-03-17

## Verification

The prompt summary matches the live study in `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline`:

- `795` total rows
- `780` valid/completed rows
- `15` blocked rows
- only rejection reason: `bandit_snapshot_not_ready`
- Stage 1, Stage 2, and Stage 3 are all populated in `phase5_summary.json`

One nuance: the overall best row in the summary still points at `stage2__threshold_003` because the Stage 3 enabled row ties that objective, but the Stage 3 winner is clearly `stage3__baseline_artifacts__ql_enabled`.

## Explicit Scope Closures

`arch_mr_bandit_frozen` is explicitly deferred from merge acceptance.

- all `15` rows for that arm were blocked
- the only rejection reason was `bandit_snapshot_not_ready`
- no bandit-ready staged snapshot path was introduced for this Phase 5 completion pass
- the arm is therefore intentionally left unaccepted and unscored rather than silently omitted

Stage 3 scope is explicitly confirmed as intended.

- `phase5_manifest.json` records `stage3_artifact_candidate_ids: []`
- the study spec defines no additional Stage 3 artifact candidates
- Stage 3 was therefore intentionally limited to the inherited baseline RL artifact pair:
  - `baseline_artifacts__ql_enabled`
  - `baseline_artifacts__ql_disabled`

## Final Winner

Accepted Phase 5 path:

1. Stage 1 winner: `stage1__arch_mr_deterministic`
2. Stage 2 winner: `stage2__threshold_003`
3. Stage 3 winner: `stage3__baseline_artifacts__ql_enabled`

Locked effective behavior:

- `EnableMR=1`
- `UseBanditMetaPolicy=0`
- `BanditStateMode=disabled`
- `QLMode=enabled`
- `EMRT_FastThresholdPct=95`
- `MR_TimeStopMin=75`
- `MR_TimeStopMax=90`
- `MR_ConfCut=0.0`
- `MR_EMRTWeight=0.0`

Accepted behavior diffs from the carried-forward Phase 4 anchor:

- `EMRT_FastThresholdPct: 100 -> 95`
- `MR_TimeStopMin: 60 -> 75`
- architecture stays deterministic MR-on
- RL stays enabled with the inherited baseline artifacts
- bandit remains disabled because the staged snapshot is not ready

## Stage 3 RL Gate Result

The paired Stage 3 comparison shows that `ql_enabled` beats `ql_disabled` on the three report windows in the only sense that matters for acceptance: the enabled run is robust across all three windows, while the disabled run collapses to zero-trade in two of them.

`stage3__baseline_artifacts__ql_enabled`

- report objective mean: `52.34879085833333`
- objective min: `48.628524612499994`
- robustness: `no_breach=true`, `no_zero_trade=true`, mild/moderate report non-collapse true

`stage3__baseline_artifacts__ql_disabled`

- report objective mean: `30.03640387916667`
- objective min: `20.0`
- robustness: `no_breach=true`, `no_zero_trade=false`, mild/moderate report non-collapse false

Per report window:

- `wf001_202508`: enabled `49.93750416666667` with `40` trades; disabled `20.0` with `0` trades
- `wf002_202509`: enabled `49.80603249999999` with `42` trades; disabled `51.27115083333334` with `42` trades
- `wf003_202510`: enabled `61.20118499999999` with `42` trades; disabled `20.0` with `0` trades

Conclusion: the runtime RL gate is behaviorally real, not cosmetic. The accepted Phase 5 winner must keep the staged RL artifacts present and `QLMode=enabled`.

## Locked Provenance

Baseline bundle:

- bundle id: `baseline_bundle_53fb4b67246a`
- bundle path: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\baseline\phase5_baseline_bundle.json`
- bundle sha256: `0193DE85BA3A01D7C0113F6232F3EA60112D186F5D5E9A4F13F3A45700966D28`
- resolved anchor set: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\baseline\anchor_mr100__phase5_resolved.set`
- resolved anchor set sha256: `311de43be9bd5d1d1c9e3bfba362aa0bd46ab878c3ad360ef4269824ed23d8ca`

Inherited RL artifact manifest:

- path: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\baseline\baseline_rl_artifact_manifest.json`
- sha256: `116B71F75A8CF2F3AA21749567EC966E57B75B2958E772C43ABC63417B3FAC28`

Locked runtime artifacts:

- qtable id: `qtable_30a624d3fc6a`
- qtable path: `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Files\RPEA\qtable\mr_qtable.bin`
- qtable sha256: `30a624d3fc6ad555d4fc29de3f9dce97a99d0105a3de58491b9a8b45befa209b`
- qtable runtime path: `RPEA/p5/882fb6ff/qtable_30a624d3fc6a.bin`

- thresholds id: `thresholds_565e78dc7fa8`
- thresholds path: `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Files\RPEA\rl\thresholds.json`
- thresholds sha256: `565e78dc7fa8d0725c09ed7030b06eb76b9bb6942261d4d2c00314b7393eb3d3`
- thresholds runtime path: `RPEA/p5/882fb6ff/thresholds_565e78dc7fa8.json`

- bandit snapshot id: `bandit_snapshot_44136fa355b3`
- bandit snapshot path: `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Files\RPEA\bandit\posterior.json`
- bandit snapshot sha256: `44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a`
- bandit runtime path: `RPEA/p5/882fb6ff/bandit_snapshot_44136fa355b3.json`
- bandit state mode: `disabled`
- bandit ready: `false`

Final selected resolved set for reproducibility:

- path: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\resolved_sets\stage3\wf001_202508\report\baseline_artifacts__ql_enabled\baseline.set`
- sha256: `06b9134cb00d5fce31d49abfa3e809a357228200e80160213b6f7cba25548e32`
- effective input hash: `fa577b08192b0d765ce212909ff191dac8d5a4513b6b31fb20502b81414c5601`

## Merge / Review Handoff

Primary artifact paths:

- summary: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\phase5_summary.json`
- run rows: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\phase5_run_rows.jsonl`
- manifest: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\phase5_manifest.json`
- final lock: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\phase5_final_lock.json`

Rationale for acceptance:

- the winning architecture is the same robust deterministic MR path that won Stage 1
- Stage 2 improves the anchor behavior without introducing breach or zero-trade collapse
- Stage 3 proves the RL gate matters and that the accepted configuration must keep the staged artifacts enabled
- no rerun is required for reproducibility because the locked bundle ids, artifact ids, hashes, resolved-set hashes, and exported row/summary artifacts are all present

Remaining risks:

- the frozen-bandit branch is still not decision-ready because the snapshot was not ready in this study
- `ql_disabled` collapses to zero-trade in two of the three report windows, so the accepted winner is artifact-dependent by design
- the shared MT5 runner now uses deterministic slug shortening for very long run names; that tooling behavior should stay intact through review

## Merge Preparation

Merge preparation is complete, but no merge has been performed.

- explicit deferred scope recorded: `arch_mr_bandit_frozen`
- explicit Stage 3 scope confirmation recorded: baseline artifacts only
- final lock artifact written: `C:\Users\AWCS\earl-1\.tmp\fundingpips_phase5\phase5_anchor_pipeline\phase5_final_lock.json`
- review note written: `C:\Users\AWCS\earl-1\docs\fundingpips-phase5-completion-note.md`

Fresh full MT5 quality pass status:

- not required under the requested rule because there were no code changes after the last successful validation
- the last successful validation already covered the final code changes that affected execution:
  - `python -m py_compile tools\fundingpips_mt5_runner.py Tests\python\test_fundingpips_mt5_runner.py tools\fundingpips_phase5.py Tests\python\test_fundingpips_phase5.py`
  - `python -m unittest Tests.python.test_fundingpips_mt5_runner Tests.python.test_fundingpips_phase5`
  - successful real Stage 3 rerun across all three report windows

Only documentation and lock artifacts changed after that validation.
