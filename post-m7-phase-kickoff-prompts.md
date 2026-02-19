# Post-M7 Phase Kickoff Prompts

Use these prompts directly with coding agents. Each prompt is phase-scoped and references the task docs as source of truth.

## Branch Cut/Merge Rule (applies to all phases)
1. Finish and validate a phase branch.
2. Merge that phase branch into `feat/m7-post-fixes`.
3. Cut the next phase branch from updated `feat/m7-post-fixes`.
4. Do not cut phase N+1 directly from phase N.

## Phase 0 Kickoff (`feat/m7-postfix-phase0-baseline`)
```text
Task: Execute Post-M7 Phase 0 baseline freeze end-to-end.

Workspace:
- Repo root: C:\Users\AWCS\earl-1
- Follow AGENTS.md rules.
- Source of truth:
  - m7-post-fixes-plan.md
  - post-m7-task-index.md
  - post-m7-task01.md

Branch:
- Use phase branch: feat/m7-postfix-phase0-baseline
- If missing, create from feat/m7-post-fixes and switch to it.

Execution requirements:
1. Execute post-m7-task01.md exactly.
2. Run sync/compile/tests as defined in the task file.
3. Produce baseline artifacts:
   - MQL5/Files/RPEA/test_results/post_m7/baseline_summary.json
   - MQL5/Files/RPEA/test_results/post_m7/todo_scan_pre.txt
4. Validate required suite:
   - run_tests.ps1 -RequiredSuite M7Task08_EndToEnd
5. Do not skip evidence generation.
6. Do not push/merge unless explicitly requested.

Final response format:
1. Overall status (complete/incomplete)
2. Task 01 checklist with PASS/FAIL + evidence paths
3. Files changed
4. Compile/test results
5. Risks/open issues
6. Ready-for-next-phase note (Phase 1)
```

## Phase 1 Kickoff (`feat/m7-postfix-phase1-data-policy`)
```text
Task: Execute Post-M7 Phase 1 data/policy foundation tasks end-to-end.

Workspace:
- Repo root: C:\Users\AWCS\earl-1
- Follow AGENTS.md rules.
- Source of truth:
  - m7-post-fixes-plan.md
  - post-m7-task-index.md
  - post-m7-task02.md
  - post-m7-task03.md
  - post-m7-task04.md
  - post-m7-task05.md
  - post-m7-task06.md

Branch:
- Use phase branch: feat/m7-postfix-phase1-data-policy
- If missing, create from feat/m7-post-fixes and switch to it.

Execution requirements:
1. Execute tasks 02 -> 06 in order. No reordering.
2. Compile checkpoint after each task.
3. Run tests after each task; full run required at task 06.
4. Implement and close:
   - m7_helpers TODOs (rolling spread buffer + ATR percentile)
   - telemetry KPI update path
   - meta-policy real efficiency helpers
5. Generate per-task artifacts:
   - task02_spread_buffer_summary.json
   - task03_atr_percentile_summary.json
   - task04_telemetry_kpi_summary.json
   - task05_metapolicy_efficiency_summary.json
   - task06_phase1_validation.json
6. Keep behavior deterministic; no safety gate regressions.
7. Do not push/merge unless explicitly requested.

Final response format:
1. Overall status
2. Task table for 02..06 with PASS/FAIL/evidence
3. Files changed
4. Compile/test summary
5. Open issues
6. Phase 2 handoff readiness
```

## Phase 2 Kickoff (`feat/m7-postfix-phase2-slo`)
```text
Task: Execute Post-M7 Phase 2 SLO realism tasks end-to-end.

Workspace:
- Repo root: C:\Users\AWCS\earl-1
- Follow AGENTS.md rules.
- Source of truth:
  - m7-post-fixes-plan.md
  - post-m7-task-index.md
  - post-m7-task07.md
  - post-m7-task08.md
  - post-m7-task09.md

Branch:
- Use phase branch: feat/m7-postfix-phase2-slo
- If missing, create from updated feat/m7-post-fixes and switch to it.

Execution requirements:
1. Execute tasks 07 -> 09 in order.
2. Add authoritative SLO closed-trade ingestion API and wire once (no double count).
3. Replace SLO placeholder metrics with rolling computed metrics.
4. Implement persistent SLO throttle policy and remove TODO[M7-Task8] in slo_monitor.mqh.
5. Compile and test after each task.
6. Produce artifacts:
   - task07_slo_ingestion_summary.json
   - task08_slo_metrics_summary.json
   - task09_slo_throttle_summary.json
7. Validate no unsupported_strategy regressions for MR paths.
8. Do not push/merge unless explicitly requested.

Final response format:
1. Overall status
2. Task table for 07..09 with PASS/FAIL/evidence
3. Files changed
4. Compile/test summary
5. Open issues
6. Phase 3 handoff readiness
```

