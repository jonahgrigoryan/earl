# M7 Task 05 - Meta-Policy Chooser Implementation

**Branch name**: `feat/m7-phase4-meta-policy` (cut from `feat/m7-ensemble-integration` base)

**Source of truth**: `docs/m7-final-workflow.md` (Phase 4, Task 5, Steps 5.1-5.4)

**Previous tasks completed**: Tasks 1-4 (EMRT, RL Agent, SignalMR, Pre-training)

## Objective

Implement the Meta-Policy module for intelligent strategy selection between BWISC and MR. This module evaluates market conditions and chooses the optimal strategy based on deterministic rules, with optional bandit-based enhancement. The module includes a decision-only gate for Phase 4 testing that logs decisions without executing trades.

## Prerequisites

- **Task 1 (EMRT)**: `EMRT_GetRank()`, `EMRT_GetP50()`, `EMRT_GetBeta()` must be implemented
- **Task 2 (RL Agent)**: `RL_ActionForState()`, `RL_GetQAdvantage()` must be implemented
- **Task 4 (SignalMR)**: `SignalsMR_Propose()` must be implemented and return valid outputs
- **Phase 0 inputs**: All M7 ensemble inputs must exist in `RPEA.mq5`
- **Helper functions**: `M7_GetCurrentORE()`, `M7_GetATR_D1_Percentile()`, `M7_GetSessionAgeMinutes()`, `M7_NewsIsWithin15Minutes()`, `M7_GetEntriesThisSession()`, `M7_IsLockedToMR()`, `M7_SetLockedToMR()` from `m7_helpers.mqh`

## Files to Modify

- `MQL5/Include/RPEA/meta_policy.mqh` (replace existing stub with full implementation)
- `MQL5/Include/RPEA/scheduler.mqh` (update callsite if signature changes)
- `Tests/RPEA/test_meta_policy.mqh` (new unit tests for deterministic rules)
- `Tests/RPEA/run_automated_tests_ea.mq5` (register new test suite)

## Workflow

1. **Get implementation details** from `docs/m7-final-workflow.md` (Phase 4, Task 5)
2. **Implement code locally** in repository workspace (`c:\Users\AWCS\earl-1`)
3. **Sync code to MT5 data folder** using `SyncRepoToTerminal.ps1`
4. **Compile from MT5 data folder** to verify implementation
5. **Run decision-only testing** to verify meta-policy choices are logged correctly

## Implementation Steps

### Step 5.1: Context Structure Definition

**Reference**: `docs/m7-final-workflow.md` -> Phase 4 -> Task 5 -> Step 5.1

**Implementation**:

1. Define `MetaPolicyContext` struct with the following fields:

   ```cpp
   struct MetaPolicyContext {
       // BWISC inputs
       bool   bwisc_has_setup;
       double bwisc_confidence;
       double bwisc_ore;
       double bwisc_efficiency;
       
       // MR inputs
       bool   mr_has_setup;
       double mr_confidence;
       double emrt_rank;
       double q_advantage;
       double mr_efficiency;
       
       // Market context
       double atr_d1_percentile;
       int    session_age_minutes;
       bool   news_within_15m;
       
       // Liquidity/news gating
       bool   entry_blocked;
       double spread_quantile;
       double slippage_quantile;
       
       // Regime context (Phase 5)
       int    regime_label;
       
       // Session state
       int    entries_this_session;
       bool   locked_to_mr;
   };
   ```

2. Add global constants for threshold values:
   ```cpp
   #define M7_DECISION_ONLY 1  // Set to 0 in Phase 5 Task 7
   ```

3. Ensure required includes exist in `meta_policy.mqh`:
   ```cpp
   #include <RPEA/bandit.mqh>
   #include <RPEA/config.mqh>
   #include <RPEA/emrt.mqh>
   #include <RPEA/logging.mqh>
   #include <RPEA/m7_helpers.mqh>
   #include <RPEA/news.mqh>
   #include <RPEA/rl_agent.mqh>
   #include <RPEA/app_context.mqh>
   ```

