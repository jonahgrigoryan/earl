# Task 3: RL Pre-Training Script - Implementation Outline

**File**: `MQL5/Scripts/rl_pretrain.mq5`
**Phase**: Phase 3 (Days 8-9)
**Purpose**: Offline Q-table training using synthetic mean-reversion trajectories

## Overview

This task creates a standalone MQL5 script that pre-trains the Q-learning agent's Q-table before live trading begins. The script:
- Generates synthetic spread trajectories using an Ornstein-Uhlenbeck (OU) process
- Simulates episodes with epsilon-greedy exploration
- Updates Q-values using the Bellman equation
- Produces two output files:
  - `RPEA/qtable/mr_qtable.bin` - Trained Q-table for live trading
  - `RPEA/rl/thresholds.json` - Calibrated quantile thresholds for state discretization

**Key constraint**: This script compiles and runs separately from the main EA. It does not block EA compilation but provides the trained Q-table that SignalMR needs to generate actual MR signals.

## Dependencies (Must Exist)

Before implementing, verify `rl_agent.mqh` (Task 2) exists and provides:

1. **Constants**:
   - `RL_NUM_PERIODS` - Number of periods for state (typically 4)
   - `RL_NUM_QUANTILES` - Quantile bins per period (typically 4)
   - `RL_NUM_STATES` - Total states (typically 256)
   - `RL_NUM_ACTIONS` - Total actions (typically 3)

2. **Enums**:
   - `RL_ACTION_EXIT=0`, `RL_ACTION_HOLD=1`, `RL_ACTION_ENTER=2`

3. **Functions** (already implemented in Task 2):
   - `RL_InitQTable()` - Initialize Q-table to zeros
   - `RL_StateFromSpread(double &changes[], int periods)` → int
   - `RL_ActionForState(int state)` → RL_ACTION
   - `RL_GetQAdvantage(int state)` → double
   - `RL_QuantileBin(double value)` → int [0-3]
   - `RL_BellmanUpdate(int state, int action, double reward, int next_state, double alpha, double gamma)` - Updates Q-value
   - `RL_SaveQTable(string path)` → bool
   - `RL_LoadQTable(string path)` → bool

**Important**: `RL_BellmanUpdate()` is critical for this script. It must be defined in `rl_agent.mqh` from Task 2.

## Implementation Steps

### Step 3.1: Script Structure and Inputs

If `MQL5/Scripts/` does not exist, create it before adding the script.

Create `MQL5/Scripts/rl_pretrain.mq5` with script inputs and OnStart handler.
After saving locally, copy it to the MT5 data folder:
`C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Scripts\rl_pretrain.mq5`

