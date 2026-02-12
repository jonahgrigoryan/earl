# Post-M7 Task 14 - Implement Bandit Selector and Posterior Persistence

## Phase and Branching
- Phase branch: feat/m7-postfix-phase4-learning-bandit
- Task branch: feat/m7-p4-task14-bandit-selector

## Objective
- Replace bandit selector stub with deterministic contextual policy and persisted posterior state.

## Prerequisites
- Tasks 12-13 complete

## Target Files
- MQL5/Include/RPEA/bandit.mqh
- Tests/RPEA/test_bandit.mqh (new)

## Implementation Steps
1. Implement selector algorithm and posterior state transitions.
2. Persist/load posterior safely with version checks.
3. Remove TODO[M7]: Thompson/LinUCB with posterior persistence.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- Bandit deterministic tests pass with fixed seeds/fixtures.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task14_bandit_summary.json

## Exit Criteria
- Bandit path is implemented and test-covered.

## Handoff
- Next task: post-m7-task15.md
- Carry forward this task evidence artifacts into the next task as inputs.
