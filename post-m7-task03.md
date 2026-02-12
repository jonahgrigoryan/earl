# Post-M7 Task 03 - Implement Full ATR Percentile in m7_helpers

## Phase and Branching
- Phase branch: feat/m7-postfix-phase1-data-policy
- Task branch: feat/m7-p1-task03-atr-percentile

## Objective
- Replace TODO[M7-Phase4] ATR percentile approximation with true percentile computation.

## Prerequisites
- Task 02 complete with passing tests

## Target Files
- MQL5/Include/RPEA/m7_helpers.mqh
- Tests/RPEA/test_m7_helpers.mqh

## Implementation Steps
1. Build lookback ATR sample collection with explicit minimum bars.
2. Implement deterministic percentile calculation (rank-based or equivalent stable method).
3. Add edge handling for unavailable bars and invalid ATR values.
4. Remove the TODO[M7-Phase4] marker.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- Percentile unit tests pass across low/high/edge conditions.
- M7Task06_RegimeTelemetry remains green.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task03_atr_percentile_summary.json

## Exit Criteria
- ATR percentile output is no longer approximation-based.

## Handoff
- Next task: post-m7-task04.md
- Carry forward this task evidence artifacts into the next task as inputs.