4. Verify all context fields can be populated from existing infrastructure:
   - `bwisc_has_setup`, `bwisc_confidence`: from scheduler/signal_BWISC
   - `bwisc_ore`: from `M7_GetCurrentORE()`
   - `mr_has_setup`, `mr_confidence`: from `SignalsMR_Propose()`
   - `emrt_rank`: from `EMRT_GetRank("XAUEUR")`
   - `q_advantage`: from `RL_GetQAdvantage()`
   - `atr_d1_percentile`: from `M7_GetATR_D1_Percentile()`
   - `session_age_minutes`: from `M7_GetSessionAgeMinutes()`
   - `news_within_15m`: from `M7_NewsIsWithin15Minutes()`
   - `entry_blocked`: from `News_IsEntryBlocked()`
   - `spread_quantile`, `slippage_quantile`: default 0.5 for Phase 4
   - `regime_label`: default 0 for Phase 4
   - `entries_this_session`: from `M7_GetEntriesThisSession()`
   - `locked_to_mr`: from `M7_IsLockedToMR()`

**Compile checkpoint**:
```powershell
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
```

**Expected**: ✅ Struct compiles, all data sources accessible

---

### Step 5.2: Deterministic Rules Implementation

**Reference**: `docs/m7-final-workflow.md` -> Phase 4 -> Task 5 -> Step 5.2

**Implementation**:

Implement `MetaPolicy_DeterministicChoice()` function with the following decision rules:

1. **Rule 0: Entry blocked gate**
   - If `entry_blocked` is true (news window or stabilization), return "Skip"
   
2. **Rule 0b: Liquidity quantile gate**
   - If `spread_quantile >= 0.90` or `slippage_quantile >= 0.90`, return "Skip"
   
3. **Rule 1: Session cap**
   - If `entries_this_session >= 2`, return "Skip"
   
4. **Rule 2: MR lock hysteresis**
   - If `locked_to_mr` is true AND `mr_has_setup` is true, return "MR"
   - This maintains MR preference after MR was chosen in previous decision
   
5. **Rule 3: Confidence tie-breaker**
   - If `bwisc_confidence < BWISC_ConfCut` AND `mr_confidence > MR_ConfCut` AND `mr_efficiency >= bwisc_efficiency` AND `mr_has_setup`, return "MR"
   
6. **Rule 4: Conditional BWISC replacement**
   - If ALL of the following conditions are met, return "MR":
     - `bwisc_ore < 0.40` (low ORE - BWISC weakness)
     - `atr_d1_percentile < 0.50` (low volatility)
     - `emrt_rank <= EMRT_FastThresholdPct / 100.0` (fast reversion - MR strength)
     - `session_age_minutes < 120` (early session)
     - `news_within_15m == false` (no news)
     - `mr_has_setup == true`
   
7. **Rule 5: BWISC if qualified**
   - If `bwisc_has_setup` AND `bwisc_confidence >= BWISC_ConfCut`, return "BWISC"
   
8. **Rule 6: MR fallback**
- If `!bwisc_has_setup` AND `mr_has_setup`, return "MR"
   
9. **Default: Skip**
   - Return "Skip" if no rules triggered

```cpp
string MetaPolicy_DeterministicChoice(const MetaPolicyContext& ctx) {
    // Rule 0: Entry blocked
    if(ctx.entry_blocked)
        return "Skip";
    
    // Rule 0b: Liquidity quantile gate
    if(ctx.spread_quantile >= 0.90 || ctx.slippage_quantile >= 0.90)
        return "Skip";
    
    // Rule 1: Session cap
    if(ctx.entries_this_session >= 2)
        return "Skip";
    
    // Rule 2: MR lock hysteresis
    if(ctx.locked_to_mr && ctx.mr_has_setup)
        return "MR";
    
    // Rule 3: Confidence tie-breaker
    if(ctx.bwisc_confidence < BWISC_ConfCut &&
       ctx.mr_confidence > MR_ConfCut &&
       ctx.mr_efficiency >= ctx.bwisc_efficiency &&
       ctx.mr_has_setup)
        return "MR";
    
    // Rule 4: Conditional BWISC replacement
    if(ctx.bwisc_ore < 0.40 &&
       ctx.atr_d1_percentile < 0.50 &&
       ctx.emrt_rank <= EMRT_FastThresholdPct / 100.0 &&
       ctx.session_age_minutes < 120 &&
       !ctx.news_within_15m &&
       ctx.mr_has_setup)
        return "MR";
    
    // Rule 5: BWISC if qualified
    if(ctx.bwisc_has_setup && ctx.bwisc_confidence >= BWISC_ConfCut)
        return "BWISC";
    
    // Rule 6: MR fallback
    if(!ctx.bwisc_has_setup && ctx.mr_has_setup)
        return "MR";
    
    // Default: Skip
    return "Skip";
}
```

