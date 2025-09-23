# Requirements Document - RPEA M2: Signal Engine (BWISC)

## Introduction

This milestone implements the core BWISC (Burst-Weighted Imbalance with Session Confluence) signal engine for the RPEA MT5 Expert Advisor. Building on the M1 skeleton, M2 adds the primary trading logic including BTR/SDR/ORE calculations, bias scoring, setup identification (BC/MSC), risk sizing with equity caps, margin guards, position caps, and budget gates. The implementation integrates with the existing scheduler and session management while adding comprehensive risk management and telemetry.

**Time Bases:** All operations use broker server time. DST handling requires manual ServerToCEST_OffsetMinutes updates. London session: 07:00-16:00 server time (default). New York session: 12:00-16:00 server time (default). London open price = first M1 close at 07:00:00 server time. Server-day baseline for daily loss cap anchors at server midnight (00:00:00 server time).

**Symbol Universe:** Primary symbols EURUSD, XAUUSD with per-symbol property handling (digits, tick value/size, min lot, step). FX leverage 1:50, metals 1:20 (configurable overrides).

**M2 Scope:** Signal evaluation and order planning only. No actual order placement - that is reserved for M3. All execution paths MUST return a planning-only response ("M2 planning only") and log the attempted action.

## Requirements

### Requirement 1: BWISC Signal Engine Core

**User Story:** As a trader, I want the EA to calculate BWISC signals based on market conditions, so that it can identify high-probability trading setups during London and New York sessions.

#### Acceptance Criteria

1. WHEN the scheduler evaluates a symbol during a session THEN the system SHALL calculate BTR (Body-to-TrueRange) from yesterday's D1 candle where C1 = yesterday's D1 close, O1 = yesterday's D1 open
2. WHEN London session opens THEN the system SHALL calculate SDR (Session Dislocation Ratio) using |Open_LO - MA20_H1| / ATR(D1), where Open_LO = first M1 close at 07:00:00 server time
3. WHEN in the first 60 minutes of a session THEN the system SHALL calculate ORE (Opening Range Energy) as range(H-L) / ATR(D1)
4. WHEN RSI(H1) is available THEN the system SHALL apply RSI guard: IF RSI > 70 AND bias > 0 OR RSI < 30 AND bias < 0 THEN reduce confidence by 50%, UNLESS SDR ≥ 0.5 (strong dislocation overrides RSI)
5. WHEN all components are calculated THEN the system SHALL compute Bias score using: Bias = 0.45*sign(C1−O1)*BTR + 0.35*sign(Open_LO − MA20_H1)*min(SDR,1) + 0.20*sign(C1−O1)*min(ORE,1), where SDR and ORE are clamped to [0,1], and ATR floor = max(ATR_D1, _Point) to prevent division by zero
6. WHEN bias calculation produces edge cases THEN the system SHALL handle: BTR=0.8, SDR=0.6→clamped to 1.0, ORE=0.4, bullish direction → Bias = 0.45*1*0.8 + 0.35*1*1.0 + 0.20*1*0.4 = 0.79 (BC setup threshold met)

### Requirement 2: Setup Identification and Targeting

**User Story:** As a trader, I want the EA to identify specific trading setups (BC/MSC) based on bias strength, so that it can execute trades with appropriate risk-reward ratios.

#### Acceptance Criteria

1. WHEN |Bias| ≥ 0.6 THEN the system SHALL propose BC (Breakout Continuation) setup with 2.2R target (Example: |Bias| = 0.68 → BC setup)
2. WHEN |Bias| ∈ [0.35,0.6) AND SDR ≥ 0.35 THEN the system SHALL propose MSC (Mean Reversion to Session Confluence) setup with 2.0R target (Example: |Bias| = 0.45, SDR = 0.42 → MSC setup)
3. WHEN neither condition is met THEN the system SHALL return no setup (Example: |Bias| = 0.25 → No setup)
4. WHEN BC setup is identified THEN the system SHALL set stop beyond OR extreme with ATR-based SL
5. WHEN MSC setup is identified THEN the system SHALL set limit entry toward MA20_H1 with SL beyond dislocation
6. WHEN a setup is identified THEN the system SHALL set base confidence as confidence_base = clamp(|Bias|, 0, 1) and apply RSI guard penalties (50%) unless SDR ≥ 0.5; confidence_final is logged
7. WHEN a setup is identified THEN the system SHALL compute expected_R = (setup == BC ? RtargetBC : RtargetMSC) × clamp(|Bias|, 0, 1)

