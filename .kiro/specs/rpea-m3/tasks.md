# Implementation Plan

## Task Overview

Convert the RPEA M3 design into a series of atomic implementation steps for the Order Engine and Synthetic Cross Support components. Each task builds incrementally with comprehensive testing and validation at each stage.

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

**HOLD POINT 1**: Review scaffolding, idempotency, normalization, and basic order placement before proceeding.

- [ ] 5. Create Retry Policy System with MT5 Error Code Mapping
  - **Goal**: Implement comprehensive retry logic with configurable error code policies
  - **Files**: `Include/RPEA/order_engine.mqh`, `Include/RPEA/config.mqh`
  - **Expected diff**: ~200 lines (retry manager, error code mapping, backoff algorithms)
  - **Tests**: Unit tests for each retry policy, error code classification
  - **Acceptance**: Different error codes trigger correct retry behavior, backoff timing is accurate
  - _Requirements: 8.1, 8.2_

- [ ] 6. Implement Market Order Fallback with Slippage Protection
  - **Goal**: Market order execution with MaxSlippagePoints enforcement and retry integration
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~180 lines (market order logic, slippage validation, fallback mechanisms)
  - **Tests**: Unit tests for slippage calculation, integration tests with retry system
  - **Acceptance**: Market orders reject excessive slippage, retry logic works correctly
  - _Requirements: 2.2, 2.3, 2.4, 2.5_

**HOLD POINT 2**: Review retry policy implementation and market order fallback before atomic operations.

- [ ] 7. Create Atomic Operation Manager with Counter-Order Rollback
  - **Goal**: Implement atomic two-leg operations with explicit counter-order rollback mechanism and global execution lock
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~300 lines (atomic manager, rollback logic, counter-order execution, reentrancy lock)
  - **Tests**: Unit tests for rollback scenarios, integration tests for two-leg failures
  - **Acceptance**: Failed second leg triggers immediate first leg rollback via counter-order, forced concurrent triggers do not produce duplicate legs in 1,000 test iterations
  - _Requirements: 7.2, 7.6, 5.6_

- [ ] 8. Implement OCO Relationship Management
  - **Goal**: OCO order establishment, expiry alignment, sibling cancellation, and risk-reduction safety tracking
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~250 lines (OCO tracking, expiry metadata, cancellation logic, risk-safety management)
  - **Tests**: Unit tests for OCO establishment and expiry metadata, integration tests for fill scenarios including risk-reduction cancellations
  - **Acceptance**: OCO pendings include broker expiry aligned to session cutoff, fills trigger immediate sibling cancel or risk-reduction resize, relationships and expiry metadata tracked in state and logs
  - _Requirements: 1.1, 1.2, 1.5_

- [ ] 9. Create Partial Fill Handler with OCO Volume Adjustment
  - **Goal**: Handle partial fills with exact math for OCO sibling volume recalculation
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~200 lines (partial fill detection, volume adjustment, aggregation)
  - **Tests**: Unit tests for volume adjustment math, integration tests for partial fill scenarios triggered via OnTradeTransaction
  - **Acceptance**: Partial fills processed via OnTradeTransaction adjust OCO sibling volumes before the next timer cycle, fill aggregation works
  - _Requirements: 6.1, 6.2, 6.5_

**HOLD POINT 3**: Review atomic operations, OCO management, and partial fill handling before budget integration.

- [ ] 10. Implement Budget Gate with Position Snapshot Locking
  - **Goal**: Budget gate validation with locked position snapshots and exact formula implementation with configurable parameters
  - **Files**: `Include/RPEA/risk.mqh`, `Include/RPEA/order_engine.mqh`, `Include/RPEA/config.mqh`
  - **Expected diff**: ~220 lines (snapshot logic, locking mechanism, budget gate formula, config parameters)
  - **Tests**: Unit tests for budget gate formula, stress tests for concurrent access
  - **Acceptance**: Budget gate uses locked snapshots, compute open_risk + pending_risk + next_trade ≤ 0.9 × min(room_today, room_overall) using a locked snapshot and log the five inputs, config keys BudgetGateLockMs and RiskGateHeadroom=0.90 implemented
  - _Requirements: 9.6_

