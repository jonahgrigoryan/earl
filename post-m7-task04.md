# Post-M7 Task 04 - Implement Telemetry KPI State and Update Pipeline

## Phase and Branching
- Phase branch: feat/m7-postfix-phase1-data-policy
- Task branch: feat/m7-p1-task04-telemetry-kpis

## Objective
- Replace telemetry KPI placeholder with real rolling KPI model consumed by policy and reports.

## Prerequisites
- Tasks 02-03 merged into phase branch

## Target Files
- MQL5/Include/RPEA/telemetry.mqh
- MQL5/Include/RPEA/logging.mqh (only if needed for event hook)
- Tests/RPEA/test_regime_telemetry.mqh

## Implementation Steps
1. Define KPI state struct(s) with sample thresholds and reset/init flow.
2. Implement Telemetry_UpdateKpis using available execution/outcome signals.
3. Keep serialization/logging lightweight and deterministic in tests.
4. Remove TODO[M7]: compute rolling KPIs.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- Telemetry tests validate KPI updates under deterministic inputs.
- No regression in existing telemetry suite.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task04_telemetry_kpi_summary.json

## Exit Criteria
- Telemetry KPI pipeline is functional, not stubbed.

## Handoff
- Next task: post-m7-task05.md
- Carry forward this task evidence artifacts into the next task as inputs.
