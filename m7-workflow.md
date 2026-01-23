# M7 Implementation Workflow - Ensemble Integration

## Overview

M7 transforms RPEA from a single-strategy EA (BWISC) into a dual-strategy ensemble (BWISC + MR) with intelligent strategy selection. This workflow breaks M7 into 5 phases with clear dependencies, compile/test checkpoints, and incremental delivery.

**Total Scope:** 8 tasks over ~12-15 days (2-3 weeks)

---

## Inputs and Artifacts (per finalspec/prd)

**Inputs to add or wire (RPEA.mq5 + config.mqh):**
- Ensemble control: `BWISC_ConfCut` (0.70), `MR_ConfCut` (0.80), `EMRT_FastThresholdPct` (40), `CorrelationFallbackRho` (0.50)
- MR parameters: `MR_RiskPct_Default` (0.90%), `MR_TimeStopMin` (60), `MR_TimeStopMax` (90), `MR_LongOnly` (false)
- EMRT formation: `EMRT_ExtremeThresholdMult` (2.0), `EMRT_VarCapMult` (2.5), `EMRT_BetaGridMin`/`EMRT_BetaGridMax` (-2.0/+2.0)
- Execution mode: `UseXAUEURProxy` (true; proxy-only in M7, false disables MR signals with warning)
- Feature flags: `UseBanditMetaPolicy` (true), `BanditShadowMode` (false), `EnableMR` (true)

**Tests to update when adding inputs:**
- `Tests/RPEA/test_config_validation.mqh` (new getters/clamps if added)
- `Tests/RPEA/run_automated_tests_ea.mq5` (register M7 test suites)
- New suites (names TBD): EMRT, RL agent, SignalMR, meta-policy, telemetry/regime

**Artifacts to persist:**
- EMRT cache: `Files/RPEA/emrt/emrt_cache.json`
- Q-table: `Files/RPEA/qtable/mr_qtable.bin`
- Bandit posterior: `Files/RPEA/bandit/posterior.json`
- Calibration: `Files/RPEA/calibration/calibration.json`
- Liquidity stats: `Files/RPEA/liquidity/spread_slippage_stats.json`
- Telemetry logs: `Files/RPEA/telemetry/...` (define in telemetry task)

---

## Phase-Based Implementation

### Phase 1: Foundation - EMRT & RL Infrastructure (Tasks 1-2) - Days 1-4

**Goal:** Build the mathematical foundations needed for MR signals.

**Tasks:**
1. **EMRT Formation Job** (`emrt.mqh`)
   - Compute EMRT on synthetic XAUEUR series (P_synth = XAUUSD/EURUSD, M1, forward-fill gaps)
   - Detect extrema with `C = EMRT_ExtremeThresholdMult * sigma_Y`
   - Enforce variance cap: `S^2(Y) <= EMRT_VarCapMult * Var(Y)` over lookback
   - Grid search beta in `[EMRT_BetaGridMin, EMRT_BetaGridMax]` and choose beta* minimizing EMRT
   - Weekly refresh with 60-90 trading day lookback
   - Persist EMRT metrics (beta*, rank, p50) to `Files/RPEA/emrt/emrt_cache.json`
   - Add accessors (e.g., `EMRT_GetRank`, `EMRT_GetP50`, `EMRT_GetBeta`)

2. **RL Agent Q-Table Infrastructure** (`rl_agent.mqh`)
   - Q-table data structure (256 states x actions)
   - Load/save Q-table to `Files/RPEA/qtable/mr_qtable.bin`
   - State discretization: 4 periods with 4 levels each = 4^4 = 256 states; k=3% threshold for discretizing percentage changes
   - Action selection (epsilon-greedy in training, pure exploitation in live)
   - Q-advantage helper (max(Q) - mean(Q), normalized to [0,1])
   - Bellman update helper (used by pre-training script)

**Dependencies:**
- Task 1 and Task 2 are independent
- Both are prerequisites for Phase 2 and Phase 3

**Compile/Test Checkpoint:**
```cpp
// After Phase 1:
- Call EMRT_RefreshWeekly() and see EMRT calculated for XAUEUR
- See EMRT cache file created in Files/RPEA/emrt/emrt_cache.json
- Load/save Q-table (even if empty initially)
- See state discretization working (spread -> state_id)
```

**Test in Strategy Tester:**
- Run EA for 1 day, verify EMRT calculation runs
- Check EMRT cache file exists and has valid data
- Test Q-table load/save (create empty table, save, reload)

