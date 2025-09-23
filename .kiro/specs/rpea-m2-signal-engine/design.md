# Design Document - RPEA M2: Signal Engine (BWISC)

## Overview

The RPEA M2 milestone implements the core BWISC (Burst-Weighted Imbalance with Session Confluence) signal engine, transforming the M1 skeleton into a functional trading system. This design builds upon the existing scheduler and session management framework while adding sophisticated signal generation, multi-layered risk management, and comprehensive telemetry.

**Key Design Principles:**
- **Incremental Enhancement**: Extend M1 stubs rather than rewrite, maintaining backward compatibility
- **Risk-First Architecture**: Multiple independent risk gates (equity rooms, budget gates, margin guards, position caps) that can each veto trades
- **Session-Aware Processing**: All calculations respect London/NY session windows and Opening Range dynamics
- **Graceful Degradation**: System continues operating with reduced confidence when components fail
- **Comprehensive Telemetry**: Every decision point logged for analysis and debugging

## Architecture

### Component Interaction Flow
```
Scheduler_Tick() 
    ↓
Sessions_InLondon/NY() → [Session Gates]
    ↓
SignalsBWISC_Evaluate() → [Signal Generation]
    ↓ 
Allocator_EvaluateSignal() → [Risk Gates Cascade]
    ↓
OrderEngine_PlaceOrder() → [Execution - M3]
```

### Risk Gates Cascade
The system implements a cascading risk management approach where each gate can independently reject trades:

1. **Session Gates**: Time windows, news blocks, spread conditions
2. **Signal Gates**: Bias thresholds, RSI overextension, setup confidence
3. **Equity Gates**: Daily/overall loss caps, minimum risk thresholds
4. **Budget Gates**: Total risk aggregation with safety multipliers
5. **Position Gates**: Global and per-symbol position/order limits
6. **Margin Gates**: Broker margin requirements and scaling

### Session Gates Table
| Gate Type | Threshold | Source | Buffer | Action |
|-----------|-----------|--------|---------|---------|
| Spread Check | MaxSpreadPoints = 40 | SymbolInfoInteger(SYMBOL_SPREAD) | N/A | Skip signal if spread > threshold |
| News Block | High Impact Events | MQL5 Calendar API (primary) | NewsBufferS = 300 seconds | Skip signal during T±300s window |
| News Fallback | High Impact Events | CSV: calendar_high_impact.csv | NewsBufferS = 300 seconds | Parse CSV when API unavailable |
| Session Window | London: 07:00-16:00 | Server time | N/A | Only evaluate during active sessions |
| Session Window | New York: 12:00-16:00 | Server time | N/A | Only evaluate during active sessions |
| OR Window | First 60 minutes | Session start + ORMinutes | N/A | Update OR stats during window |
| NY Gate | realized day loss ≤ NYGatePctOfDailyCap × DailyLossCapPct of today's baseline | Equity Guardian | N/A | Allow NY only if gate passes; else skip and log |

## Change-Set Table

| Path | Action | Reason | New Types/Functions | Touch-Points |
|------|--------|--------|-------------------|--------------|
| MQL5/Include/RPEA/signals_bwisc.mqh | Modify | Implement full BWISC logic with BTR/SDR/ORE calculations | BWISCSignal, BWISCContext, SignalsBWISC_CalculateBTR, SignalsBWISC_CalculateSDR, SignalsBWISC_CalculateORE, SignalsBWISC_CalculateBias, SignalsBWISC_DetermineSetup | scheduler.mqh, indicators.mqh, sessions.mqh |
| MQL5/Include/RPEA/indicators.mqh | Modify | Add real indicator handles and OR tracking | IndicatorValues, Indicators_GetATR, Indicators_GetMA20, Indicators_GetRSI, Indicators_UpdateOR, Indicators_InitSymbol | signals_bwisc.mqh, sessions.mqh |
| MQL5/Include/RPEA/sessions.mqh | Modify | Add OR window lifecycle and session statistics | SessionStats, Sessions_GetORHigh, Sessions_GetORLow, Sessions_ResetORStats, Sessions_UpdateORStats, Sessions_FinalizeORStats | signals_bwisc.mqh, scheduler.mqh, indicators.mqh |
| MQL5/Include/RPEA/risk.mqh | Modify | Implement position sizing, margin guard, risk aggregation | RiskCalculation, Risk_CalculatePositionSize, Risk_CheckMarginGuard, Risk_GetValuePerPoint, Risk_GetOpenPositionRisk, Risk_GetPendingOrderRisk | allocator.mqh, equity_guardian.mqh |
| MQL5/Include/RPEA/equity_guardian.mqh | Modify | Implement equity rooms, budget gates, floor monitoring | EquityRooms, Equity_CalculateRooms, Equity_CheckBudgetGate, Equity_CheckSecondTradeRule, Equity_CheckFloors | risk.mqh, allocator.mqh, scheduler.mqh |
| MQL5/Include/RPEA/allocator.mqh | Modify | Implement order planning with cascading risk gates | OrderPlan, AllocationResult, Allocator_EvaluateSignal, Allocator_CheckPositionCaps, Allocator_ApplyBudgetGate | risk.mqh, equity_guardian.mqh, signals_bwisc.mqh |
| MQL5/Include/RPEA/state.mqh | Modify | Add session-specific state persistence | SessionState, State_GetSessionStats, State_UpdateSessionStats, State_ResetSessionStats | signals_bwisc.mqh, sessions.mqh |
| MQL5/Include/RPEA/logging.mqh | Modify | Add M2-specific telemetry and error logging | LogSignalEvaluation, LogRiskCalculation, LogBudgetGate, LogPositionCaps, LogMarginGuard, LogSessionStats | All M2 components |

