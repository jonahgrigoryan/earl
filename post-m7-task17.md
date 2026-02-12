# Post-M7 Task 17 - Final TODO[M7*] Closure, Release Gate, and Documentation

## Phase and Branching
- Phase branch: feat/m7-postfix-phase5-tuning-closeout
- Task branch: feat/m7-p5-task17-final-closeout

## Objective
- Close all remaining TODO[M7*] markers, run final gates, and publish closeout artifacts.

## Prerequisites
- Tasks 01-16 complete

## Target Files
- MQL5/Include/RPEA/* (as required)
- MQL5/Experts/FundingPips/* (if required)
- AGENTS.md
- m7-post-fixes-plan.md

## Implementation Steps
1. Run final code scan: rg -n "TODO\\[M7" MQL5/Include/RPEA MQL5/Experts/FundingPips.
2. Resolve any remaining TODO markers with real implementation or finalized logic.
3. Run sync, compile, full tests, and required-suite checks.
4. Write final evidence bundle and update AGENTS living document.

## Compile and Test Checkpoints
1. Run commands:
- powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
- cd C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075; & C:\Program Files\MetaTrader 5\metaeditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- powershell -ExecutionPolicy Bypass -File run_tests.ps1
2. Compile expectations:
- EA compile 0 errors.
3. Test expectations:
- run_tests.ps1 success with total_failed=0.
- Required suites pass (M7Task07_AllocatorMR, M7Task08_EndToEnd, and all new post-M7 suites).

## Evidence Artifacts
- MQL5/Files/RPEA/test_results/post_m7/todo_scan_post.txt (must be empty)
- MQL5/Files/RPEA/test_results/post_m7/final_summary.json

## Exit Criteria
- rg -n "TODO\\[M7" returns no matches.
- Documentation and evidence complete for merge.

## Handoff
- This is the final closeout task.
- Proceed to merge readiness review and release decision.