**Compile checkpoint**:
```powershell
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
```

**Expected**: ✅ Deterministic rules compile with all rule branches

---

### Step 5.3: Bandit Integration (Optional)

**Reference**: `docs/m7-final-workflow.md` -> Phase 4 -> Task 5 -> Step 5.3

**Implementation**:

1. Implement `MetaPolicy_BanditIsReady()` function:
   - Check if bandit posterior file exists and is valid
   - Return `false` by default (use deterministic rules)
   - TODO: Check for `Files/RPEA/bandit/posterior.json`

2. Implement `MetaPolicy_BanditChoice()` function:
   - Call existing `Bandit_SelectPolicy()` from `bandit.mqh`
   - Map `BanditPolicy` enum to string ("BWISC", "MR", "Skip")
   - Implement shadow mode: log bandit vs deterministic choice, use deterministic
   - Shadow mode enabled by `BanditShadowMode` input

```cpp
// Check if bandit is ready (has trained posterior)
bool MetaPolicy_BanditIsReady() {
    // TODO[M7-Phase5]: Check if posterior.json exists and is valid
    // For Phase 4, always return false to use deterministic rules
    return false;
}

string MetaPolicy_BanditChoice(const AppContext& ctx, const string symbol, 
                                const MetaPolicyContext& mpc) {
    if(!UseBanditMetaPolicy || !MetaPolicy_BanditIsReady())
        return MetaPolicy_DeterministicChoice(mpc);
    
    // Call existing bandit API
    BanditPolicy bandit_result = Bandit_SelectPolicy(ctx, symbol);
    
    string bandit_str;
    switch(bandit_result) {
        case Bandit_BWISC: bandit_str = "BWISC"; break;
        case Bandit_MR:    bandit_str = "MR"; break;
        default:           bandit_str = "Skip"; break;
    }
    
    // Shadow mode: log bandit vs deterministic, use deterministic
    if(BanditShadowMode) {
        string det_str = MetaPolicy_DeterministicChoice(mpc);
        LogDecision("MetaPolicy", "SHADOW",
            StringFormat("{\"bandit\":\"%s\",\"deterministic\":\"%s\"}", 
                bandit_str, det_str));
        return det_str;  // Use deterministic in shadow mode
    }
    
    return bandit_str;
}
```

**Compile checkpoint**:
```powershell
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
```

**Expected**: ✅ Bandit integration compiles (returns deterministic by default)

---

### Step 5.4: Main Entry Point Implementation

**Reference**: `docs/m7-final-workflow.md` -> Phase 4 -> Task 5 -> Step 5.4

**Implementation**:

1. Implement `MetaPolicy_Choose()` function with signature:
   ```cpp
   string MetaPolicy_Choose(
       const AppContext& ctx,
       const string symbol,
       bool bw_has, double bw_conf,
       bool mr_has, double mr_conf
   );
   ```