## New Files/Modules

**MQL5/Include/RPEA/config_m2.mqh** - M2-specific configuration constants with bounds, defaults, and rationale comments. This centralizes all magic numbers from the design into configurable parameters.

## Scope Guards

**Synthetic Replication Margin Aggregation**: Marked as future implementation (M3/M7). M2 code paths SHALL NOT depend on synthetic replication features. All synthetic-related margin calculations are gated behind `UseXAUEURProxy=false` flag and will return "not implemented" errors in M2. M2 focuses exclusively on single-symbol EURUSD/XAUUSD proxy mode trading.

## API Contracts

### Core Function Signatures

#### SignalsBWISC_Evaluate
```mql5
BWISCSignal SignalsBWISC_Evaluate(const AppContext& ctx, const string symbol);
// Returns: Complete signal evaluation result
// Units: bias [-1.0, +1.0], confidence [0.0, 1.0], points as integers
// Rounding: bias to 4 decimals, confidence to 3 decimals
// Normalization: SDR/ORE clamped to [0,1] in bias calc, ATR floor = max(ATR, _Point)
// Error handling: Returns hasSetup=false with error logged on failure
```

#### Risk_CalculatePositionSize  
```mql5
RiskCalculation Risk_CalculatePositionSize(const string symbol, const double entry, const double stop, const double risk_pct);
// Returns: Position size calculation with validation
// Units: volume in lots, risk_money in account currency, points as integers
// Rounding: volume to symbol step size, money to 2 decimals
// Normalization: Volume clamped to [symbol_min, symbol_max], margin scaled if >60% free
// Error handling: Returns valid=false with error_reason on any failure
```

#### Equity_CalculateRooms
```mql5
EquityRooms Equity_CalculateRooms(const AppContext& ctx);
// Returns: Available trading room calculations
// Units: All monetary values in account currency
// Rounding: Room values to 2 decimal places
// Normalization: Negative rooms set to 0.0, baseline anchored to server midnight
// Persistence: Reads/writes initial_baseline and baseline_today to RPEA/state/challenge_state.json; re-anchors baseline_today at server midnight
// Error handling: Uses current equity if baseline unavailable
```

#### Allocator_EvaluateSignal
```mql5
AllocationResult Allocator_EvaluateSignal(const AppContext& ctx, const BWISCSignal& signal, const string symbol);
// Returns: Complete allocation decision with order plan
// Units: Volume in lots, prices in symbol quote currency
// Rounding: Prices to symbol digits, volume to symbol step
// Normalization: All risk gates applied in cascade, rejection at first failure
// Error handling: Returns approved=false with detailed rejection_reason
```

### Error Codes
```mql5
enum RPEA_ERROR_CODE {
    RPEA_SUCCESS = 0,
    RPEA_ERROR_INVALID_SYMBOL = 1001,
    RPEA_ERROR_INDICATOR_FAILURE = 1002,
    RPEA_ERROR_INSUFFICIENT_DATA = 1003,
    RPEA_ERROR_RISK_CALCULATION = 1004,
    RPEA_ERROR_BUDGET_EXCEEDED = 1005,
    RPEA_ERROR_POSITION_CAPS = 1006,
    RPEA_ERROR_MARGIN_INSUFFICIENT = 1007,
    RPEA_ERROR_SPREAD_TOO_WIDE = 1008,
    RPEA_ERROR_NEWS_BLOCKED = 1009,
    RPEA_ERROR_SESSION_INACTIVE = 1010
};
```

