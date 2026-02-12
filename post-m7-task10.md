# Post-M7 Task 10 - Implement Adaptive Risk Multiplier Function

## Phase and Branching
- Phase branch: feat/m7-postfix-phase3-adaptive-risk
- Task branch: feat/m7-p3-task10-adaptive-multiplier

## Objective
- Replace adaptive stub with deterministic multiplier based on regime and efficiency.

## Prerequisites
- Phase-2 complete

## Target Files
- MQL5/Include/RPEA/adaptive.mqh
- Tests/RPEA/test_adaptive_risk.mqh (new)

## Implementation Steps
1. Implement Adaptive_RiskMultiplier mapping with strict clamp bounds.
2. Define safe defaults and invalid-input fallback to 1.0.
3. Remove TODO[M7]: scale risk by regime/efficiency/room.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- Clamp and mapping tests pass across regime/efficiency combinations.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task10_adaptive_multiplier_summary.json

## Exit Criteria
- Adaptive multiplier is production-safe and deterministic.

## Handoff
- Next task: post-m7-task11.md
- Carry forward this task evidence artifacts into the next task as inputs.
