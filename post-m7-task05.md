# Post-M7 Task 05 - Wire Real Efficiency into MetaPolicy

## Phase and Branching
- Phase branch: feat/m7-postfix-phase1-data-policy
- Task branch: feat/m7-p1-task05-metapolicy-efficiency

## Objective
- Replace MetaPolicy efficiency stubs with KPI-driven values.

## Prerequisites
- Task 04 telemetry KPIs available

## Target Files
- MQL5/Include/RPEA/meta_policy.mqh
- Tests/RPEA/test_meta_policy.mqh

## Implementation Steps
1. Implement both efficiency helper functions using telemetry KPI state.
2. Return safe defaults when sample threshold not met.
3. Validate that deterministic rule outcomes only change when thresholds are crossed.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- Meta-policy regression tests for rule 3/4 transitions pass.
- Existing M7Task05_MetaPolicy suite stays green.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task05_metapolicy_efficiency_summary.json

## Exit Criteria
- No placeholder efficiency logic remains in meta-policy.

## Handoff
- Next task: post-m7-task06.md
- Carry forward this task evidence artifacts into the next task as inputs.
