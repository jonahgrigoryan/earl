# RPEA (RapidPass Expert Advisor) - Production Implementation Guide

## M1 Compile & Run Notes

- Build: open `MQL5/Experts/FundingPips/RPEA.mq5` in MetaEditor and compile (requires `#property strict` which is set).
- Attach to a chart to start the 30s scheduler. The EA auto-creates `MQL5/Files/RPEA/*` folders and placeholder files.
- Logging: heartbeat/decisions to `MQL5/Files/RPEA/logs/decisions_YYYYMMDD.csv`, audit events to `MQL5/Files/RPEA/logs/audit_YYYYMMDD.csv`.
- State: persisted at `MQL5/Files/RPEA/state/challenge_state.json` with anchors `{server_midnight_ts, baseline_today_e0, baseline_today_b0, baseline_today}`.
- News: tolerant CSV fallback at `MQL5/Files/RPEA/news/calendar_high_impact.csv` (empty file is valid).
- Placeholders for EMRT/Q‑table/bandit/liquidity/calibration/sets/tester are created on first run.
- All headers start with `#pragma once` and contain TODO markers like `TODO[M1]..TODO[M7]` for roadmap items.
- M1 has no broker side-effects; order functions are stubs and only log.

## Overview

The **FundingPips 10K RapidPass EA (RPEA)** is a sophisticated MT5 Expert Advisor designed to pass the FundingPips 1-step $10,000 challenge by achieving +10% profit ($1,000) with zero drawdown violations in 3-5 trading days.

**Key Features:**
- Hybrid ensemble architecture (BWISC primary + MR fallback strategies)
- Adaptive regime detection and dynamic risk allocation
- Real-time correlation monitoring for synthetic pairs
- Advanced news compliance with account-type differentiation
- Self-healing order management with intent journaling
- Comprehensive learning and calibration systems

## 🎯 Challenge Requirements

- **Target**: +$1,000 profit (+10% of $10K account)
- **Timeline**: 3-5 trading days ideally
- **Constraints**: Zero daily/overall drawdown cap violations
- **Minimum**: ≥3 distinct trading days required
- **Leverage**: 1:50 FX / 1:20 metals
- **Compliance**: Account-specific news restrictions

## 📋 Technical Specifications

### Core Documents
- **`finalspec.md`**: Locked technical specification (670 lines) - AUTHORITATIVE
- **`prd.md`**: Product requirements document (166 lines)
- **`rpea_structure.txt`**: File organization and project layout
- **`statstical_arbitrage.txt`**: Research background for EMRT/RL

### Architecture Overview
```
RPEA (Ensemble EA)
├── BWISC Strategy (Primary)    # Burst-Weighted Imbalance with Session Confluence
├── MR Strategy (Fallback)      # Mean Reversion with EMRT/RL
├── Meta-Policy Controller      # Strategy selection and routing
├── Adaptive Risk Allocator     # Regime-aware position sizing
├── News Compliance Engine      # Account-specific restrictions
└── Synthetic Pair Manager     # XAUEUR proxy/replication
```

## 🏗️ Project Structure