2. Build `MetaPolicyContext` from inputs and helpers:
   ```cpp
   MetaPolicyContext mpc;
   mpc.bwisc_has_setup = bw_has;
   mpc.bwisc_confidence = bw_conf;
   mpc.mr_has_setup = mr_has;
   mpc.mr_confidence = mr_conf;
   mpc.bwisc_efficiency = 0.0;    // TODO Phase 5
   mpc.mr_efficiency = 0.0;       // TODO Phase 5
   
   // Fill from helpers
   mpc.emrt_rank = EMRT_GetRank("XAUEUR");
   mpc.q_advantage = RL_GetQAdvantage(0);
   mpc.bwisc_ore = M7_GetCurrentORE(ctx, symbol);
   mpc.atr_d1_percentile = M7_GetATR_D1_Percentile(ctx, symbol);
   mpc.session_age_minutes = M7_GetSessionAgeMinutes(ctx, symbol);
   mpc.news_within_15m = M7_NewsIsWithin15Minutes(symbol);
   mpc.entry_blocked = News_IsEntryBlocked(symbol);
   mpc.spread_quantile = 0.5;     // TODO Phase 5
   mpc.slippage_quantile = 0.5;   // TODO Phase 5
   mpc.regime_label = 0;          // TODO Phase 5
   mpc.entries_this_session = M7_GetEntriesThisSession(ctx, symbol);
   mpc.locked_to_mr = M7_IsLockedToMR();
   ```

3. Make decision using `MetaPolicy_BanditChoice()`:
   ```cpp
   string choice = MetaPolicy_BanditChoice(ctx, symbol, mpc);
   ```

4. Implement decision-only gate:
   ```cpp
   #if M7_DECISION_ONLY
   LogDecision("MetaPolicy", "DECISION_ONLY",
       StringFormat("{\"choice\":\"%s\",\"bw_conf\":%.2f,\"mr_conf\":%.2f}",
           choice, bw_conf, mr_conf));
   return "Skip";  // Phase 4: disable all execution
   #else
   // Update session state if MR chosen
   if(choice == "MR") {
       M7_SetLockedToMR(true);
   }
   return choice;
   #endif
   ```

5. **Critical**: Update scheduler to call new signature:
   - `scheduler.mqh` must pass `ctx` and `symbol` to `MetaPolicy_Choose()`
   - This updates from the Phase 0 stub signature

**Compile checkpoint**:
```powershell
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
```

**Expected**: ✅ Full meta-policy compiles with decision-only gate

---

### Step 5.5: Update Scheduler Callsite

**Implementation**:

Update `scheduler.mqh` to use the new `MetaPolicy_Choose()` signature:

1. Find existing call to `MetaPolicy_Choose()`
2. Update to pass `ctx` and `symbol`:
   ```cpp
   string chosen_strategy = MetaPolicy_Choose(
       ctx,
       sym,
       hasBWISC, bwisc_confidence,
       hasMR, mr_confidence
   );
   ```

3. Remove or update the old stub signature call

**Compile checkpoint**:
```powershell
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
```

**Expected**: ✅ Scheduler compiles with updated meta-policy call

---

### Step 5.6: Add Unit Tests for Meta-Policy Rules

**Purpose**: Verify deterministic rule ordering and gating without relying on live market data.

**Implementation**:

1. Create `Tests/RPEA/test_meta_policy.mqh` with deterministic unit tests that call
   `MetaPolicy_DeterministicChoice()` directly using a constructed `MetaPolicyContext`.
   - Avoid `MetaPolicy_Choose()` in Phase 4 because `M7_DECISION_ONLY=1` forces `Skip`.
   - Use helper builders to minimize boilerplate (e.g., `MakeContext()` with overrides).

2. Add test cases that map to each rule (order matters):
   - Rule 0: `entry_blocked=true` → `Skip`
   - Rule 0b: `spread_quantile >= 0.90` → `Skip`
   - Rule 1: `entries_this_session >= 2` → `Skip`
   - Rule 2: `locked_to_mr=true` + `mr_has_setup=true` → `MR`
   - Rule 3: tie-breaker (low BWISC conf, high MR conf, MR efficiency >= BWISC) → `MR`
   - Rule 4: conditional replacement (low ORE, low ATR pct, fast EMRT, early session, no news, MR setup) → `MR`
   - Rule 5: `bwisc_has_setup=true` + `bwisc_confidence >= BWISC_ConfCut` → `BWISC`
   - Rule 6: `!bwisc_has_setup` + `mr_has_setup=true` → `MR`
   - Precedence: `entry_blocked=true` should override MR lock and any other rule.

