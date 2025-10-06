# Implementation Plan

## Task Overview

Convert the RPEA M3 design into a series of atomic implementation steps for the Order Engine and Synthetic Signal Generation. Each task builds incrementally with comprehensive testing and validation at each stage.

**M3 Scope (Challenge-Focused):**
- Core order execution engine (Tasks 1-10)
- XAUEUR synthetic signal generation (Task 11) - for signal diversity, not execution
- Queue management and trailing stops (Tasks 12-13)
- Audit logging and integration (Tasks 14-15)
- State recovery and error handling (Tasks 16-17)
- Testing and optimization (Tasks 18-20)
- Performance enhancements (Tasks 21-24)

**Total: 24 tasks** (down from 28 - removed atomic operations and replication mode)

**Key Simplification:** XAUEUR is used as a signal source only. When BWISC generates a signal from XAUEUR synthetic data, execution maps to XAUUSD (proxy mode) with simple SL/TP distance scaling. No two-leg replication, no atomic operations complexity.

- [ ] 1. Create Order Engine Scaffolding and Event Model
  - **Goal**: Establish basic Order Engine structure with proper event model (OnInit/OnTick/OnTradeTransaction/OnTimer/OnDeinit)
  - **Files**: `Include/RPEA/order_engine.mqh`, `Include/RPEA/config.mqh`, `Experts/FundingPips/RPEA.mq5`
  - **Expected diff**: ~300 lines (class structure, event handlers, basic interfaces)
  - **Tests**: Unit tests for event handler registration (including OnTradeTransaction dispatch) and basic state management
  - **Acceptance**: Order Engine initializes without errors, OnTradeTransaction dispatchers fire before timer housekeeping, event handlers run in correct sequence, OnDeinit flushes journals and logs
  - _Requirements: 8.4, 8.6_

- [ ] 2. Implement Idempotency System with Intent Journal
  - **Goal**: Create intent_id/action_id system for deduplication and state persistence for both orders and queued actions
  - **Files**: `Include/RPEA/persistence.mqh`, `Files/RPEA/state/intents.json`
  - **Expected diff**: ~200 lines (intent generation, JSON serialization, dedup logic)
  - **Tests**: Unit tests for intent generation, deduplication, and persistence
  - **Acceptance**: Duplicate intents are rejected, state persists across restarts, duplicate queued actions are ignored across restarts using action_id, intents/queued actions persist expiry and validation_threshold metadata
  - _Requirements: 8.6, 11.1_

- [ ] 3. Create Volume and Price Normalization System
  - **Goal**: Implement SYMBOL_VOLUME_STEP and SYMBOL_POINT rounding with validation
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~150 lines (normalization functions, validation logic)
  - **Tests**: Unit tests for volume rounding, price normalization, range validation
  - **Acceptance**: All volumes rounded to valid steps, prices normalized to symbol points
  - _Requirements: 9.4_

- [ ] 4. Implement Basic Order Placement with Position Limits
  - **Goal**: Core order placement with MaxOpenPositionsTotal, MaxOpenPerSymbol, MaxPendingsPerSymbol enforcement
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~250 lines (order placement logic, limit checks, basic error handling)
  - **Tests**: Unit tests for limit enforcement, integration tests for order placement
  - **Acceptance**: Orders respect position limits, proper error messages for limit violations
  - _Requirements: 9.1_

- [ ] 5. Create Retry Policy System with MT5 Error Code Mapping
  - **Goal**: Implement comprehensive retry logic with configurable error code policies
  - **Files**: `Include/RPEA/order_engine.mqh`, `Include/RPEA/config.mqh`
  - **Expected diff**: ~200 lines (retry manager, error code mapping, backoff algorithms)
  - **Tests**: Unit tests for each retry policy, error code classification
  - **Acceptance**: Different error codes trigger correct retry behavior, backoff timing is accurate; default policy attempts ≤3 retries with 300ms backoff; fail-fast on TRADE_DISABLED and NO_MONEY
  - _Requirements: 8.1, 8.2_

- [ ] 6. Implement Market Order Fallback with Slippage Protection
  - **Goal**: Market order execution with MaxSlippagePoints enforcement and retry integration
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~180 lines (market order logic, slippage validation, fallback mechanisms)
  - **Tests**: Unit tests for slippage calculation, integration tests with retry system
  - **Acceptance**: Market orders reject excessive slippage per MaxSlippagePoints; retries integrate with Task 5 defaults (≤3 attempts, 300ms backoff); fail-fast on TRADE_DISABLED and NO_MONEY
  - _Requirements: 2.2, 2.3, 2.4, 2.5_

**HOLD POINT 1**: Review scaffolding, idempotency, normalization, basic order placement, retry policy, and market fallback before OCO management.