### Core Files Layout
```
MQL5/
├── Experts/FundingPips/
│   └── RPEA.mq5                    # Main EA entry point
├── Include/RPEA/
│   ├── config.mqh                  # Input parameters and constants
│   ├── state.mqh                   # Persistent state management
│   ├── timeutils.mqh               # DST-aware time handling
│   ├── sessions.mqh                # Session predicates and OR windows
│   ├── indicators.mqh              # ATR/RSI/MA handles
│   ├── regime.mqh                  # Market regime classification
│   ├── liquidity.mqh               # Spread/slippage monitoring
│   ├── anomaly.mqh                 # Shock detection and protection
│   ├── signals_bwisc.mqh           # BWISC signal engine
│   ├── signals_mr.mqh              # Mean reversion engine
│   ├── emrt.mqh                    # EMRT formation calculations
│   ├── rl_agent.mqh                # Q-learning implementation
│   ├── bandit.mqh                  # Contextual bandit selector
│   ├── meta_policy.mqh             # Strategy routing logic
│   ├── allocator.mqh               # Risk budget allocation
│   ├── adaptive.mqh                # Regime-based risk scaling
│   ├── risk.mqh                    # Position sizing and margin
│   ├── equity_guardian.mqh         # Baseline tracking and floors
│   ├── order_engine.mqh            # OCO and atomic operations
│   ├── synthetic.mqh               # XAUEUR implementation
│   ├── news.mqh                    # Calendar API and CSV fallback
│   ├── learning.mqh                # Online learning manager
│   ├── persistence.mqh             # State persistence and recovery
│   ├── logging.mqh                 # CSV audit and telemetry
│   └── telemetry.mqh               # SLO monitoring and auto-actions
└── Files/RPEA/
    ├── state/                      # Persistent state files
    ├── logs/                       # Audit trails and decisions
    ├── news/                       # CSV news fallback
    ├── emrt/                       # EMRT cache and formation data
    ├── qtable/                     # Q-learning tables
    ├── bandit/                     # Contextual bandit posteriors
    ├── liquidity/                  # Market microstructure stats
    ├── calibration/                # Rolling parameter calibration
    ├── sets/                       # Strategy Tester configurations
    ├── strategy_tester/            # Tester INI and configs
    └── reports/                    # Generated audit/report artifacts
```

## 🖥️ MT5 Setup & Compilation

1. In MT5, open the terminal Data Folder: File → Open Data Folder.
2. Copy this repo’s `MQL5/` tree into the terminal’s Data Folder `MQL5/` directory, preserving structure.
3. Open MetaEditor and compile `MQL5/Experts/FundingPips/RPEA.mq5`.
4. In MT5 terminal:
   - Enable Algo Trading.
   - Open a chart (e.g., `EURUSD`) and attach `RPEA`.
   - Configure inputs (update `ServerToCEST_OffsetMinutes` on DST flips).
5. Verify that on load the EA creates `MQL5/Files/RPEA/{state,logs,news,...}` and writes heartbeat rows to `MQL5/Files/RPEA/logs/decisions_YYYYMMDD.csv` every 30–60s while attached.

Tip: Use the Strategy Tester (Every tick based on real ticks) to validate initialization, logging, and timer behavior before enabling trading logic.

## 🔧 Implementation Priorities

### Critical Project Specification Requirements

#### 1. DST-Aware Session Handling ⚠️
- Implement automatic daylight saving time detection in `timeutils.mqh`
- Flexible session definitions to prevent timing misalignment
- Server-to-CEST mapping with configurable offset

#### 2. Correlation Risk Management ⚠️
- Real-time correlation monitoring for XAUEUR synthetic pairs
- Enforce maximum correlation exposure limits in portfolio management
- Cross-reference synthetic pair dependencies

#### 3. Adaptive Execution Modeling ⚠️
- Dynamic spread and slippage modeling in `liquidity.mqh`
- Volatility regime-based execution adjustments
- Time-of-day execution quality metrics

#### 4. Parameter Stability Testing ⚠️
- Automated parameter sensitivity analysis during optimization
- Stability testing to prevent overfitting
- Rolling calibration validation

#### 5. Forex-Specific RL Adaptations ⚠️
- Session-based EMRT measurement (Asian/London/NY patterns)
- Currency strength analysis integration
- Regime-aware strategy switching based on risk sentiment

### Strategy Implementation Order

#### Phase 1: Foundation (M1-M2)
1. **Core Infrastructure** (`config.mqh`, `state.mqh`, `persistence.mqh`)
2. **Time Management** (`timeutils.mqh`, `sessions.mqh`) - DST-aware
3. **Basic Indicators** (`indicators.mqh`)
4. **Risk Framework** (`risk.mqh`, `equity_guardian.mqh`)