**Branch:** `feat/m7-phase1-foundation`

---

### Phase 2: Pre-Training Script (Task 3) - Days 5-7

**Goal:** Generate pre-trained Q-table from simulated data.

**Tasks:**
3. **RL Pre-Training Script** (standalone script or EA mode)
   - Simulate OU processes with varying (mu, theta, sigma)
   - Generate 1000+ synthetic spread paths
   - Reward function: `r_{t+1} = A_t * (theta - Y_t) - c * |A_t|` where theta=0 (mean), plus:
     - Barrier penalties tied to server-day floors and +10% target
     - News penalties per News Compliance (Master 10-min window blocks, internal buffer penalties)
   - Run Q-learning for 10,000 episodes
   - Epsilon-greedy exploration (epsilon = 0.10)
   - Save trained Q-table to `Files/RPEA/qtable/mr_qtable.bin`
   - Can run offline (no live market data needed)

**Dependencies:**
- Requires Phase 1 complete (Q-table infrastructure)
- Can be done in parallel with Phase 3 (does not block SignalMR)

**Compile/Test Checkpoint:**
```cpp
// After Phase 2:
- Run pre-training script standalone
- See Q-table file generated with 256 states populated
- Verify Q-values are reasonable (not all zeros)
- Load Q-table in main EA and see it's valid
```

**Test:**
- Run pre-training script, verify Q-table file created
- Check Q-table has non-zero values
- Load Q-table in main EA, verify no errors

**Branch:** `feat/m7-phase2-pretraining`

**Note:** This can be done in parallel with Phase 3 if you want to start SignalMR implementation early.

---

### Phase 3: SignalMR Implementation (Task 4) - Days 8-10

**Goal:** Implement MR signal generation using EMRT + RL.

**Tasks:**
4. **SignalMR Module** (`signals_mr.mqh`)
   - Call EMRT_RefreshWeekly() and EMRT_GetRank / EMRT_GetP50
   - Get RL state from recent spread trajectory
   - Get RL action (enter/hold/exit) and Q-advantage
   - Define EMRT_fastness = `1.0 - EMRT_rank` (lower rank = faster reversion)
   - Compute confidence: `0.5 * EMRT_fastness + 0.5 * Q_advantage` (normalized 0-1)
   - Calculate expected_hold_min: `clamp(EMRT_p50, MR_TimeStopMin, MR_TimeStopMax)`
   - Generate SL/TP based on spread mean reversion
   - Respect news windows (Master +/-300s, Evaluation internal buffer)
   - Skip if symbol overlap with active or pending positions (any strategy)
   - Respect MR_LongOnly for direction
   - XAUEUR: proxy mode only for M7 (XAUUSD execution); if UseXAUEURProxy=false, log warning and return no setup (replication deferred)
   - Fix init validation in `MQL5/Experts/FundingPips/RPEA.mq5`: change fail-fast error (lines 238-242) to warning when UseXAUEURProxy=false; allow EA to start but SignalMR skips XAUEUR signals
   - Output matches current signature: `hasSetup`, `setupType`, `slPoints`, `tpPoints`, `bias`, `confidence`
   - Persist expected_hold / expected_R for telemetry or intent metadata (not function outputs)

**Dependencies:**
- Requires Phase 1 complete (EMRT + RL infrastructure)
- Can use empty Q-table initially (returns default actions)
- Pre-training (Phase 2) improves performance but is not required for basic functionality

**Compile/Test Checkpoint:**
```cpp
// After Phase 3:
- Call SignalsMR_Propose() and get real signals (not stub)
- See MR signals for XAUEUR when conditions are right
- Confidence scores in [0.0, 1.0]
- SL/TP points calculated correctly
- MR respects news windows (no signals during blocked periods)
```

**Test in Strategy Tester:**
- Run EA, check logs for MR signal proposals
- Verify MR signals blocked during news windows
- Check confidence scores are reasonable

**Branch:** `feat/m7-phase3-signalmr`

---

### Phase 4: Meta-Policy Implementation (Task 5) - Days 11-12

**Goal:** Implement intelligent strategy selection with bandit + deterministic fallbacks.