## Components and Interfaces

### BWISC Signal Engine (signals_bwisc.mqh)

**Core Responsibility**: Generate trading signals based on market structure analysis combining burst patterns, session dislocation, and opening range dynamics.

**Key Algorithms**:

#### BTR (Body-to-TrueRange) Calculation
```
Purpose: Measure yesterday's candle momentum strength
Input: Yesterday's D1 OHLC (O[1], H[1], L[1], C[1])
Steps:
1. body = |C[1] - O[1]|
2. true_range = max(H[1] - L[1], |H[1] - C[2]|, |L[1] - C[2]|)
3. If true_range <= _Point: true_range = _Point
4. BTR = body / true_range
Bounds: [0.0, 1.0]
Rationale: Higher BTR indicates strong directional momentum
```

#### SDR (Session Dislocation Ratio) Calculation
```
Purpose: Measure price displacement from trend reference
Input: London Open price, MA20_H1, ATR_D1
Steps:
1. dislocation = |Open_LO - MA20_H1|
2. If ATR_D1 <= _Point: ATR_D1 = _Point
3. SDR = dislocation / ATR_D1
Bounds: [0.0, unbounded] (clamped to 1.0 in bias calculation)
Rationale: Normalizes gap size relative to recent volatility
```

#### ORE (Opening Range Energy) Calculation
```
Purpose: Measure initial session volatility expansion
Input: OR High, OR Low (from first 60 minutes), ATR_D1
Steps:
1. or_range = OR_High - OR_Low
2. If ATR_D1 <= _Point: ATR_D1 = _Point
3. ORE = or_range / ATR_D1
Bounds: [0.0, unbounded] (clamped to 1.0 in bias calculation)
Rationale: High ORE suggests strong session momentum
```

#### Bias Calculation and Setup Logic
```
Purpose: Combine all components into directional bias score
Formula: Bias = 0.45 * sign(C1-O1) * BTR + 0.35 * sign(Open_LO - MA20_H1) * min(SDR,1) + 0.20 * sign(C1-O1) * min(ORE,1)

Component Weights Rationale:
- 45% BTR: Yesterday's momentum is primary driver
- 35% SDR: Session gap provides directional context  
- 20% ORE: Opening range confirms or contradicts setup

Setup Selection:
- |Bias| >= 0.6: BC (Breakout Continuation) - strong momentum
- |Bias| >= 0.35 AND SDR >= 0.35: MSC (Mean Reversion to Session Confluence) - moderate bias with dislocation
- Otherwise: No setup
```

#### RSI Overextension Guard (Updated)
```
Purpose: Avoid entries during extreme momentum conditions unless strong dislocation present
Logic:
- If SDR >= 0.5: ignore RSI (strong dislocation overrides RSI guard)
- If SDR < 0.5: apply RSI guard
  - If RSI > 70 AND bias > 0: confidence *= 0.5
  - If RSI < 30 AND bias < 0: confidence *= 0.5
Rationale: Strong session gaps (SDR >= 0.5) justify ignoring overextension
```

#### Confidence and ExpectedR
```
Purpose: Establish base setup confidence and expected payoff
Base Confidence: confidence_base = clamp(|bias|, 0, 1)
Penalties/Overrides: If SDR < 0.5 apply RSI guard (×0.5); if SDR ≥ 0.5 ignore RSI
Final Confidence: confidence = confidence_base after penalties
Expected R: expectedR = (setup == BC ? RtargetBC : RtargetMSC) × clamp(|bias|, 0, 1)
```

### Risk Management System

#### Position Sizing (risk.mqh)
```
Purpose: Calculate appropriate position size based on risk parameters
Formula: 
1. risk_money = current_equity * risk_percentage
2. sl_points = max(|entry_price - stop_price| / _Point, MinStopPoints)
3. value_per_point = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE) * _Point
4. raw_volume = risk_money / (sl_points * value_per_point)
5. normalized_volume = normalize_to_broker_constraints(raw_volume)

Error Handling: Return invalid result with error_reason if any step fails
```

#### Equity Room Management (equity_guardian.mqh)
```
Purpose: Enforce daily and overall loss limits
Calculations:
- baseline_today = max(balance_at_server_midnight, equity_at_server_midnight)
- room_today = (DailyLossCapPct/100) * baseline_today - (baseline_today - current_equity)
- room_overall = (OverallLossCapPct/100) * initial_baseline - (initial_baseline - current_equity)

Trading Rules:
- If room_today < MinRiskDollar: pause trading for day
- If room_overall < MinRiskDollar: disable trading permanently
- Budget gate: total_risk <= 0.9 * min(room_today, room_overall)
- Second trade rule: total_risk <= 0.8 * min(room_today, room_overall)
```