- [ ] 7. Implement OCO Relationship Management
  - **Goal**: OCO order establishment, expiry alignment, sibling cancellation, and risk-reduction safety tracking
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~250 lines (OCO tracking, expiry metadata, cancellation logic, risk-safety management)
  - **Tests**: Unit tests for OCO establishment and expiry metadata, integration tests for fill scenarios including risk-reduction cancellations
  - **Acceptance**: OCO pendings include broker expiry aligned to session cutoff, fills trigger immediate sibling cancel or risk-reduction resize, relationships and expiry metadata tracked in state and logs
  - _Requirements: 1.1, 1.2, 1.5_

- [ ] 8. Create Partial Fill Handler with OCO Volume Adjustment
  - **Goal**: Handle partial fills with exact math for OCO sibling volume recalculation
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~200 lines (partial fill detection, volume adjustment, aggregation)
  - **Tests**: Unit tests for volume adjustment math, integration tests for partial fill scenarios triggered via OnTradeTransaction
  - **Acceptance**: Partial fills processed via OnTradeTransaction adjust OCO sibling volumes before the next timer cycle, fill aggregation works
  - _Requirements: 6.1, 6.2, 6.5_

**HOLD POINT 2**: Review OCO management and partial fill handling before budget integration.

- [ ] 9. Implement Budget Gate with Position Snapshot Locking
  - **Goal**: Budget gate validation with locked position snapshots and exact formula implementation with configurable parameters
  - **Files**: `Include/RPEA/risk.mqh`, `Include/RPEA/order_engine.mqh`, `Include/RPEA/config.mqh`
  - **Expected diff**: ~220 lines (snapshot logic, locking mechanism, budget gate formula, config parameters)
  - **Tests**: Unit tests for budget gate formula, stress tests for concurrent access
  - **Acceptance**: Budget gate uses locked snapshots, compute open_risk + pending_risk + next_trade ≤ 0.9 × min(room_today, room_overall) using a locked snapshot and log the five inputs, and log pass/fail (gate_pass boolean); config keys BudgetGateLockMs and RiskGateHeadroom=0.90 implemented
  - _Requirements: 9.6_

- [ ] 10. Create News CSV Fallback System
  - **Goal**: CSV parser with schema validation and staleness checking for news events using specified schema and path
  - **Files**: `Include/RPEA/news.mqh`, `Include/RPEA/config.mqh`, `Files/RPEA/news/calendar_high_impact.csv`
  - **Expected diff**: ~180 lines (CSV parser, schema validation, staleness checks)
  - **Tests**: Unit tests for CSV parsing, integration tests with news filtering
  - **Acceptance**: CSV fallback works when API fails, staleness detection prevents old data usage, reject file if missing required columns [timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min] or if mtime exceeds config `NewsCSVMaxAgeHours`; CSV path read from `NewsCSVPath`
  - _Requirements: 10.6_

- [ ] 11. Create Synthetic Price Manager for Signal Generation
  - **Goal**: XAUEUR synthetic price calculation and bar building for BWISC signal generation (not for execution)
  - **Files**: `Include/RPEA/synthetic.mqh`, `Include/RPEA/indicators.mqh`
  - **Expected diff**: ~200 lines (price calculation, synthetic bar building, caching)
  - **Tests**: Unit tests for price calculation, synthetic bar construction, indicator compatibility
  - **Acceptance**: XAUEUR synthetic prices calculated correctly (XAUUSD/EURUSD), synthetic OHLC bars available for ATR/MA/RSI calculations, BWISC can generate signals from XAUEUR data
  - **Note**: XAUEUR is used as a signal source only; execution maps to XAUUSD (proxy mode)
  - _Requirements: 4.3, 4.4_

- [ ] 12. Create Queue Manager with Bounds and TTL Management
  - **Goal**: News window action queuing for trailing and SL/TP updates with configurable MAX_QUEUE_SIZE, precondition revalidation, and explicit back-pressure policy
  - **Files**: `Include/RPEA/order_engine.mqh`, `Include/RPEA/config.mqh`
  - **Expected diff**: ~200 lines (queue management, precondition validation, TTL tracking, back-pressure logic, config parameters)
  - **Tests**: Unit tests for queue bounds/precondition logic, stress tests for overflow scenarios
  - **Acceptance**: Queue respects size limits, TTL expiration works correctly, precondition checks validate queued actions before execution, back-pressure prevents overflow with configurable policy (drop oldest vs reject new) and MAX_QUEUE_SIZE in config
  - _Requirements: 3.2, 3.4_

- [ ] 13. Implement Trailing Stop Management with Queue Integration
  - **Goal**: Trailing stops with news window queuing, SL/TP optimization hooks, and post-news execution
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~180 lines (trailing logic, queue integration, activation conditions)
  - **Tests**: Unit tests for trailing calculations, integration tests with news queuing and post-news revalidation
  - **Acceptance**: Trailing activates at +1R, queues trailing/SLTP adjustments during news windows, enforces TTL and precondition validation before executing post-news
  - _Requirements: 3.1, 3.3_