### Requirement 3: Session Statistics and Indicators

**User Story:** As a trader, I want the EA to maintain accurate session statistics and technical indicators, so that signal calculations are based on current market conditions.

#### Acceptance Criteria

1. WHEN a session starts THEN the system SHALL calculate Opening Range (OR) from first 60 minutes using M5 bars AND check spread ≤ MaxSpreadPoints before proceeding
2. WHEN evaluating signals THEN the system SHALL maintain MA20_H1 (EMA 20 on H1 close) AND verify news buffer (MQL5 Calendar API primary, CSV fallback) with NewsBufferS minutes around high-impact events
3. WHEN calculating distances THEN the system SHALL use ATR_D1 (ATR 14 on D1)
4. WHEN checking overextension THEN the system SHALL use RSI_H1 (RSI 14 on H1)
5. WHEN session ends or cutoff is reached THEN the system SHALL reset session-specific statistics

### Requirement 4: Risk Sizing with Equity Caps

**User Story:** As a trader, I want the EA to size positions based on available equity room and risk limits, so that it never exceeds daily or overall loss caps.

#### Acceptance Criteria

1. WHEN calculating position size THEN the system SHALL use formula: risk_money = equity * risk_pct AND normalize volume to symbol properties (min lot, step, max lot)
2. WHEN determining SL distance THEN the system SHALL use max(|entry - stop| / _Point, MinStopPoints) AND handle FX (5-digit) vs metals (3-digit) correctly
3. WHEN sizing volume THEN the system SHALL calculate raw_volume = risk_money / (sl_points * value_per_point) using SYMBOL_TRADE_TICK_VALUE and SYMBOL_TRADE_TICK_SIZE
4. WHEN equity room is insufficient THEN the system SHALL reduce position size or skip trade
5. WHEN MinRiskDollar threshold is not met THEN the system SHALL pause trading for the day
6. WHEN calculating per-point value THEN the system SHALL use value_per_point = SYMBOL_TRADE_TICK_VALUE / (SYMBOL_TRADE_TICK_SIZE / _Point)
7. WHEN normalizing values THEN the system SHALL round prices to symbol digits and volumes to SYMBOL_VOLUME_STEP, and clamp volumes within broker min/max lot
8. WHEN calculating rooms THEN the system SHALL persist and reload initial_baseline and baseline_today (server-day anchor) from RPEA/state/challenge_state.json; on missing/invalid data, initialize safely and log

### Requirement 5: Budget Gate and Risk Aggregation

**User Story:** As a trader, I want the EA to enforce budget gates that consider all open and pending risk, so that total exposure never exceeds safe limits.

#### Acceptance Criteria

1. WHEN evaluating a new trade THEN the system SHALL calculate: open_risk + pending_risk + next_trade_worst_case ≤ 0.9 * min(room_today, room_overall), where open_risk = sum of |current_price - SL| * volume * value_per_point for all positions, pending_risk = sum of worst-case risk for all pending orders
2. WHEN room_today < MinRiskDollar THEN the system SHALL pause trading for the day
3. WHEN overall room is insufficient THEN the system SHALL disable trading permanently  
4. WHEN budget gate fails THEN the system SHALL log the gating reason and skip the trade (M2 planning only - no actual orders placed)
5. WHEN multiple trades are considered in same session THEN the system SHALL apply second-trade rule with 0.8x room multiplier, where "second trade" = any trade after the first trade placement attempt in the same London or New York session window

### Requirement 6: Position and Order Caps

**User Story:** As a trader, I want the EA to enforce position and order limits per symbol and globally, so that it maintains controlled exposure.

#### Acceptance Criteria

