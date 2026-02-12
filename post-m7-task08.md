# Post-M7 Task 08 - Compute Rolling SLO Metrics from Ingested Outcomes

## Phase and Branching
- Phase branch: feat/m7-postfix-phase2-slo
- Task branch: feat/m7-p2-task08-slo-rolling-metrics

## Objective
- Replace default optimistic SLO values with rolling metrics derived from ingested trade outcomes.

## Prerequisites
- Task 07 complete

## Target Files
- MQL5/Include/RPEA/slo_monitor.mqh
- Tests/RPEA/test_slo_monitor.mqh
- Tests/RPEA/test_m7_end_to_end.mqh

## Implementation Steps
1. Implement rolling-window calculations for win rate, hold median/p80, efficiency median, friction median.
2. Update periodic check to recompute breach flags from rolling set.
3. Keep calculations deterministic and robust with insufficient sample guards.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- SLO metric tests validate breach and recovery transitions.
- M7 end-to-end tests continue to pass.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task08_slo_metrics_summary.json

## Exit Criteria
- SLO breach state is metric-driven, not default-driven.

## Handoff
- Next task: post-m7-task09.md
- Carry forward this task evidence artifacts into the next task as inputs.