- [ ] 11. Create News CSV Fallback System
  - **Goal**: CSV parser with schema validation and staleness checking for news events using specified schema and path
  - **Files**: `Include/RPEA/news.mqh`, `Include/RPEA/config.mqh`, `Files/RPEA/news/calendar_high_impact.csv`
  - **Expected diff**: ~180 lines (CSV parser, schema validation, staleness checks)
  - **Tests**: Unit tests for CSV parsing, integration tests with news filtering
  - **Acceptance**: CSV fallback works when API fails, staleness detection prevents old data usage, reject file if missing required columns [timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min] or if mtime exceeds config `NewsCSVMaxAgeHours`; CSV path read from `NewsCSVPath`
  - _Requirements: 10.6_

**HOLD POINT 4**: Review budget gate integration and news CSV fallback before synthetic implementation.

- [ ] 12. Create Synthetic Price Manager with Quote Staleness Detection
  - **Goal**: XAUEUR synthetic price calculation with quote age validation using configurable freshness threshold
  - **Files**: `Include/RPEA/synthetic.mqh`, `Include/RPEA/config.mqh`
  - **Expected diff**: ~200 lines (price calculation, staleness detection, cache management, config parameter)
  - **Tests**: Unit tests for price calculation, integration tests for staleness scenarios
  - **Acceptance**: Synthetic prices calculated correctly, stale quotes trigger appropriate fallbacks, if either XAUUSD or EURUSD quote age > QuoteMaxAgeMs then mark synthetic as STALE
  - _Requirements: 4.3, 4.4_

- [ ] 13. Implement Replication Margin Calculator with 20% Buffer
  - **Goal**: Exact replication margin formula for both legs with 20% buffer and hedged-netting considerations
  - **Files**: `Include/RPEA/synthetic.mqh`
  - **Expected diff**: ~150 lines (margin calculation, buffer application, downgrade logic)
  - **Tests**: Unit tests for margin formula, integration tests for downgrade scenarios
  - **Acceptance**: Margin calculations include 20% buffer, downgrade triggers at correct thresholds, if free_margin < required×1.2 then abort replication and rollback first leg
  - _Requirements: 5.5, 5.6_

- [ ] 14. Create XAUEUR Proxy Mode Implementation
  - **Goal**: Proxy mode execution using XAUUSD with synthetic SL distance mapping
  - **Files**: `Include/RPEA/synthetic.mqh`
  - **Expected diff**: ~180 lines (proxy logic, distance mapping, execution flow)
  - **Tests**: Unit tests for distance mapping, integration tests for proxy execution
  - **Acceptance**: Proxy mode correctly maps synthetic distances to XAUUSD, executes single-leg orders
  - _Requirements: 4.1, 4.2_

- [ ] 15. Implement XAUEUR Replication Mode with Two-Leg Coordination
  - **Goal**: Two-leg replication with delta-based sizing, atomic execution, and automatic downgrade logic
  - **Files**: `Include/RPEA/synthetic.mqh`
  - **Expected diff**: ~250 lines (replication logic, volume calculation, coordination, downgrade logic)
  - **Tests**: Unit tests for volume calculations, integration tests for two-leg scenarios
  - **Acceptance**: Replication mode executes both legs atomically, volumes calculated per specification, on STALE quotes or margin shortfall auto-downgrade to Proxy otherwise fail-fast
  - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [ ] 16. Create Queue Manager with Bounds and TTL Management
  - **Goal**: News window action queuing for trailing and SL/TP updates with configurable MAX_QUEUE_SIZE, precondition revalidation, and explicit back-pressure policy
  - **Files**: `Include/RPEA/order_engine.mqh`, `Include/RPEA/config.mqh`
  - **Expected diff**: ~200 lines (queue management, precondition validation, TTL tracking, back-pressure logic, config parameters)
  - **Tests**: Unit tests for queue bounds/precondition logic, stress tests for overflow scenarios
  - **Acceptance**: Queue respects size limits, TTL expiration works correctly, precondition checks validate queued actions before execution, back-pressure prevents overflow with configurable policy (drop oldest vs reject new) and MAX_QUEUE_SIZE in config
  - _Requirements: 3.2, 3.4_

- [ ] 17. Implement Trailing Stop Management with Queue Integration
  - **Goal**: Trailing stops with news window queuing, SL/TP optimization hooks, and post-news execution
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~180 lines (trailing logic, queue integration, activation conditions)
  - **Tests**: Unit tests for trailing calculations, integration tests with news queuing and post-news revalidation
  - **Acceptance**: Trailing activates at +1R, queues trailing/SLTP adjustments during news windows, enforces TTL and precondition validation before executing post-news
  - _Requirements: 3.1, 3.3_

