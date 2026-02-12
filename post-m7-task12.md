# Post-M7 Task 12 - Implement Learning Calibration Load Path

## Phase and Branching
- Phase branch: feat/m7-postfix-phase4-learning-bandit
- Task branch: feat/m7-p4-task12-learning-load

## Objective
- Replace learning load stub with file-backed calibration initialization and safe defaults.

## Prerequisites
- Phase-3 complete

## Target Files
- MQL5/Include/RPEA/learning.mqh
- Tests/RPEA/test_learning.mqh (new)

## Implementation Steps
1. Implement Learning_LoadCalibration with validation and fallback behavior.
2. Define file schema/version handling and missing-file behavior.
3. Keep deterministic behavior in tester mode.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- Load success, missing file fallback, malformed file fallback tests pass.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task12_learning_load_summary.json

## Exit Criteria
- Load path is implemented; no load stub remains.

## Handoff
- Next task: post-m7-task13.md
- Carry forward this task evidence artifacts into the next task as inputs.