#### Phase 2: Signal Engines (M2-M3)
1. **BWISC Implementation** (`signals_bwisc.mqh`)
   - BTR, SDR, ORE calculations
   - Bias score computation
   - BC/MSC setup logic
2. **MR Engine Foundation** (`signals_mr.mqh`, `emrt.mqh`)
   - EMRT formation methodology
   - Basic Q-learning framework

#### Phase 3: Advanced Features (M3-M5)
1. **Regime Detection** (`regime.mqh`) - Adaptive strategy preference
2. **Liquidity Intelligence** (`liquidity.mqh`) - Execution modeling
3. **News Compliance** (`news.mqh`) - Account-specific policies
4. **Order Engine** (`order_engine.mqh`) - OCO and atomic operations

#### Phase 4: Ensemble & Learning (M5-M7)
1. **Meta-Policy Controller** (`meta_policy.mqh`, `bandit.mqh`)
2. **RL Agent** (`rl_agent.mqh`) - Q-learning with forex adaptations
3. **Adaptive Allocator** (`adaptive.mqh`) - Regime-aware sizing
4. **Learning Systems** (`learning.mqh`) - Online calibration

## 🎛️ Key Configuration Parameters

### Risk & Governance
```cpp
input double DailyLossCapPct = 4.0;        // FundingPips default
input double OverallLossCapPct = 6.0;      
input int MinTradeDaysRequired = 3;
input double OneAndDoneR = 1.5;
input double NYGatePctOfDailyCap = 0.50;
```

### Strategy Parameters
```cpp
input double RiskPct = 1.5;                // BWISC risk per trade
input double MR_RiskPct_Default = 0.90;    // MR risk (lower than BWISC)
input double RtargetBC = 2.2;              // Burst Capture target
input double RtargetMSC = 2.0;             // Mean-Shift Capture target
```

### Ensemble Control
```cpp
input double BWISC_ConfCut = 0.70;         // Confidence threshold
input double MR_ConfCut = 0.80;
input int EMRT_FastThresholdPct = 40;      // Fast reversion threshold
```

### News Compliance
```cpp
input int NewsBufferS = 300;               // Master: ±300s, Eval: internal buffer
input int MinHoldSeconds = 120;
input int QueuedActionTTLMin = 5;          // Queue expiry time
```

## 🧠 Machine Learning Components

### EMRT Formation (`emrt.mqh`)
- **Purpose**: Empirical Mean Reversion Time calculation
- **Methodology**: Model-free metric for spread reversion duration
- **Update Frequency**: Weekly refresh with 60-90 day lookback
- **Data**: `/emrt/emrt_cache.json`, `/emrt/beta_grid.json`

### Q-Learning Agent (`rl_agent.mqh`)
- **State Space**: 256 states (4 periods × 4^4 discretization)
- **Action Space**: Enter/hold/exit bands
- **Reward Function**: `r_{t+1} = A_t·(θ − Y_t) − c·|A_t|` with barrier penalties
- **Training**: Pre-train with simulated OU processes
- **Data**: `/qtable/mr_qtable.bin`

### Contextual Bandit (`bandit.mqh`)
- **Purpose**: Strategy selection (BWISC/MR/Skip)
- **Context Vector**: Regime features, ORE/SDR, EMRT rank, efficiency
- **Algorithm**: Thompson/LinUCB with exploration disabled in live
- **Data**: `/bandit/posterior.json`

## 📊 Compliance & Risk Management

### Account-Specific News Policy
```cpp
// Master (Funded) Accounts
- Block entries/holding: T±300s around high-impact events
- Profit exclusion: Trades opened/closed in 10-minute window (unless ≥5h prior)
- Protective exits: Always allowed

// Evaluation (Student) Accounts  
- No provider restrictions
- Internal buffer for safety (NewsBufferS)
```

### Floor Breach Behavior
```cpp
DailyFloor = baseline_today - DailyLossCapPct%
OverallFloor = initial_baseline - OverallLossCapPct%

// On breach: Close all positions, disable trading, allow protective exits
```