#### Margin Guard (risk.mqh)
```
Purpose: Prevent margin calls and over-leveraging
Logic:
1. estimated_margin = calculate_margin_required(symbol, volume)
2. free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE)
3. margin_threshold = 0.6 * free_margin
4. If estimated_margin > margin_threshold: scale_volume = volume * (margin_threshold / estimated_margin)
5. If scaled_volume < symbol_min_volume: reject trade

Rationale: 60% threshold provides safety buffer for market volatility
```

### Session and Indicator Management

#### Opening Range Tracking (sessions.mqh)
```
Purpose: Calculate OR statistics during first 60 minutes of session
Process:
1. Session start: Reset OR stats, initialize tracking
2. During OR window: Update high/low from M5 bars every 30 seconds
3. OR completion: Finalize stats, calculate ORE
4. Session end: Clean up session-specific data

Integration: OR stats feed directly into BWISC signal calculations
```

#### Technical Indicators (indicators.mqh)
```
Purpose: Provide reliable technical indicator values with error handling
Indicators:
- ATR_D1: 14-period ATR on daily timeframe for volatility normalization
- MA20_H1: 20-period EMA on H1 timeframe for trend reference
- RSI_H1: 14-period RSI on H1 timeframe for overextension detection

Error Handling:
- Invalid handles: Retry creation, use cached values if available
- Missing data: Return invalid result, log error, continue with degraded confidence
- Cache TTL: 15 minutes to balance performance vs freshness
```

## Algorithms

### BTR (Body-to-TrueRange) Calculation
```
Input: Yesterday's D1 OHLC (O[1], H[1], L[1], C[1])
Steps:
1. body = |C[1] - O[1]|
2. true_range = max(H[1] - L[1], |H[1] - C[2]|, |L[1] - C[2]|)
3. If true_range <= _Point: true_range = _Point
4. BTR = body / true_range
Bounds: [0.0, 1.0]
Default: Use previous valid value if calculation fails
```

### SDR (Session Dislocation Ratio) Calculation
```
Input: London Open price (first M1 close at 07:00:00), MA20_H1, ATR_D1
Steps:
1. dislocation = |Open_LO - MA20_H1|
2. If ATR_D1 <= _Point: ATR_D1 = _Point
3. SDR = dislocation / ATR_D1
Bounds: [0.0, unbounded] (clamped to 1.0 in bias calculation)
Default: 0.0 if ATR unavailable
```

### ORE (Opening Range Energy) Calculation
```
Input: OR High, OR Low (from first 60 minutes), ATR_D1
Steps:
1. or_range = OR_High - OR_Low
2. If ATR_D1 <= _Point: ATR_D1 = _Point
3. ORE = or_range / ATR_D1
Bounds: [0.0, unbounded] (clamped to 1.0 in bias calculation)
Default: 0.0 if OR not established or ATR unavailable
```

### RSI Guard (Updated to Match Requirements)
```
Input: RSI_H1 value, SDR, bias
Logic:
- If SDR >= 0.5: ignore RSI (strong dislocation overrides RSI)
- If SDR < 0.5: apply RSI guard
  - If RSI > 70 AND bias > 0: confidence *= 0.5
  - If RSI < 30 AND bias < 0: confidence *= 0.5
Default RSI bounds: [30, 70], confidence penalty = 50%
```

### Bias Calculation
```
Input: BTR, SDR, ORE, price direction signs
Formula: Bias = 0.45 * sign(C1-O1) * BTR + 0.35 * sign(Open_LO - MA20_H1) * min(SDR,1) + 0.20 * sign(C1-O1) * min(ORE,1)
Where:
- sign(x) = +1 if x > 0, -1 if x < 0, 0 if x == 0
- min(x,1) caps the value at 1.0
Bounds: [-1.0, +1.0]
```

### BC vs MSC Setup Selection
```
Input: Bias, SDR, RSI
Logic:
1. If |Bias| >= 0.6: setup = "BC"
2. Else if |Bias| >= 0.35 AND SDR >= 0.35: setup = "MSC"  
3. Else: setup = "None"

RSI Override Logic (matching requirements):
- If setup != "None" AND SDR < 0.5: apply RSI guard
  - If RSI > 70 AND bias > 0: confidence *= 0.5
  - If RSI < 30 AND bias < 0: confidence *= 0.5
- If SDR >= 0.5: ignore RSI (strong dislocation overrides)

Default thresholds: Bias_BC = 0.6, Bias_MSC = 0.35, SDR_MSC = 0.35, RSI_bounds = [30, 70]
```

