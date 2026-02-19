# Post-M7 Task 13 - Implement Learning Update Path and SLO Freeze

## Phase and Branching
- Phase branch: feat/m7-postfix-phase4-learning-bandit
- Task branch: feat/m7-p4-task13-learning-update

## Objective
- Replace learning update stub with controlled persistence and SLO-aware freeze behavior.

## Prerequisites
- Task 12 complete

## Target Files
- MQL5/Include/RPEA/learning.mqh
- MQL5/Include/RPEA/slo_monitor.mqh (read-only integration)
- Tests/RPEA/test_learning.mqh

## Implementation Steps
1. Implement Learning_Update with atomic persistence writes.
2. Gate updates when SLO breach is active.
3. Remove remaining learning TODO markers.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- Update persistence and freeze-on-breach tests pass.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task13_learning_update_summary.json

## Exit Criteria
- Learning update path is implemented and SLO-safe.

## Handoff
- Next task: post-m7-task14.md
- Carry forward this task evidence artifacts into the next task as inputs.