**HOLD POINT 3**: Review budget gate, news CSV fallback, synthetic signal generation, queue manager, and trailing stop management before integration.

- [ ] 14. Create Comprehensive Audit Logging System
  - **Goal**: Complete CSV audit logging with all required fields including detailed order and risk information
  - **Files**: `Include/RPEA/logging.mqh`, `Files/RPEA/logs/audit_YYYYMMDD.csv`
  - **Expected diff**: ~150 lines (audit logger, CSV formatting, field mapping)
  - **Tests**: Unit tests for log formatting (including new context columns), integration tests for all audit scenarios
  - **Acceptance**: All order activities logged with complete field set, CSV format matches specification, every placement/adjust/cancel (including risk-reduction actions) writes one row with columns [timestamp,intent_id,action_id,symbol,mode(proxy|repl),requested_price,executed_price,requested_vol,filled_vol,remaining_vol,tickets[],retry_count,gate_open_risk,gate_pending_risk,gate_next_risk,room_today,room_overall,gate_pass,decision,confidence,efficiency,rho_est,est_value,hold_time,gating_reason,news_window_state]
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

- [ ] 15. Integrate Order Engine with Existing Risk Management and XAUEUR Signal Mapping
  - **Goal**: Full integration with existing risk engine, equity guardian, news filter, and XAUEUR synthetic signal mapping
  - **Files**: `Include/RPEA/order_engine.mqh`, `Include/RPEA/allocator.mqh`, `Experts/FundingPips/RPEA.mq5`
  - **Expected diff**: ~150 lines (integration points, interface adaptation, XAUEUR signal mapping)
  - **Tests**: Integration tests for risk engine interaction, XAUEUR signal-to-execution mapping, end-to-end workflow tests
  - **Acceptance**: Order engine respects all existing risk constraints, integrates seamlessly; XAUEUR signals map to XAUUSD execution with proper SL/TP distance scaling (multiply by EURUSD rate); on funded (Master) accounts, SL is set within 30 seconds of opening and enforcement is logged if late
  - **XAUEUR Mapping Logic**: When signal_symbol == "XAUEUR", execute on "XAUUSD" with SL/TP distances scaled by current EURUSD rate
  - _Requirements: 9.2, 9.3, 9.5, 4.1, 4.2_

