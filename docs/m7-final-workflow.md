# M7 Final Workflow: BWISC + MR Ensemble Integration

> **Compiled from analysis of**: m7-workflow.md, m7-implementation-workflow.md, m7-revised-workflow.md
> **Optimized for**: Compile-after-each-task, zero forward dependencies, FundingPips challenge success

---

## Executive Summary

This workflow transforms RPEA from single-strategy (BWISC) to dual-strategy ensemble (BWISC + MR) with intelligent selection. Every task is designed to compile independently with no forward dependencies.

**Key Principles:**
1. **Safe Defaults**: All accessors return valid defaults when data unavailable
2. **Compile-After-Each-Step**: Every numbered step must compile without errors
3. **Foundation First**: Mathematical infrastructure before signal generation
4. **Decision Before Execution**: Log choices before enabling actual trading

---

## Phase Overview

| Phase | Tasks | Days | Focus |
|-------|-------|------|-------|
| **0** | - | 0.5 | Scaffolding: Inputs, stubs, feature flags |
| **1** | 1, 2 | 1-4 | Foundation: EMRT + RL infrastructure |
| **2** | 4 | 5-7 | SignalMR generation (uses empty Q-table) |
| **3** | 3 | 8-9 | Pre-training script (standalone, parallel OK) |
| **4** | 5 | 10-11 | Meta-policy: deterministic rules + bandit |
| **5** | 6, 7, 8 | 12-15 | Integration: Telemetry, allocator, E2E testing |

**Critical Path:**
```
Phase 0 → Phase 1 (EMRT + RL) → Phase 2 (SignalMR) → Phase 4 (Meta-Policy) → Phase 5 (Integration)
                                       ↓
                               Phase 3 (Pre-training) [can run parallel]
```

---

## Phase 0: Scaffolding (Day 0.5)

**Objective**: Wire inputs and create stubs so all future phases compile immediately.

### 0.1 Add New Inputs to RPEA.mq5

```cpp
// === M7 ENSEMBLE INPUTS ===
input group "-------------------------------------------"
input group "          M7: Ensemble Integration         "
input group "-------------------------------------------"

input bool   EnableMR              = true;     // Enable MR strategy
input double MR_RiskPct_Default    = 0.90;     // MR per-trade risk %
input int    MR_TimeStopMin        = 60;       // Min hold time (minutes)
input int    MR_TimeStopMax        = 90;       // Max hold time (minutes)
input bool   MR_LongOnly           = false;    // Restrict MR to longs only
input double BWISC_ConfCut         = 0.70;     // BWISC confidence threshold
input double MR_ConfCut            = 0.80;     // MR confidence threshold
input double MR_EMRTWeight         = 0.60;     // Confidence weight on EMRT fastness
input bool   MR_UseLogRatio        = true;     // Use log(XAUUSD) - log(EURUSD) for XAUEUR

// EMRT Configuration
input double EMRT_ExtremeThresholdMult = 2.0;  // Extrema detection (sigma multiples)
input double EMRT_VarCapMult           = 2.5;  // Variance cap multiplier
input double EMRT_BetaGridMin          = -2.0; // Min beta for grid search
input double EMRT_BetaGridMax          = 2.0;  // Max beta for grid search
input int    EMRT_FastThresholdPct     = 40;   // EMRT percentile for MR preference

// Q-Learning Configuration
input double QL_LearningRate       = 0.10;     // Alpha
input double QL_DiscountFactor     = 0.99;     // Gamma

// Meta-Policy Configuration
input bool   UseBanditMetaPolicy   = true;     // Use Thompson/LinUCB vs deterministic
input bool   BanditShadowMode      = true;     // Log decisions without executing
input double CorrelationFallbackRho = 0.50;    // Assumed correlation if unknown

// Proxy Symbol
input bool   UseXAUEURProxy        = true;     // Enable synthetic XAUEUR
```

### 0.2 Create Stub Files

Create minimal stubs that compile but return safe defaults:

**emrt.mqh stub:**
```cpp
#ifndef EMRT_MQH
#define EMRT_MQH

void   EMRT_RefreshWeekly()        { /* stub */ }
double EMRT_GetRank(string sym)    { return 0.5; }   // Neutral rank
double EMRT_GetP50(string sym)     { return 75.0; }  // Midpoint of TimeStop range
double EMRT_GetBeta(string sym)    { return 0.0; }   // No hedge

#endif
```

**rl_agent.mqh stub:**
```cpp
#ifndef RL_AGENT_MQH
#define RL_AGENT_MQH

enum RL_ACTION { RL_ACTION_EXIT=0, RL_ACTION_HOLD=1, RL_ACTION_ENTER=2 };

int    RL_StateFromSpread(double &changes[], int periods) { return 0; }
int    RL_ActionForState(int state) { return RL_ACTION_HOLD; }  // Safe default
double RL_GetQAdvantage(int state)  { return 0.5; }             // Neutral

bool   RL_LoadQTable(string path)   { return true; }
bool   RL_SaveQTable(string path)   { return true; }

#endif
```

**signals_mr.mqh stub:**
```cpp
#ifndef SIGNALS_MR_MQH
#define SIGNALS_MR_MQH

void SignalsMR_Propose(
    const AppContext& ctx,
    const string symbol,
    bool &hasSetup,
    string &setupType,
    int &slPoints,
    int &tpPoints,
    double &bias,
    double &confidence
) {
    hasSetup = false;
    setupType = "None";
    slPoints = 0;
    tpPoints = 0;
    bias = 0.0;
    confidence = 0.0;
}

#endif
```

**meta_policy.mqh stub:**
```cpp
#ifndef META_POLICY_MQH
#define META_POLICY_MQH

string MetaPolicy_Choose(
    const AppContext& ctx,
    const string symbol,
    bool bw_has, double bw_conf,
    bool mr_has, double mr_conf
) {
    if(symbol == "") { /* no-op */ }
    if(bw_has) return "BWISC";  // Primary strategy
    if(mr_has) return "MR";
    return "Skip";
}

#endif
```

### 0.3 Compile Checkpoint

```
✅ RPEA.mq5 compiles with all stubs
✅ All inputs accessible via getters
✅ SignalMR stub returns no setup, so MR path is inert even if EnableMR=true
✅ BanditShadowMode only affects choice; no execution occurs in Phase 0 (scheduler logs only, allocator does not send orders)
```

---

## Helper Functions Reference

This section documents which helper functions exist in the codebase vs. which need implementation.

### Existing Functions (from M1-M6)

| Function | Location | Usage |
|----------|----------|-------|
| `Indicators_GetSnapshot(symbol, &snapshot)` | `indicators.mqh` | Returns `snapshot.atr_d1` for ATR |
| `News_IsBlocked(symbol)` | `news.mqh` | Primary news blocking check |
| `News_IsEntryBlocked(symbol)` | `news.mqh` | Entry-specific blocking |
| `Sessions_GetORSnapshot(ctx, symbol, label, &snapshot)` | `sessions.mqh` | Returns `or_high`, `or_low` |
| `Sessions_GetLondonORSnapshot(ctx, symbol, &snapshot)` | `sessions.mqh` | London OR specifically |
| `Sessions_InLondon(ctx, symbol)` | `sessions.mqh` | Check if in London session |
| `Sessions_InNewYork(ctx, symbol)` | `sessions.mqh` | Check if in NY session |
| `Sessions_InORWindow(ctx, symbol)` | `sessions.mqh` | Check if in OR window |
| `Liquidity_SpreadOK(symbol, &out_spread, &out_threshold)` | `liquidity.mqh` | Gets current spread via out param |
| `Config_GetSLmult()` | `config.mqh` | SL multiplier |

### Wrapper Functions to Implement (Phase 0)

These thin wrappers provide a cleaner API for M7 modules. Add to `MQL5/Include/RPEA/m7_helpers.mqh`:

```cpp
//+------------------------------------------------------------------+
//| m7_helpers.mqh - M7 Ensemble Helper Functions                     |
//+------------------------------------------------------------------+
#ifndef M7_HELPERS_MQH
#define M7_HELPERS_MQH

#include "indicators.mqh"
#include "liquidity.mqh"
#include "sessions.mqh"
#include "symbol_bridge.mqh"
#include "emrt.mqh"
#include "order_engine.mqh"

#include "indicators.mqh"
#include "liquidity.mqh"
#include "sessions.mqh"
#include "news.mqh"

// === M7 Session State Globals ===
int    g_entries_this_session = 0;
bool   g_locked_to_mr = false;
string g_current_session_label = "";

// ATR accessor using existing snapshot infrastructure
double M7_GetATR_D1(const string symbol) {
    IndicatorSnapshot snapshot;
    if(Indicators_GetSnapshot(symbol, snapshot))
        return snapshot.atr_d1;
    return 0.0;  // Safe default
}

// Spread accessor: synthetic for XAUEUR, Liquidity_SpreadOK for others
double M7_GetSpreadCurrent(const string symbol) {
    if(symbol == "XAUEUR") {
        double xau = SymbolInfoDouble("XAUUSD", SYMBOL_BID);
        double eur = SymbolInfoDouble("EURUSD", SYMBOL_BID);
        if(xau <= 0.0 || eur <= 0.0) return 0.0;
        if(MR_UseLogRatio)
            return MathLog(xau) - MathLog(eur);
        double beta = EMRT_GetBeta("XAUEUR");
        return xau - beta * eur;
    }

    string exec_symbol = SymbolBridge_GetExecutionSymbol(symbol);
    if(exec_symbol == "") exec_symbol = symbol;

    double spread_out, threshold_out;
    Liquidity_SpreadOK(exec_symbol, spread_out, threshold_out);
    return spread_out;
}

// Spread mean - simple moving average of recent spreads
// NOTE: Returns current spread as baseline; full implementation in Phase 2
double M7_GetSpreadMean(const string symbol, int periods) {
    // TODO[M7-Phase2]: Implement rolling spread buffer
    return M7_GetSpreadCurrent(symbol);
}

// ORE (Opening Range Energy) - uses existing OR snapshot + ATR
double M7_GetCurrentORE(const AppContext& ctx, const string symbol) {
    SessionORSnapshot or_snap;
    if(!Sessions_GetLondonORSnapshot(ctx, symbol, or_snap))
        return 0.5;  // Neutral default
    if(!or_snap.or_complete)
        return 0.5;

    double or_span = or_snap.or_high - or_snap.or_low;
    double atr = M7_GetATR_D1(symbol);
    if(atr < 1e-9) return 0.5;

    return or_span / atr;  // ORE = OR span / ATR(D1)
}

// ATR percentile vs lookback - compares current to 20-day SMA
double M7_GetATR_D1_Percentile(const AppContext& ctx, const string symbol) {
    double current_atr = M7_GetATR_D1(symbol);
    if(current_atr < 1e-9) return 0.5;

    // Get ATR SMA using indicator buffer
    // TODO[M7-Phase4]: Full percentile calculation
    // For now, use simple ratio approximation
    IndicatorSnapshot snapshot;
    if(!Indicators_GetSnapshot(symbol, snapshot))
        return 0.5;

    // Approximate: if ATR > 1.2x typical, high percentile
    double typical_atr = snapshot.atr_d1;  // Baseline
    if(typical_atr < 1e-9) return 0.5;

    double ratio = current_atr / typical_atr;
    return MathMin(1.0, MathMax(0.0, ratio - 0.5));  // Map [0.5, 1.5] to [0, 1]
}

// Session age in minutes since session start
int M7_GetSessionAgeMinutes(const AppContext& ctx, const string symbol) {
    // Determine current session
    bool in_london = Sessions_InLondon(ctx, symbol);
    bool in_ny = Sessions_InNewYork(ctx, symbol);

    if(!in_london && !in_ny)
        return 0;  // Not in session

    // Get session start time from OR snapshot
    SessionORSnapshot or_snap;
    if(in_london) {
        if(!Sessions_GetLondonORSnapshot(ctx, symbol, or_snap))
            return 60;  // Default
    } else {
        if(!Sessions_GetORSnapshot(ctx, symbol, SESSION_LABEL_NEWYORK, or_snap))
            return 60;  // Default
    }

    // Calculate minutes since OR start
    datetime now = ctx.current_server_time;
    int age_seconds = (int)(now - or_snap.or_start);
    return age_seconds / 60;
}

// News proximity check - wrapper around existing News_IsBlocked
bool M7_NewsIsWithin15Minutes(const string symbol) {
    // The existing News_IsBlocked uses configurable windows
    return News_IsBlocked(symbol);
}

// Session entry counter
int M7_GetEntriesThisSession(const AppContext& ctx, const string symbol) {
    // Check if session changed
    string current_label = "";
    if(Sessions_InLondon(ctx, symbol)) current_label = SESSION_LABEL_LONDON;
    else if(Sessions_InNewYork(ctx, symbol)) current_label = SESSION_LABEL_NEWYORK;

    if(current_label != g_current_session_label) {
        // Session changed - reset counters
        g_entries_this_session = 0;
        g_locked_to_mr = false;
        g_current_session_label = current_label;
        M7_ClearPositionTracking();
    }

    return g_entries_this_session;
}

// Increment entry counter
// IMPORTANT: Call from OnTradeTransaction on DEAL_ENTRY_IN, NOT from allocator
// This ensures we count actual fills, not just order attempts
// Filter by EA magic number and use first-entry-per-position guard
void M7_IncrementEntries() {
    g_entries_this_session++;
}

// Track positions to avoid double-counting partials
ulong g_counted_positions[];

// Call from OnTradeTransaction when deal is confirmed
// Returns true if this is a new entry that should be counted
bool M7_ShouldCountEntry(const ulong position_id, const long deal_magic) {
    // Filter: only count our EA's trades
    if(position_id == 0) return false;
    if(!OrderEngine_IsOurMagic(deal_magic)) return false;

    // Check if we already counted this position
    int size = ArraySize(g_counted_positions);
    for(int i = 0; i < size; i++) {
        if(g_counted_positions[i] == position_id)
            return false;  // Already counted
    }

    // New position - add to tracked list and count it
    ArrayResize(g_counted_positions, size + 1);
    g_counted_positions[size] = position_id;
    return true;
}

// Clear position tracking on session change
void M7_ClearPositionTracking() {
    ArrayResize(g_counted_positions, 0);
}

// MR lock flag for hysteresis
bool M7_IsLockedToMR() {
    return g_locked_to_mr;
}

// Set MR lock (call when MR is chosen)
void M7_SetLockedToMR(bool locked) {
    g_locked_to_mr = locked;
}

// Reset session state (call on session change or EA init)
void M7_ResetSessionState() {
    g_entries_this_session = 0;
    g_locked_to_mr = false;
    g_current_session_label = "";
    M7_ClearPositionTracking();
}

#endif // M7_HELPERS_MQH
```

### OnTradeTransaction Integration

Insert this block inside the existing `OnTradeTransaction` (after `OrderEngine_OnTradeTxn`
and the day-count logic). Do not return early.

```cpp
if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
{
    ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
    if(deal_entry == DEAL_ENTRY_IN)
    {
        long deal_magic = (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
        ulong position_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
        string deal_symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
        if(deal_symbol == "") deal_symbol = trans.symbol;
        if(deal_symbol == "") deal_symbol = "XAUUSD";

        if(M7_ShouldCountEntry(position_id, deal_magic))
        {
            datetime deal_time = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
            if(deal_time <= 0) deal_time = TimeCurrent();

            AppContext ctx = g_ctx;
            ctx.current_server_time = deal_time;

            // Ensure session label is current before counting
            M7_GetEntriesThisSession(ctx, deal_symbol);
            M7_IncrementEntries();

            LogDecision("M7", "ENTRY_COUNTED",
                StringFormat("{\"position\":%I64u,\"entries\":%d}",
                    position_id, M7_GetEntriesThisSession(ctx, deal_symbol)));
        }
    }
}
```

