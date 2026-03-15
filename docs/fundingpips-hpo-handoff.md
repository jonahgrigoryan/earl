# FundingPips HPO Handoff Log

## Purpose

This file is the active handoff and progress log for the FundingPips profitability workstream.
It exists so a new agent or a new conversation can resume work without re-scanning the full repo.

## Scope

- Goal: move the EA toward rule-compliant profitable trading for the FundingPips 1-Step evaluation.
- Workstream: staged HPO pipeline plus any EA instrumentation needed to measure pass/fail correctly.
- Related references:
  - `docs/fundingpips-hpo-implementation-outline.md`
  - `docs/fundingpips-profitability-run-2026-03-03.md`
  - `AGENTS.md`

## Update Protocol

- Update this file after every substantive step in this workstream.
- Always refresh `Current Snapshot`, `Next Recommended Action`, and `Open Risks / Questions`.
- Append to `Session Log`; do not delete older entries unless they are factually wrong.
- Record exact branch names, commit hashes, validation artifacts, and blockers.
- If implementation begins, note whether the branch was cut from `master` or from an already-updated HPO baseline branch.

## Current Snapshot

- Status: Phases 0-3 are complete through candidate selection. The active branch is `feat/hpo-phase3-optuna-search`, and the next execution step is to cut or prepare `feat/hpo-phase4-wfo-stress` around the Phase 3 post-fix anchor cluster.
- User go-ahead to begin edits: granted.
- Repo default branch: `master`.
- Baseline branch for this workstream: `feat/hpo-pipeline`.
- Active Phase 2 branch: `feat/hpo-phase2-objective-windows`.
- Branches created for this workstream:
  - `feat/hpo-pipeline`
  - `feat/hpo-phase0-metrics-exports`
  - `feat/hpo-phase1-mt5-runner`
  - `feat/hpo-phase2-objective-windows`
  - `feat/hpo-phase3-optuna-search`
- Code changes applied in this workstream:
  - Phase 0 merged: `MQL5/Include/RPEA/evaluation_report.mqh`, `MQL5/Experts/FundingPips/RPEA.mq5`, `Tests/RPEA/test_evaluation_report.mqh`, and runner registration in `Tests/RPEA/run_automated_tests_ea.mq5`
  - Phase 1 added `tools/__init__.py`
  - Phase 1 added `tools/fundingpips_mt5_runner.py`
  - Phase 1 added `Tests/python/test_fundingpips_mt5_runner.py`
  - Phase 2 added `tools/fundingpips_hpo.py`
  - Phase 2 added `tools/fundingpips_rules_profiles/fundingpips_1step_eval.json`
  - Phase 2 added `tools/fundingpips_studies/phase2_baseline.json`
  - Phase 2 follow-up added `tools/fundingpips_studies/phase2_baseline_postriskfix.json`
  - Phase 3 added `tools/fundingpips_studies/phase3_focus_postriskfix.json`
  - Phase 2 added `Tests/RPEA/RPEA_candidate_B_2024H2.set`
  - Phase 2 added `Tests/python/test_fundingpips_phase2.py`
  - Phase 2 extended `tools/fundingpips_mt5_runner.py` with `build_runner_paths()` for library callers
  - Phase 3 extended `tools/fundingpips_mt5_runner.py` to collect decision/event CSV diagnostics into each run folder
  - Phase 3 updated `MQL5/Include/RPEA/m7_helpers.mqh` so MR entry-budget and lock state reset by trading day instead of overlapping session-label changes
