---
description: Repository Information Overview
alwaysApply: true
---

# RPEA (RapidPass Expert Advisor) Information

## Summary
RPEA is a sophisticated MT5 Expert Advisor designed to pass the FundingPips 1-step $10,000 challenge by achieving +10% profit with zero drawdown violations in 3-5 trading days. It implements BWISC (Burst-Weighted Imbalance with Session Confluence) as the primary strategy with comprehensive order execution, OCO pending orders, trailing stops, and synthetic XAUEUR signal generation for enhanced trading opportunities (signal-only with XAUUSD proxy execution).

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
- **Signal Engine**: BWISC strategy implementation (M2 complete)
- **Risk Management**: Position sizing, equity guardian, budget gate, and position limits (M2 complete)
- **Order Engine**: Trade execution, OCO pendings, trailing stops, retry logic (M3 - in progress)
- **Synthetic Signal Generation**: XAUEUR price calculation for signal diversity (M3 - in progress)
- **News Compliance**: News filter with queue management for trailing stops during news windows (M3 - in progress)

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
- MQL5/Include/RPEA/signals_bwisc.mqh (Primary strategy - M2 complete)
- MQL5/Include/RPEA/signals_mr.mqh (Fallback strategy - M7 future)
- MQL5/Include/RPEA/order_engine.mqh (Order execution - M3 in progress)
- MQL5/Include/RPEA/synthetic.mqh (XAUEUR signal generation - M3 in progress)

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
1. **Initialization (OnInit)**: Load persisted state, initialize indicators, ensure folders exist, restore intent journal
2. **Trade Transaction (OnTradeTransaction)**: Process fills/partial fills immediately, adjust OCO siblings, update risk exposure
3. **Timer Event (OnTimer)**: 30-second scheduler that drives the EA's main loop
4. **Scheduler Tick**: Check equity rooms, iterate through symbols, check news/sessions
5. **Signal Generation**: Generate BWISC signals from EURUSD, XAUUSD, and XAUEUR (synthetic)
6. **Risk Validation**: Budget gate checks (open_risk + pending_risk + next_trade ≤ 0.9 × min(room_today, room_overall))
7. **Order Execution**: Place OCO pendings or market orders with retry logic and slippage protection
8. **Trailing Management**: Activate at +1R, queue updates during news windows, execute post-news
9. **Logging**: Comprehensive audit trail with all order activities and risk metrics
10. **Shutdown (OnDeinit)**: Flush logs, persist state to intent journal

## Synthetic Cross Support
**XAUEUR Signal-Only Implementation**: XAUEUR (Gold vs Euro) provides signal diversity without complex execution
- Task 11 builds synthetic prices (XAUUSD / EURUSD) and OHLC bars for BWISC signal generation
- BWISC generates signals from XAUEUR data alongside EURUSD/XAUUSD for enhanced opportunities
- Task 15 maps XAUEUR signals to XAUUSD proxy execution (single-leg orders)
- SL/TP distances scaled by current EURUSD rate using simple mathematical mapping
- No two-leg replication or atomic operations - maintains challenge timeline efficiency

## Deferred Features (Post-Challenge)
**Removed from M3 scope for faster challenge completion:**
- Atomic Operation Manager (original Task 7) - Only needed for two-leg replication
- XAUEUR Replication Mode (original Tasks 13-15) - Two-leg execution with delta-based sizing
- Replication Margin Calculator - 20% buffer calculations for two-leg positions
- NEWS_PAIR_PROTECT - Orphaned leg protection during news windows
- Integration Tests with Fake Broker (Task 18) - Manual testing acceptable for challenge
- Performance Optimization (Task 19) - Optional for 2-symbol trading
- Documentation (Task 20) - Optional for challenge

**Rationale**: XAUEUR signals provide trading opportunity diversity without the complexity of two-leg replication. Simple proxy mode (XAUUSD execution with scaled SL/TP) achieves the goal with ~880 fewer lines of code and 4-5 fewer days of implementation time.

## Implementation Phases
1. **M1 (Complete)**: Core infrastructure, time management, scheduler, logging, indicators, sessions
2. **M2 (Complete)**: BWISC signal engine, risk sizing, budget gate, position caps, equity guardian
3. **M3 (In Progress - 24 tasks)**: Order Engine + Synthetic Signal Generation
   - Phase 1: Foundation (Tasks 1-6) - Order execution, retry logic, market fallback
   - Phase 2: OCO + Partial Fills (Tasks 7-8) - OCO pendings, sibling cancellation
   - Phase 3: Risk + Trailing + Queue (Tasks 9-13) - Budget gate, news CSV, XAUEUR signals, trailing stops
   - Phase 4: Integration + Polish (Tasks 14-17) - Audit logging, XAUEUR mapping, state recovery
   - Phase 5: Performance Enhancements (Tasks 21-24) - Dynamic sizing, spread filter, breakeven stop
4. **M4 (Future)**: Compliance polish, calendar integration, kill-switch enforcement
5. **M5-M7 (Future)**: Strategy Tester artifacts, hardening, MR/EMRT ensemble (optional)