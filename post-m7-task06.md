# Post-M7 Task 06 - Phase-1 Integration Validation and Handoff

## Phase and Branching
- Phase branch: feat/m7-postfix-phase1-data-policy
- Task branch: feat/m7-p1-task06-phase1-validation

## Objective
- Lock Phase-1 stability before SLO work starts.

## Prerequisites
- Tasks 02-05 complete in phase branch

## Target Files
- m7-post-fixes-plan.md (evidence section only)
- AGENTS.md (living doc update after phase completion)

## Implementation Steps
1. Run sync, compile, and full automated suites.
2. Run targeted backtest window and capture policy decision evidence with new efficiency values.
3. Record phase handoff artifact with baseline-vs-phase1 deltas.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- run_tests.ps1 full pass with total_failed=0.
- M7Task05_MetaPolicy and M7Task08_EndToEnd pass.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task06_phase1_validation.json

## Exit Criteria
- Phase-1 artifacts approved; downstream tasks consume validated KPI/efficiency data.

## Handoff
- Next task: post-m7-task07.md
- Carry forward this task evidence artifacts into the next task as inputs.