- Validation runs executed in this workstream:
  - Python syntax check: `python -m py_compile tools\fundingpips_mt5_runner.py tools\fundingpips_hpo.py Tests\python\test_fundingpips_mt5_runner.py Tests\python\test_fundingpips_phase2.py`
  - Python unit tests: `29/29` passing in `Tests.python.test_fundingpips_mt5_runner` plus `Tests.python.test_fundingpips_phase2`, including the new Phase 2 fail-then-resume coverage
  - Phase 1 probe run: `python tools\fundingpips_mt5_runner.py run --name phase1_probe --symbol EURUSD --from-date 2024.01.02 --to-date 2024.01.05 --stop-existing --force`
  - Phase 1 forced rerun probe: repeated the same `--force` probe twice back to back against the same cache key to confirm stale artifacts are not reused
  - Phase 1 cache-hit probe: reran the same spec without `--force` and confirmed an immediate `cache_hit` return before sync/compile preflight, with `report_path` present in the cached result
  - Phase 2 window generation: `python tools\fundingpips_hpo.py generate-windows --study-spec tools\fundingpips_studies\phase2_baseline.json`
  - Candidate B `.set` coverage check against `RPEA.mq5`: `101/101` inputs present
  - Phase 2 real-study attempt: `python tools\fundingpips_hpo.py run-study --study-spec tools\fundingpips_studies\phase2_baseline.json --n-trials 2 --stop-existing`
  - Phase 2 export regeneration after the interrupted real study: `python tools\fundingpips_hpo.py export-study --study-dir .tmp\fundingpips_hpo_studies\phase2_baseline`
  - Phase 2 end-to-end completion run: `python tools\fundingpips_hpo.py run-study --study-spec tools\fundingpips_studies\phase2_baseline.json --n-trials 4 --resume --stop-existing`
  - Phase 2 export regeneration after the completed study: `python tools\fundingpips_hpo.py export-study --study-dir .tmp\fundingpips_hpo_studies\phase2_baseline`
  - Fresh Phase 2 clean validation run: `python tools\fundingpips_hpo.py run-study --study-spec .tmp\phase2_baseline_clean.json --stop-existing`
  - Fresh Phase 2 clean validation resume: `python tools\fundingpips_hpo.py run-study --study-spec .tmp\phase2_baseline_clean.json --n-trials 4 --resume --stop-existing`
  - Fresh Phase 2 clean export regeneration: `python tools\fundingpips_hpo.py export-study --study-dir .tmp\fundingpips_hpo_studies\phase2_baseline_clean`
  - EA compile: `0 errors, 2 warnings`
  - automated suites: `42/42` passing (`success=true`)
  - Post-riskfix targeted replay review on the winning cluster:
    - corrected `compliance_restore` replay reduced the old June 30 daily-loss event from about `4.14%` / `449.20` to about `0.45%` / `44.92`
    - corrected daily CSV export no longer carries `daily_breach=true` into later non-breach days
    - replay ablations showed `SpreadMultATR=0.005` alone restores the cluster's `68` trades and `+0.8462%` return
    - `NewsBufferS=300` alone and `MaxSpreadPoints=40` alone both produced `0` trades on the same window
  - Clean post-riskfix Phase 2 study execution completed under `tools\fundingpips_studies\phase2_baseline_postriskfix.json`
  - Top-candidate replay review after the clean rerun:
    - nominal best Phase 2 trial (`RiskPct=2.0`, `MR_RiskPct_Default=0.75`, `ORMinutes=45`, `CutoffHour=23`, `StartHourLO=7`) replayed at `+0.5754%` with `85` trades and no breaches
    - the Phase 2 runner-up cluster (`RiskPct=2.0`, `MR_RiskPct_Default=1.05`, `ORMinutes=45`, `CutoffHour=23`, `StartHourLO=5`) replayed better at `+1.2845%` with `77` trades and no breaches
    - `NewsBufferS=300` remained non-binding for the new best profile, so the prior two-scenario mix is no longer adding useful separation
  - Focused Phase 3 study execution/export completed under `tools\fundingpips_studies\phase3_focus_postriskfix.json`
  - Gate-level replay diagnostics after the focused study:
    - raw decision/event log collection showed the weak LO7 path was not getting a better signal, it was getting an extra MR budget reset when the session label flipped from NY to LO inside the same trading day
    - exact divergence rows were confirmed on `2025-08-14` and `2025-08-25`, where the pre-fix LO7 path admitted extra late-morning MR entries via `RULE_2_MR_LOCK` after the session counter had reset
    - fixing the entry-budget reset in `m7_helpers.mqh` raised the LO7 replay (`RiskPct=2.0`, `MR_RiskPct_Default=1.0`, `ORMinutes=45`, `CutoffHour=23`, `StartHourLO=7`, `SpreadMultATR=0.005`) from `+0.9754%` to `+1.5041%` with `65` trades and no breaches
    - the current anchor replay (`RiskPct=2.0`, `MR_RiskPct_Default=1.05`, `ORMinutes=45`, `CutoffHour=23`, `StartHourLO=5`, `SpreadMultATR=0.005`) improved to `+1.5637%` with `65` trades and no breaches
    - the nearby anchor neighbor (`MR_RiskPct_Default=1.0`, same remaining params) matched the anchor exactly at `+1.5637%`, establishing a small stable cluster for Phase 4
