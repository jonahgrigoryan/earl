# M7 Task 02 - RL Agent Q-Table Infrastructure

Branch name: feat/m7-task02-rl-agent (cut from feat/m7-phase1-foundation)

Source of truth: docs/m7-final-workflow.md (Phase 1, Task 2)
Plan: docs/plans/2026-01-29-m7-task02-rl-agent.md

## Objective
Implement the RL Q-table infrastructure for MR, including state discretization, action selection, persistence, and Bellman update. Add unit tests to verify expected behavior and wire them into the automated test runner.

## Scope
- Implement all RL functions in MQL5/Include/RPEA/rl_agent.mqh
- Add unit tests in Tests/RPEA/test_rl_agent.mqh
- Wire tests into Tests/RPEA/run_automated_tests_ea.mq5

## Files to Modify
- MQL5/Include/RPEA/rl_agent.mqh
- Tests/RPEA/test_rl_agent.mqh (new)
- Tests/RPEA/run_automated_tests_ea.mq5

## Key Requirements (from workflow)
- State space: 4 periods, 4 quantile bins, 256 states
- Actions: EXIT/HOLD/ENTER
- Safe defaults: HOLD action when Q-table not loaded; advantage = 0.5 when undefined
- Thresholds: fixed 3% by default; optional calibration via Files/RPEA/rl/thresholds.json
- File I/O: use FILE_QTABLE_BIN for production; tests must use a dedicated test file
- Bellman update available for both EA and pre-training script

## Workflow Steps (Compile after each step)

### Step 2.1: Constants + Enum
- Define RL_NUM_PERIODS, RL_NUM_QUANTILES, RL_NUM_STATES, RL_NUM_ACTIONS
- Define RL_ACTION enum

### Step 2.2: Q-Table Storage + Init
- Define g_qtable[states][actions] and g_qtable_loaded
- Implement RL_InitQTable()

### Step 2.3: State Discretization
- Implement threshold storage + optional RL_LoadThresholds()
- Implement RL_QuantileBin() and RL_StateFromSpread()

### Step 2.4: Action Selection + Advantage
- Implement RL_ActionForState() and RL_GetQAdvantage()

### Step 2.5: File I/O
- Implement RL_LoadQTable() and RL_SaveQTable()
- Use FILE_QTABLE_BIN for production path

### Step 2.6: Bellman Update
- Implement RL_BellmanUpdate()

### Tests + Runner
- Add unit tests for each function in Tests/RPEA/test_rl_agent.mqh
- Wire tests into Tests/RPEA/run_automated_tests_ea.mq5

## Verification
- Compile after each step:
  MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- Compile automated test runner after test wiring:
  MetaEditor64.exe /compile:Tests\RPEA\run_automated_tests_ea.mq5 /log:Tests\RPEA\compile_automated_tests.log

## Hold Point
Stop after Task 02 is complete and compiled; report results before moving to Phase 2.