### Target/SL Mapping
```
BC Setup:
- SL = ATR_D1 * SLmult (default SLmult = 1.0)
- TP = SL * RtargetBC (default RtargetBC = 2.2)
- Entry: Stop order beyond OR extreme + EntryBufferPoints

MSC Setup:
- SL = max(ATR_D1 * SLmult, dislocation_distance * 1.2)
- TP = SL * RtargetMSC (fixed RtargetMSC = 2.0, matching requirements)
- Entry: Limit order toward MA20_H1

Convert to points: distance_points = distance_price / _Point
```

## Data Models

### Core Signal Structure
```mql5
struct BWISCSignal {
    bool hasSetup;           // Whether a valid setup was identified
    string setupType;        // "BC", "MSC", or "None"
    double bias;            // Calculated bias score [-1.0, +1.0]
    double confidenceBase;  // Base confidence before penalties [0.0, 1.0]
    double confidence;      // Final confidence after penalties [0.0, 1.0]
    double btr;             // Body-to-TrueRange component
    double sdr;             // Session Dislocation Ratio component
    double ore;             // Opening Range Energy component
    double rsi;             // RSI value for overextension check
    int slPoints;           // Stop loss distance in points
    int tpPoints;           // Take profit distance in points
    double expectedR;       // Expected risk-reward ratio
};
```

### Risk Calculation Result
```mql5
struct RiskCalculation {
    double volume;          // Calculated position size
    double risk_money;      // Dollar amount at risk
    double sl_points;       // Stop loss distance in points
    double value_per_point; // Dollar value per point movement
    double margin_required; // Estimated margin requirement
    bool valid;             // Whether calculation succeeded
    string error_reason;    // Error description if invalid
    datetime calculated_at; // Timestamp for cache management
};
```

### Equity Room Status
```mql5
struct EquityRooms {
    double room_today;      // Available room for today's trading
    double room_overall;    // Available room vs overall cap
    double baseline_today;  // Today's starting equity baseline
    double initial_baseline;// Initial account baseline
    double current_equity;  // Current account equity
    datetime calculated_at; // Calculation timestamp
};
```

### Order Planning Result
```mql5
struct OrderPlan {
    bool valid;             // Whether plan is executable
    string symbol;          // Trading symbol
    double volume;          // Position size
    double entry_price;     // Entry price level
    double sl_price;        // Stop loss price
    double tp_price;        // Take profit price
    ENUM_ORDER_TYPE order_type; // Market, limit, or stop order
    string rejection_reason;// Why plan was rejected (if invalid)
    datetime expires_at;    // Order expiration time
};
```

## Concurrency Policy

### Per-Symbol State Management
```
Cache Structure: Each symbol maintains independent state
- IndicatorValues cache with 15-minute TTL
- SessionStats with session-lifetime scope  
- OR statistics reset at session start, locked at 60-minute mark
- No cross-symbol dependencies in calculations

Locking Rules: Single-threaded execution model (MT5 constraint)
- No explicit locking required - OnTimer() is atomic
- State updates are immediate and consistent
- Cache invalidation is synchronous

Update Cadence: 30-second timer cycle
- Indicator refresh: Every cycle during session
- OR updates: Every cycle during first 60 minutes
- Signal evaluation: Every cycle when session active
- Risk calculations: On-demand per signal

Failure Back-offs:
- Indicator handle failure: Retry next cycle, max 3 attempts
- Data retrieval failure: Skip current cycle, resume next
- Risk calculation failure: Use cached values if available
- File I/O failure: Continue in-memory, retry next cycle
```

### Multi-Symbol Loop Management
```
Processing Order: Deterministic symbol iteration (EURUSD, XAUUSD)
- Each symbol processed independently
- Failures isolated to individual symbols
- Global state (equity rooms) calculated once per cycle
- Session predicates evaluated per symbol

Memory Management:
- Indicator handles cached per symbol
- Session stats maintained per symbol
- No shared mutable state between symbols
- Automatic cleanup on session end
```

## Error Handling and Resilience

### Graceful Degradation Strategy
The system is designed to continue operating even when individual components fail:

#### Indicator Failure Recovery
```
1. Handle Creation Failure:
   - Retry handle creation up to 3 times
   - Use cached values if available (TTL: 15 minutes)
   - Apply confidence penalty (0.1) for degraded mode
   - Log error for monitoring

2. Data Retrieval Failure:
   - Attempt data refresh
   - Fall back to previous valid values
   - Skip signal generation if critical data missing
   - Continue with other symbols
```

