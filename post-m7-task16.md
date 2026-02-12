# Post-M7 Task 16 - Walk-Forward Tuning Protocol and Evidence Report

## Phase and Branching
- Phase branch: feat/m7-postfix-phase5-tuning-closeout
- Task branch: feat/m7-p5-task16-walkforward-tuning

## Objective
- Run controlled tuning protocol with out-of-sample validation and durable performance evidence.

## Prerequisites
- Phase-4 complete and green

## Target Files
- m7-post-fixes-plan.md (references only)
- MQL5/Files/RPEA/test_results/post_m7/* (artifacts)
- optional scripts under scripts/ for report generation

## Implementation Steps
1. Tune one parameter family at a time (confidence cuts, liquidity gates, time-stop bounds, adaptive clamps).
2. Run fixed walk-forward windows and compare against Task 01 baseline.
3. Record expectancy, drawdown, SLO breach rate, and placement quality deltas.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors with tuned settings.
3. Test expectations:
- Full automated suites still pass at tuned settings.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/step4_tuning_report.json
- MQL5/Files/RPEA/test_results/post_m7/task16_walkforward_summary.json

## Exit Criteria
- Promotion recommendation is evidence-backed and reproducible.

## Handoff
- Next task: post-m7-task17.md
- Carry forward this task evidence artifacts into the next task as inputs.