### Implementation Notes

1. **ATR**: Already computed and cached in `indicators.mqh`. Access via `Indicators_GetSnapshot()`.
2. **ORE**: OR values exist in `sessions.mqh`. Combine with ATR to compute energy metric.
3. **Spread**: For XAUEUR, use log-ratio `log(XAUUSD)-log(EURUSD)` when `MR_UseLogRatio=true`; otherwise use linear spread `XAUUSD - beta*EURUSD`. Other symbols use `Liquidity_SpreadOK()`. Mean requires new rolling buffer.
4. **News**: Fully implemented. Use `News_IsBlocked()` or `News_IsEntryBlocked()`.
5. **Session state**: Predicates exist. Age calculation and entry tracking need implementation.

---

## Phase 1: Foundation (Days 1-4)

### Task 1: EMRT Formation Job (Days 1-2)

**File**: `MQL5/Include/RPEA/emrt.mqh`

**Purpose**: Calculate Empirical Mean Reversion Time for synthetic XAUEUR spread.

> **M7 amendment**: When `MR_UseLogRatio=true`, compute XAUEUR as `log(XAUUSD) - log(EURUSD)` and
> hardcode `beta=1.0` (skip grid search). When false, use linear spread `XAUUSD - beta*EURUSD`
> with beta search in `[EMRT_BetaGridMin, EMRT_BetaGridMax]`.

#### Step 1.1: Data Structures & File I/O

```cpp
struct EMRT_Cache {
    double beta_star;      // Optimal hedge ratio
    double rank;           // Percentile vs lookback [0.0-1.0]
    double p50_minutes;    // 50th percentile reversion time
    datetime last_refresh;
    string symbol;
};

EMRT_Cache g_emrt_cache;
bool       g_emrt_loaded = false;

bool EMRT_LoadCache(string path);
bool EMRT_SaveCache(string path);
```

**Compile checkpoint**: ✅ Compiles, returns safe defaults (0.5, 75.0, 0.0)

#### Step 1.2: Synthetic Spread Generation

```cpp
void EMRT_BuildSyntheticSpread(
    const double &xauusd_close[],
    const double &eurusd_close[],
    double beta,
    double &spread[]
) {
    int len = MathMin(ArraySize(xauusd_close), ArraySize(eurusd_close));
    ArrayResize(spread, len);
    for(int i = 0; i < len; i++) {
        if(MR_UseLogRatio) {
            // beta ignored when using log-ratio
            if(xauusd_close[i] <= 0.0 || eurusd_close[i] <= 0.0) {
                spread[i] = 0.0;
                continue;
            }
            spread[i] = MathLog(xauusd_close[i]) - MathLog(eurusd_close[i]);
        } else {
            spread[i] = xauusd_close[i] - beta * eurusd_close[i];
        }
    }
}
```

**Compile checkpoint**: ✅ Function compiles, not yet called

#### Step 1.3: Extrema Detection & Crossing Times

```cpp
void EMRT_FindCrossingTimes(
    const double &spread[],
    double threshold_mult,
    double &crossing_times[]
) {
    // Find extrema where |Y - mean| > threshold_mult * sigma
    // Track time to cross back to rolling mean
}
```

**Compile checkpoint**: ✅ Function compiles

#### Step 1.4: Beta Grid Search

```cpp
void EMRT_RefreshWeekly() {
    if(!UseXAUEURProxy) {
        Print("[EMRT] WARNING: UseXAUEURProxy=false, EMRT refresh skipped (proxy-only in M7)");
        return;
    }

    // Get 60-90 day lookback of XAUUSD and EURUSD M1 data
    // If log-ratio is enabled, skip beta grid search (beta = 1.0 implicit)
    // Otherwise grid search beta in [EMRT_BetaGridMin, EMRT_BetaGridMax]
    // Select beta* minimizing EMRT (subject to variance cap)
    // Compute rank percentile
    // Save to emrt_cache.json
}
```

**Compile checkpoint**: ✅ Full EMRT module compiles

#### Step 1.5: Accessor Functions

```cpp
double EMRT_GetRank(string sym) {
    if(!g_emrt_loaded) return 0.5;  // Safe default
    return g_emrt_cache.rank;
}

double EMRT_GetP50(string sym) {
    if(!g_emrt_loaded) return 75.0;  // Midpoint of MR_TimeStopMin/Max
    return g_emrt_cache.p50_minutes;
}

double EMRT_GetBeta(string sym) {
    if(!g_emrt_loaded) return 0.0;
    return g_emrt_cache.beta_star;
}
```

**Compile checkpoint**: ✅ Accessors work with or without cache

---

### Task 2: RL Agent Q-Table Infrastructure (Days 3-4)

**File**: `MQL5/Include/RPEA/rl_agent.mqh`

**Purpose**: Q-Learning agent for spread position management.

#### Step 2.1: State Space Definition

```cpp
#define RL_NUM_PERIODS    4
#define RL_NUM_QUANTILES  4
#define RL_NUM_STATES     256  // 4^4
#define RL_NUM_ACTIONS    3

enum RL_ACTION {
    RL_ACTION_EXIT  = 0,
    RL_ACTION_HOLD  = 1,
    RL_ACTION_ENTER = 2
};
```

**Compile checkpoint**: ✅ Enums defined

#### Step 2.2: Q-Table Structure

```cpp
double g_qtable[RL_NUM_STATES][RL_NUM_ACTIONS];
bool   g_qtable_loaded = false;

void RL_InitQTable() {
    ArrayInitialize(g_qtable, 0.0);  // Start with zeros
}
```

**Compile checkpoint**: ✅ Array initializes

> **Init note**: Call `RL_LoadThresholds()` during module init (or OnInit) so calibrated thresholds
> are available before any `RL_StateFromSpread()` calls. If it returns false, fixed 3% thresholds apply.

#### Step 2.3: State Discretization

```cpp
// Quantile bin thresholds (calibrated to spread change distribution)
// Default fallback: fixed 3% thresholds (spec baseline)
double g_quantile_thresholds[3] = {-0.03, 0.0, 0.03};
double g_sigma_ref = 0.0;
datetime g_thresholds_calibrated_at = 0;
bool g_thresholds_loaded = false;

// Load thresholds generated during pre-training
// File: Files/RPEA/rl/thresholds.json
// Format: { "k_thresholds": [-0.02, 0.0, 0.02], "sigma_ref": 0.015, "calibrated_at": "2026-01-28" }
// Fallback: if missing or stale (>30 days), keep fixed 3% thresholds
bool RL_LoadThresholds() {
    // TODO[M7-Phase1]: Load JSON, parse k_thresholds/sigma_ref/calibrated_at
    // If file missing or parse fails, return false (use defaults)
    // If calibrated_at older than 30 days, return false (use defaults)
    g_thresholds_loaded = false;
    return false;
}

int RL_QuantileBin(double value) {
    // Map continuous value to quantile bin [0, 3]
    // Uses calibrated thresholds when available (else fixed 3%)
    if(value < g_quantile_thresholds[0]) return 0;  // Large negative
    if(value < g_quantile_thresholds[1]) return 1;  // Small negative
    if(value < g_quantile_thresholds[2]) return 2;  // Small positive
    return 3;  // Large positive
}

int RL_StateFromSpread(double &changes[], int periods) {
    // Convert spread changes to quantile bins
    // Returns state ID [0, 255]
    if(ArraySize(changes) < periods) return 0;

    int state = 0;
    for(int i = 0; i < periods && i < RL_NUM_PERIODS; i++) {
        int quantile = RL_QuantileBin(changes[i]);
        state = state * RL_NUM_QUANTILES + quantile;
    }
    return state;
}
```

