# Post-M7 Task 07 - Add SLO Closed-Trade Ingestion API

## Phase and Branching
- Phase branch: feat/m7-postfix-phase2-slo
- Task branch: feat/m7-p2-task07-slo-ingestion

## Objective
- Create authoritative runtime API to feed SLO metrics from realized trade outcomes.

## Prerequisites
- Phase-1 complete and merged

## Target Files
- MQL5/Include/RPEA/slo_monitor.mqh
- MQL5/Include/RPEA/order_engine.mqh (or canonical close path)
- Tests/RPEA/test_slo_monitor.mqh (new)

## Implementation Steps
1. Define SLO_OnTradeClosed payload contract (strategy, pnl proxy, hold duration, friction, timestamp).
2. Invoke ingestion from one authoritative closure path to avoid double counting.
3. Add duplicate-protection by intent/ticket id where applicable.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- Unit tests confirm ingestion counts exactly once per closure event.
- No regressions in order engine suites.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task07_slo_ingestion_summary.json

## Exit Criteria
- SLO runtime can consume real outcomes deterministically.

## Handoff
- Next task: post-m7-task08.md
- Carry forward this task evidence artifacts into the next task as inputs.