**Tasks:**
5. **Meta-Policy Chooser** (`meta_policy.mqh`)
   - Build context vector (regime features, ORE/SDR, EMRT rank, recent efficiency, spread/slippage quantiles, news proximity)
   - Contextual bandit (Thompson or LinUCB):
     - Choose BWISC vs MR vs Skip based on context
     - Exploration OFF in live (exploitation only)
     - Persist posterior/weights to `Files/RPEA/bandit/posterior.json`
     - Feature flags:
       - `UseBanditMetaPolicy` (default true) - enable/disable bandit; use deterministic rules when false
       - `BanditShadowMode` (default false) - log bandit decisions without executing (for A/B testing)
   - Single best symbol per session/day selection based on bandit expected efficiency; avoid correlated concurrent exposure
   - Deterministic fallback rules (when bandit disabled or uninitialized):
     - Confidence tie-breaker: if BWISC_conf < BWISC_ConfCut AND MR_conf > MR_ConfCut AND efficiency(MR) >= efficiency(BWISC) -> MR
     - Conditional replacement: if ORE < p40 AND ATR_D1 < p50 AND EMRT <= H* (H* = EMRT_FastThresholdPct percentile of EMRT lookback) AND session_age < 2h AND no active/pending overlap AND no high-impact news +/-15m -> MR for session
     - Default: BWISC if it has setup and BWISC_conf >= BWISC_ConfCut
     - Fallback: MR if BWISC has no setup
     - Skip: if neither has qualified setup
   - Hysteresis: once switched to MR, stay until session end
   - Absolute cap: 2 new entries per session

**Dependencies:**
- Requires Phase 3 complete (SignalMR must work)
- Needs BWISC signals (already working from M2)
- Needs efficiency calculation (E[R] / WorstCaseRisk) and CorrelationFallbackRho for phi

**Compile/Test Checkpoint:**
```cpp
// After Phase 4:
- MetaPolicy_Choose() returns BWISC, MR, or Skip
- MR chosen when BWISC confidence is low and MR is strong
- MR chosen when market conditions favor mean reversion
- Hysteresis prevents rapid switching
- Bandit choice persisted to posterior.json
```

**Test in Strategy Tester:**
- Run EA, check logs for meta-policy decisions
- Verify tie-breaker and conditional replacement cases
- Verify hysteresis prevents rapid switching

**Branch:** `feat/m7-phase4-metapolicy`

---

### Phase 5: Telemetry & Integration (Tasks 6-8) - Days 13-15

**Goal:** Add telemetry, allocator enhancements, and full integration.

**Tasks:**
6. **Telemetry + Regime Detection** (`telemetry.mqh`, `regime.mqh`)
   - Implement Regime_Label / Regime_Features:
     - ATR/stddev bands for volatility classification
     - ADX for trend strength
     - Hurst exponent / ACF decay for mean-reversion tendency
     - Opening Range Energy (ORE)
     - Rolling spread percentiles
     - Output regime labels: trend / range / volatile / illiquid
   - Liquidity Intelligence:
     - Maintain rolling spread/slippage quantiles per symbol/session
     - Persist to `Files/RPEA/liquidity/spread_slippage_stats.json`
     - Gate entries when spread/slippage above p75-p90 thresholds
   - Log: regime label, liquidity/anomaly flags, context vector, bandit choice + posterior snapshot
   - Log adaptive risk multiplier and post-news stabilization checks
   - CSV audit fields (extend existing audit): `confidence`, `efficiency`, `rho_est`, `hold_time`, `gating_reason`, `news_window_state`
   - Post-news re-engagement: after T+NewsBufferS, require 3 consecutive bars with spread <= p60 and realized sigma <= p70 before re-enabling entries
   - Track SLOs with specific targets:
     - 30-day MR hit-rate: target 58-62%, warn <55%
     - Median hold time: <= 2.5h; 80th percentile <= 4h
     - Median efficiency (realized R / WorstCaseRisk): >= 0.8
     - Friction tax (realized - theoretical R): median <= 0.4R
   - Auto-action: if >=2 SLOs breached 3 consecutive weeks, reduce MR risk by 25% until recovery
   - Freeze online learning when SLOs breach

