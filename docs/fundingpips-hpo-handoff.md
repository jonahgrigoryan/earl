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

- Status: Phase 0 is merged into `feat/hpo-pipeline`; Phase 1 is implemented, validated, pushed, and waiting for review on `feat/hpo-phase1-mt5-runner`.
- User go-ahead to begin edits: granted.
- Repo default branch: `master`.
- Baseline branch for this workstream: `feat/hpo-pipeline`.
- Active Phase 1 branch: `feat/hpo-phase1-mt5-runner`.
- Branches created for this workstream:
  - `feat/hpo-pipeline`
  - `feat/hpo-phase0-metrics-exports`
  - `feat/hpo-phase1-mt5-runner`
- Code changes applied in this workstream:
  - Phase 0 merged: `MQL5/Include/RPEA/evaluation_report.mqh`, `MQL5/Experts/FundingPips/RPEA.mq5`, `Tests/RPEA/test_evaluation_report.mqh`, and runner registration in `Tests/RPEA/run_automated_tests_ea.mq5`
  - Phase 1 added `tools/__init__.py`
  - Phase 1 added `tools/fundingpips_mt5_runner.py`
  - Phase 1 added `Tests/python/test_fundingpips_mt5_runner.py`
- Validation runs executed in this workstream:
  - Python syntax check: `python -m py_compile tools\fundingpips_mt5_runner.py Tests\python\test_fundingpips_mt5_runner.py`
  - Python unit tests: `12/12` passing in `Tests.python.test_fundingpips_mt5_runner`
  - Phase 1 probe run: `python tools\fundingpips_mt5_runner.py run --name phase1_probe --symbol EURUSD --from-date 2024.01.02 --to-date 2024.01.05 --stop-existing --force`
  - Phase 1 forced rerun probe: repeated the same `--force` probe twice back to back against the same cache key to confirm stale artifacts are not reused
  - Phase 1 cache-hit probe: reran the same spec without `--force` and confirmed an immediate `cache_hit` return before sync/compile preflight
  - EA compile: `0 errors, 2 warnings`
  - automated suites: `42/42` passing (`success=true`)
  - Phase 1 collected artifacts written under `.tmp/fundingpips_hpo_runs/phase1_probe__6c0b176b77dfd288/collected/`:
    - `fundingpips_eval_summary.json`
    - `fundingpips_eval_daily.csv`
    - `phase1_probe_6c0b176b77dfd288.xml.htm`
- Phase 0 merge result: PR `#47` squash-merged into `feat/hpo-pipeline`
- Current Phase 1 branch state: branch updates pending review on `origin/feat/hpo-phase1-mt5-runner`
- Current Phase 1 PR: `https://github.com/jonahgrigoryan/earl/pull/48`
- Immediate objective: review and squash-merge the Phase 1 PR into `feat/hpo-pipeline`.

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
| 2 | `feat/hpo-phase2-objective-windows` | Objective function, rolling windows, and baseline Optuna study | Not started |
| 3 | `feat/hpo-phase3-optuna-search` | Parameter reduction and conditional search | Not started |
| 4 | `feat/hpo-phase4-wfo-stress` | Walk-forward and stress harness | Not started |
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
- Phase 0 solves measurement, not alpha. The verified probe artifact still showed `trades_total=0`, so profitability work now depends on Phase 1+ automation and subsequent search/strategy fixes rather than additional reporting changes.

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

## Next Recommended Action

- Review and squash-merge PR `#48` into `feat/hpo-pipeline`.
- After the Phase 1 merge, fast-forward the local baseline branch.
- Only then cut `feat/hpo-phase2-objective-windows` from the updated baseline branch.