```cpp
#property script_show_inputs

#include <RPEA/rl_agent.mqh>

// Training hyperparameters
input int    TrainingEpisodes    = 10000;   // Number of training episodes
input double LearningRate        = 0.10;    // Alpha (α) for Bellman update
input double DiscountFactor      = 0.99;    // Gamma (γ) for future rewards
input double EpsilonStart        = 1.0;     // Initial exploration rate
input double EpsilonEnd          = 0.1;     // Final exploration rate
input string QTableOutputPath    = "RPEA/qtable/mr_qtable.bin";
input string ThresholdsOutputPath = "RPEA/rl/thresholds.json";

// OU process parameters for spread simulation
input double OU_Theta            = 0.1;     // Mean reversion speed
input double OU_Sigma            = 0.02;    // Volatility
input int    EpisodeLength       = 100;     // Timesteps per episode

// Reward function parameters
input double CostPerStep         = 0.001;   // Cost for holding position (c)
input double NewsPenalty         = 0.005;   // Penalty for trades in news windows
input double BarrierPenalty      = 0.01;    // Penalty for breaching floor/target

void OnStart() {
    Print("=== RL Pre-Training Started ===");
    Print("Episodes: ", TrainingEpisodes);
    Print("Learning Rate: ", LearningRate);
    Print("Discount Factor: ", DiscountFactor);

    // Ensure output folders exist under MQL5/Files
    if(!EnsureOutputFolders()) {
        Print("ERROR: Failed to prepare output folders");
        return;
    }

    // Initialize Q-table
    RL_InitQTable();
    Print("Q-table initialized");

    // Track best reward for reporting
    double best_reward = -1e308;
    double cumulative_reward = 0.0;

    // Training loop
    for(int ep = 0; ep < TrainingEpisodes; ep++) {
        // Decay epsilon: linear schedule
        double epsilon = EpsilonStart - (EpsilonStart - EpsilonEnd) * ep / TrainingEpisodes;

        double ep_reward = RunEpisode(epsilon, LearningRate, DiscountFactor);
        cumulative_reward += ep_reward;

        if(ep_reward > best_reward) {
            best_reward = ep_reward;
        }

        // Progress reporting every 1000 episodes
        if(ep % 1000 == 0) {
            double avg_reward = cumulative_reward / (ep + 1);
            PrintFormat("Episode %d/%d | Epsilon: %.3f | Avg Reward: %.4f | Best: %.4f",
                ep, TrainingEpisodes, epsilon, avg_reward, best_reward);
        }
    }

    Print("=== Training Complete ===");
    Print("Final Average Reward: ", cumulative_reward / TrainingEpisodes);

    // Save outputs
    if(RL_SaveQTable(QTableOutputPath)) {
        Print("Q-table saved to: ", QTableOutputPath);
    } else {
        Print("ERROR: Failed to save Q-table");
    }

    if(RL_SaveThresholds(ThresholdsOutputPath)) {
        Print("Thresholds saved to: ", ThresholdsOutputPath);
    } else {
        Print("WARNING: Failed to save thresholds (using defaults)");
    }

    Print("=== RL Pre-Training Finished ===");
}
```

**Compile checkpoint**: Script structure compiles with all inputs defined.

### Step 3.2: Episode Simulation

Implement `RunEpisode()` to simulate one training episode:

```cpp
double RunEpisode(double epsilon, double alpha, double gamma) {
    // Generate synthetic spread trajectory
    double spread_changes[];
    GenerateSpreadTrajectory(spread_changes, EpisodeLength);

    // Initialize episode state
    int state = BuildStateFromIndex(spread_changes, 0); // Current RL state
    int position = 0;                 // -1=short, 0=flat, 1=long
    double spread_level = 0.0;        // Cumulative spread (mean-centered)
    double cumulative_reward = 0.0;

    // Simulate timesteps
    for(int t = 0; t < EpisodeLength - 1; t++) {
        // Update spread level
        spread_level += spread_changes[t];

        // Select action (epsilon-greedy)
        int action;
        if(MathRand() / 32768.0 < epsilon) {
            // Exploration: random action
            action = MathRand() % RL_NUM_ACTIONS;
        } else {
            // Exploitation: greedy action from Q-table
            action = RL_ActionForState(state);
        }

        // Simulate market conditions for this timestep
        bool news_blocked = SimulateNewsWindow(t, EpisodeLength);
        bool barrier_breached = SimulateBarrierBreach(spread_level, position);

        // Execute action and calculate reward
        double reward = ExecuteAction(action, position, spread_level, CostPerStep,
                                       news_blocked, barrier_breached);

        // Calculate next state
        int next_state = BuildStateFromIndex(spread_changes, t + 1);

        // Bellman update
        RL_BellmanUpdate(state, action, reward, next_state, alpha, gamma);

        // Advance to next timestep
        state = next_state;
        cumulative_reward += reward;
    }

    return cumulative_reward;
}

// Build RL state from a rolling window of recent changes
int BuildStateFromIndex(const double &changes[], const int index) {
    double window[];
    ArrayResize(window, RL_NUM_PERIODS);
    int total = ArraySize(changes);

    for(int i = 0; i < RL_NUM_PERIODS; i++) {
        int src = index - i;
        if(src >= 0 && src < total) {
            window[i] = changes[src];  // Most recent first
        } else {
            window[i] = 0.0;
        }
    }

    return RL_StateFromSpread(window, RL_NUM_PERIODS);
}
```