7. **Allocator Integration** (`allocator.mqh`, risk sizing, `calibration.mqh`)
   - Enable MR strategy (allocator currently rejects non-BWISC)
   - Apply MR_RiskPct_Default (default 0.90%, clamp 0.8-1.0%) and MR_TimeStopMin/Max
   - BWISC weekly recalibration: recalibrate Bias/SDR gates from rolling percentiles; persist to `Files/RPEA/calibration/calibration.json` and load at runtime
   - Optional online Q-table updates with capped step size and decay; freeze when SLOs breach
   - Second-trade rule per session:
     - Budget: open_risk + pending_risk + WC_next1 + WC_next2 <= 0.8 * min(room_today, room_overall)
     - Efficiency: (E[R1] + phi * E[R2]) / (WC_next1 + WC_next2) >= 1.3; phi = 1 - |rho| (use CorrelationFallbackRho if unknown)
     - Floor buffer after both >= 0.5% of baseline
     - Absolute cap: 2 new entries per session
   - XAUEUR: proxy-only in M7; no replication handling in allocator/order engine

8. **End-to-End Testing & Validation**
   - Ensemble test in Strategy Tester
   - Verify both strategies can trade
   - Verify meta-policy switches correctly
   - Verify no symbol overlap between strategies
   - Check telemetry logs are complete
   - Forward demo plan (test in demo before live)

**Dependencies:**
- Requires all previous phases complete

**Compile/Test Checkpoint:**
```cpp
// After Phase 5:
- Telemetry logs show regime, strategy choice, confidence, efficiency
- SLO tracking works and auto-throttle triggers correctly
- Full ensemble runs end-to-end
- Orders placed by both BWISC and MR
- No duplicate orders on the same symbol
```

**Branch:** `feat/m7-phase5-telemetry`

---

## Branching Strategy

### Git Workflow Structure

```
master (current - M6 complete)
  -> feat/m7-ensemble-integration (base branch for M7)
       -> feat/m7-phase1-foundation
       -> feat/m7-phase2-pretraining
       -> feat/m7-phase3-signalmr
       -> feat/m7-phase4-metapolicy
       -> feat/m7-phase5-telemetry
```

### Workflow Steps

**1. Create or use M7 base branch:**
```bash
git checkout master
git checkout -b feat/m7-ensemble-integration
git push -u origin feat/m7-ensemble-integration
```

**2. For each phase:**
```bash
# Phase 1
git checkout feat/m7-ensemble-integration
git checkout -b feat/m7-phase1-foundation

# Work on tasks 1-2
git commit -m "M7 Task 1: EMRT formation job"
git commit -m "M7 Task 2: RL agent Q-table infrastructure"

# When phase complete and tested
git push origin feat/m7-phase1-foundation
git checkout feat/m7-ensemble-integration
git merge feat/m7-phase1-foundation
git push origin feat/m7-ensemble-integration
```

**3. After all phases complete:**
```bash
git checkout master
git merge feat/m7-ensemble-integration
# Or create PR: feat/m7-ensemble-integration -> master
```

---

## Dependency Map

### Task Dependencies

```
Phase 1 (Foundation)
  -> Task 1 (EMRT) ----+
  -> Task 2 (RL)       |
                       |
Phase 2 (Pre-training) |
  -> Task 3 (Q-table)  | (uses Task 2)
                       |
Phase 3 (SignalMR)     |
  -> Task 4 -----------+ (uses Tasks 1 & 2)
                       |
Phase 4 (Meta-Policy)  |
  -> Task 5 -----------+ (uses Task 4)
                       |
Phase 5 (Telemetry)    |
  -> Task 6 -----------+ (uses all)
  -> Task 7 -----------+ (uses all)
  -> Task 8 -----------+ (requires all)
```

### Critical Path

```
Task 1 -> Task 4 -> Task 5 -> Task 8
EMRT -> SignalMR -> Meta-Policy -> Testing
```

**Parallel Opportunities:**
- Task 2 (RL infrastructure) can be done in parallel with Task 1
- Task 3 (Pre-training) can be done in parallel with Task 4 (empty Q-table initially)
- Task 6 (Telemetry) can be started early

---

## Implementation Details by Task

### Task 1: EMRT Formation Job

**File:** `MQL5/Include/RPEA/emrt.mqh`

**Key Functions:**
```cpp
void EMRT_RefreshWeekly()
{
   // 1. Get synthetic XAUEUR bars (M1, forward-fill gaps)
   // 2. Build Y_t = P1 - beta * P2 for beta grid
   // 3. Detect extrema: C = EMRT_ExtremeThresholdMult * sigma_Y
   // 4. Find first mean crossing after each extreme
   // 5. EMRT = mean(delta_t) with variance cap (EMRT_VarCapMult)
   // 6. Choose beta* minimizing EMRT
   // 7. Store EMRT rank (percentile vs lookback) and p50
   // 8. Persist to Files/RPEA/emrt/emrt_cache.json
}

double EMRT_GetRank(const string symbol)
{
   // Return percentile rank (0.0-1.0) vs lookback
   // Lower rank = faster reversion
}
```

