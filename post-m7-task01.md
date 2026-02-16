# Post-M7 Task 01 - Baseline Snapshot and TODO Inventory Freeze

## Phase and Branching
- Phase branch: feat/m7-postfix-phase0-baseline
- Task branch: feat/m7-p0-task01-baseline-freeze

## Objective
- Establish immutable baseline metrics and a pre-implementation TODO inventory before any functional change.

## Prerequisites
- Branch starts from feat/m7-post-fixes
- Task 08 baseline green (M7Task08_EndToEnd)

## Target Files
- run_tests.ps1 (execution only, no code change required)
- MQL5/Files/RPEA/test_results/post_m7/* (artifacts)

## Implementation Steps
1. Run sync + compile + full automated tests.
2. Capture decision-log baseline counters: EVAL, PLAN_REJECT, PLACE_OK, PLACE_FAIL, SLO_MR_THROTTLED, MR_TIMESTOP.
3. Run rg -n "TODO\\[M7" MQL5/Include/RPEA MQL5/Experts/FundingPips and store output as pre-scan.
4. Write baseline_summary.json and todo_scan_pre.txt.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile log reports Result: 0 errors.
3. Test expectations:
- run_tests.ps1 -RequiredSuite M7Task08_EndToEnd passes.
- test_results.json shows total_failed=0.

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/baseline_summary.json
- MQL5/Files/RPEA/test_results/post_m7/todo_scan_pre.txt

## Exit Criteria
- Baseline artifacts exist and are populated.
- No code modified in this task except optional artifact helper scripts.

## Handoff
- Next task: post-m7-task02.md
- Carry forward this task evidence artifacts into the next task as inputs.