#### Risk Calculation Failures
```
1. Symbol Property Errors:
   - Use conservative defaults (min volume, standard tick values)
   - Log warnings for manual review
   - Proceed with reduced position sizing

2. Margin Calculation Errors:
   - Default to 50% margin utilization limit
   - Use minimum position sizes
   - Disable trading for affected symbol until resolved
```

#### File I/O and Persistence Failures
```
1. State File Corruption:
   - Initialize with safe defaults
   - Rebuild session statistics from current data
   - Log data loss for audit trail

2. Log File Issues:
   - Continue operation without logging
   - Buffer critical events in memory
   - Attempt log recovery on next cycle
```

## Testing Strategy

### Unit Testing Approach
Each component will have comprehensive unit tests covering:

#### Signal Engine Tests
- **BTR Calculation**: Test with known OHLC values, edge cases (zero body, zero true range)
- **SDR Calculation**: Test with various dislocation distances and ATR values
- **ORE Calculation**: Test OR range calculations with different volatility scenarios
- **Bias Formula**: Verify component weighting and bounds enforcement
- **Setup Logic**: Test BC/MSC thresholds and edge cases
- **RSI Guard**: Verify overextension logic and SDR override behavior

#### Risk Management Tests
- **Position Sizing**: Test formula accuracy with various equity and risk percentages
- **Margin Guard**: Test volume scaling and rejection scenarios
- **Budget Gates**: Test room calculations and multi-trade scenarios
- **Position Caps**: Test global and per-symbol limits
- **Error Handling**: Test graceful degradation with invalid inputs

#### Integration Tests
- **Session Lifecycle**: Test OR window management and session transitions
- **Scheduler Integration**: Test signal evaluation timing and session gates
- **Risk Gate Cascade**: Test multiple risk gates working together
- **Error Recovery**: Test system behavior with component failures

### Strategy Tester Validation
The implementation will be validated using MT5's Strategy Tester with:

#### Historical Data Testing
- **Signal Accuracy**: Verify BTR/SDR/ORE calculations match manual calculations
- **Setup Generation**: Confirm BC/MSC setups generated at correct bias thresholds
- **Risk Enforcement**: Validate position sizing and risk gate behavior
- **Session Compliance**: Ensure signals only generated during appropriate windows

#### Performance Metrics
- **Signal Quality**: Track setup success rates and R-multiple achievement
- **Risk Compliance**: Monitor adherence to daily/overall loss caps
- **System Stability**: Verify continuous operation without crashes or hangs
- **Resource Usage**: Monitor CPU and memory consumption during operation

## Integration with Scheduler and Sessions

### Session Lifecycle Integration
The M2 signal engine integrates seamlessly with the existing M1 scheduler framework:

#### Session Start Processing
```
When Sessions_InLondon() or Sessions_InNewYork() transitions from false to true:
1. Sessions_ResetORStats(symbol) - Clear previous session data
2. Sessions_InitializeSessionStats(symbol) - Set up new session tracking
3. Indicators_UpdateOR(ctx, symbol) - Begin OR window monitoring
4. Log session start event with timestamp and session type
```

#### Opening Range Window Management
```
During first 60 minutes of session (Sessions_InORWindow() == true):
1. Every 30 seconds: Sessions_UpdateORStats(ctx, symbol)
   - Retrieve latest M5 bar high/low
   - Update running OR high/low values
   - Calculate current ORE if ATR available
2. At 60-minute mark: Sessions_FinalizeORStats(symbol)
   - Lock in final OR values
   - Log OR completion with statistics
```

#### Signal Evaluation Integration
```
In Scheduler_Tick() main loop (every 30 seconds):
1. Check session predicates (London/NY active)
2. Check news blocking status
3. Check spread conditions
4. If all gates pass: SignalsBWISC_Evaluate(ctx, symbol)
5. If signal has setup: Allocator_EvaluateSignal(ctx, signal, symbol)
6. Log all decisions for telemetry
```

#### Session End Processing
```
When session ends or cutoff reached:
1. Sessions_EndSession(symbol) - Clean up session data
2. Cancel any pending orders (M3 implementation)
3. Log session summary statistics
4. Reset session-specific state for next session
```

## Acceptance Criteria Mapping

This section maps each requirement to specific validation approaches, ensuring comprehensive coverage of all functional and non-functional requirements.

### Requirement 1: BWISC Signal Engine Core
**Validation Approach**: Component-level testing of signal calculations
- **Unit Tests**: Test BTR/SDR/ORE formulas with known inputs and edge cases
- **Integration Tests**: Verify signal evaluation integrates correctly with scheduler
- **Strategy Tester**: Validate calculations match manual verification across historical data
- **Success Criteria**: All signal components calculate correctly, bias scores stay within bounds