3. Register the suite in `Tests/RPEA/run_automated_tests_ea.mq5`.

**Compile checkpoint**:
```powershell
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
```

**Expected**: ✅ Unit tests compile and are registered in the harness

---

## Verification Steps

### Compile Verification

```powershell
# Sync and compile
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log

# Check compile log
Get-Content "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\FundingPips\compile_rpea.log"
```

**Expected**: ✅ Compiles successfully with no errors

### Decision-Only Testing

In Phase 4, with `M7_DECISION_ONLY=1`:

1. **Attach EA to chart** with both BWISC and MR enabled
2. **Monitor Experts tab** for meta-policy decisions:
   ```
   MetaPolicy DECISION_ONLY {"choice":"BWISC","bw_conf":0.75,"mr_conf":0.65}
   MetaPolicy DECISION_ONLY {"choice":"Skip","bw_conf":0.55,"mr_conf":0.70}
   MetaPolicy SHADOW {"bandit":"MR","deterministic":"BWISC"}
   ```
3. **Verify**:
   - No orders are placed (decision-only mode)
   - Decisions are logged with full context
   - MR lock hysteresis works across ticks
   - Rules fire correctly based on market conditions

### Rule Coverage Testing

Create test scenarios to verify each rule:

| Rule | Test Scenario | Expected Choice |
|------|---------------|-----------------|
| Rule 0 | News blocked | Skip |
| Rule 0b | Spread quantile 0.95 | Skip |
| Rule 1 | 2+ entries this session | Skip |
| Rule 2 | Locked to MR, MR has setup | MR |
| Rule 3 | Low BWISC conf, high MR conf | MR |
| Rule 4 | Low ORE, fast EMRT, early session | MR |
| Rule 5 | High BWISC conf | BWISC |
| Rule 6 | No BWISC setup, MR has setup | MR |

---

## Integration Points

### Input Dependencies

| Input | Source | Usage |
|-------|--------|-------|
| `EnableMR` | RPEA.mq5 | Gate for MR strategy |
| `MR_RiskPct_Default` | RPEA.mq5 | Risk sizing for MR |
| `BWISC_ConfCut` | RPEA.mq5 | BWISC confidence threshold |
| `MR_ConfCut` | RPEA.mq5 | MR confidence threshold |
| `MR_EMRTWeight` | RPEA.mq5 | Confidence weighting |
| `EMRT_FastThresholdPct` | RPEA.mq5 | EMRT percentile for MR preference |
| `MR_LongOnly` | RPEA.mq5 | Restrict MR direction |
| `UseBanditMetaPolicy` | RPEA.mq5 | Enable bandit selection |
| `BanditShadowMode` | RPEA.mq5 | Log bandit vs deterministic |

### Function Dependencies

| Function | Source | Usage |
|----------|--------|-------|
| `EMRT_GetRank()` | emrt.mqh | EMRT fastness metric |
| `EMRT_GetP50()` | emrt.mqh | Expected reversion time |
| `EMRT_GetBeta()` | emrt.mqh | Hedge ratio for spread |
| `RL_ActionForState()` | rl_agent.mqh | RL-based action |
| `RL_GetQAdvantage()` | rl_agent.mqh | RL confidence metric |
| `SignalsMR_Propose()` | signals_mr.mqh | MR signal generation |
| `M7_GetCurrentORE()` | m7_helpers.mqh | BWISC opening range energy |
| `M7_GetATR_D1_Percentile()` | m7_helpers.mqh | Volatility regime |
| `M7_GetSessionAgeMinutes()` | m7_helpers.mqh | Session timing |
| `M7_NewsIsWithin15Minutes()` | m7_helpers.mqh | News proximity |
| `M7_GetEntriesThisSession()` | m7_helpers.mqh | Session cap |
| `M7_IsLockedToMR()` | m7_helpers.mqh | Hysteresis state |
| `M7_SetLockedToMR()` | m7_helpers.mqh | Hysteresis state |
| `News_IsEntryBlocked()` | news.mqh | Entry gating |
| `Bandit_SelectPolicy()` | bandit.mqh | Bandit selection |
| `LogDecision()` | logging.mqh | Telemetry logging |