**Compile checkpoint**: Episode simulation compiles with RL function calls.

### Step 3.3: Action Execution and Reward Function

Implement `ExecuteAction()` following the reward specification from the workflow:

```cpp
double ExecuteAction(int action, int &position, double spread_level,
                     double cost_per_step, bool news_blocked, bool barrier_breached) {
    double reward = 0.0;

    switch(action) {
        case RL_ACTION_ENTER:
            if(position == 0) {
                // Enter position opposite to spread deviation (mean reversion)
                // If spread > 0, expect reversion down → short
                // If spread < 0, expect reversion up → long
                position = (spread_level > 0) ? -1 : 1;
            }
            break;

        case RL_ACTION_HOLD:
            // No position change
            break;

        case RL_ACTION_EXIT:
            if(position != 0) {
                position = 0;
            }
            break;
    }

    // Base reward per spec: r_{t+1} = A_t * (θ - Y_t) - c * |A_t|
    // θ = 0 (mean-centered), Y_t = spread_level, A_t = position
    reward += position * (0.0 - spread_level);
    reward -= cost_per_step * MathAbs((double)position);

    // Penalties
    if(news_blocked)
        reward -= NewsPenalty;     // Penalty for trades in news windows
    if(barrier_breached)
        reward -= BarrierPenalty;  // Penalty for breaching barriers

    return reward;
}
```

**Compile checkpoint**: Reward function compiles with correct formula.

### Step 3.4: Spread Trajectory Generation

Implement synthetic spread generation using OU process:

```cpp
void GenerateSpreadTrajectory(double &changes[], int length) {
    ArrayResize(changes, length);

    // Initialize OU process
    double spread = 0.0;  // Start at mean
    double dt = 1.0;      // Time step

    for(int i = 0; i < length; i++) {
        // dY = -θ * Y * dt + σ * dW
        double dW = MathRandomNormal(0, 1) * MathSqrt(dt);
        double d_spread = -OU_Theta * spread * dt + OU_Sigma * dW;

        changes[i] = d_spread;
        spread += d_spread;
    }
}

// Box-Muller transform for normal distribution
double MathRandomNormal(double mean, double stddev) {
    double u1 = (MathRand() + 1) / 32768.0;  // Avoid log(0)
    double u2 = MathRand() / 32768.0;
    const double pi = 3.14159265358979323846;

    double z = MathSqrt(-2.0 * MathLog(u1)) * MathCos(2.0 * pi * u2);
    return mean + stddev * z;
}
```

**Compile checkpoint**: OU process simulation compiles with normal distribution.

### Step 3.5: Market Condition Simulation

Implement helper functions for simulated market conditions:

```cpp
// Simulate news window blockage (randomly ~10% of timesteps)
bool SimulateNewsWindow(int timestep, int episode_length) {
    // Simulate news events occurring ~10% of the time
    // In real trading, use actual News_IsBlocked()
    return (MathRand() % 100) < 10;
}

// Simulate barrier breach (floor/target)
bool SimulateBarrierBreach(double spread_level, int position) {
    if(position == 0) return false;  // No position, no breach

    // Simulate barriers at ±2 standard deviations
    double barrier_threshold = 2.0 * OU_Sigma;  // Approximate

    return MathAbs(spread_level) > barrier_threshold;
}
```

**Compile checkpoint**: Market simulation helpers compile.

### Step 3.6: Threshold Calibration and Saving

Implement `RL_SaveThresholds()` to calibrate and save quantile thresholds:

```cpp
bool RL_SaveThresholds(const string path) {
    // Collect training statistics for threshold calibration
    int sample_episodes = MathMin(TrainingEpisodes, 100);
    int total_samples = sample_episodes * EpisodeLength;
    if(total_samples <= 0) return false;

    double all_changes[];
    ArrayResize(all_changes, total_samples);

    int idx = 0;
    for(int ep = 0; ep < sample_episodes; ep++) {  // Sample first 100 episodes
        double trajectory[];
        GenerateSpreadTrajectory(trajectory, EpisodeLength);

        for(int t = 0; t < EpisodeLength && idx < total_samples; t++) {
            all_changes[idx++] = trajectory[t];
        }
    }

    // Sort for percentile calculation
    ArraySort(all_changes, 0, idx);

    // Calculate thresholds at 25th, 50th, 75th percentiles
    int n = idx;
    if(n < 4) return false;

    // k-thresholds at 25%, 50%, 75% percentiles
    double k0 = all_changes[n / 4];           // 25th percentile
    double k1 = all_changes[n / 2];           // 50th percentile (median)
    double k2 = all_changes[3 * n / 4];       // 75th percentile

    // Calculate reference sigma from training distribution
    double sum = 0.0;
    for(int i = 0; i < n; i++) sum += all_changes[i];
    double mean = sum / n;

    double variance_sum = 0.0;
    for(int i = 0; i < n; i++) {
        double diff = all_changes[i] - mean;
        variance_sum += diff * diff;
    }
    double sigma_ref = MathSqrt(variance_sum / n);

    // Get current timestamp
    string calibrated_at = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);

    // Write JSON file
    int handle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE) {
        Print("ERROR: Cannot create thresholds file: ", path);
        return false;
    }

    string json = StringFormat(
        "{\n"
        "  \"k_thresholds\": [%.6f, %.6f, %.6f],\n"
        "  \"sigma_ref\": %.6f,\n"
        "  \"calibrated_at\": \"%s\",\n"
        "  \"training_episodes\": %d,\n"
        "  \"ou_theta\": %.3f,\n"
        "  \"ou_sigma\": %.3f\n"
        "}",
        k0, k1, k2,
        sigma_ref,
        calibrated_at,
        TrainingEpisodes,
        OU_Theta,
        OU_Sigma
    );

    FileWriteString(handle, json);
    FileClose(handle);

    PrintFormat("Thresholds calibrated: k=[%.6f, %.6f, %.6f], sigma_ref=%.6f",
        k0, k1, k2, sigma_ref);

    return true;
}
```

**Compile checkpoint**: Threshold calibration and file I/O compile.

### Step 3.7: Output Directory Creation

Implement directory creation helper (uses existing persistence folder setup):

```cpp
bool EnsureOutputFolders() {
    // Create all standard RPEA folders under MQL5/Files
    Persistence_EnsureFolders();

    // RL thresholds live under RPEA/rl (not covered by Persistence_EnsureFolders)
    ResetLastError();
    if(!FolderCreate(RPEA_DIR"/rl")) {
        // FolderCreate returns false on failure; tolerate if already exists
        int err = GetLastError();
        if(err != 0) {
            Print("ERROR: Failed to create RPEA/rl folder, err=", err);
            return false;
        }
    }
    return true;
}
```

**Compile checkpoint**: Directory creation compiles.

## Output Files

After running the script, two files are created:

### 1. Q-Table Binary (`RPEA/qtable/mr_qtable.bin`)

Format: Raw double values, `RL_NUM_STATES * RL_NUM_ACTIONS` entries.

Used by: `RL_LoadQTable()` in `rl_agent.mqh` during EA initialization.

### 2. Thresholds JSON (`RPEA/rl/thresholds.json`)

```json
{
  "k_thresholds": [-0.015, 0.0, 0.018],
  "sigma_ref": 0.012,
  "calibrated_at": "2026-01-30 20:15",
  "training_episodes": 10000,
  "ou_theta": 0.1,
  "ou_sigma": 0.02
}
```