**Test Strategy:**
- Run EA for 1 day, verify EMRT calculation completes
- Check cache file has valid EMRT values
- Verify EMRT rank is between 0.0-1.0

---

### Task 2: RL Agent Q-Table Infrastructure

**File:** `MQL5/Include/RPEA/rl_agent.mqh`

**Key Functions:**
```cpp
int RL_StateFromSpread(const double spread_changes[], const int periods)
{
   // Discretize spread trajectory into 256 states
   // 4 periods with 4 levels each = 4^4 = 256 states
   // Return state_id (0-255)
}

int RL_ActionForState(const int state_id)
{
   // Load Q-table
   // Return action with highest Q-value (exploitation mode)
   // Or random action with probability epsilon (training mode)
}

double RL_GetQAdvantage(const int state_id)
{
   // max(Q) - mean(Q) normalized to [0,1]
}

bool RL_LoadQTable(const string path)
{
   // Load from Files/RPEA/qtable/mr_qtable.bin
}

bool RL_SaveQTable(const string path)
{
   // Save to Files/RPEA/qtable/mr_qtable.bin
}
```

**Test Strategy:**
- Test state discretization with sample spread data
- Test Q-table load/save (create empty table, save, reload)
- Verify state_id is always 0-255

---

### Task 3: RL Pre-Training Script

**File:** `MQL5/Scripts/rl_pretrain.mq5`

**Key Functions:**
```cpp
void SimulateOUProcess(double &spread_path[], const int length,
                       const double mu, const double theta, const double sigma)
{
   // Simulate Ornstein-Uhlenbeck process
}

void QLearning_Train(const int episodes, const int simulation_paths)
{
   // Generate OU paths and run Q-learning updates
   // Save final Q-table to Files/RPEA/qtable/mr_qtable.bin
}
```

**Test Strategy:**
- Run script standalone
- Verify Q-table file created
- Check Q-values are not all zeros
- Load Q-table in main EA without errors

---

### Task 4: SignalMR Module

**File:** `MQL5/Include/RPEA/signals_mr.mqh`

**Key Functions:**
```cpp
void SignalsMR_Propose(const AppContext& ctx, const string symbol,
                       bool &hasSetup, string &setupType,
                       int &slPoints, int &tpPoints,
                       double &bias, double &confidence)
{
   // Use EMRT + RL to build MR setup
   // Respect news windows, overlap rules, MR_LongOnly
   // Provide SL/TP in points and confidence in [0,1]
}
```

**Test Strategy:**
- Run EA, check logs for MR signal proposals
- Verify MR signals blocked during news windows
- Check confidence scores are reasonable (0.0-1.0)

---

### Task 5: Meta-Policy Chooser

**File:** `MQL5/Include/RPEA/meta_policy.mqh`

**Key Functions:**
```cpp
string MetaPolicy_Choose(const MetaPolicyContext &ctx)
{
   // Bandit choice (contextual) with deterministic fallback rules
   // Returns "BWISC", "MR", or "Skip"
}
```

**Test Strategy:**
- Run EA, check logs for meta-policy decisions
- Verify MR chosen when BWISC confidence is low
- Verify MR chosen when conditions favor mean reversion
- Verify hysteresis prevents rapid switching

---

### Task 6: Telemetry Pipeline

**File:** `MQL5/Include/RPEA/telemetry.mqh`

**Key Functions:**
```cpp
void Telemetry_LogEnsembleDecision(...)
{
   // Log regime, strategy choice, confidences, efficiency,
   // bandit choice + posterior snapshot, adaptive risk multiplier
}

void Telemetry_UpdateSLOs(...)
{
   // Track hit-rate, hold time, efficiency, friction tax
   // Auto-throttle MR risk by 25% if >=2 SLOs breached 3 weeks
}
```

**Test Strategy:**
- Run EA, check telemetry logs capture all fields
- Verify SLO tracking (may need extended run)
- Test auto-throttle (simulate SLO breach)

---

## Compile/Test Frequency

### Compile After Every Task
```bash
# In MetaEditor
F7 (Compile)
# Fix any errors immediately
```