## Phase 3 Kickoff (`feat/m7-postfix-phase3-adaptive-risk`)
```text
Task: Execute Post-M7 Phase 3 adaptive risk tasks end-to-end.

Workspace:
- Repo root: C:\Users\AWCS\earl-1
- Follow AGENTS.md rules.
- Source of truth:
  - m7-post-fixes-plan.md
  - post-m7-task-index.md
  - post-m7-task10.md
  - post-m7-task11.md

Branch:
- Use phase branch: feat/m7-postfix-phase3-adaptive-risk
- If missing, create from updated feat/m7-post-fixes and switch to it.

Execution requirements:
1. Execute tasks 10 -> 11 in order.
2. Implement Adaptive_RiskMultiplier with strict clamps.
3. Close the Phase 2 carry-forward by wiring real `friction_r` into `SLO_OnTradeClosed(...)` (no constant `0.0` close payload).
4. Integrate adaptive risk in allocator behind runtime toggle:
   - default must preserve baseline behavior.
5. Preserve MicroMode and all hard risk/budget gates.
6. Compile/test after each task.
7. Produce artifacts:
   - task10_adaptive_multiplier_summary.json
   - task11_allocator_adaptive_summary.json
8. Do not push/merge unless explicitly requested.

Final response format:
1. Overall status
2. Task table for 10..11 with PASS/FAIL/evidence
3. Files changed
4. Compile/test summary
5. Open issues
6. Phase 4 handoff readiness
```

## Phase 4 Kickoff (`feat/m7-postfix-phase4-learning-bandit`)
```text
Task: Execute Post-M7 Phase 4 learning + bandit shadow tasks end-to-end.

Workspace:
- Repo root: C:\Users\AWCS\earl-1
- Follow AGENTS.md rules.
- Source of truth:
  - m7-post-fixes-plan.md
  - post-m7-task-index.md
  - post-m7-task12.md
  - post-m7-task13.md
  - post-m7-task14.md
  - post-m7-task15.md

Branch:
- Use phase branch: feat/m7-postfix-phase4-learning-bandit
- If missing, create from updated feat/m7-post-fixes and switch to it.

Execution requirements:
1. Execute tasks 12 -> 15 in order.
2. Implement learning load/update persistence with SLO freeze on update.
3. Implement bandit selector + posterior persistence.
4. Implement meta-policy bandit readiness check.
5. Keep shadow mode safe:
   - no live decision takeover unless explicitly enabled.
6. Compile/test after each task.
7. Produce artifacts:
   - task12_learning_load_summary.json
   - task13_learning_update_summary.json
   - task14_bandit_summary.json
   - task15_metapolicy_bandit_shadow.json
8. Remove TODO[M7] stubs in learning/bandit/meta-policy scope.
9. Do not push/merge unless explicitly requested.

Final response format:
1. Overall status
2. Task table for 12..15 with PASS/FAIL/evidence
3. Files changed
4. Compile/test summary
5. Open issues
6. Phase 5 handoff readiness
```

## Phase 5 Kickoff (`feat/m7-postfix-phase5-tuning-closeout`)
```text
Task: Execute Post-M7 Phase 5 tuning + final closeout tasks end-to-end.

Workspace:
- Repo root: C:\Users\AWCS\earl-1
- Follow AGENTS.md rules.
- Source of truth:
  - m7-post-fixes-plan.md
  - post-m7-task-index.md
  - post-m7-task16.md
  - post-m7-task17.md

Branch:
- Use phase branch: feat/m7-postfix-phase5-tuning-closeout
- If missing, create from updated feat/m7-post-fixes and switch to it.

Execution requirements:
1. Execute tasks 16 -> 17 in order.
2. Run controlled walk-forward tuning and produce reproducible reports.
3. Final hard gate:
   - rg -n "TODO\\[M7" MQL5/Include/RPEA MQL5/Experts/FundingPips
   - must return zero matches.
4. Generate final artifacts:
   - step4_tuning_report.json
   - task16_walkforward_summary.json
   - todo_scan_post.txt (empty/no lines)
   - final_summary.json
5. Run final sync/compile/full tests.
6. Update AGENTS.md living doc and final closeout notes.
7. Do not push/merge unless explicitly requested.

Final response format:
1. Overall status
2. Task table for 16..17 with PASS/FAIL/evidence
3. TODO[M7*] closure proof (scan output)
4. Files changed
5. Compile/test summary
6. Risks/open issues
7. Remaining user-only actions
```

## Optional Full-Run Prompt (single agent, all phases)
```text
Task: Execute all post-M7 phases (0..5) end-to-end using the post-M7 task pack.

Source of truth:
- m7-post-fixes-plan.md
- post-m7-task-index.md
- post-m7-task01.md .. post-m7-task17.md

Rules:
1. Execute tasks strictly in numeric order.
2. Respect per-task branch topology from post-m7-task-index.md.
3. Compile/test/evidence gates must pass per task.
4. Stop only on hard blockers; otherwise continue.
5. Final acceptance requires zero TODO[M7*] hits.
6. Do not push/merge unless explicitly requested.
```