Used by: `RL_LoadThresholds()` in `rl_agent.mqh` for state discretization.

**Staleness rule**: If `calibrated_at` is older than 30 days, live trading falls back to fixed 3% thresholds.

## Input Parameters Reference

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| TrainingEpisodes | 10000 | 1000-100000 | Number of training episodes |
| LearningRate | 0.10 | 0.01-0.5 | Alpha (α) for Bellman update |
| DiscountFactor | 0.99 | 0.9-0.999 | Gamma (γ) for future rewards |
| EpsilonStart | 1.0 | 0.5-1.0 | Initial exploration rate |
| EpsilonEnd | 0.1 | 0.01-0.3 | Final exploration rate |
| OU_Theta | 0.1 | 0.05-0.5 | Mean reversion speed |
| OU_Sigma | 0.02 | 0.01-0.05 | Volatility |
| EpisodeLength | 100 | 50-500 | Timesteps per episode |
| CostPerStep | 0.001 | 0.0001-0.01 | Holding cost per timestep |
| NewsPenalty | 0.005 | 0.001-0.02 | Penalty for news-window trades |
| BarrierPenalty | 0.01 | 0.005-0.05 | Penalty for barrier breaches |

## Testing Checklist

- [ ] Script compiles without errors
- [ ] Q-table file created at `RPEA/qtable/mr_qtable.bin`
- [ ] Thresholds file created at `RPEA/rl/thresholds.json`
- [ ] Q-table has correct dimensions (RL_NUM_STATES × RL_NUM_ACTIONS)
- [ ] Thresholds JSON is valid and parseable
- [ ] Q-table can be loaded by `RL_LoadQTable()` in the mainEA
- [ ] Training reward converges (avg reward increases over episodes)
- [ ] Script runs to completion within reasonable time (< 5 minutes for 10000 episodes)

## Run Instructions

1. Open MetaEditor
2. Copy `MQL5/Scripts/rl_pretrain.mq5` from the repo to the MT5 data folder:
   `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Scripts\`
3. Navigate to `MQL5/Scripts/` in MetaEditor (MT5 data folder)
4. Compile `rl_pretrain.mq5` (MetaEditor or command line)
5. Run the script from the Navigator or Strategy Tester
6. Monitor the Experts tab for progress output
7. Verify output files are created:
   - Check `MQL5/Files/RPEA/qtable/mr_qtable.bin`
   - Check `MQL5/Files/RPEA/rl/thresholds.json`

## Integration with Main EA

After running the pre-training script:

1. Ensure the EA loads the trained artifacts (e.g., call `RL_LoadQTable(FILE_QTABLE_BIN)` and `RL_LoadThresholds()` during init or module init)
2. `RL_ActionForState()` can now return trained actions instead of default HOLD
3. SignalMR can generate actual MR signals (not just `hasSetup=false`)

## Compile Checkpoint

After completing all steps, run:

```
MetaEditor64.exe /compile:MQL5\Scripts\rl_pretrain.mq5 /log:MQL5\Scripts\compile_rl_pretrain.log
✅ rl_pretrain.mq5 compiles independently in the MT5 data folder (separate from main EA)
✅ Script runs without errors
✅ Q-table file created (verify file size: ~6KB for 256×3 states)
✅ Thresholds JSON is valid
MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
✅ Main EA compiles after artifacts are generated
✅ SignalMR returns hasSetup=true when conditions met (after Task 3 complete)
```

## Notes

- The script is designed to run ONCE before live trading begins
- Re-running with different parameters produces different Q-tables
- For production, consider:
  - Using actual historical spread data instead of synthetic OU process
  - Running more episodes (50000-100000) for better convergence
  - Saving checkpoint Q-tables periodically during long training runs
- The OU parameters (theta, sigma) should be calibrated to historical spread behavior
- Training can be distributed: run multiple scripts with different seeds and pick the best Q-table
