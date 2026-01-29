# M7 Task 02 (RL Agent) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement RL Q-table infrastructure (state discretization, action selection, persistence, Bellman update) and add unit tests to verify expected behavior.

**Architecture:** The RL module lives in MQL5/Include/RPEA/rl_agent.mqh and exposes deterministic, compile-safe functions with safe defaults when the Q-table is unloaded. Tests live in Tests/RPEA/test_rl_agent.mqh and are wired into Tests/RPEA/run_automated_tests_ea.mq5.

**Tech Stack:** MQL5 (EA + tests), existing test harness in Tests/RPEA, file I/O via FileOpen/FileWrite in MQL5/Files.

### Task 1: RL Module Constants and Globals

**Files:**
- Modify: MQL5/Include/RPEA/rl_agent.mqh

**Step 1: Write failing test for constants**
Add in Tests/RPEA/test_rl_agent.mqh:
`
bool TestRL_Constants() {
   g_current_test = "TestRL_Constants";
   ASSERT_EQUALS(4, RL_NUM_PERIODS, "RL_NUM_PERIODS");
   ASSERT_EQUALS(4, RL_NUM_QUANTILES, "RL_NUM_QUANTILES");
   ASSERT_EQUALS(256, RL_NUM_STATES, "RL_NUM_STATES");
   ASSERT_EQUALS(3, RL_NUM_ACTIONS, "RL_NUM_ACTIONS");
   return (g_test_failed == 0);
}
`

**Step 2: Run tests to see failure**
Run: MetaEditor64.exe /compile:Tests\RPEA\run_automated_tests_ea.mq5 /log:Tests\RPEA\compile_automated_tests.log
Expected: compile fails (missing test file or constants).

**Step 3: Implement constants + enum**
In MQL5/Include/RPEA/rl_agent.mqh:
`
#define RL_NUM_PERIODS    4
#define RL_NUM_QUANTILES  4
#define RL_NUM_STATES     256
#define RL_NUM_ACTIONS    3

enum RL_ACTION {
   RL_ACTION_EXIT  = 0,
   RL_ACTION_HOLD  = 1,
   RL_ACTION_ENTER = 2
};
`

**Step 4: Re-compile**
Expected: compile passes (constants now defined).

**Step 5: Commit**
`
git add MQL5/Include/RPEA/rl_agent.mqh Tests/RPEA/test_rl_agent.mqh

git commit -m "M7: Task 02 - RL constants"
`

### Task 2: Q-table Storage + Init

**Files:**
- Modify: MQL5/Include/RPEA/rl_agent.mqh
- Modify: Tests/RPEA/test_rl_agent.mqh

**Step 1: Write failing test**
`
bool TestRL_InitQTable() {
   g_current_test = "TestRL_InitQTable";
   RL_InitQTable();
   ASSERT_EQUALS(0.0, g_qtable[0][0], "Q-table initialized");
   return (g_test_failed == 0);
}
`

**Step 2: Implement storage + init**
`
double g_qtable[RL_NUM_STATES][RL_NUM_ACTIONS];
bool   g_qtable_loaded = false;

void RL_InitQTable() {
   ArrayInitialize(g_qtable, 0.0);
   g_qtable_loaded = false;
}
`

**Step 3: Run compile**
Expected: compile passes.

**Step 4: Commit**
`
git add MQL5/Include/RPEA/rl_agent.mqh Tests/RPEA/test_rl_agent.mqh

git commit -m "M7: Task 02 - RL Q-table init"
`

### Task 3: Thresholds + State Discretization

**Files:**
- Modify: MQL5/Include/RPEA/rl_agent.mqh
- Modify: Tests/RPEA/test_rl_agent.mqh

**Step 1: Write failing tests**
`
bool TestRL_QuantileBin() {
   g_current_test = "TestRL_QuantileBin";
   ASSERT_EQUALS(0, RL_QuantileBin(-0.05), "large negative");
   ASSERT_EQUALS(1, RL_QuantileBin(-0.02), "small negative");
   ASSERT_EQUALS(2, RL_QuantileBin(0.01), "small positive");
   ASSERT_EQUALS(3, RL_QuantileBin(0.05), "large positive");
   return (g_test_failed == 0);
}

bool TestRL_StateFromSpread() {
   g_current_test = "TestRL_StateFromSpread";
   double changes[4] = {-0.05, -0.02, 0.01, 0.05};
   int state = RL_StateFromSpread(changes, 4);
   ASSERT_TRUE(state >= 0 && state < RL_NUM_STATES, "state in range");
   return (g_test_failed == 0);
}
`

**Step 2: Implement thresholds + bins**
`
double g_quantile_thresholds[3] = {-0.03, 0.0, 0.03};

typedef struct {
   double k_thresholds[3];
   double sigma_ref;
   datetime calibrated_at;
} RL_Thresholds;

bool RL_LoadThresholds() { return false; }

int RL_QuantileBin(double value) { ... }

int RL_StateFromSpread(double &changes[], int periods) { ... }
`

**Step 3: Compile**
Expected: pass.

