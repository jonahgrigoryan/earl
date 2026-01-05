# Requirements Document

## Introduction

RPEA M3 focuses on implementing the Order Engine and Synthetic Cross Support components for the FundingPips 10K RapidPass EA. This milestone builds upon the signal engine and risk management foundations from M1-M2 to deliver robust order execution capabilities, including OCO (One-Cancels-Other) pending orders, market fallbacks with slippage protection, trailing stop functionality, and synthetic XAUEUR cross-pair support through both proxy and replication modes. The implementation must handle partial fills, provide atomic two-leg operations for synthetic replication, and maintain compliance with news restrictions and risk management rules.

## Requirements

### Requirement 1: OCO Pending Order System

**User Story:** As a trader, I want the EA to place OCO pending orders so that only one direction gets filled while the other is automatically cancelled, reducing manual intervention and ensuring clean position management.

#### Acceptance Criteria

1. WHEN a signal generates both buy and sell setups THEN the system SHALL place OCO pending orders with automatic sibling cancellation
2. WHEN one pending order fills THEN the system SHALL immediately cancel the opposite direction pending order
3. WHEN a pending order partially fills THEN the system SHALL adjust the opposite order volume accordingly and maintain OCO relationship
4. IF OCO placement fails for any reason THEN the system SHALL fall back to market orders with slippage protection
5. WHEN placing pending OCO orders THEN the system SHALL set order expiry no later than the session cutoff or configured TTL so stale orders auto-cancel
6. WHEN session ends or cutoff hour is reached THEN the system SHALL cancel all unfilled pending orders for that session
7. IF an unexpected fill or partial fill would cause combined risk to exceed allowed buffers THEN the system SHALL cancel or resize the sibling pending order immediately and record the risk reduction

### Requirement 2: Market Order Fallback with Slippage Protection

**User Story:** As a trader, I want market orders to execute with slippage protection so that trades are not executed at unfavorable prices that would compromise the risk-reward profile.

#### Acceptance Criteria

1. WHEN pending orders are not suitable or fail THEN the system SHALL execute market orders as fallback
2. WHEN placing market orders THEN the system SHALL enforce MaxSlippagePoints limit to prevent excessive slippage
3. IF market order slippage exceeds MaxSlippagePoints THEN the system SHALL reject the order and log the rejection reason
4. WHEN market order execution fails THEN the system SHALL retry up to 3 times with 300ms backoff intervals
5. IF all retry attempts fail with REJECT/NO_MONEY/TRADE_DISABLED THEN the system SHALL fail fast without further retries

### Requirement 3: Trailing Stop Management

**User Story:** As a trader, I want positions to have trailing stops that activate after reaching +1R profit so that I can protect gains while allowing for continued upside.

#### Acceptance Criteria

1. WHEN a position reaches +1R profit THEN the system SHALL activate trailing stop functionality
2. WHEN trailing is active THEN the system SHALL move stop loss by ATR × TrailMult when price moves favorably
3. WHEN in news buffer window THEN the system SHALL queue trailing updates and any SL/TP optimizations and apply them after the news window expires
4. IF queued trailing actions become stale (older than QueuedActionTTLMin) THEN the system SHALL drop them from the queue
5. WHEN processing queued actions after a news buffer THEN the system SHALL re-validate that the position exists and preconditions still hold before applying any update, otherwise drop the action
6. WHEN position is closed THEN the system SHALL clear any queued trailing actions for that position

### Requirement 4: XAUEUR Synthetic Cross Support - Proxy Mode

**User Story:** As a trader, I want to trade XAUEUR signals through XAUUSD proxy execution so that I can access synthetic cross-pair opportunities without the complexity of two-leg replication.

#### Acceptance Criteria

1. WHEN UseXAUEURProxy is true THEN the system SHALL execute XAUEUR signals using only XAUUSD positions
2. WHEN calculating position size for proxy mode THEN the system SHALL map synthetic SL distance to XAUUSD using current EURUSD rate
3. WHEN building synthetic price data THEN the system SHALL compute P_synth = XAUUSD / EURUSD using consistent bid/ask sides
4. WHEN computing indicators for XAUEUR THEN the system SHALL build synthetic OHLC candles from synchronized M1 bars with forward-fill for gaps
5. WHEN checking news restrictions for XAUEUR THEN the system SHALL block entries if either XAUUSD or EURUSD has high-impact events within NewsBufferS

### Requirement 5: XAUEUR Synthetic Cross Support - Replication Mode

**User Story:** As a trader, I want the option to replicate XAUEUR exposure through two-leg positions so that I can achieve more precise synthetic cross-pair delta when proxy mode is insufficient.

#### Acceptance Criteria

1. WHEN UseXAUEURProxy is false THEN the system SHALL execute XAUEUR signals using two-leg replication (XAUUSD + EURUSD)
2. WHEN calculating replication volumes THEN the system SHALL use delta-based sizing: V_xau = K / (ContractXAU × E), V_eur = K × (P/E²) / ContractFX
3. WHEN placing replication orders THEN the system SHALL ensure atomic execution where second leg failure triggers first leg rollback
4. WHEN validating replication risk THEN the system SHALL simulate worst-case loss at SL for both legs combined and ensure it fits within budget constraints
5. WHEN computing free-margin feasibility THEN the system SHALL include both legs in margin calculation and downgrade to proxy mode or scale proportionally if estimated margin exceeds threshold
6. IF second-leg failure occurs THEN the system SHALL rollback first leg and log the decision to downgrade to proxy or scale proportionally

### Requirement 6: Partial Fill Handling

**User Story:** As a trader, I want the system to handle partial fills correctly so that position sizing remains accurate and OCO relationships are maintained properly.