**Compile checkpoint**: ✅ State encoding works (RL_QuantileBin defined)

#### Step 2.4: Action Selection & Q-Advantage

```cpp
int RL_ActionForState(int state) {
    if(!g_qtable_loaded || state < 0 || state >= RL_NUM_STATES)
        return RL_ACTION_HOLD;  // Safe default

    // Argmax over actions
    int best_action = 0;
    double best_q = g_qtable[state][0];
    for(int a = 1; a < RL_NUM_ACTIONS; a++) {
        if(g_qtable[state][a] > best_q) {
            best_q = g_qtable[state][a];
            best_action = a;
        }
    }
    return best_action;
}

double RL_GetQAdvantage(int state) {
    if(!g_qtable_loaded || state < 0 || state >= RL_NUM_STATES)
        return 0.5;  // Neutral

    double q_max = g_qtable[state][0];
    double q_min = q_max;
    double q_sum = q_max;

    for(int a = 1; a < RL_NUM_ACTIONS; a++) {
        double q = g_qtable[state][a];
        q_sum += q;
        if(q > q_max) q_max = q;
        if(q < q_min) q_min = q;
    }

    double q_mean = q_sum / RL_NUM_ACTIONS;
    double range = q_max - q_min;
    if(range < 1e-9) return 0.5;

    return (q_max - q_mean) / range;  // Normalized advantage
}
```

**Compile checkpoint**: ✅ Action selection works

#### Step 2.5: File I/O

```cpp
bool RL_LoadQTable(string path) {
    int handle = FileOpen(path, FILE_READ|FILE_BIN);
    if(handle == INVALID_HANDLE) {
        RL_InitQTable();
        return false;
    }

    for(int s = 0; s < RL_NUM_STATES; s++) {
        for(int a = 0; a < RL_NUM_ACTIONS; a++) {
            g_qtable[s][a] = FileReadDouble(handle);
        }
    }
    FileClose(handle);
    g_qtable_loaded = true;
    return true;
}

bool RL_SaveQTable(string path) {
    int handle = FileOpen(path, FILE_WRITE|FILE_BIN);
    if(handle == INVALID_HANDLE) return false;

    for(int s = 0; s < RL_NUM_STATES; s++) {
        for(int a = 0; a < RL_NUM_ACTIONS; a++) {
            FileWriteDouble(handle, g_qtable[s][a]);
        }
    }
    FileClose(handle);
    return true;
}
```

**Compile checkpoint**: ✅ File I/O compiles

#### Step 2.6: Bellman Update (for Pre-Training)

> **Note**: This function is used by the Phase 3 pre-training script but must be defined here
> in the RL module so both the main EA and the script can access it.

```cpp
void RL_BellmanUpdate(int state, int action, double reward, int next_state, double alpha, double gamma) {
    // Q(s,a) = Q(s,a) + alpha * [r + gamma * max(Q(s',a')) - Q(s,a)]
    if(state < 0 || state >= RL_NUM_STATES) return;
    if(action < 0 || action >= RL_NUM_ACTIONS) return;
    if(next_state < 0 || next_state >= RL_NUM_STATES) return;

    double q_current = g_qtable[state][action];
    double q_max_next = g_qtable[next_state][0];

    for(int a = 1; a < RL_NUM_ACTIONS; a++) {
        if(g_qtable[next_state][a] > q_max_next)
            q_max_next = g_qtable[next_state][a];
    }

    double td_target = reward + gamma * q_max_next;
    g_qtable[state][action] = q_current + alpha * (td_target - q_current);
}
```

**Compile checkpoint**: ✅ Full RL module compiles (including Bellman for Phase 3)

---

## Phase 2: SignalMR Module (Days 5-7)

### Task 4: SignalMR Generation

**File**: `MQL5/Include/RPEA/signals_mr.mqh`

**Purpose**: Generate MR trade signals using EMRT + RL infrastructure.

> **Note**: Task numbering follows original spec. Task 4 executes before Task 3 because SignalMR can use empty Q-table.

#### Step 4.0: Init Validation Update

**File**: `MQL5/Experts/FundingPips/RPEA.mq5`

Ensure `UseXAUEURProxy=false` does not fail `OnInit()`. Log a warning and allow the EA to start:

```cpp
if(!UseXAUEURProxy) {
    Print("[Init] WARNING: UseXAUEURProxy=false (replication not implemented); MR signals will be skipped.");
    // Do not return INIT_FAILED
}
```

**Compile checkpoint**: ✅ EA starts with proxy disabled (MR path skipped)

#### Step 4.1: Required Includes & Validation

```cpp
#include "emrt.mqh"
#include "rl_agent.mqh"
#include "news.mqh"  // For News_IsBlocked() from M4
#include "m7_helpers.mqh"  // Spread/ATR/session helpers + SymbolBridge

// Module-scope guard (no static locals per repo rules)
bool g_mr_proxy_warned = false;

// Verify dependencies compile
void SignalsMR_ValidateDependencies() {
    double rank = EMRT_GetRank("XAUEUR");      // Returns 0.5 if not loaded
    double p50 = EMRT_GetP50("XAUEUR");        // Returns 75.0 if not loaded
    int action = RL_ActionForState(0);         // Returns HOLD if not loaded
    double qadv = RL_GetQAdvantage(0);         // Returns 0.5 if not loaded
}
```

**Compile checkpoint**: ✅ Dependencies resolve with safe defaults

#### Step 4.2: Entry Condition Logic

```cpp
bool SignalsMR_CheckEntryConditions(
    const AppContext& ctx,
    const string symbol,
    double &confidence
) {
    if(!EnableMR) return false;

    // Gate 1: News block (uses M4 news.mqh)
    string news_symbol = SymbolBridge_GetExecutionSymbol(symbol);
    if(news_symbol == "") news_symbol = symbol;
    if(News_IsEntryBlocked(news_symbol)) return false;

    // Gate 2: EMRT rank must be favorable (< p40 = fast reversion)
    string emrt_symbol = (symbol == "XAUUSD" ? "XAUEUR" : symbol);
    double emrt_rank = EMRT_GetRank(emrt_symbol);
    if(emrt_rank > EMRT_FastThresholdPct / 100.0) return false;

    // Gate 3: RL action must be ENTER
    double spread_changes[];  // Get from recent spread history
    SignalsMR_GetSpreadChanges(emrt_symbol, spread_changes, RL_NUM_PERIODS);
    int state = RL_StateFromSpread(spread_changes, RL_NUM_PERIODS);
    int action = RL_ActionForState(state);
    if(action != RL_ACTION_ENTER) return false;

    // Confidence = weighted combination of EMRT fastness + Q-advantage
    // EMRT_fastness = 1.0 - emrt_rank (lower rank = faster reversion = higher fastness)
    double emrt_fastness = 1.0 - emrt_rank;
    double q_advantage = RL_GetQAdvantage(state);

    // Weighted confidence: MR_EMRTWeight * EMRT fastness + (1 - MR_EMRTWeight) * Q-advantage
    double emrt_weight = MR_EMRTWeight;
    double q_weight = 1.0 - emrt_weight;
    confidence = emrt_weight * emrt_fastness + q_weight * q_advantage;
    return true;
}

// Helper: Get recent spread changes for state calculation
void SignalsMR_GetSpreadChanges(const string symbol, double &changes[], int periods) {
    ArrayResize(changes, periods);

    // Get recent synthetic spread values
    // For XAUEUR: use log-ratio when MR_UseLogRatio=true; otherwise linear spread with beta
    string emrt_symbol = (symbol == "XAUUSD" ? "XAUEUR" : symbol);
    double beta = EMRT_GetBeta(emrt_symbol);

    // Retrieve M1 bar data for spread calculation
    double xau_close[], eur_close[];
    ArraySetAsSeries(xau_close, true);
    ArraySetAsSeries(eur_close, true);

    int copied_xau = CopyClose("XAUUSD", PERIOD_M1, 0, periods + 1, xau_close);
    int copied_eur = CopyClose("EURUSD", PERIOD_M1, 0, periods + 1, eur_close);

    if(copied_xau < periods + 1 || copied_eur < periods + 1) {
        ArrayInitialize(changes, 0.0);  // Safe default
        return;
    }

    // Calculate spread changes (current - previous)
    for(int i = 0; i < periods; i++) {
        double spread_curr;
        double spread_prev;
        if(MR_UseLogRatio) {
            if(xau_close[i] <= 0.0 || eur_close[i] <= 0.0 ||
               xau_close[i + 1] <= 0.0 || eur_close[i + 1] <= 0.0) {
                changes[i] = 0.0;
                continue;
            }
            spread_curr = MathLog(xau_close[i]) - MathLog(eur_close[i]);
            spread_prev = MathLog(xau_close[i + 1]) - MathLog(eur_close[i + 1]);
        } else {
            spread_curr = xau_close[i] - beta * eur_close[i];
            spread_prev = xau_close[i + 1] - beta * eur_close[i + 1];
        }
        changes[i] = spread_curr - spread_prev;
    }
}
```