**Step 4: Commit**
`
git add MQL5/Include/RPEA/rl_agent.mqh Tests/RPEA/test_rl_agent.mqh

git commit -m "M7: Task 02 - RL thresholds and state"
`

### Task 4: Action Selection + Q-Advantage

**Files:**
- Modify: MQL5/Include/RPEA/rl_agent.mqh
- Modify: Tests/RPEA/test_rl_agent.mqh

**Step 1: Write failing tests**
`
bool TestRL_ActionDefaults() {
   g_current_test = "TestRL_ActionDefaults";
   g_qtable_loaded = false;
   ASSERT_EQUALS(RL_ACTION_HOLD, RL_ActionForState(0), "default hold");
   return (g_test_failed == 0);
}

bool TestRL_QAdvantage() {
   g_current_test = "TestRL_QAdvantage";
   RL_InitQTable();
   g_qtable_loaded = true;
   g_qtable[0][0] = 0.0; g_qtable[0][1] = 0.0; g_qtable[0][2] = 1.0;
   double adv = RL_GetQAdvantage(0);
   ASSERT_TRUE(adv > 0.5, "advantage > 0.5");
   return (g_test_failed == 0);
}
`

**Step 2: Implement**
`
int RL_ActionForState(int state) { ... }

double RL_GetQAdvantage(int state) { ... }
`

**Step 3: Compile**
Expected: pass.

**Step 4: Commit**
`
git add MQL5/Include/RPEA/rl_agent.mqh Tests/RPEA/test_rl_agent.mqh

git commit -m "M7: Task 02 - RL action and advantage"
`

### Task 5: File I/O (Save/Load)

**Files:**
- Modify: MQL5/Include/RPEA/rl_agent.mqh
- Modify: Tests/RPEA/test_rl_agent.mqh
- Modify: Tests/RPEA/run_automated_tests_ea.mq5

**Step 1: Write failing I/O test**
`
bool TestRL_QTableSaveLoad() {
   g_current_test = "TestRL_QTableSaveLoad";
   RL_InitQTable();
   g_qtable_loaded = true;
   g_qtable[0][0] = 1.23;

   string test_path = "RPEA/qtable/mr_qtable_test.bin";
   FileDelete(test_path);
   bool saved = RL_SaveQTable(test_path);
   ASSERT_TRUE(saved, "saved");

   RL_InitQTable();
   bool loaded = RL_LoadQTable(test_path);
   ASSERT_TRUE(loaded, "loaded");
   ASSERT_TRUE(MathAbs(g_qtable[0][0] - 1.23) < 1e-6, "value restored");
   FileDelete(test_path);
   return (g_test_failed == 0);
}
`

**Step 2: Implement file I/O**
`
bool RL_LoadQTable(string path) { ... }

bool RL_SaveQTable(string path) { ... }
`

**Step 3: Wire test runner**
Add #include "test_rl_agent.mqh" to Tests/RPEA/run_automated_tests_ea.mq5 and call all new tests.

**Step 4: Compile**
Expected: pass.

**Step 5: Commit**
`
git add MQL5/Include/RPEA/rl_agent.mqh Tests/RPEA/test_rl_agent.mqh Tests/RPEA/run_automated_tests_ea.mq5

git commit -m "M7: Task 02 - RL Q-table I/O"
`

### Task 6: Bellman Update

**Files:**
- Modify: MQL5/Include/RPEA/rl_agent.mqh
- Modify: Tests/RPEA/test_rl_agent.mqh

**Step 1: Write failing test**
`
bool TestRL_BellmanUpdate() {
   g_current_test = "TestRL_BellmanUpdate";
   RL_InitQTable();
   g_qtable_loaded = true;
   RL_BellmanUpdate(0, 2, 1.0, 1, 0.5, 0.99);
   ASSERT_TRUE(g_qtable[0][2] > 0.0, "Q updated");
   return (g_test_failed == 0);
}
`

**Step 2: Implement**
`
void RL_BellmanUpdate(int state, int action, double reward, int next_state, double alpha, double gamma) { ... }
`

**Step 3: Compile**
Expected: pass.

**Step 4: Commit**
`
git add MQL5/Include/RPEA/rl_agent.mqh Tests/RPEA/test_rl_agent.mqh

git commit -m "M7: Task 02 - RL Bellman update"
`

### Task 7: Automated Runner Integration

**Files:**
- Modify: Tests/RPEA/run_automated_tests_ea.mq5

**Step 1: Call tests**
Add a new block to run all RL tests (order: constants, init, thresholds, state, action, advantage, I/O, Bellman).

**Step 2: Compile**
Expected: compile passes.

**Step 3: Commit**
`
git add Tests/RPEA/run_automated_tests_ea.mq5

git commit -m "M7: Task 02 - RL tests wired"
`

---

## Execution Handoff

Plan complete and saved to docs/plans/2026-01-29-m7-task02-rl-agent.md. Two execution options:

1) **Subagent-Driven (this session)** – I dispatch fresh subagent per task, review between tasks, fast iteration
2) **Parallel Session (separate)** – Open new session with executing-plans, batch execution with checkpoints

Which approach?