- Phase 1 collected artifacts written under `.tmp/fundingpips_hpo_runs/phase1_probe__6c0b176b77dfd288/collected/`:
  - `fundingpips_eval_summary.json`
  - `fundingpips_eval_daily.csv`
  - `phase1_probe_6c0b176b77dfd288.xml.htm`
- Phase 2 baseline study assets now live under `.tmp/fundingpips_hpo_studies/phase2_baseline/`:
  - `study_manifest.json`
  - `study.sqlite3`
  - `windows.json`
  - flat exports generated from the SQLite custom tables
  - `best_trial_summary.json` now points to winning trial `2` (objective `15.143758394097217`)
- Fresh clean-validation assets live under `.tmp/fundingpips_hpo_studies/phase2_baseline_clean/`:
  - `study_manifest.json`
  - `study.sqlite3`
  - `windows.json`
  - flat exports generated from the SQLite custom tables
  - `best_trial_summary.json` points to winning trial `0` with the same best params as the canonical baseline study
- Phase 0 merge result: PR `#47` squash-merged into `feat/hpo-pipeline`
- Current Phase 1 branch state: branch updates pending review on `origin/feat/hpo-phase1-mt5-runner`
- Current Phase 1 PR: `https://github.com/jonahgrigoryan/earl/pull/48`
- Immediate objective: move into Phase 4 walk-forward/stress on the post-fix anchor cluster: `RiskPct=2.0`, `MR_RiskPct_Default in {1.0,1.05}`, `ORMinutes=45`, `CutoffHour=23`, `StartHourLO=5`, `SpreadMultATR=0.005`.

## Locked Decisions So Far

- Use a phase-based branch model with one accumulating baseline branch and short-lived phase branches.
- Adapt the branch plan to this repo's `master` branch instead of `main`.
- Do not tune for profitability first; fix measurement first.
- Treat v0 as Phases 0-2, then bank v0 before deeper v1 robustness work.
- Start v0 with deterministic behavior and Q-learning off unless evidence later proves it belongs in the evaluation profile.

## Planned Phase Map

| Phase | Branch | Goal | Status |
|---|---|---|---|
| 0 | `feat/hpo-phase0-metrics-exports` | Deterministic tester metrics for FundingPips-style pass/fail and drawdown tracking | Squash-merged into `feat/hpo-pipeline` via PR `#47` |
| 1 | `feat/hpo-phase1-mt5-runner` | Python MT5 runner for repeatable single backtests | Committed, pushed, and awaiting review in PR `#48` |
| 2 | `feat/hpo-phase2-objective-windows` | Objective function, rolling windows, and baseline Optuna study | Complete locally with real resumed study validation |
| 3 | `feat/hpo-phase3-optuna-search` | Parameter reduction, conditional search, and gate-level replay diagnosis | Complete locally; phase-4-ready candidate cluster selected |
| 4 | `feat/hpo-phase4-wfo-stress` | Walk-forward and stress harness | Ready to start from updated Phase 3 branch state |
| 5 | `feat/hpo-phase5-mr-ql-staging` | MR / ensemble / Q-learning staged tuning | Not started |

## First Execution Pass When Approved

1. Establish repo/build/test baseline and confirm branch hygiene.
2. Audit existing FundingPips rule measurement in:
   - `MQL5/Experts/FundingPips/RPEA.mq5`
   - `MQL5/Include/RPEA/config.mqh`
   - `MQL5/Include/RPEA/equity_guardian.mqh`
   - `MQL5/Include/RPEA/telemetry.mqh`
   - `MQL5/Include/RPEA/logging.mqh`