### Output Dependencies

| Consumer | Usage |
|----------|-------|
| `allocator.mqh` | Receives chosen strategy string |
| `scheduler.mqh` | Calls MetaPolicy_Choose() |
| Telemetry system | Logs decision context |

---

## Phase 4 vs Phase 5

| Aspect | Phase 4 (Current) | Phase 5 Task 7 |
|--------|-------------------|----------------|
| `M7_DECISION_ONLY` | 1 (logs only) | 0 (enables execution) |
| `bwisc_efficiency` | 0.0 (default) | Compute rolling efficiency |
| `mr_efficiency` | 0.0 (default) | Compute rolling efficiency |
| `spread_quantile` | 0.5 (default) | Compute from liquidity stats |
| `slippage_quantile` | 0.5 (default) | Compute from liquidity stats |
| `regime_label` | 0 (UNKNOWN) | Compute from Regime_Detect() |
| Bandit integration | Shadow mode only | Full bandit execution |

---

## Critical Paths

**Repository workspace**: `c:\Users\AWCS\earl-1`

**MT5 Data Folder**: `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075`

**Sync Script**: `SyncRepoToTerminal.ps1` (run from repo root)

**File Sync Mappings** (via `SyncRepoToTerminal.ps1`):
- **Source Include**: `c:\Users\AWCS\earl-1\MQL5\Include\RPEA` → **Destination**: `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Include\RPEA`
- **Source Expert**: `c:\Users\AWCS\earl-1\MQL5\Experts\FundingPips` → **Destination**: `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\FundingPips`
- **Source Tests**: `c:\Users\AWCS\earl-1\Tests\RPEA` → **Destination**: `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\Tests\RPEA` ✅ Verified

**Compile Command** (run from MT5 data folder):
```powershell
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
```

**Note**: The relative path `MQL5\Experts\FundingPips\RPEA.mq5` is resolved relative to the current working directory (MT5 data folder). The compile checkpoints change directory to the MT5 data folder before running the compile command.

---

## Implementation Notes

- **Decision-only gate**: `M7_DECISION_ONLY=1` in Phase 4 ensures no trades are executed while testing meta-policy decisions
- **Shadow mode**: When bandit is enabled but not ready, log bandit vs deterministic for later analysis
- **Safe defaults**: All efficiency/quantile/regime fields default to neutral values until Phase 5
- **Hysteresis**: MR lock prevents oscillation between strategies when both have marginal confidence
- **Rule priority**: Rules are evaluated in order; first matching rule returns
- **Logging**: All decisions should include full context for post-hoc analysis
- **No forward dependencies**: Meta-policy uses existing EMRT/RL/SignalMR outputs

---

## Deliverables

- Complete `meta_policy.mqh` implementation with all 5 steps
- Updated scheduler callsite in `scheduler.mqh`
- Decision logging working correctly
- Code compiles successfully after each step
- Phase 4 decision-only mode functional

## Acceptance Checklist

- [ ] Step 5.1: Context structure defined and compiles
- [ ] Step 5.2: Deterministic rules implemented with all 9 rules
- [ ] Step 5.3: Bandit integration compiles (returns deterministic by default)
- [ ] Step 5.4: Main entry point implemented with decision-only gate
- [ ] Step 5.5: Scheduler callsite updated
- [ ] Code compiles successfully after each step
- [ ] Decision-only mode logs choices correctly
- [ ] No forward dependencies (uses Tasks 1, 2, 4 infrastructure)
- [ ] All integration points documented

## Hold Point

Stop after Task 05 is complete and compiled successfully. Report results before proceeding to Phase 5 Task 6 (Telemetry + Regime Detection).

**Phase 5 will require**:
- Setting `M7_DECISION_ONLY = 0` to enable actual trading
- Implementing efficiency tracking
- Implementing liquidity quantiles
- Implementing regime detection
- Updating allocator to accept MR strategy
