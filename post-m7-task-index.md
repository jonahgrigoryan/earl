# Post-M7 Task Index

This index defines the implementation flow for full `TODO[M7*]` closure and post-M7 hardening.

## Branch Topology

1. `feat/m7-postfix-phase0-baseline`
2. `feat/m7-postfix-phase1-data-policy`
3. `feat/m7-postfix-phase2-slo`
4. `feat/m7-postfix-phase3-adaptive-risk`
5. `feat/m7-postfix-phase4-learning-bandit`
6. `feat/m7-postfix-phase5-tuning-closeout`

## Phase Promotion Model (Required)

Use a base-anchored promotion flow, not chained phase ancestry:

1. Complete all tasks in the current phase branch.
2. Merge current phase branch into `feat/m7-post-fixes`.
3. Cut the next phase branch from updated `feat/m7-post-fixes`.
4. Repeat until Phase 5 completes.

Final promotion:

1. Merge `feat/m7-postfix-phase5-tuning-closeout` into `feat/m7-post-fixes`.
2. Run final gates on `feat/m7-post-fixes` (compile/tests/TODO scan).
3. Merge `feat/m7-post-fixes` into `feat/m7-ensemble-integration`.

## Task Order

| Task | File | Phase Branch | Primary Output |
|---|---|---|---|
| 01 | `post-m7-task01.md` | `feat/m7-postfix-phase0-baseline` | baseline + pre TODO scan artifacts |
| 02 | `post-m7-task02.md` | `feat/m7-postfix-phase1-data-policy` | rolling spread buffer implemented |
| 03 | `post-m7-task03.md` | `feat/m7-postfix-phase1-data-policy` | full ATR percentile implemented |
| 04 | `post-m7-task04.md` | `feat/m7-postfix-phase1-data-policy` | telemetry KPI state + updater |
| 05 | `post-m7-task05.md` | `feat/m7-postfix-phase1-data-policy` | meta-policy real efficiency wiring |
| 06 | `post-m7-task06.md` | `feat/m7-postfix-phase1-data-policy` | Step-1 full validation + docs checkpoint |
| 07 | `post-m7-task07.md` | `feat/m7-postfix-phase2-slo` | SLO trade-outcome ingestion API wired |
| 08 | `post-m7-task08.md` | `feat/m7-postfix-phase2-slo` | rolling SLO metrics computed from outcomes |
| 09 | `post-m7-task09.md` | `feat/m7-postfix-phase2-slo` | persistent SLO throttle policy finalized |
| 10 | `post-m7-task10.md` | `feat/m7-postfix-phase3-adaptive-risk` | adaptive risk multiplier function |
| 11 | `post-m7-task11.md` | `feat/m7-postfix-phase3-adaptive-risk` | allocator adaptive risk integration + toggles |
| 12 | `post-m7-task12.md` | `feat/m7-postfix-phase4-learning-bandit` | calibration load path + safe defaults |
| 13 | `post-m7-task13.md` | `feat/m7-postfix-phase4-learning-bandit` | learning updates + persistence + SLO freeze |
| 14 | `post-m7-task14.md` | `feat/m7-postfix-phase4-learning-bandit` | bandit selector + posterior persistence |
| 15 | `post-m7-task15.md` | `feat/m7-postfix-phase4-learning-bandit` | meta-policy readiness + shadow integration |
| 16 | `post-m7-task16.md` | `feat/m7-postfix-phase5-tuning-closeout` | walk-forward tuning protocol + reports |
| 17 | `post-m7-task17.md` | `feat/m7-postfix-phase5-tuning-closeout` | zero `TODO[M7*]` closure + final release gate |

## Mandatory Flow Rule

Each task must finish with:

1. Compile checkpoint (`0 errors`).
2. Automated suite run with no failures.
3. Task evidence artifact write to `MQL5/Files/RPEA/test_results/post_m7/`.
4. Handoff section completed for the next task.

## Final Hard Gate

Run at Task 17 closeout:

- `rg -n "TODO\\[M7" MQL5/Include/RPEA MQL5/Experts/FundingPips`
- Required result: no matches.