**Compile checkpoint**: ✅ Entry logic compiles (confidence includes EMRT fastness)

#### Step 4.3: SL/TP Calculation

```cpp
void SignalsMR_CalculateSLTP(
    const string signal_symbol,
    int direction,
    int &slPoints,
    int &tpPoints
) {
    // Map signal symbol to execution symbol via SymbolBridge
    string exec_symbol = SymbolBridge_GetExecutionSymbol(signal_symbol);

    double atr = M7_GetATR_D1(exec_symbol);
    double point = SymbolInfoDouble(exec_symbol, SYMBOL_POINT);

    if(point < 1e-9) {
        // Fallback for synthetic symbol - use XAUUSD point
        point = SymbolInfoDouble("XAUUSD", SYMBOL_POINT);
    }

    // SL: ATR-scaled
    slPoints = (int)(atr * Config_GetSLmult() / point);

    // TP: Based on EMRT p50 and expected R
    double p50 = EMRT_GetP50(signal_symbol);
    double expected_R = 1.5;  // Target R:R
    tpPoints = (int)(slPoints * expected_R);

    // Time-stop bounds from inputs
    // MR_TimeStopMin, MR_TimeStopMax applied in allocator
}
```

**Compile checkpoint**: Compiles (uses SymbolBridge for exec symbol mapping)

#### Step 4.4: Main Proposal Function

```cpp
void SignalsMR_Propose(
    const AppContext& ctx,
    const string symbol,
    bool &hasSetup,
    string &setupType,
    int &slPoints,
    int &tpPoints,
    double &bias,
    double &confidence
) {
    // Initialize outputs
    hasSetup = false;
    setupType = "None";
    slPoints = 0;
    tpPoints = 0;
    bias = 0.0;
    confidence = 0.0;

    // Gate: Only process XAUEUR (synthetic) or XAUUSD when proxy enabled
    if(!UseXAUEURProxy) {
        // MR disabled when proxy off - log warning once
        if(!g_mr_proxy_warned) {
            Print("[SignalsMR] WARNING: UseXAUEURProxy=false, MR signals disabled");
            g_mr_proxy_warned = true;
        }
        return;
    }

    // Gate: MR only applies to gold symbols
    if(symbol != "XAUEUR" && symbol != "XAUUSD") {
        return;  // Not applicable to this symbol
    }

    // Check if MR entry conditions met
    string signal_symbol = (symbol == "XAUUSD" ? "XAUEUR" : symbol);
    if(!SignalsMR_CheckEntryConditions(ctx, signal_symbol, confidence))
        return;

    // Determine direction from spread analysis
    double spread_mean = M7_GetSpreadMean(signal_symbol, 60);  // 60-period mean
    double spread_current = M7_GetSpreadCurrent(signal_symbol);

    if(spread_current > spread_mean) {
        bias = -1.0;  // Short: revert down to mean
    } else {
        bias = 1.0;   // Long: revert up to mean
    }

    // Respect MR_LongOnly input
    if(MR_LongOnly && bias < 0) return;

    // Calculate SL/TP
    int direction = (bias > 0) ? 1 : -1;
    SignalsMR_CalculateSLTP(signal_symbol, direction, slPoints, tpPoints);

    // Check confidence threshold
    if(confidence < MR_ConfCut) return;

    // Valid setup
    hasSetup = true;
    setupType = "MR";
}
```

**Compile checkpoint**: Full SignalMR module compiles (with symbol guards)

> **Phase 2 Expectation**: With empty Q-table and no EMRT cache, SignalMR will return
> `hasSetup=false` for all calls. This is expected behavior until Phase 3 (pre-training)
> and EMRT refresh are complete. The compile checkpoint validates structure, not signal generation.

---

## Phase 3: Pre-Training Script (Days 8-9)

### Task 3: RL Pre-Training

**File**: `MQL5/Scripts/rl_pretrain.mq5`

> **Note**: Create `MQL5/Scripts/` directory if it doesn't exist. This script compiles
> separately from the main EA and does NOT block EA compilation.

**Purpose**: Offline Q-table training using historical spread data.

#### Step 3.1: Script Structure

```cpp
#property script_show_inputs

#include <RPEA/rl_agent.mqh>

input int    TrainingEpisodes = 10000;
input double LearningRate     = 0.1;
input double DiscountFactor   = 0.99;
input double EpsilonStart     = 1.0;
input double EpsilonEnd       = 0.1;
input string OutputPath       = "RPEA/qtable/mr_qtable.bin";

void OnStart() {
    Print("Starting RL Pre-Training...");

    // Initialize Q-table
    RL_InitQTable();

    // Run training episodes
    for(int ep = 0; ep < TrainingEpisodes; ep++) {
        double epsilon = EpsilonStart - (EpsilonStart - EpsilonEnd) * ep / TrainingEpisodes;
        RunEpisode(epsilon, LearningRate, DiscountFactor);

        if(ep % 1000 == 0)
            PrintFormat("Episode %d/%d", ep, TrainingEpisodes);
    }

    // Save trained Q-table
    if(RL_SaveQTable(OutputPath))
        Print("Q-table saved to ", OutputPath);
    else
        Print("ERROR: Failed to save Q-table");

    // Save calibrated thresholds for live discretization
    // File: MQL5/Files/RPEA/rl/thresholds.json
    if(RL_SaveThresholds("RPEA/rl/thresholds.json"))
        Print("Thresholds saved.");
    else
        Print("WARNING: Failed to save thresholds.");
}
```

**Compile checkpoint**: ✅ Script compiles independently

#### Step 3.2: Episode Simulation

```cpp
void RunEpisode(double epsilon, double alpha, double gamma) {
    // Simulate spread trajectory using historical volatility
    double spread_changes[];
    GenerateSpreadTrajectory(spread_changes, 100);  // 100 timesteps

    int state = 0;
    int position = 0;  // -1=short, 0=flat, 1=long
    double spread = 0.0; // Y_t (spread level, mean-centered)
    double cumulative_reward = 0.0;
    const double cost_per_step = 0.001; // c in spec (tune as needed)

    for(int t = 0; t < ArraySize(spread_changes) - 1; t++) {
        spread += spread_changes[t];

        // Get action (epsilon-greedy)
        int action;
        if(MathRand() / 32768.0 < epsilon) {
            action = MathRand() % RL_NUM_ACTIONS;  // Random
        } else {
            action = RL_ActionForState(state);     // Greedy
        }

        // Execute action, get reward
        // TODO: simulate news windows + floor/target barriers for penalties
        bool news_blocked = false;
        bool barrier_breached = false;
        double reward = ExecuteAction(action, position, spread, cost_per_step, news_blocked, barrier_breached);

        // Next state
        int next_state = RL_StateFromSpread(spread_changes, t + 1);

        // Bellman update
        RL_BellmanUpdate(state, action, reward, next_state, alpha, gamma);

        state = next_state;
        cumulative_reward += reward;
    }
}
```