### Requirement 2: Setup Identification and Targeting  
**Validation Approach**: Setup logic and risk-reward validation
- **Unit Tests**: Test BC/MSC threshold logic with boundary conditions
- **Integration Tests**: Verify setup determination integrates with risk sizing
- **Strategy Tester**: Confirm setup types match expected bias/SDR combinations
- **Success Criteria**: Correct setup identification, appropriate R-multiple targeting

### Requirement 3: Session Statistics and Indicators
**Validation Approach**: Session lifecycle and indicator reliability testing
- **Unit Tests**: Test OR calculations and session state management
- **Integration Tests**: Verify indicator integration with signal calculations
- **Strategy Tester**: Validate session windows and OR tracking with real data
- **Success Criteria**: Accurate session statistics, reliable indicator values

### Requirement 4: Risk Sizing with Equity Caps
**Validation Approach**: Position sizing accuracy and equity protection
- **Unit Tests**: Test risk calculation formulas and volume normalization
- **Integration Tests**: Verify equity room integration with position sizing
- **Strategy Tester**: Validate position sizes scale correctly with equity changes
- **Success Criteria**: Accurate position sizing, proper equity cap enforcement

### Requirement 5: Budget Gate and Risk Aggregation
**Validation Approach**: Risk aggregation accuracy and budget enforcement
- **Unit Tests**: Test budget gate math and second trade rules
- **Integration Tests**: Verify risk aggregation across multiple positions
- **Strategy Tester**: Validate budget gates prevent over-risking in live scenarios
- **Success Criteria**: Accurate risk aggregation, proper budget gate enforcement

### Requirement 6: Position and Order Caps
**Validation Approach**: Limit enforcement and cap validation
- **Unit Tests**: Test position counting and cap enforcement logic
- **Integration Tests**: Verify caps integrate with order planning
- **Strategy Tester**: Validate caps prevent excessive position concentration
- **Success Criteria**: Proper cap enforcement, accurate position/order counting

### Requirement 7: Margin Guard
**Validation Approach**: Margin calculation and protection validation
- **Unit Tests**: Test margin calculations and volume scaling
- **Integration Tests**: Verify margin guard integrates with position sizing
- **Strategy Tester**: Validate margin protection with real account constraints
- **Success Criteria**: Accurate margin calculations, proper over-leverage prevention

### Requirement 8: Spread and News Guards
**Unit Tests:**
- Test_Spread_Check: Verify spread threshold enforcement
- Test_News_API_Integration: MQL5 Calendar API usage and CSV fallback
- Test_News_Buffer: NewsBufferS minute window enforcement
- Test_News_Fallback: CSV parsing and event matching

**Strategy Tester:**
- Verify spread rejections logged when threshold exceeded
- Confirm news events block signal generation appropriately
- Validate CSV fallback when API unavailable

### Requirement 9: Integration with Scheduler and Sessions
**Validation Approach**: System integration and timing validation
- **Unit Tests**: Test session predicate integration and timing logic
- **Integration Tests**: Verify complete signal evaluation flow
- **Strategy Tester**: Validate session compliance and timing accuracy
- **Success Criteria**: Proper session integration, accurate timing enforcement

### Requirement 10: Telemetry and Logging
**Validation Approach**: Logging completeness and accuracy validation
- **Unit Tests**: Test log function coverage and data accuracy
- **Integration Tests**: Verify logging integrates with all components
- **Strategy Tester**: Validate log completeness and format consistency
- **Success Criteria**: Comprehensive logging, accurate telemetry data

### Requirement 11: Error Handling and Resilience
**Validation Approach**: Failure simulation and recovery testing
- **Unit Tests**: Test error handling paths and fallback mechanisms
- **Integration Tests**: Verify system continues operating with component failures
- **Strategy Tester**: Validate graceful degradation under adverse conditions
- **Success Criteria**: Robust error handling, continued operation during failures

## Telemetry Schema

The telemetry system provides comprehensive logging for all M2 components, enabling detailed analysis and debugging. All logs use CSV format with consistent timestamp and symbol fields.

### Signal Evaluation Log
**Purpose**: Track all signal calculations and setup decisions
```csv
Fields: timestamp,symbol,session,btr,sdr,ore,rsi,bias,setup_type,confidence_base,confidence,expected_r,sl_points,tp_points,gate_reasons
Example: 2024-01-15 08:30:00,EURUSD,LONDON,0.7500,0.4200,0.3800,45.20,0.6800,BC,0.6800,0.6800,2.20,150,330,""
Precision: 4 decimal places for signal values, 2 for points
```