1. WHEN placing any order THEN the system SHALL verify OpenPositionsTotal < MaxOpenPositionsTotal
2. WHEN placing order for specific symbol THEN the system SHALL verify OpenPositionsBySymbol(sym) < MaxOpenPerSymbol
3. WHEN placing pending order THEN the system SHALL verify OpenPendingsBySymbol(sym) < MaxPendingsPerSymbol
4. WHEN any cap is exceeded THEN the system SHALL reject the order and log the reason
5. WHEN caps allow THEN the system SHALL proceed with order placement

### Requirement 7: Margin Guard

**User Story:** As a trader, I want the EA to monitor margin usage and prevent over-leveraging, so that positions can be maintained safely.

#### Acceptance Criteria

1. WHEN calculating position size THEN the system SHALL ensure estimated margin ≤ 60% of free margin
2. WHEN margin would be exceeded THEN the system SHALL reduce position size proportionally
3. WHEN margin is critically low THEN the system SHALL pause new entries
4. WHEN synthetic replication is used THEN the system SHALL aggregate margin for both legs
5. WHEN margin calculation fails THEN the system SHALL default to conservative sizing

### Requirement 8: Spread and News Guards

**User Story:** As a trader, I want the EA to respect spread limits and news buffers, so that it avoids trading during unfavorable market conditions.

#### Acceptance Criteria

1. WHEN evaluating any signal THEN the system SHALL verify spread ≤ MaxSpreadPoints (default 40 points) before proceeding
2. WHEN checking news events THEN the system SHALL use MQL5 Calendar API as primary source with CSV fallback (calendar_high_impact.csv)
3. WHEN high-impact news event is within NewsBufferS minutes (default 300s) THEN the system SHALL skip signal generation entirely
4. WHEN news API is unavailable THEN the system SHALL fall back to CSV file and log the fallback
5. WHEN spread exceeds threshold THEN the system SHALL log the rejection and skip signal generation
6. Clarification: SYMBOL_SPREAD and MaxSpreadPoints are expressed in points (not pips); thresholds and logs MUST use points consistently

### Requirement 9: Integration with Scheduler and Sessions

**User Story:** As a trader, I want the signal engine to integrate seamlessly with existing session management, so that signals are only generated during appropriate trading windows.

#### Acceptance Criteria

1. WHEN scheduler calls signal evaluation THEN the system SHALL check session predicates (London/NY)
2. WHEN in OR window THEN the system SHALL update OR statistics for signal calculations
3. WHEN session ends THEN the system SHALL clean up session-specific data
4. WHEN cutoff hour is reached THEN the system SHALL stop generating new signals
5. WHEN news is blocked THEN the system SHALL skip signal generation
6. WHEN evaluating New York session THEN the system SHALL enforce NY Gate: allow NY only if realized day loss ≤ (NYGatePctOfDailyCap × DailyLossCapPct) of today's server‑day baseline; otherwise skip NY evaluation and log the gate reason

### Requirement 10: Telemetry and Logging

**User Story:** As a trader, I want comprehensive logging of signal decisions and risk calculations, so that I can monitor and debug the EA's behavior.

#### Acceptance Criteria

1. WHEN signal is evaluated THEN the system SHALL log BTR, SDR, ORE, RSI, and Bias values
2. WHEN setup is identified THEN the system SHALL log setup type, confidence, expected R, and risk parameters
3. WHEN budget gate triggers THEN the system SHALL log gating reason and room calculations
4. WHEN position caps are hit THEN the system SHALL log cap type and current counts
5. WHEN margin guard activates THEN the system SHALL log margin calculations and adjustments

### Requirement 11: Error Handling and Resilience

**User Story:** As a trader, I want the EA to handle errors gracefully and continue operating, so that temporary issues don't stop trading entirely.

#### Acceptance Criteria

1. WHEN indicator calculation fails THEN the system SHALL use fallback values or skip the signal
2. WHEN price data is missing THEN the system SHALL attempt to refresh or use cached values
3. WHEN risk calculation produces invalid results THEN the system SHALL default to minimum safe sizing
4. WHEN file operations fail THEN the system SHALL log errors and continue with in-memory data
5. WHEN any component fails THEN the system SHALL isolate the failure and maintain other functionality