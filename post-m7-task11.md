# Post-M7 Task 11 - Integrate Adaptive Risk into Allocator with Toggle

## Phase and Branching
- Phase branch: feat/m7-postfix-phase3-adaptive-risk
- Task branch: feat/m7-p3-task11-allocator-adaptive-integration

## Objective
- Apply adaptive multiplier in allocator risk path with runtime toggle and MicroMode precedence.

## Prerequisites
- Task 10 complete

## Target Files
- MQL5/Include/RPEA/allocator.mqh
- MQL5/Include/RPEA/config.mqh
- Tests/RPEA/test_allocator_mr.mqh
- Tests/RPEA/test_adaptive_risk.mqh

## Implementation Steps
1. Add config toggle EnableAdaptiveRisk default false.
2. Apply multiplier after base strategy risk and before final sizing call.
3. Ensure MicroMode and hard risk/budget gates still dominate.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- When disabled, outputs match pre-task baseline.
- When enabled, risk remains within configured clamps.
- Allocator MR suite remains green.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task11_allocator_adaptive_summary.json

## Exit Criteria
- Adaptive risk integration is optional and non-regressive by default.

## Handoff
- Next task: post-m7-task12.md
- Carry forward this task evidence artifacts into the next task as inputs.