**Compile checkpoint**: ✅ Training loop compiles

#### Step 3.3: Reward Function & Episode Helpers

> **Note**: `RL_BellmanUpdate()` is already defined in Phase 1 Task 2 Step 2.6.
> The pre-training script includes `rl_agent.mqh` which provides this function.

```cpp
// Reward function for mean reversion training
// Spec: r_{t+1} = A_t * (theta - Y_t) - c * |A_t| - penalties
// Here theta = 0 (mean-centered), Y_t = spread level, A_t = position after action
double ExecuteAction(int action, int &position, double spread_level,
                     double cost_per_step, bool news_blocked, bool barrier_breached) {
    double reward = 0.0;

    switch(action) {
        case RL_ACTION_ENTER:
            if(position == 0) {
                // Enter position in direction opposite to spread deviation
                position = (spread_level > 0) ? -1 : 1;
            }
            break;

        case RL_ACTION_HOLD:
            break;

        case RL_ACTION_EXIT:
            if(position != 0) {
                // Exit position
                position = 0;
            }
            break;
    }

    // Base reward per spec: A_t * (0 - Y_t) - c * |A_t|
    reward += position * (0.0 - spread_level) - cost_per_step * MathAbs((double)position);

    // Penalties per spec (news window + floor/target breaches)
    if(news_blocked)
        reward -= cost_per_step;     // Placeholder penalty (tune)
    if(barrier_breached)
        reward -= cost_per_step * 5; // Placeholder penalty (tune)

    return reward;
}

// Generate synthetic spread trajectory for training
void GenerateSpreadTrajectory(double &changes[], int length) {
    ArrayResize(changes, length);

    // Ornstein-Uhlenbeck process simulation
    double theta = 0.1;   // Mean reversion speed
    double sigma = 0.02;  // Volatility
    double spread = 0.0;

    for(int i = 0; i < length; i++) {
        double dW = MathRandomNormal(0, 1) * MathSqrt(1.0);  // dt=1
        double d_spread = -theta * spread + sigma * dW;
        changes[i] = d_spread;
        spread += d_spread;
    }
}

// Simple normal distribution approximation
double MathRandomNormal(double mean, double stddev) {
    // Box-Muller transform using MathRand()
    double u1 = (MathRand() + 1) / 32768.0;  // Avoid log(0)
    double u2 = MathRand() / 32768.0;
    const double pi = 3.14159265358979323846;
    double z = MathSqrt(-2.0 * MathLog(u1)) * MathCos(2.0 * pi * u2);
    return mean + stddev * z;
}
```

**Compile checkpoint**: ✅ Full pre-training script compiles

#### Step 3.4: Save Threshold Calibration (Required)

During pre-training, compute thresholds from simulated spread changes and persist them
so live trading uses consistent bins.

**File**: `Files/RPEA/rl/thresholds.json`

**Format**:
```
{ "k_thresholds": [-0.02, 0.0, 0.02], "sigma_ref": 0.015, "calibrated_at": "2026-01-28" }
```

**Staleness rule**: If `calibrated_at` is older than 30 days, live trading falls back to fixed 3% thresholds.

```cpp
bool RL_SaveThresholds(const string path) {
    // TODO[M7-Phase3]: derive k_thresholds from training distribution
    double k_thresholds[3] = {-0.02, 0.0, 0.02};
    double sigma_ref = 0.015;
    string calibrated_at = TimeToString(TimeCurrent(), TIME_DATE);

    int handle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE) return false;
    FileWriteString(handle,
        StringFormat("{\"k_thresholds\":[%.4f,%.4f,%.4f],\"sigma_ref\":%.6f,\"calibrated_at\":\"%s\"}",
            k_thresholds[0], k_thresholds[1], k_thresholds[2], sigma_ref, calibrated_at));
    FileClose(handle);
    return true;
}
```

---

## Phase 4: Meta-Policy (Days 10-11)

### Task 5: Meta-Policy Chooser

**File**: `MQL5/Include/RPEA/meta_policy.mqh`

**Purpose**: Intelligent strategy selection between BWISC and MR.

#### Step 5.1: Context Structure

> **Note**: Regime, liquidity quantiles, and efficiency are wired in Phase 5.
> In Phase 4, keep safe defaults (neutral) so the module compiles.

```cpp
struct MetaPolicyContext {
    // BWISC inputs
    bool   bwisc_has_setup;
    double bwisc_confidence;
    double bwisc_ore;           // Opening Range Energy
    double bwisc_efficiency;    // Expected or recent efficiency (Phase 5)

    // MR inputs
    bool   mr_has_setup;
    double mr_confidence;
    double emrt_rank;
    double q_advantage;
    double mr_efficiency;       // Expected or recent efficiency (Phase 5)

    // Market context
    double atr_d1_percentile;   // ATR vs lookback
    int    session_age_minutes;
    bool   news_within_15m;     // News window proximity

    // Liquidity/news gating
    bool   entry_blocked;       // News window + stabilization (Phase 5 uses News_IsEntryBlocked)
    double spread_quantile;     // Rolling spread percentile [0..1]
    double slippage_quantile;   // Rolling slippage percentile [0..1]

    // Regime context (Phase 5)
    int    regime_label;        // REGIME_LABEL

    // Session state
    int    entries_this_session;
    bool   locked_to_mr;
};
```

**Compile checkpoint**: ✅ Struct compiles

#### Step 5.2: Deterministic Rules (Primary)

```cpp
string MetaPolicy_DeterministicChoice(const MetaPolicyContext& ctx) {
    // Rule 0: Entry blocked (news window or stabilization)
    if(ctx.entry_blocked)
        return "Skip";

    // Rule 0b: Liquidity quantile gate (Phase 5 stats)
    if(ctx.spread_quantile >= 0.90 || ctx.slippage_quantile >= 0.90)
        return "Skip";

    // Rule 1: Session cap
    if(ctx.entries_this_session >= 2)
        return "Skip";

    // Rule 2: MR lock (hysteresis)
    if(ctx.locked_to_mr && ctx.mr_has_setup)
        return "MR";

    // Rule 3: Confidence tie-breaker
    if(ctx.bwisc_confidence < BWISC_ConfCut &&
       ctx.mr_confidence > MR_ConfCut &&
       ctx.mr_efficiency >= ctx.bwisc_efficiency &&
       ctx.mr_has_setup)
        return "MR";

    // Rule 4: Conditional BWISC replacement
    if(ctx.bwisc_ore < 0.40 &&                    // Low ORE
       ctx.atr_d1_percentile < 0.50 &&            // Low volatility
       ctx.emrt_rank <= EMRT_FastThresholdPct / 100.0 && // Fast reversion
       ctx.session_age_minutes < 120 &&           // Early session
       !ctx.news_within_15m &&                    // No news
       ctx.mr_has_setup)
        return "MR";

    // Rule 5: BWISC if qualified
    if(ctx.bwisc_has_setup && ctx.bwisc_confidence >= BWISC_ConfCut)
        return "BWISC";

    // Rule 6: MR if BWISC has no setup
    if(!ctx.bwisc_has_setup && ctx.mr_has_setup)
        return "MR";

    // Default: Skip
    return "Skip";
}
```

**Compile checkpoint**: ✅ Deterministic rules compile

#### Step 5.3: Bandit Integration (Optional)

> **API Note**: The existing `bandit.mqh` provides `Bandit_SelectPolicy(const AppContext&, const string)`
> which returns `BanditPolicy` enum. We wrap this to match meta-policy flow.

```cpp
// Check if bandit is ready (has trained posterior)
bool MetaPolicy_BanditIsReady() {
    // TODO[M7]: Check if posterior.json exists and is valid
    // For now, return false to use deterministic rules
    return false;
}

string MetaPolicy_BanditChoice(const AppContext& ctx, const string symbol, const MetaPolicyContext& mpc) {
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
            StringFormat("{\"bandit\":\"%s\",\"deterministic\":\"%s\"}", bandit_str, det_str));
        return det_str;
    }

    return bandit_str;
}
```

