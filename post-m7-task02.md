# Post-M7 Task 02 - Implement Rolling Spread Buffer in m7_helpers

## Phase and Branching
- Phase branch: feat/m7-postfix-phase1-data-policy
- Task branch: feat/m7-p1-task02-rolling-spread-buffer

## Objective
- Replace TODO[M7-Phase2] spread-mean placeholder with real rolling-buffer behavior.

## Prerequisites
- Task 01 artifacts committed/available
- Phase branch created from feat/m7-post-fixes

## Target Files
- MQL5/Include/RPEA/m7_helpers.mqh
- Tests/RPEA/test_m7_helpers.mqh (new or extend existing test file)
- Tests/RPEA/run_automated_tests_ea.mq5 (suite registration if needed)

## Implementation Steps
1. Add symbol-indexed rolling spread buffer with bounded window and deterministic update path.
2. Implement mean computation over requested period with guardrails for insufficient samples.
3. Keep behavior deterministic in tester mode and stable for EURUSD/XAUUSD paths.
4. Remove the TODO[M7-Phase2] marker.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors after helper changes.
3. Test expectations:
- New helper tests pass for window fill, rollover, insufficient samples.
- Full automated suites remain green.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task02_spread_buffer_summary.json

## Exit Criteria
- M7_GetSpreadMean no longer returns placeholder logic.
- No regressions in MR/BWISC signal tests.

## Handoff
- Next task: post-m7-task03.md
- Carry forward this task evidence artifacts into the next task as inputs.
