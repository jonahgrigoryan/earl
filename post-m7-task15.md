# Post-M7 Task 15 - MetaPolicy Bandit Readiness and Shadow Integration

## Phase and Branching
- Phase branch: feat/m7-postfix-phase4-learning-bandit
- Task branch: feat/m7-p4-task15-metapolicy-bandit-shadow

## Objective
- Complete meta-policy bandit readiness TODO and verify shadow-mode decision telemetry.

## Prerequisites
- Task 14 complete

## Target Files
- MQL5/Include/RPEA/meta_policy.mqh
- MQL5/Include/RPEA/telemetry.mqh
- Tests/RPEA/test_meta_policy.mqh
- Tests/RPEA/test_bandit.mqh

## Implementation Steps
1. Implement posterior readiness check in MetaPolicy_BanditIsReady.
2. Keep hard blocks enforced before any bandit choice.
3. Ensure shadow-mode logs bandit vs deterministic deltas without changing execution choice unless explicitly enabled.
4. Remove TODO[M7-Phase5] marker.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- Bandit shadow tests pass.
- Meta-policy regression suites remain green.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/task15_metapolicy_bandit_shadow.json

## Exit Criteria
- Bandit readiness and shadow path complete and safe.

## Handoff
- Next task: post-m7-task16.md
- Carry forward this task evidence artifacts into the next task as inputs.