### Risk Calculation Log  
**Purpose**: Document position sizing and risk management decisions
```csv
Fields: timestamp,symbol,risk_pct,risk_money,sl_points,value_per_point,volume,margin_required,margin_available,scaled
Example: 2024-01-15 08:30:00,EURUSD,1.50,150.00,150,1.00,0.15,75.00,5000.00,false
Precision: 2 decimal places for money values, 4 for rates
```

### Budget Gate Log
**Purpose**: Track risk aggregation and budget gate enforcement
```csv
Fields: timestamp,symbol,open_risk,pending_risk,next_trade_risk,total_risk,room_today,room_overall,available_room,gate_result,is_second_trade
Example: 2024-01-15 08:30:00,EURUSD,120.00,0.00,150.00,270.00,400.00,600.00,360.00,PASS,false
Precision: 2 decimal places for all money values
```

### Position Caps Log
**Purpose**: Monitor position and order limit enforcement
```csv
Fields: timestamp,symbol,total_positions,symbol_positions,symbol_pendings,max_total,max_per_symbol,max_pendings,cap_result
Example: 2024-01-15 08:30:00,EURUSD,1,1,0,2,1,2,PASS
Precision: Integer values for all counts
```

### Margin Guard Log
**Purpose**: Track margin calculations and volume scaling
```csv
Fields: timestamp,symbol,requested_volume,final_volume,margin_required,margin_available,margin_threshold,scaled,guard_result
Example: 2024-01-15 08:30:00,EURUSD,0.20,0.15,100.00,1000.00,600.00,true,SCALED
Precision: 2 decimal places for volumes and money values
```

### Session Statistics Log
**Purpose**: Document session lifecycle and OR window statistics
```csv
Fields: timestamp,symbol,session,or_high,or_low,ore,atr_d1,ma20_h1,rsi_h1,session_age_minutes,or_complete
Example: 2024-01-15 08:30:00,EURUSD,LONDON,1.0850,1.0820,0.3800,0.0078,1.0835,45.20,30,true
Precision: 5 decimal places for prices, 4 for calculated values
```

### Error and Warning Log
**Purpose**: Track system errors and recovery actions
```csv
Fields: timestamp,component,error_type,symbol,severity,message,recovery_action,retry_count
Example: 2024-01-15 08:30:00,Indicators,HANDLE_INVALID,EURUSD,WARNING,ATR handle creation failed,Using cached value,2
Severity Levels: ERROR, WARNING, INFO
```

### Allocation Decision Log
**Purpose**: Track order planning and rejection reasons
```csv
Fields: timestamp,symbol,signal_setup,allocation_result,error_code,rejection_reason,final_volume,entry_price,sl_price,tp_price
Example: 2024-01-15 08:30:00,EURUSD,BC,APPROVED,0,"",0.15,1.0845,1.0830,1.0878
Precision: 2 decimal places for volumes, 5 for prices
```

### Log Management and Rotation

**File Paths**: All logs stored under MQL5/Files/RPEA/logs/
- Signal logs: `signal_evaluation_YYYYMMDD.csv`
- Risk logs: `risk_calculation_YYYYMMDD.csv`  
- Budget logs: `budget_gate_YYYYMMDD.csv`
- Position logs: `position_caps_YYYYMMDD.csv`
- Margin logs: `margin_guard_YYYYMMDD.csv`
- Session logs: `session_stats_YYYYMMDD.csv`
- Error logs: `errors_warnings_YYYYMMDD.csv`
- Allocation logs: `allocation_decisions_YYYYMMDD.csv`

**File Size Limits**: 
- Max file size: 10MB per log file
- Max daily logs: 50MB total
- Automatic compression for files >5MB

**Rotation Policy**:
- Daily rotation at server midnight (00:00:00)
- Historical retention: 30 days
- Automatic cleanup of files older than 30 days
- Emergency rotation if file size exceeds 10MB

**Guaranteed Logging**: 
- All rejection decisions logged even on system errors
- Critical events buffered in memory if file I/O fails
- Retry logging on next successful cycle
- No silent failures - all log errors reported to main audit trail

## CI Notes

CI compiles .mq5/.mqh, runs unit tests, and enforces header linting. Builds FAIL on warnings.

- MetaEditor command-line on a self-hosted Windows/macOS runner or Dockerized Windows image
- Artifacts: compiled EX5, unit test logs, linter report
- Gates: compilation success, tests green, no warnings