**Compile checkpoint**: Bandit integration compiles (uses existing API)

#### Step 5.4: Main Entry Point

> **Decision-Only Gate**: In Phase 4, set `M7_DECISION_ONLY=1` to log decisions
> and return `Skip`, which disables all execution (BWISC + MR). Remove the gate
> in Phase 5 Task 7 to allow trading.

```cpp
// Phase 4 decision-only flag - set to false in Phase 5
#define M7_DECISION_ONLY 1

string MetaPolicy_Choose(
    const AppContext& ctx,
    const string symbol,
    bool bw_has, double bw_conf,
    bool mr_has, double mr_conf
) {
    // Build context (gather additional data)
    MetaPolicyContext mpc;
    mpc.bwisc_has_setup = bw_has;
    mpc.bwisc_confidence = bw_conf;
    mpc.mr_has_setup = mr_has;
    mpc.mr_confidence = mr_conf;
    mpc.bwisc_efficiency = 0.0; // TODO Phase 5: compute recent/expected efficiency
    mpc.mr_efficiency = 0.0;    // TODO Phase 5: compute recent/expected efficiency

    // Fill remaining context from M7 helpers (all take ctx/symbol)
    mpc.emrt_rank = EMRT_GetRank("XAUEUR");  // EMRT computed for synthetic
    mpc.q_advantage = RL_GetQAdvantage(0);   // Current state
    mpc.bwisc_ore = M7_GetCurrentORE(ctx, symbol);
    mpc.atr_d1_percentile = M7_GetATR_D1_Percentile(ctx, symbol);
    mpc.session_age_minutes = M7_GetSessionAgeMinutes(ctx, symbol);
    mpc.news_within_15m = M7_NewsIsWithin15Minutes(symbol);
    mpc.entry_blocked = News_IsEntryBlocked(symbol); // includes post-news stabilization
    mpc.spread_quantile = 0.5;   // TODO Phase 5: Liquidity spread percentile
    mpc.slippage_quantile = 0.5; // TODO Phase 5: Liquidity slippage percentile
    mpc.regime_label = 0;        // TODO Phase 5: Regime_Detect(ctx, symbol)
    mpc.entries_this_session = M7_GetEntriesThisSession(ctx, symbol);
    mpc.locked_to_mr = M7_IsLockedToMR();

    // Make decision
    string choice = MetaPolicy_BanditChoice(ctx, symbol, mpc);

    // Decision-only gate for Phase 4 testing
    #if M7_DECISION_ONLY
    LogDecision("MetaPolicy", "DECISION_ONLY",
        StringFormat("{\"choice\":\"%s\",\"bw_conf\":%.2f,\"mr_conf\":%.2f}",
            choice, bw_conf, mr_conf));
    return "Skip";  // Phase 4: disable all execution (BWISC + MR)
    #else
    // Update session state if MR chosen
    if(choice == "MR") {
        M7_SetLockedToMR(true);
    }
    return choice;
    #endif
}
```

**Compile checkpoint**: Full meta-policy compiles (with decision-only gate)

> **Callsite update**: `scheduler.mqh` must pass `ctx` and `symbol` to `MetaPolicy_Choose()`
> (signature updated from the Phase 0 stub).

> **Phase 4 vs Phase 5**: In Phase 4, `M7_DECISION_ONLY=1` logs decisions and
> disables execution (no BWISC/MR trades). In Phase 5 Task 7, change to
> `#define M7_DECISION_ONLY 0` to enable actual order placement.

---

## Phase 5: Integration (Days 12-15)

### Task 6: Telemetry + Regime Detection (Days 12-13)

**File**: `MQL5/Include/RPEA/telemetry.mqh` (extend), `MQL5/Include/RPEA/regime.mqh` (extend)

> **Note**: `regime.mqh` already exists as a stub. Extend it with detection logic.

#### Step 6.1: Regime Detection

```cpp
// regime.mqh - extend existing stub
#include "indicators.mqh"
#include "m7_helpers.mqh"

enum REGIME_LABEL {
    REGIME_UNKNOWN = 0,
    REGIME_TRENDING = 1,
    REGIME_RANGING = 2,
    REGIME_VOLATILE = 3
};

// ADX indicator handle cache
int g_adx_handle = INVALID_HANDLE;

bool Regime_Init(const string symbol) {
    if(g_adx_handle == INVALID_HANDLE) {
        g_adx_handle = iADX(symbol, PERIOD_D1, 14);
    }
    return (g_adx_handle != INVALID_HANDLE);
}

double Regime_GetADX(const string symbol) {
    if(g_adx_handle == INVALID_HANDLE) {
        if(!Regime_Init(symbol)) return 0.0;
    }

    double adx_buffer[];
    ArraySetAsSeries(adx_buffer, true);
    if(CopyBuffer(g_adx_handle, 0, 0, 1, adx_buffer) < 1)
        return 0.0;

    return adx_buffer[0];
}

REGIME_LABEL Regime_Detect(const AppContext& ctx, const string symbol) {
    double atr = M7_GetATR_D1(symbol);
    double atr_pct = M7_GetATR_D1_Percentile(ctx, symbol);
    double adx = Regime_GetADX(symbol);

    // High ATR percentile = volatile
    if(atr_pct > 0.75) return REGIME_VOLATILE;

    // High ADX = trending
    if(adx > 25.0) return REGIME_TRENDING;

    // Default = ranging
    return REGIME_RANGING;
}
```

**Compile checkpoint**: Regime module compiles (uses existing indicator infrastructure)

#### Step 6.2: Enhanced Telemetry

> **Note**: Use existing `LogDecision()` from `logging.mqh` for all telemetry.
> **Required audit fields (spec)**: `confidence`, `efficiency`, `rho_est`,
> `hold_time`, `gating_reason`, `news_window_state`. Include regime label and
> liquidity quantiles when available (Phase 5).

```cpp
void LogMetaPolicyDecision(
    const string symbol,
    const string choice,
    const string gating_reason,
    const string news_state,
    double bwisc_conf,
    double mr_conf,
    double bwisc_eff,
    double mr_eff,
    double emrt_rank,
    double rho_est,
    double spread_q,
    double slippage_q,
    int hold_minutes_est,
    REGIME_LABEL regime
) {
    string regime_str;
    switch(regime) {
        case REGIME_TRENDING: regime_str = "TRENDING"; break;
        case REGIME_RANGING:  regime_str = "RANGING"; break;
        case REGIME_VOLATILE: regime_str = "VOLATILE"; break;
        default: regime_str = "UNKNOWN";
    }

    // Use existing LogDecision API from logging.mqh
    string fields = StringFormat(
        "{\"symbol\":\"%s\",\"choice\":\"%s\",\"gating_reason\":\"%s\",\"news_window_state\":\"%s\","
        "\"bwisc_conf\":%.2f,\"mr_conf\":%.2f,\"bwisc_eff\":%.2f,\"mr_eff\":%.2f,"
        "\"emrt\":%.2f,\"rho_est\":%.2f,\"spread_q\":%.2f,\"slippage_q\":%.2f,"
        "\"hold_time_min\":%d,\"regime\":\"%s\"}",
        symbol, choice, gating_reason, news_state,
        bwisc_conf, mr_conf, bwisc_eff, mr_eff,
        emrt_rank, rho_est, spread_q, slippage_q,
        hold_minutes_est, regime_str);

    LogDecision("MetaPolicy", "EVAL", fields);
}
```

**Compile checkpoint**: Telemetry extensions compile (uses existing LogDecision)

#### Step 6.3: Liquidity Quantiles + Entry Gates

**File**: `MQL5/Include/RPEA/liquidity.mqh` (extend)

