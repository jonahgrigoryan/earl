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

- Status: Phase 0 implementation is in progress and locally validated; not merged to the baseline branch yet.
- User go-ahead to begin edits: granted.
- Repo default branch: `master`.
- Baseline branch for this workstream: `feat/hpo-pipeline`.
- Active Phase 0 branch: `feat/hpo-phase0-metrics-exports`.
- Branches created for this workstream:
  - `feat/hpo-pipeline`
  - `feat/hpo-phase0-metrics-exports`
- Code changes applied in this workstream:
  - added `MQL5/Include/RPEA/evaluation_report.mqh`
  - wired evaluation-report lifecycle hooks into `MQL5/Experts/FundingPips/RPEA.mq5`
  - added `Tests/RPEA/test_evaluation_report.mqh`
  - registered the new suite in `Tests/RPEA/run_automated_tests_ea.mq5`
- Validation runs executed in this workstream:
  - EA compile: `0 errors, 5 warnings`
  - automated suites: `42/42` passing (`success=true`)
  - controlled tester probe previously wrote:
    - `RPEA/reports/fundingpips_eval_summary.json`
    - `RPEA/reports/fundingpips_eval_daily.csv`
- Current Phase 0 commit: `0b7d80b` (`FundingPips: add Phase 0 evaluation reporting`)
- Current Phase 0 PR: `https://github.com/jonahgrigoryan/earl/pull/47`
- Immediate objective: review/merge Phase 0 into `feat/hpo-pipeline`, then cut Phase 1.

## Locked Decisions So Far

- Use a phase-based branch model with one accumulating baseline branch and short-lived phase branches.
- Adapt the branch plan to this repo's `master` branch instead of `main`.
- Do not tune for profitability first; fix measurement first.
- Treat v0 as Phases 0-2, then bank v0 before deeper v1 robustness work.
- Start v0 with deterministic behavior and Q-learning off unless evidence later proves it belongs in the evaluation profile.

## Planned Phase Map

| Phase | Branch | Goal | Status |
|---|---|---|---|
| 0 | `feat/hpo-phase0-metrics-exports` | Deterministic tester metrics for FundingPips-style pass/fail and drawdown tracking | Implemented locally; compile/tests green; pending review + merge |
| 1 | `feat/hpo-phase1-mt5-runner` | Python MT5 runner for repeatable single backtests | Not started |
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
- Phase 0 solves measurement, not alpha. The verified probe artifact still showed `trades_total=0`, so profitability work now depends on Phase 1+ automation and subsequent search/strategy fixes rather than additional reporting changes.

## Session Log

- 2026-03-07: Created this handoff log before implementation at the user's request so future agents can resume cleanly. No code changes or HPO branches have been created yet. Important repo-specific correction: the default branch is `master`, so any new HPO baseline branch should be cut from `master`, not `main`.
- 2026-03-07: Added `docs/fundingpips-hpo-implementation-outline.md` as the canonical end-to-end implementation plan for the new HPO workstream. It reformats and supersedes the rough note in `## 0) FundingPips 1-Step rule.md` while preserving the same strategic direction: measurement first, v0 before v1, and staged MR / Q-learning handling.
- 2026-03-07: User approved implementation. Created `feat/hpo-pipeline` from `master` and `feat/hpo-phase0-metrics-exports` from the baseline branch, then implemented Phase 0 evaluation reporting.
- 2026-03-07: Added `MQL5/Include/RPEA/evaluation_report.mqh`, wired `RPEA.mq5` to initialize/update/write the evaluation artifacts, added `Tests/RPEA/test_evaluation_report.mqh`, and registered `FundingPips_Phase0_EvaluationReport` in the automated runner. Controlled tester evidence was produced at `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Tester\D0E8209F77C8CF37AD8BF550E51FF075\Agent-127.0.0.1-3001\MQL5\Files\RPEA\reports\fundingpips_eval_summary.json` and `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Tester\D0E8209F77C8CF37AD8BF550E51FF075\Agent-127.0.0.1-3001\MQL5\Files\RPEA\reports\fundingpips_eval_daily.csv`.
- 2026-03-07: Fixed the only remaining red test by updating the stale-rollover expectation in `Tests/RPEA/test_evaluation_report.mqh` to match runtime fallback logic and by keeping a separate fresh-rollover assertion. Final validation: EA compile `0 errors, 5 warnings`; `run_tests.ps1` copied `MQL5/Files/RPEA/test_results/test_results.json` with `total_failed=0` and `success=true`.
- 2026-03-07: Committed the Phase 0 work on `feat/hpo-phase0-metrics-exports` as `0b7d80b` (`FundingPips: add Phase 0 evaluation reporting`), pushed both `feat/hpo-pipeline` and `feat/hpo-phase0-metrics-exports` to `origin`, and opened PR `#47` targeting `feat/hpo-pipeline` for the requested squash merge workflow.

## Next Recommended Action

- Review and merge `feat/hpo-phase0-metrics-exports` into `feat/hpo-pipeline`.
- After the Phase 0 merge, cut `feat/hpo-phase1-mt5-runner` from the updated baseline branch and start the MT5 runner automation work.