- [ ] 16. Implement State Recovery and Reconciliation on Startup
  - **Goal**: Complete state restoration from intent journal with broker reconciliation
  - **Files**: `Include/RPEA/persistence.mqh`, `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~200 lines (recovery logic, reconciliation, consistency checks)
  - **Tests**: Unit tests for state recovery, integration tests for restart scenarios
  - **Acceptance**: System recovers all state on restart, reconciles with broker correctly
  - _Requirements: 8.4, 8.5_

- [ ] 17. Add Comprehensive Error Handling and Resilience Features
  - **Goal**: Complete error handling framework with self-healing capabilities
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~150 lines (error handling, self-healing, consistency checks)
  - **Tests**: Unit tests for error scenarios, stress tests for resilience
  - **Acceptance**: System handles all error conditions gracefully, self-heals when possible
  - _Requirements: 8.1, 8.2, 8.3, 8.5_

**HOLD POINT 4**: Review audit logging, integration with risk management and XAUEUR signal mapping, state recovery, and error handling before proceeding to optional tasks.

- [ ] 18. Create Integration Tests for End-to-End Order Flows
  - **Goal**: Comprehensive integration testing with deterministic seeds and fake broker layer for reproducible results
  - **Files**: `Tests/RPEA/integration_tests.mqh`, `Tests/RPEA/fake_broker.mqh`, `Include/RPEA/config.mqh`
  - **Expected diff**: ~300 lines (test scenarios, validation logic, mock data, fake broker implementation)
  - **Tests**: Full end-to-end integration test suite with deterministic behavior
  - **Acceptance**: All order execution paths tested, edge cases covered, end-to-end suite passes with seed stability using config `TestSeed`; failures reproducible via fake broker
  - _Requirements: All requirements validated through integration testing_

- [ ] 19. Implement Performance Optimization and Memory Management
  - **Goal**: Optimize performance for high-frequency operations and manage memory efficiently
  - **Files**: `Include/RPEA/order_engine.mqh`, `Include/RPEA/synthetic.mqh`
  - **Expected diff**: ~100 lines (optimization, memory management, caching)
  - **Tests**: Performance tests, memory leak detection
  - **Acceptance**: CPU usage remains low, memory usage is stable, no performance degradation
  - _Requirements: Performance and stability requirements_

- [ ] 20. Create Documentation and Configuration Validation
  - **Goal**: Complete documentation and parameter validation for all configuration options
  - **Files**: `Include/RPEA/config.mqh`, `README.md`
  - **Expected diff**: ~100 lines (validation logic, documentation)
  - **Tests**: Unit tests for parameter validation
  - **Acceptance**: All parameters validated on startup, comprehensive documentation available
  - _Requirements: Configuration and usability requirements_

---

---

## M3 Performance Enhancements (Challenge-Critical)

These 4 additions significantly boost execution quality with minimal complexity. Implement after core M3 tasks (1-20).

- [ ] 21. Implement Dynamic Position Sizing Based on Confidence
  - **Goal**: Scale risk by BWISC confidence to increase size on high-confidence setups
  - **Files**: `Include/RPEA/risk.mqh`, `Include/RPEA/allocator.mqh`
  - **Expected diff**: ~10 lines (confidence-based risk scaling)
  - **Formula**: `effective_risk = RiskPct * confidence` (e.g., 0.7 conf → 1.05% risk, 0.9 conf → 1.35% risk)
  - **Tests**: Unit tests for risk scaling at different confidence levels
  - **Acceptance**: High-confidence setups (|Bias| ≥ 0.8) get larger position sizes, low-confidence setups get smaller sizes
  - **Impact**: +10-15% on risk-adjusted returns
  - _Requirements: 9.1, 9.4_

- [ ] 22. Add Spread Filter to Liquidity Check
  - **Goal**: Reject trades when spread exceeds threshold relative to ATR to avoid bad fills
  - **Files**: `Include/RPEA/liquidity.mqh`
  - **Expected diff**: ~15 lines (spread calculation and validation)
  - **Logic**: Reject if `current_spread > ATR * 0.005` (0.5% of ATR, configurable)
  - **Tests**: Unit tests for spread validation at different ATR levels
  - **Acceptance**: Wide spreads (e.g., XAUUSD > 50 points during news) block entry, normal spreads allow entry
  - **Impact**: +5-10% on net returns (avoiding bad fills)
  - _Requirements: 9.4_

- [ ] 23. Implement Breakeven Stop at +0.5R
  - **Goal**: Move SL to breakeven at +0.5R profit to protect winners early, then activate trailing at +1R
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~20 lines (breakeven logic, position modification)
  - **Logic**: At +0.5R → move SL to entry + spread buffer; at +1R → activate trailing
  - **Tests**: Unit tests for breakeven trigger, integration tests for SL modification
  - **Acceptance**: Positions move to breakeven at +0.5R, trailing activates at +1R, converts potential losers to breakevens
  - **Impact**: +10-15% on win rate (more breakevens, fewer full losses)
  - _Requirements: 3.1, 3.3_

- [ ] 24. Optimize Pending Order Expiry Timing
  - **Goal**: Expire pending orders after 45 minutes if not filled to avoid stale order fills
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~5 lines (expiry time calculation)
  - **Logic**: Set pending expiry to `TimeCurrent() + (45 * 60)` instead of session cutoff
  - **Tests**: Unit tests for expiry time calculation
  - **Acceptance**: Pending orders expire 45 minutes after placement if not filled, preventing stale fills
  - **Impact**: +5-10% on avoiding bad fills
  - _Requirements: 1.5, 1.6_

**HOLD POINT 5**: Review dynamic position sizing, spread filter, breakeven stop, and pending expiry optimization before final testing and deployment.

**M3 Performance Enhancement Summary:**
- Total additional code: ~50 lines
- Total impact: +30-50% improvement in execution quality
- Implementation time: 4-6 hours
- Priority: Implement after core M3 tasks (1-20) are complete

**Note:** Additional performance enhancements for signal logic (time-of-day filter, volatility-adjusted targets, RSI confirmation) belong in M2 signal engine updates. Session momentum filter belongs in M4 governance tasks.

---

## Deferred to Post-Challenge

The following tasks have been removed from M3 scope and deferred until after challenge completion:

**Removed Tasks:**
- **Atomic Operation Manager** (original Task 7): Two-leg atomic operations with counter-order rollback - only needed for replication mode, not for challenge
- **Replication Margin Calculator** (original Task 13): Margin calculations for two-leg replication - not needed for proxy-only execution
- **XAUEUR Proxy Mode Implementation** (original Task 14): Formal proxy mode with complex distance mapping - replaced with simple signal mapping in Task 15
- **XAUEUR Replication Mode** (original Task 15): Two-leg replication with delta-based sizing - too complex for challenge, deferred to post-funding

**Rationale:** XAUEUR is used as a signal source only (Task 11), with simple execution mapping to XAUUSD (Task 15). Full replication mode and atomic operations add significant complexity (~1,080 lines) for uncertain benefit during the challenge phase.