### Test in Strategy Tester After Each Phase
- Phase 1: Test EMRT calculation and Q-table load/save
- Phase 2: Test pre-training script generates valid Q-table
- Phase 3: Test MR signals are generated correctly
- Phase 4: Test meta-policy chooses correctly
- Phase 5: Test full ensemble end-to-end

### Automated Test Runs (Required)
- Add M7 suites to `Tests/RPEA/run_automated_tests_ea.mq5` as they land
- Run `powershell -ExecutionPolicy Bypass -File run_tests.ps1` after each phase
- Review `MQL5/Files/RPEA/test_results/test_results.json` for regressions

### Don't Wait Until Everything is Done
- Compile frequently (after each task)
- Test after each phase (not each task)
- Fix bugs immediately (do not accumulate technical debt)

---

## Time Estimates (Realistic)

| Phase | Tasks | Days | Cumulative |
|-------|-------|------|------------|
| Phase 1 | 1-2 | 4 days | Day 4 |
| Phase 2 | 3 | 3 days | Day 7 |
| Phase 3 | 4 | 3 days | Day 10 |
| Phase 4 | 5 | 2 days | Day 12 |
| Phase 5 | 6-8 | 3 days | Day 15 |
| **Total** | **8 tasks** | **15 days** | **~3 weeks** |

**Buffer:** Add 2-3 days for debugging, testing, unexpected issues = **17-18 days total**

### Weekly Breakdown
- Week 1: Phases 1-2 (foundation + pre-training)
- Week 2: Phases 3-4 (SignalMR + meta-policy)
- Week 3: Phase 5 + testing + bug fixes

---

## Pro Tips

### 1. Start with Stubs
```cpp
void SignalsMR_Propose(...)
{
   // Step 1: return no setup
   hasSetup = false;
   return;
}
```

### 2. Use Logging Extensively
```cpp
PrintFormat("[SignalMR] symbol=%s emrt_rank=%.2f state_id=%d action=%d conf=%.2f",
            symbol, emrt_rank, state_id, action, confidence);
```

### 3. Test Components Independently
```cpp
void TestEMRT()
{
   EMRT_RefreshWeekly();
   double rank = EMRT_GetRank("XAUEUR");
   PrintFormat("[TEST] EMRT rank: %.2f", rank);
}
```

### 4. Keep BWISC Working
Do not break existing BWISC functionality. Test that M1-M6 still works after each phase.

### 5. Use Hold Points
Stop and review at each phase completion:
- Hold Point 1 (after Phase 1): EMRT and RL infrastructure
- Hold Point 2 (after Phase 2): pre-training results
- Hold Point 3 (after Phase 3): MR signal generation
- Hold Point 4 (after Phase 4): meta-policy decisions
- Hold Point 5 (after Phase 5): full ensemble performance

---

## Critical Success Factors

### Must Do
OK Compile after every task (catch errors early)
OK Test after every phase (do not wait until the end)
OK Use logging extensively (visibility into behavior)
OK Follow the dependency map (do not skip prerequisites)
OK Commit often (easy rollback)
OK Keep BWISC working (do not break existing functionality)

### Don't Do
- Do not skip compilation until "everything is done"
- Do not work on multiple phases simultaneously (unless experienced)
- Do not ignore hold points
- Do not break M1-M6 functionality
- Do not accumulate bugs (fix immediately)

---

## Getting Started

### Step 1: Create or confirm M7 Base Branch
```bash
git checkout master
git checkout -b feat/m7-ensemble-integration
git push -u origin feat/m7-ensemble-integration
```

### Step 2: Create Phase 1 Branch
```bash
git checkout feat/m7-ensemble-integration
git checkout -b feat/m7-phase1-foundation
```

### Step 3: Start Task 1
Open `MQL5/Include/RPEA/emrt.mqh` and begin implementing EMRT formation.

---

## Summary

**Implementation Strategy:**
- Work in 5 phases
- Create phase branches off the M7 base branch
- Compile after every task
- Test after every phase
- Merge phases back to base when complete
- Follow dependency map
- Use hold points for review

**Timeline:**
- 15 days of focused work
- 17-18 days with buffer
- 3 weeks total

**Success Criteria:**
- All 8 tasks complete
- EA compiles without errors
- All phases tested in Strategy Tester
- M1-M6 functionality still works
- Ensemble produces >=1 qualified setup/day (median)
- Ready for forward demo testing

**Next Step:** Begin Phase 1, Task 1 - EMRT Formation Job