3. Identify the exact Phase 0 metric gap: pass flag, days to target, max daily DD, max overall DD, breach flags, reset-time baselines, minimum trading days.
4. Implement the smallest deterministic artifact export that makes the evaluator trustworthy.
5. Validate with compile, automated tests, and at least one controlled tester run.

## Open Risks / Questions

- FundingPips public sources conflict on exact rules; the purchased dashboard remains the source of truth for target, daily loss, overall loss, minimum trading days, reset clock, leverage, and news policy.
- MT5 built-in statistics are not sufficient on their own for FundingPips-style daily drawdown tracking; custom run artifacts are expected to be required.
- The repo already contains a prior profitability branch and evidence bundle; new work should reuse that context where useful but should not assume it already solves Phase 0 measurement.
- The Phase 1 runner depends on local MT5 terminal state, including `config/common.ini`, terminal authorization, and report naming quirks such as MT5 writing XML reports as `.xml.htm`.
- PR review feedback confirmed two correctness risks in the initial runner: cache reuse across include-only EA changes and shallow batch `set_overrides` merging. Both are now fixed on the Phase 1 branch and covered by Python regression tests.
- PR review feedback also exposed a stale-artifact risk on rapid `--force` reruns. The Phase 1 branch now requires artifact mtimes to be strictly newer than the current run start, and that path has been validated with back-to-back real reruns.
- Additional PR review feedback exposed three more correctness risks: cache-key collisions across agent-mode flags, cache hits paying sync/compile preflight cost, and non-ASCII text from `common.ini` failing on ASCII-only merged INI writes. All three are now fixed on the Phase 1 branch and covered by runtime/unit validation.
- The latest PR review feedback exposed two more correctness risks: mixed cache-hit/cache-miss batch runs could skip the initial sync for the first uncached run, and stale `.xml` files could block detection of the fresh `.xml.htm` report variant. Both are now fixed on the Phase 1 branch and covered by Python regression tests plus a real probe revalidation.
- The latest cache-hit review feedback exposed one more contract gap: cached runs were considered reusable without a collected tester report. The Phase 1 branch now requires the cached report artifact to exist before returning `cache_hit`, and cached results now include `report_path`.
- Phase 0 solves measurement, not alpha. The verified probe artifact still showed `trades_total=0`, so profitability work now depends on Phase 1+ automation and subsequent search/strategy fixes rather than additional reporting changes.
- The repo-tracked Candidate B seed set now has full `RPEA.mq5` input coverage, but it remains a study seed only, not a promoted production profile.
- Long MT5 studies can still exceed an interactive shell budget. The difference now is that interrupted trials are recorded as `FAIL` and the resumed study refills the missing valid trial budget instead of silently treating the interruption as a finished trial.
- The small Phase 2 search completed cleanly from a tooling perspective, but none of the four valid completed trials achieved `pass_rate > 0`; the next bottleneck is EA behavior and candidate quality, not Phase 2 orchestration.
- The original March 12, 2026 Phase 2 leaderboard is no longer trustworthy for ranking because it was produced before the March 13, 2026 XAUUSD stop-risk correction. Any new Phase 3 or Phase 4 work should use only the post-riskfix rerun outputs.
- The EA is still far from challenge-pass alpha (`+1.5637%` best full-window replay versus a `10%` target), so Phase 4 should be used to validate robustness of the new cluster, not to claim funded-account readiness.

## Session Log