### Position Limits
```cpp
MaxOpenPositionsTotal = 2    // Global limit
MaxOpenPerSymbol = 1         // Per-symbol limit  
MaxPendingsPerSymbol = 2     // Pending order limit
```

### News CSV Fallback (Schema)

- Location: `MQL5/Files/RPEA/news/calendar_high_impact.csv`
- Header: `timestamp,impact,countries,symbols`
- Field semantics:
  - `timestamp`: Unix epoch seconds (UTC)
  - `impact`: HIGH | MEDIUM | LOW (Master enforces HIGH with ±300s; Evaluation uses internal buffer)
  - `countries`: semicolon-delimited ISO country codes (e.g., `US;EU`)
  - `symbols`: semicolon-delimited MT5 symbols or currency codes affecting either leg (e.g., `USD;XAUUSD;EURUSD`)

```csv
1717075200,HIGH,US;EU,USD;XAUUSD;EURUSD
```

Protective exits are always allowed inside the window. Non-protective modifications are queued and applied after `T + NewsBufferS` if still valid.

## 🔄 Synthetic Pair Implementation (XAUEUR)

### Proxy Mode (Default)
```cpp
UseXAUEURProxy = true
// Execute only XAUUSD, size using synthetic SL mapped via EURUSD rate
P_synth = XAUUSD / EURUSD
sl_xau ≈ sl_synth * E
```

### Replication Mode (Optional)
```cpp
UseXAUEURProxy = false
// Two-leg approach:
// Long XAUEUR ≈ Long XAUUSD + Short EURUSD
// Short XAUEUR ≈ Short XAUUSD + Long EURUSD

V_xau = K / (ContractXAU * E)
V_eur = K * (P/E²) / ContractFX
```

## 📈 Success Metrics & SLOs

### Primary Success Criteria
- **Pass Rate**: Net P/L ≥ +$1,000 with 0 cap violations
- **Timeline**: Complete within 3-5 trading days
- **Trade Days**: Minimum 3 distinct calendar days
- **Operational**: No entries during blocked news windows

### Service Level Objectives (SLOs)
- **MR Hit-Rate**: 58-62% (warn <55%)
- **Median Hold Time**: ≤2.5h (80th percentile ≤4h)
- **Efficiency**: Realized R / WorstCaseRisk ≥ 0.8
- **Friction Tax**: Realized - Theoretical R median ≤ 0.4R

### Auto-Actions on SLO Breach
```cpp
// If ≥2 SLOs breached for 3 consecutive weeks:
// Reduce MR risk by 25% until recovery
```

## 🛠️ Development Guidelines

### Critical Implementation Notes

1. **Locked Constraints**: The 11 decisions in `finalspec.md` are IMMUTABLE
2. **Server-Day Anchoring**: All daily calculations use server midnight baseline
3. **Budget Gate**: `open_risk + pending_risk + next_trade ≤ 0.9 × min(room_today, room_overall)`
4. **News Window Queuing**: Queue modifications during news, apply after T+NewsBufferS
5. **Order Intent Journaling**: Persist all order intentions for restart recovery

### Error Handling Patterns
```cpp
// Retry/backoff for transient errors (3 attempts, 300ms)
// Fail fast on REJECT/NO_MONEY/TRADE_DISABLED
// Rollback first leg if second leg fails in replication
```

### State Persistence Requirements
```cpp
// Must persist across restarts:
- initial_baseline
- gDaysTraded  
- last_counted_server_date
- trading_enabled/micro_mode flags
- order intents and queued actions
```

### Performance Requirements
- **CPU Usage**: <2% on typical VPS
- **Memory**: Stable memory footprint
- **Timer Frequency**: OnTimer every 30-60 seconds
- **File I/O**: Minimize during trading hours

## 🧪 Testing & Validation

