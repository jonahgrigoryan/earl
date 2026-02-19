# Post-M7 Task 09 - Finalize Persistent SLO Throttle Policy

## Phase and Branching
- Phase branch: feat/m7-postfix-phase2-slo
- Task branch: feat/m7-p2-task09-slo-persistent-throttle

## Objective
- Resolve persistent-throttle TODO with explicit staged behavior for prolonged SLO breaches.

## Prerequisites
- Task 08 complete

## Target Files
- MQL5/Include/RPEA/slo_monitor.mqh
- MQL5/Include/RPEA/meta_policy.mqh
- Tests/RPEA/test_m7_end_to_end.mqh

## Implementation Steps
1. Define staged actions (warn-only, throttle, disable MR after configurable persistence).
2. Integrate with meta-policy override preserving BWISC eligibility.
3. Remove TODO[M7-Task8] marker in slo_monitor.mqh.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- Deterministic tests for both reroute branches: MR to BWISC and MR to Skip.
- No regression in Task 08 suite.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task09_slo_throttle_summary.json

## Exit Criteria
- Persistent breach behavior implemented and tested.

## Handoff
- Next task: post-m7-task10.md
- Carry forward this task evidence artifacts into the next task as inputs.