- 2026-03-07: Created this handoff log before implementation at the user's request so future agents can resume cleanly. No code changes or HPO branches have been created yet. Important repo-specific correction: the default branch is `master`, so any new HPO baseline branch should be cut from `master`, not `main`.
- 2026-03-07: Added `docs/fundingpips-hpo-implementation-outline.md` as the canonical end-to-end implementation plan for the new HPO workstream. It reformats and supersedes the rough note in `## 0) FundingPips 1-Step rule.md` while preserving the same strategic direction: measurement first, v0 before v1, and staged MR / Q-learning handling.
- 2026-03-07: User approved implementation. Created `feat/hpo-pipeline` from `master` and `feat/hpo-phase0-metrics-exports` from the baseline branch, then implemented Phase 0 evaluation reporting.
- 2026-03-07: Added `MQL5/Include/RPEA/evaluation_report.mqh`, wired `RPEA.mq5` to initialize/update/write the evaluation artifacts, added `Tests/RPEA/test_evaluation_report.mqh`, and registered `FundingPips_Phase0_EvaluationReport` in the automated runner. Controlled tester evidence was produced at `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Tester\D0E8209F77C8CF37AD8BF550E51FF075\Agent-127.0.0.1-3001\MQL5\Files\RPEA\reports\fundingpips_eval_summary.json` and `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Tester\D0E8209F77C8CF37AD8BF550E51FF075\Agent-127.0.0.1-3001\MQL5\Files\RPEA\reports\fundingpips_eval_daily.csv`.
- 2026-03-07: Fixed the only remaining red test by updating the stale-rollover expectation in `Tests/RPEA/test_evaluation_report.mqh` to match runtime fallback logic and by keeping a separate fresh-rollover assertion. Final validation: EA compile `0 errors, 5 warnings`; `run_tests.ps1` copied `MQL5/Files/RPEA/test_results/test_results.json` with `total_failed=0` and `success=true`.
- 2026-03-07: Committed the Phase 0 work on `feat/hpo-phase0-metrics-exports` as `0b7d80b` (`FundingPips: add Phase 0 evaluation reporting`), pushed both `feat/hpo-pipeline` and `feat/hpo-phase0-metrics-exports` to `origin`, and opened PR `#47` targeting `feat/hpo-pipeline` for the requested squash merge workflow.
- 2026-03-07: User squash-merged Phase 0 PR `#47`. Fast-forwarded local `feat/hpo-pipeline` to the merged baseline, then cut `feat/hpo-phase1-mt5-runner` from the updated baseline branch.
- 2026-03-07: Implemented the Phase 1 MT5 runner in `tools/fundingpips_mt5_runner.py` with generated `.ini` and `.set` files, explicit MetaEditor compile-before-run behavior, cache keying by run spec plus EA source hash, structured artifact collection, and MT5 report-name fallback for `.xml.htm`. Added Python regression coverage in `Tests/python/test_fundingpips_mt5_runner.py`.
- 2026-03-07: Validated Phase 1 locally with `py_compile`, `4/4` Python unit tests, a successful probe run for `EURUSD` (`2024.01.02` through `2024.01.05`) that collected summary/daily/report artifacts under `.tmp/fundingpips_hpo_runs/phase1_probe__dd6fa6165b2ce967/`, EA compile `0 errors, 2 warnings`, and automated suites `42/42` passing.
- 2026-03-07: Committed the Phase 1 work on `feat/hpo-phase1-mt5-runner` as `2182b0c` (`FundingPips: add Phase 1 MT5 runner`), pushed the branch to `origin`, and opened PR `#48` targeting `feat/hpo-pipeline` for the requested squash-merge workflow.
- 2026-03-07: Addressed PR `#48` review feedback by changing the runner cache key to hash the full repo-controlled EA source tree (`MQL5/Experts/FundingPips` plus `MQL5/Include/RPEA`) instead of only `RPEA.mq5`, and by deep-merging batch `set_overrides` so run-level overrides no longer drop shared defaults. Expanded Python regression coverage to `7/7` tests and revalidated the real probe run, EA compile, and automated MT5 suite.
- 2026-03-07: Addressed a second PR `#48` review comment by removing the 2-second artifact mtime grace window in `tools/fundingpips_mt5_runner.py`. The runner now accepts only artifacts with `mtime >= started_at`, preventing fast back-to-back `--force` reruns from reusing stale summary/daily/report files and terminating MT5 early. Added two Python tests for stale-vs-fresh `locate_recent_file` behavior, bringing the suite to `9/9`, then revalidated with two consecutive forced probe runs plus EA compile and the full `42/42` automated MT5 suite.
- 2026-03-07: Addressed three additional PR `#48` review comments by adding `use_local`/`use_remote`/`use_cloud` to the cache key, moving cache-hit evaluation ahead of sync/compile/MT5-process preflight, and preserving the detected `common.ini` encoding when writing the merged run INI. Expanded Python regression coverage to `12/12`, verified a real forced probe run with cache key `6c0b176b77dfd288`, confirmed an immediate `cache_hit` on the same spec without `--force`, then reran EA compile (`0 errors, 2 warnings`) and the full `42/42` automated MT5 suite.
- 2026-03-09: Addressed two further PR `#48` review comments by ensuring batch execution keeps `sync_before_run` enabled until the first non-cache-hit run actually occurs, and by checking `.xml` and `.xml.htm` report candidates independently so a stale XML file cannot block a fresh HTML-wrapped report. Expanded Python regression coverage to `14/14`, revalidated the real forced probe plus immediate cache-hit path for `EURUSD` (`2024.01.02..2024.01.05`), then reran EA compile (`0 errors, 2 warnings`) and the full `42/42` automated MT5 suite.
- 2026-03-09: Addressed one more PR `#48` review comment by requiring a cached tester report before declaring `cache_hit`. The runner now resolves the cached report path from the manifest or the expected collected report filenames and only short-circuits when summary, daily, and report artifacts all exist; cached results now return `report_path`. Expanded Python regression coverage to `15/15`, revalidated the real forced probe plus immediate cache-hit path for `EURUSD` (`2024.01.02..2024.01.05`), then reran EA compile (`0 errors, 2 warnings`) and the full `42/42` automated MT5 suite.
- 2026-03-10: Implemented Phase 2 on `feat/hpo-phase2-objective-windows`. Added `tools/fundingpips_hpo.py` for study-spec and rules-profile loading, weekday rolling-window generation, Optuna orchestration, MT5 report parsing, Phase 0 artifact normalization, custom SQLite trial/run tables, and flat export regeneration. Added the repo-tracked baseline seed `Tests/RPEA/RPEA_candidate_B_2024H2.set`, `requirements-hpo.txt`, rules/study JSON configs, and Python regression coverage in `Tests/python/test_fundingpips_phase2.py`. Extended `tools/fundingpips_mt5_runner.py` with `build_runner_paths()` so the Phase 2 orchestrator can call it as a library.
- 2026-03-10: Validated the finished Phase 2 toolchain with `python -m py_compile`, Python unit tests `28/28`, Candidate B set coverage `101/101` against `RPEA.mq5`, baseline window generation (`12` windows), EA compile (`0 errors, 2 warnings`), and automated suites `42/42`. A real `run-study --n-trials 2` attempt persisted partial run records under `.tmp/fundingpips_hpo_studies/phase2_baseline/` before the interactive shell timeout interrupted the process.
- 2026-03-10: Hardened Phase 2 resume behavior after the interrupted real study by teaching `tools/fundingpips_hpo.py` to recover stale Optuna `RUNNING` trials as `FAIL` when `--resume` is used, preserving partial run records while allowing new trials to continue. Added unit coverage for this recovery path and corrected `run-study` result accounting so `completed_trials` counts only `COMPLETE` trials, not all stored trial rows.
- 2026-03-12: Completed the long real Phase 2 baseline study with `python tools\fundingpips_hpo.py run-study --study-spec tools\fundingpips_studies\phase2_baseline.json --n-trials 4 --resume --stop-existing`, then regenerated flat exports with `export-study`. The winning trial is `trial_number=2` with objective `15.143758394097217` and params `RiskPct=1.75`, `MR_RiskPct_Default=0.9`, `ORMinutes=15`, `CutoffHour=20`, `StartHourLO=5`.
- 2026-03-12: Hardened Phase 2 trial failure accounting after observing that the earlier timeout trial had been stored as `COMPLETE` even though it was invalid. Updated `tools/fundingpips_hpo.py` so invalid/timed-out trials are now persisted as `FAIL` and raised through Optuna catch-handling, then added `Tests/python/test_fundingpips_phase2.py` coverage for fail-then-resume replacement. This closes the gap where resumed studies could stop at the requested trial count without actually delivering that many valid completed trials.
- 2026-03-12: Ran a fresh clean-validation study under `.tmp\phase2_baseline_clean.json`. The first 3-hour session completed two valid trials before timing out mid-trial, and the resumed run recovered that stale `RUNNING` trial as `FAIL` exactly as designed, then finished with four valid `COMPLETE` trials plus one recovered `FAIL`. This provides end-to-end live proof that the new failure accounting works under a real interrupted session, not just in unit tests.
- 2026-03-13: Reviewed post-fix winning-cluster replays after correcting XAUUSD stop-risk sizing in `risk.mqh` and day-local breach export behavior in `evaluation_report.mqh`. The corrected `compliance_restore` replay stayed compliant and profitable (`68` trades, `+0.8462%`, `max_daily_dd_pct=0.445683`) but no longer resembled the stale pre-fix `+10.75%` result, confirming the old Phase 2 ranking was inflated by bad realized sizing.
- 2026-03-13: Ran targeted replay ablations on the winning cluster. `NewsBufferS=300` alone and `MaxSpreadPoints=40` alone both produced `0` trades; `SpreadMultATR=0.005` alone restored the full live path (`68` trades, `+0.8462%`) and matched the paired-spread replay exactly. Added `tools/fundingpips_studies/phase2_baseline_postriskfix.json` so the next HPO rerun uses a clean study name and treats `SpreadMultATR=0.005` as the restored baseline condition.
- 2026-03-14: Exported the clean post-riskfix Phase 2 study and confirmed all four trials were valid, breach-free, and non-zero-trade, but still `pass_rate=0.0`. The nominal study winner shifted to a slower safer cluster (`RiskPct=2.0`, `MR_RiskPct_Default=0.75`, `ORMinutes=45`, `CutoffHour=23`, `StartHourLO=7`), yet full-window replays showed the trial-3 cluster (`RiskPct=2.0`, `MR_RiskPct_Default=1.05`, `ORMinutes=45`, `CutoffHour=23`, `StartHourLO=5`) made materially more return while staying fully compliant.
- 2026-03-14: Completed Phase 2 branch hygiene. Committed the corrected Phase 2 work as `a70a665` on `feat/hpo-phase2-objective-windows`, merged it into `feat/hpo-pipeline` as merge commit `9aebabd`, and cut the dedicated Phase 3 branch `feat/hpo-phase3-optuna-search` from that updated baseline.
- 2026-03-14: Added `tools/fundingpips_studies/phase3_focus_postriskfix.json` on `feat/hpo-phase3-optuna-search`. It fixes `SpreadMultATR=0.005`, collapses to a single baseline scenario because the old compliance-restore scenario no longer separates behavior, and narrows the search to the proven post-riskfix cluster around `RiskPct=2.0`, `ORMinutes=45`, `CutoffHour=23`, `StartHourLO in {5,7}`, and `MR_RiskPct_Default in {0.8,0.9,1.0}`.
- 2026-03-15: Ran the focused Phase 3 study and replayed the practical winners. The small Optuna search remained breach-free but plateaued, so the work shifted to raw replay diagnostics using new per-run decision/event log collection in `tools/fundingpips_mt5_runner.py`.
- 2026-03-15: Used the collected decision/event logs to trace the weak LO7 path to an intra-day session-budget reset in `m7_helpers.mqh`. Under `StartHourLO=7`, an early XAUUSD MR trade could be counted under one active session label and then forgotten when the preferred label flipped later in the same day, granting an extra late-morning MR entry on dates like `2025-08-14` and `2025-08-25`.
- 2026-03-15: Fixed that reset so MR entry-budget and lock state now roll by trading day instead of by session label. Fresh full-window reruns then produced the current Phase 4-ready cluster: anchor `RiskPct=2.0`, `MR_RiskPct_Default=1.05`, `ORMinutes=45`, `CutoffHour=23`, `StartHourLO=5`, `SpreadMultATR=0.005` returned `+1.5637%` with `65` trades and no breaches, while the nearby neighbor with `MR_RiskPct_Default=1.0` matched it exactly. This beats the prior anchor and satisfies the local robustness bar for starting Phase 4.

## Next Recommended Action

- Cut or prepare `feat/hpo-phase4-wfo-stress` from the current `feat/hpo-phase3-optuna-search` state.
- Use the post-fix anchor cluster as the Phase 4 candidate set:
  - `RiskPct=2.0`
  - `MR_RiskPct_Default in {1.0,1.05}`
  - `ORMinutes=45`
  - `CutoffHour=23`
  - `StartHourLO=5`
  - `SpreadMultATR=0.005`
- Build the walk-forward/stress harness around this cluster before any further alpha expansion.