- [ ] 18. Create Comprehensive Audit Logging System
  - **Goal**: Complete CSV audit logging with all required fields including detailed order and risk information
  - **Files**: `Include/RPEA/logging.mqh`, `Files/RPEA/logs/audit_YYYYMMDD.csv`
  - **Expected diff**: ~150 lines (audit logger, CSV formatting, field mapping)
  - **Tests**: Unit tests for log formatting (including new context columns), integration tests for all audit scenarios
  - **Acceptance**: All order activities logged with complete field set, CSV format matches specification, every placement/adjust/cancel (including risk-reduction actions) writes one row with columns [timestamp,intent_id,action_id,symbol,mode(proxy|repl),requested_price,executed_price,requested_vol,filled_vol,remaining_vol,tickets[],retry_count,gate_open_risk,gate_pending_risk,gate_next_risk,room_today,room_overall,decision,confidence,efficiency,est_value,hold_time,gating_reason,news_window_state]
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

- [ ] 19. Integrate Order Engine with Existing Risk Management
  - **Goal**: Full integration with existing risk engine, equity guardian, and news filter
  - **Files**: `Include/RPEA/order_engine.mqh`, `Experts/FundingPips/RPEA.mq5`
  - **Expected diff**: ~100 lines (integration points, interface adaptation)
  - **Tests**: Integration tests for risk engine interaction, end-to-end workflow tests
  - **Acceptance**: Order engine respects all existing risk constraints, integrates seamlessly
  - _Requirements: 9.2, 9.3, 9.5_

- [ ] 20. Implement State Recovery and Reconciliation on Startup
  - **Goal**: Complete state restoration from intent journal with broker reconciliation
  - **Files**: `Include/RPEA/persistence.mqh`, `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~200 lines (recovery logic, reconciliation, consistency checks)
  - **Tests**: Unit tests for state recovery, integration tests for restart scenarios
  - **Acceptance**: System recovers all state on restart, reconciles with broker correctly
  - _Requirements: 8.4, 8.5_

- [ ] 21. Add Comprehensive Error Handling and Resilience Features
  - **Goal**: Complete error handling framework with self-healing capabilities
  - **Files**: `Include/RPEA/order_engine.mqh`
  - **Expected diff**: ~150 lines (error handling, self-healing, consistency checks)
  - **Tests**: Unit tests for error scenarios, stress tests for resilience
  - **Acceptance**: System handles all error conditions gracefully, self-heals when possible
  - _Requirements: 8.1, 8.2, 8.3, 8.5_

- [ ] 22. Create Integration Tests for End-to-End Order Flows
  - **Goal**: Comprehensive integration testing with deterministic seeds and fake broker layer for reproducible results
  - **Files**: `Tests/RPEA/integration_tests.mqh`, `Tests/RPEA/fake_broker.mqh`, `Include/RPEA/config.mqh`
  - **Expected diff**: ~300 lines (test scenarios, validation logic, mock data, fake broker implementation)
  - **Tests**: Full end-to-end integration test suite with deterministic behavior
  - **Acceptance**: All order execution paths tested, edge cases covered, end-to-end suite passes with seed stability using config `TestSeed`; failures reproducible via fake broker
  - _Requirements: All requirements validated through integration testing_

- [ ] 23. Implement Performance Optimization and Memory Management
  - **Goal**: Optimize performance for high-frequency operations and manage memory efficiently
  - **Files**: `Include/RPEA/order_engine.mqh`, `Include/RPEA/synthetic.mqh`
  - **Expected diff**: ~100 lines (optimization, memory management, caching)
  - **Tests**: Performance tests, memory leak detection
  - **Acceptance**: CPU usage remains low, memory usage is stable, no performance degradation
  - _Requirements: Performance and stability requirements_

- [ ] 24. Create Documentation and Configuration Validation
  - **Goal**: Complete documentation and parameter validation for all configuration options
  - **Files**: `Include/RPEA/config.mqh`, `README.md`
  - **Expected diff**: ~100 lines (validation logic, documentation)
  - **Tests**: Unit tests for parameter validation
  - **Acceptance**: All parameters validated on startup, comprehensive documentation available
  - _Requirements: Configuration and usability requirements_