### Strategy Tester Configuration
```
Deposit: $10,000
Leverage: 1:50 FX / 1:20 metals  
Model: Every tick based on real ticks
Period: Recent 3-6 months with high-impact news weeks
Symbols: EURUSD, XAUUSD (primary)
```

### Optimization Ranges
```cpp
RiskPct ∈ [0.8, 2.0]
SLmult ∈ [0.7, 1.3] 
RtargetBC ∈ [1.8, 2.6]
ORMinutes ∈ {30, 45, 60, 75}
TrailMult ∈ [0.6, 1.2]
```

### Validation Checklist
- [ ] Zero single-day violations of DailyLossCapPct
- [ ] Minimum 3 distinct calendar trade days
- [ ] Micro-Mode properly triggered after +10%
- [ ] News compliance verified for both account types
- [ ] Restart recovery maintains state consistency
- [ ] Position caps enforced before all order placements

## 📚 Supporting Tools

### Repo-Side Helpers (Recommended)
```
tools/
├── emrt_formation.py           # Weekly EMRT calculation
├── calibration_update.py       # Parameter recalibration  
├── liquidity_stats.py          # Market microstructure analysis
├── audit_report.py             # Log analysis and reporting
├── make_zip.py                  # Deployment packaging
└── rl_training/                 # Q-table pretraining
```

### External Dependencies
- MQL5 Economic Calendar API (primary)
- CSV fallback files in `/news/` folder
- Weekly maintenance scripts for EMRT and calibration

## 🚀 Getting Started

1. **Review Specifications**: Start with `finalspec.md` - all requirements are locked
2. **Set Up Structure**: Create the MQL5 folder hierarchy as specified
3. **Begin with Phase 1**: Implement foundation components first
4. **Follow Memory Guidelines**: Implement DST awareness, correlation monitoring, etc.
5. **Test Incrementally**: Validate each component before proceeding
6. **Maintain Audit Trail**: Comprehensive logging from day one

## 🤖 Zencoder Workflow

1. Create a feature branch: `feat/rpea-m1-skeleton`.
2. Ask the agent to scaffold M1 using `finalspec.md`, `prd.md`, and `rpea_structure.txt`:
   - Create directories/files exactly as specified.
   - Implement `RPEA.mq5` init/deinit/timer wiring (no order placement).
   - Add inputs (`config.mqh`), state/persistence stubs, `news.mqh` CSV parser, and `logging.mqh` heartbeat.
3. Open a PR and run the Strategy Tester to confirm acceptance below.

### M1 (Skeleton) Acceptance
- Compiles cleanly in MetaEditor; no trading actions executed.
- On first run, ensures `MQL5/Files/RPEA/*` subfolders exist and initializes state files.
- Writes a heartbeat row to `logs/decisions_YYYYMMDD.csv` on each timer tick.
- `news.mqh` parses CSV and exposes `IsNewsBlocked(symbol)` stub.
- Timer frequency 30–60s; CPU usage negligible; clean deinit with timer killed.

## ⚠️ Critical Warnings

- **DO NOT** modify locked decisions from finalspec.md
- **DO NOT** use hardcoded 5%/10% drawdown limits - use configurable inputs
- **DO NOT** skip news compliance implementation
- **DO NOT** implement without proper state persistence
- **DO NOT** ignore the ensemble architecture - both strategies are required

## 📞 Success Criteria Validation

Before declaring implementation complete, verify:
- [ ] All 11 locked constraints are implemented correctly
- [ ] Both BWISC and MR strategies are functional
- [ ] Meta-policy correctly routes between strategies
- [ ] Account-specific news policies are enforced
- [ ] State persists correctly across restarts
- [ ] All SLO monitoring is in place
- [ ] Strategy Tester passes validation scenarios

---

**This README serves as the authoritative implementation guide. Refer to `finalspec.md` for detailed technical specifications and `prd.md` for product context. The AI coding agent should implement all components according to these specifications while maintaining the project's adaptive and learning-oriented architecture.**