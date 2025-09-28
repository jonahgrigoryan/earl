---
description: Repository Information Overview
alwaysApply: true
---

# RPEA (RapidPass Expert Advisor) Information

## Summary
RPEA is a sophisticated MT5 Expert Advisor designed to pass the FundingPips 1-step $10,000 challenge by achieving +10% profit with zero drawdown violations in 3-5 trading days. It implements a hybrid ensemble architecture with BWISC (Burst-Weighted Imbalance with Session Confluence) as the primary strategy and MR (Mean Reversion) as the fallback strategy.

## Structure
- **MQL5/Experts/FundingPips**: Contains the main EA entry point (RPEA.mq5)
- **MQL5/Include/RPEA**: Contains all the modular components of the EA
- **MQL5/Files/RPEA**: Contains runtime data, logs, and configuration files

## Language & Runtime
**Language**: MQL5 (MetaQuotes Language 5)
**Version**: 0.1.0 (as defined in config.mqh)
**Build System**: MetaEditor compiler
**Execution Environment**: MetaTrader 5 Terminal

## Main Components
- **Core Infrastructure**: Configuration, state management, and persistence
- **Time Management**: DST-aware session handling
- **Signal Engines**: BWISC and MR strategy implementations
- **Risk Management**: Position sizing, equity guardian, and adaptive allocation
- **Order Engine**: Trade execution and management
- **Learning Systems**: Q-learning agent and contextual bandit for strategy selection

## Dependencies
The EA relies on the following built-in MQL5 functions and objects:
- **TimeCurrent()**: For time-based operations
- **AccountInfoDouble()**: For account equity and balance information
- **EventSetTimer()**: For scheduling the EA's main loop
- **StringSplit()**: For parsing input parameters
- **HistoryDealGetInteger()**: For trade history analysis

## Build & Installation
```bash
# 1. Open MetaEditor and compile the main file
# 2. Copy the compiled EA to the MT5 terminal's Experts directory
# 3. Attach the EA to a chart in MT5
```

## File Structure
**Main Entry Point**: MQL5/Experts/FundingPips/RPEA.mq5
**Configuration**: MQL5/Include/RPEA/config.mqh
**State Management**: MQL5/Include/RPEA/state.mqh
**Scheduler**: MQL5/Include/RPEA/scheduler.mqh
**Strategy Modules**:
- MQL5/Include/RPEA/signals_bwisc.mqh (Primary strategy)
- MQL5/Include/RPEA/signals_mr.mqh (Fallback strategy)
- MQL5/Include/RPEA/meta_policy.mqh (Strategy selection)

## Persistence
**State Directory**: MQL5/Files/RPEA/state/
**Main State File**: challenge_state.json
**Persisted Data**:
- Initial baseline equity
- Daily baseline values
- Trading day count
- Trading enabled/disabled flags
- Server midnight timestamp

## Logging
**Log Directory**: MQL5/Files/RPEA/logs/
**Log Files**:
- audit_YYYYMMDD.csv: Detailed audit trail
- decisions_YYYYMMDD.csv: Strategy decisions

## Configuration Parameters
**Risk & Governance**:
- DailyLossCapPct: 4.0% (default)
- OverallLossCapPct: 6.0%
- MinTradeDaysRequired: 3
- MaxOpenPositionsTotal: 2
- MaxOpenPerSymbol: 1

**Strategy Parameters**:
- RiskPct: 1.5% (BWISC risk per trade)
- MR_RiskPct_Default: 0.90% (MR risk)
- BWISC_ConfCut: 0.70 (Confidence threshold)
- MR_ConfCut: 0.80 (Confidence threshold)

**News Compliance**:
- NewsBufferS: 300 (±300s buffer around high-impact events)
- MinHoldSeconds: 120
- QueuedActionTTLMin: 5

## Execution Flow
1. **Initialization**: Load persisted state, initialize indicators, ensure folders exist
2. **Timer Event**: 30-second scheduler that drives the EA's main loop
3. **Scheduler Tick**: Check equity rooms, iterate through symbols, check news/sessions
4. **Signal Generation**: Generate BWISC and MR signals
5. **Meta-Policy**: Choose between BWISC and MR strategies
6. **Order Planning**: Create order plan based on chosen strategy
7. **Execution**: Execute orders (stub implementation in current version)
8. **Logging**: Log decisions and audit trail

## Machine Learning Components
**EMRT Formation**: Empirical Mean Reversion Time calculation
**Q-Learning Agent**: 256-state reinforcement learning model
**Contextual Bandit**: Strategy selection mechanism

## Implementation Phases
1. **Foundation (M1-M2)**: Core infrastructure, time management, basic indicators
2. **Signal Engines (M2-M3)**: BWISC and MR implementations
3. **Advanced Features (M3-M5)**: Regime detection, liquidity intelligence, news compliance
4. **Ensemble & Learning (M5-M7)**: Meta-policy controller, RL agent, adaptive allocation