#### Acceptance Criteria

1. WHEN a pending order receives partial fill THEN the system SHALL adjust the opposite OCO order volume to match the filled amount
2. WHEN partial fills occur in replication mode THEN the system SHALL ensure both legs maintain proper delta relationship
3. WHEN calculating risk for partially filled positions THEN the system SHALL use actual filled volume rather than requested volume
4. WHEN trailing stops are applied to partially filled positions THEN the system SHALL base calculations on actual position size
5. WHEN logging partial fill events THEN the system SHALL write requested_volume, filled_volume, remaining_volume, and sibling adjustments to the audit log row for that event
6. WHEN partial fills or fills are received THEN the system SHALL process them via OnTradeTransaction (or equivalent immediate callback) so OCO adjustments and risk updates occur before the next timer tick

### Requirement 7: Two-Leg Atomic Operations

**User Story:** As a trader, I want two-leg synthetic replication to be atomic so that I don't end up with unhedged single-leg exposure due to execution failures.

#### Acceptance Criteria

1. WHEN executing two-leg replication THEN the system SHALL place both legs within the same execution cycle
2. IF the first leg succeeds but second leg fails THEN the system SHALL immediately close the first leg to prevent unhedged exposure
3. WHEN both legs are successfully placed THEN the system SHALL count both positions toward MaxOpenPerSymbol and MaxOpenPositionsTotal limits
4. WHEN closing replication positions THEN the system SHALL close both legs simultaneously or as close as possible in time
5. WHEN news buffer affects either leg THEN the system SHALL apply restrictions to the entire synthetic position
6. WHEN executing atomic operations THEN the system SHALL guard execution with a reentrancy lock so no duplicate placements occur across OnTick/OnTimer

### Requirement 8: Order Engine Error Handling and Resilience

**User Story:** As a trader, I want the order engine to handle broker errors gracefully so that temporary issues don't cause the EA to malfunction or leave positions in inconsistent states.

#### Acceptance Criteria

1. WHEN broker returns temporary errors THEN the system SHALL implement exponential backoff retry logic up to 3 attempts
2. WHEN broker returns permanent errors (TRADE_DISABLED, NO_MONEY) THEN the system SHALL fail fast without retries
3. WHEN order modification fails during news windows THEN the system SHALL queue the modification for later execution
4. WHEN system restarts THEN the system SHALL reconcile existing positions and orders before placing new trades
5. WHEN detecting order state inconsistencies THEN the system SHALL log detailed error information and attempt self-healing recovery
6. WHEN persisting state THEN the system SHALL persist all order intents and queued actions under MQL5/Files/RPEA/state/ and restore them on init before new placements with idempotent reconciliation

### Requirement 9: Integration with Risk Management

**User Story:** As a trader, I want the order engine to respect all risk management constraints so that no orders are placed that would violate daily/overall loss caps or position limits.

#### Acceptance Criteria

1. WHEN placing any order THEN the system SHALL verify compliance with MaxOpenPositionsTotal, MaxOpenPerSymbol, and MaxPendingsPerSymbol limits
2. WHEN calculating order size THEN the system SHALL ensure worst-case loss fits within available daily and overall room
3. WHEN budget gate validation fails THEN the system SHALL reject the order and log the reason
4. WHEN margin requirements exceed available margin THEN the system SHALL reduce position size or reject the order
5. WHEN kill-switch floors are breached THEN the system SHALL allow protective exits even during news buffer windows
6. BEFORE placing any order THEN the system SHALL compute open_risk + pending_risk + next_trade and fail if it exceeds 0.9 × min(room_today, room_overall) and record the three terms and both rooms in the audit log

### Requirement 10: News Compliance Integration

**User Story:** As a trader, I want the order engine to respect news restrictions so that the EA remains compliant with FundingPips rules regarding high-impact news events.

#### Acceptance Criteria

1. WHEN high-impact news affects a symbol within NewsBufferS THEN the system SHALL block new order placement for that symbol
2. WHEN in news buffer window THEN the system SHALL queue trailing stop updates and SL/TP modifications for later execution
3. WHEN protective exits are required THEN the system SHALL allow SL/TP hits and kill-switch actions even during news windows
4. WHEN OCO sibling cancellation is needed for risk reduction THEN the system SHALL allow the cancellation during news windows
5. WHEN replication pair protection is needed THEN the system SHALL allow closing the remaining leg during news windows
6. IF primary news API fails THEN the system SHALL parse Files/RPEA/news/calendar_high_impact.csv per the documented schema and enforce the same rules

### Requirement 11: Telemetry and Audit Logging

**User Story:** As a trader and compliance officer, I want comprehensive logging of all order engine activities so that I can audit trading decisions and troubleshoot issues effectively.

#### Acceptance Criteria

1. WHEN any order intent is created THEN the system SHALL log the intent with timestamp, symbol, order type, volume, price levels, and reasoning to Files/RPEA/logs/*.csv
2. WHEN orders are executed THEN the system SHALL log requested vs filled volumes, slippage, execution time, and any modifications to the audit trail
3. WHEN queue actions are processed THEN the system SHALL log queued action type, trigger conditions, execution time, and results
4. WHEN OCO relationships are established or modified THEN the system SHALL log both order tickets, relationship type, and any adjustments
5. WHEN atomic operations succeed or fail THEN the system SHALL log all legs involved, success/failure status, and rollback actions taken
6. WHEN budget gate calculations are performed THEN the system SHALL log open_risk, pending_risk, next_trade_risk, room_today, room_overall, and pass/fail decision
7. WHEN writing audit rows THEN the system SHALL include strategy context columns (confidence, efficiency, est_value, hold_time, gating_reason, news_window_state) alongside the existing fields