**Purpose**: Maintain rolling spread/slippage stats and expose percentiles for gating.

```cpp
// TODO[M7-Phase5]: Extend liquidity.mqh with rolling stats
bool   Liquidity_UpdateStats(const string symbol, double spread_pts, double slippage_pts);
double Liquidity_GetSpreadQuantile(const string symbol);   // percentile of current spread [0..1]
double Liquidity_GetSlippageQuantile(const string symbol); // percentile of recent slippage [0..1]
```

**Integration**:
- Feed `mpc.spread_quantile` and `mpc.slippage_quantile` in `MetaPolicy_Choose`.
- Gate entries when either quantile >= 0.90 (see Rule 0b).

**Compile checkpoint**: Liquidity quantile helpers compile with safe defaults (0.5)

#### Step 6.4: Efficiency Tracking

**File**: `MQL5/Include/RPEA/telemetry.mqh` (extend) or a new helper in `meta_policy.mqh`

**Purpose**: Provide rolling efficiency for BWISC/MR: `efficiency = expected_R / worst_case_risk`

```cpp
// TODO[M7-Phase5]: Track rolling efficiency per strategy
double MetaPolicy_GetBWISCEfficiency();  // return 0.0 until populated
double MetaPolicy_GetMREfficiency();     // return 0.0 until populated
```

**Integration**:
- Use in Rule 3: only prefer MR when `mr_efficiency >= bwisc_efficiency`.

**Compile checkpoint**: Efficiency helpers compile with safe defaults (0.0)

### Task 7: Allocator Integration (Day 14)

**File**: `MQL5/Include/RPEA/allocator.mqh`

> **Important**: Also change `#define M7_DECISION_ONLY 0` in `meta_policy.mqh` to enable execution.

#### Step 7.1: Enable MR Strategy

Change from:
```cpp
if(strategy != "BWISC") {
    LogDecision("Allocator", "REJECTED", "{\"reason\":\"unsupported_strategy\"}");
    return false;
}
```

To:
```cpp
if(strategy != "BWISC" && strategy != "MR") {
    LogDecision("Allocator", "REJECTED", "{\"reason\":\"unsupported_strategy\"}");
    return false;
}

// Use strategy-specific risk
double riskPct;
if(strategy == "MR") {
    riskPct = MR_RiskPct_Default / 100.0;
} else {
    riskPct = Config_GetRiskPct();
}
```

**Compile checkpoint**: ✅ Allocator accepts MR orders

#### Step 7.2: SLO Monitoring

```cpp
struct SLO_Metrics {
    double mr_win_rate_30d;
    double mr_median_hold_hours;
    double mr_hold_p80_hours;
    double mr_median_efficiency;   // realized R / worst_case_risk
    double mr_median_friction_r;   // (realized - theoretical) R
    bool   warn_only;
    bool   slo_breached;
};

void SLO_CheckAndThrottle(SLO_Metrics& metrics) {
    // Spec thresholds:
    // - MR win rate warn < 55% (target 58-62%)
    // - Median hold <= 2.5h, 80th percentile <= 4h
    // - Median efficiency >= 0.8
    // - Median friction tax <= 0.4R
    metrics.warn_only = (metrics.mr_win_rate_30d < 0.55);

    if(metrics.mr_win_rate_30d < 0.55 ||
       metrics.mr_median_hold_hours > 2.5 ||
       metrics.mr_hold_p80_hours > 4.0 ||
       metrics.mr_median_efficiency < 0.80 ||
       metrics.mr_median_friction_r > 0.40) {
        metrics.slo_breached = true;
        // Throttle: MR_RiskPct *= 0.75 (or disable MR if persistent)
    }
}
```

**Compile checkpoint**: ✅ SLO monitoring compiles

### Task 8: End-to-End Testing (Day 15)

**Test Plan:**

1. **Unit Tests:**
   - EMRT calculation with known spread data
   - RL state discretization edge cases
   - Meta-policy rule triggers

2. **Integration Tests:**
   - Strategy Tester: 5 trading days
   - Verify both BWISC and MR generate signals
   - Verify no symbol overlap
   - Validate telemetry logs

3. **Regression Tests:**
   - BWISC-only mode still works (EnableMR=false)
   - News compliance unchanged
   - Risk sizing unchanged for BWISC

**Compile checkpoint**: ✅ All tests pass, full EA compiles

---

## Dependency Verification Matrix

| Task | Requires | Provides | Safe Default |
|------|----------|----------|--------------|
| Phase 0 | - | Inputs, stubs, helper wrappers | All stubs return safe values |
| Task 1 | Phase 0 | EMRT_GetRank(), EMRT_GetP50(), EMRT_GetBeta() | 0.5, 75.0, 0.0 |
| Task 2 | Phase 0 | RL_StateFromSpread(), RL_ActionForState(), RL_GetQAdvantage(), RL_QuantileBin(), RL_BellmanUpdate() | 0, HOLD, 0.5 |
| Task 4 | Tasks 1,2 | SignalsMR_Propose(), SignalsMR_GetSpreadChanges() | hasSetup=false |
| Task 3 | Task 2 | Pre-trained Q-table file | Script compiles separately (uses RL_BellmanUpdate from Task 2) |
| Task 5 | Task 4 | MetaPolicy_Choose() | Falls back to BWISC |
| Task 6 | - | Regime_Detect(), enhanced telemetry | UNKNOWN regime |
| Task 7 | Task 5 | Allocator accepts MR | - |
| Task 8 | All | Validation | - |

**✅ No forward dependencies. Every task can be compiled after completion.**

### Key Dependency Notes

1. **RL_BellmanUpdate()**: Defined in Task 2 (Phase 1), used by Task 3 (Phase 3). No forward dependency since Task 2 completes before Task 3.
2. **RL_QuantileBin()**: Defined in Task 2, called by RL_StateFromSpread(). Self-contained within Task 2.
3. **Helper wrappers** (GetATR_D1, GetSpreadCurrent, etc.): Defined in Phase 0 using existing M1-M6 infrastructure.
4. **Confidence calculation**: Uses `MR_EMRTWeight * EMRT_fastness + (1 - MR_EMRTWeight) * Q_advantage` (default 0.60/0.40).

---

## FundingPips Challenge Alignment

| Requirement | How Addressed |
|-------------|---------------|
| 4% daily loss cap | Existing kill-switch unchanged |
| 6% overall loss cap | Existing kill-switch unchanged |
| +10% profit target | MR fills gaps when BWISC confidence low |
| Minimum 3 trading days | Ensemble increases daily opportunity count |
| News compliance | MR uses same News_IsBlocked() from M4 |
| Risk management | MR uses 0.9% default (lower than BWISC) |
| Win rate 58-62% | EMRT + RL optimize for mean reversion success |
| Median hold ≤ 2.5h | MR_TimeStopMin/Max enforce bounds |

---

## Quick Reference: Compile Checkpoints

```
Phase 0: ✅ RPEA.mq5 with stubs compiles
Task 1:  ✅ EMRT module compiles with safe defaults
Task 2:  ✅ RL module compiles with safe defaults
Task 4:  ✅ SignalMR compiles (uses EMRT + RL defaults)
Task 3:  ✅ Pre-training script compiles separately
Task 5:  ✅ Meta-policy compiles (falls back to deterministic)
Task 6:  ✅ Telemetry + regime compiles
Task 7:  ✅ Allocator accepts MR strategy
Task 8:  ✅ All tests pass
```

---

## Summary

This final workflow consolidates the best elements from all three source documents:

1. **From m7-workflow.md**: Phase 0 scaffolding concept, explicit compile checkpoints
2. **From m7-implementation-workflow.md**: Parallel execution opportunities, detailed dependency chain
3. **From m7-revised-workflow.md**: Safe defaults pattern, Task 4 before Task 3 ordering

The result is a **zero-forward-dependency workflow** where every task compiles independently, enabling incremental validation and reducing integration risk.
