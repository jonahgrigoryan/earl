# Implementation Plan - RPEA M2: Signal Engine (BWISC)

- [ ] 1. Create M2 configuration constants header
  - Create MQL5/Include/RPEA/config_m2.mqh with all M2-specific constants
  - Define BWISC signal thresholds, risk management constants, position caps, and error handling parameters
  - Include bounds, defaults, and rationale comments for each constant
  - Add #define M2_PLAN_ONLY that rejects any live order calls with "M2 planning only" error
  - _Requirements: 1.1, 2.1, 4.1, 5.1, 6.1, 7.1_
  - Defaults to include: RtargetBC=2.2, RtargetMSC=2.0, SLmult=1.0, EntryBufferPoints=3, ORMinutes=60, StartHourLO=7, StartHourNY=12, CutoffHour=16, MaxSpreadPoints=40, NewsBufferS=300, DailyLossCapPct=4.0, OverallLossCapPct=6.0, MinRiskDollar=10, RiskPct=1.5, UseLondonOnly=false

- [ ] 1.5. Compile and guardrails setup
  - Fix all #property pragmas and compilation directives for M2
  - Ensure M2 builds clean without warnings or errors
  - Add compile-time guards to prevent live trading in M2 (M2_PLAN_ONLY)
  - **Done Criteria**: Strategy Tester runs without errors, all order placement calls return "planning only" message
  - _Requirements: All requirements - compilation prerequisite_

- [ ] 2. Implement core data structures and state management
  - [ ] 2.1 Extend state.mqh with session-specific structures
    - Add SessionState struct with OR statistics and session timing
    - Implement State_GetSessionStats, State_UpdateSessionStats, State_ResetSessionStats functions
    - Add session state persistence and recovery mechanisms
    - _Requirements: 3.5, 8.1_

  - [ ] 2.2 Create BWISC signal data structures
    - Define BWISCSignal and BWISCContext structs in signals_bwisc.mqh
    - Add RiskCalculation, EquityRooms, OrderPlan, and AllocationResult structs
    - Ensure all structs include proper validation and error handling fields
    - _Requirements: 1.1, 4.1, 5.1_

- [ ] 3. Implement technical indicator management
  - [ ] 3.1 Create indicator handle management system
    - Implement Indicators_InitSymbol and Indicators_CleanupSymbol functions
    - Create ATR_D1, MA20_H1, and RSI_H1 indicator handles with error handling
    - Add IndicatorValues struct with caching and TTL management
    - _Requirements: 3.2, 3.3, 10.1_

  - [ ] 3.2 Implement indicator value retrieval with fallbacks
    - Code Indicators_GetATR, Indicators_GetMA20, Indicators_GetRSI functions
    - Add error handling for invalid handles and missing data
    - Implement cached value system with 15-minute TTL
    - _Requirements: 3.2, 10.1, 10.2_

  - [ ] 3.3 Add Opening Range tracking integration
    - Implement Indicators_UpdateOR function to track OR high/low from M5 bars
    - Add OR completion detection and statistics finalization
    - Integrate OR tracking with session management
    - _Requirements: 3.1, 8.2_

- [ ] 4. Implement session management and OR window lifecycle
  - [ ] 4.1 Extend session lifecycle management
    - Implement Sessions_ResetORStats, Sessions_InitializeSessionStats functions
    - Add Sessions_UpdateORStats for real-time OR tracking during first 60 minutes
    - Code Sessions_FinalizeORStats and Sessions_EndSession functions
    - _Requirements: 3.1, 3.5, 8.1, 8.2_

  - [ ] 4.2 Add session statistics and timing
    - Implement Sessions_GetStats, Sessions_GetORHigh, Sessions_GetORLow functions
    - Add session age tracking and session type identification
    - Code Sessions_ORWindowJustEnded detection logic
    - _Requirements: 3.1, 3.5, 8.2_

- [ ] 5. Implement risk management system
  - [ ] 5.1 Create position sizing calculations
    - Implement Risk_CalculatePositionSize with equity-based risk formula
    - Code Risk_GetValuePerPoint and Risk_NormalizeVolume functions
    - Add volume normalization to broker min/max/step constraints
    - _Requirements: 4.1, 4.2, 4.3_

  - [ ] 5.2 Implement margin guard system
    - Code Risk_CheckMarginGuard with 60% free margin threshold
    - Implement Risk_GetMarginRequired and Risk_ScaleVolumeForMargin functions
    - Add proportional volume scaling when margin limits exceeded
    - _Requirements: 7.1, 7.2, 7.3_

  - [ ] 5.3 Add risk aggregation functions
    - Implement Risk_GetOpenPositionRisk and Risk_GetPendingOrderRisk functions
    - Code Risk_CalculateWorstCaseRisk for proposed trades
    - Add error handling for invalid risk calculations
    - _Requirements: 5.1, 10.3_

- [ ] 6. Implement equity guardian and budget gates (SEQUENCED: Must complete before task 7)
  - [ ] 6.1 Create equity room calculations (FIRST)
    - Implement Equity_CalculateRooms with daily and overall loss cap formulas
    - Code baseline calculations using server midnight and initial account values
    - Add room sufficiency checking with MinRiskDollar threshold
    - **Rejection Reason**: "Insufficient equity room" when room < MinRiskDollar
    - _Requirements: 4.4, 4.5, 5.2_
    - Persist/recover initial_baseline and baseline_today to/from RPEA/state/challenge_state.json; re-anchor baseline_today at server midnight

  - [ ] 6.2 Implement budget gate enforcement (AFTER 6.1, 5.3)
    - Code Equity_CheckBudgetGate with 0.9x room utilization multiplier
    - Implement Equity_CheckSecondTradeRule with 0.8x multiplier for second trades
    - Add budget gate math: total_risk <= available_room
    - **Rejection Reason**: "Budget gate exceeded: total_risk X > available_room Y"
    - _Requirements: 5.1, 5.3, 5.5_

  - [ ] 6.3 Add floor monitoring and risk aggregation (AFTER 6.1)
    - Implement Equity_CheckFloors, Equity_IsAboveDailyFloor, Equity_IsAboveOverallFloor
    - Code Equity_GetOpenRisk, Equity_GetPendingRisk, Equity_GetTotalRisk functions
    - Add floor breach detection and trading pause logic
    - **Rejection Reason**: "Daily/Overall floor breached" with specific floor type
    - _Requirements: 5.2, 5.3_

- [ ] 7. Implement BWISC signal engine core (SEQUENCED: After task 6 completion)
  - [ ] 7.1 Create BTR, SDR, ORE calculation functions
    - Implement SignalsBWISC_CalculateBTR using yesterday's D1 OHLC data
    - Code SignalsBWISC_CalculateSDR using London open and MA20_H1 dislocation
    - Implement SignalsBWISC_CalculateORE using OR range and ATR normalization
    - **Rejection Reason**: "Signal calculation failed: [component] invalid"
    - _Requirements: 1.1, 1.2, 1.3_

  - [ ] 7.2 Implement bias calculation and setup determination
    - Code SignalsBWISC_CalculateBias with weighted component formula
    - Implement SignalsBWISC_DetermineSetup for BC/MSC setup identification
    - Add bias thresholds (0.6 for BC, 0.35 for MSC) and SDR requirements
    - **Rejection Reason**: "No setup: bias X below threshold Y" or "MSC: SDR X below 0.35"
    - _Requirements: 1.5, 2.1, 2.2, 2.3_

  - [ ] 7.3 Add RSI guard and target calculations
    - Implement RSI overextension guard with confidence penalty (50% reduction)
    - Code SignalsBWISC_CalculateTargets for BC (2.2R) and MSC (2.0R) setups
    - Add entry buffer and SL/TP distance calculations
    - **Rejection Reason**: "RSI overextension: RSI X, confidence reduced to Y"
    - _Requirements: 1.4, 2.4, 2.5_
    - Compute confidence_base = clamp(|bias|,0,1), apply penalties to obtain confidence; compute expected_R accordingly and include in BWISCSignal

  - [ ] 7.4 Create main signal evaluation function
    - Implement SignalsBWISC_Evaluate as main entry point
    - Integrate all component calculations with error handling
    - Add signal validation and confidence scoring
    - **Rejection Reason**: "Signal evaluation failed: [specific error]"
    - _Requirements: 1.1, 1.5, 10.1_

- [ ] 8. Implement allocator and order planning (SEQUENCED: After tasks 6 and 7)
  - [ ] 8.1 Create position and order cap checking (AFTER 6.x completion)
    - Implement Allocator_CheckPositionCaps with global and per-symbol limits
    - Code position and pending order counting functions
    - Add cap enforcement before order planning
    - **Rejection Reason**: "Position cap exceeded: X/Y positions" or "Pending cap exceeded: X/Y orders"
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [ ] 8.2 Implement margin guard integration (AFTER 5.2, 6.x)
    - Integrate Risk_CheckMarginGuard into allocation flow
    - Add margin-based volume scaling and rejection logic
    - Code margin threshold enforcement (60% free margin)
    - **Rejection Reason**: "Insufficient margin: required X, available Y" or "Volume scaled: X -> Y"
    - _Requirements: 7.1, 7.2, 7.3_

  - [ ] 8.3 Implement order plan generation (AFTER 8.1, 8.2)
    - Code Allocator_BuildOrderPlan with entry/SL/TP price calculations
    - Implement volume calculation integration with risk management
    - Add order type determination (market, limit, stop) based on setup
    - **Rejection Reason**: "Order plan failed: [specific calculation error]"
    - _Requirements: 2.4, 2.5, 4.1, 4.2_
    - Units & rounding: prices rounded to symbol digits; volumes normalized to SYMBOL_VOLUME_STEP; volumes clamped to min/max; distances converted to integer points; enforce MinStopPoints

  - [ ] 8.4 Create signal evaluation with cascading gates (FINAL INTEGRATION)
    - Implement Allocator_EvaluateSignal as main allocation entry point
    - **ENFORCE ORDER**: equity rooms → risk sizing → budget/position/margin gates → allocator plan
    - Integrate all risk gates in sequence with early termination on first failure
    - Add comprehensive rejection reason tracking with gate-specific messages
    - _Requirements: 5.1, 5.4, 6.4, 7.1_

- [ ] 9. Implement comprehensive logging and telemetry
  - [ ] 9.1 Create M2-specific logging functions
    - Implement LogSignalEvaluation, LogRiskCalculation, LogBudgetGate functions
    - Code LogPositionCaps, LogMarginGuard, LogSessionStats functions
    - Add proper CSV formatting with configured precision
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
    - Signal log fields: include confidence_base, confidence, expected_r, gate_reasons (comma-joined)

  - [ ] 9.2 Add error and warning logging
    - Implement LogIndicatorError, LogRiskError, LogAllocationError functions
    - Add structured error logging with component, severity, and recovery actions
    - Code log rotation and file management
    - _Requirements: 9.5, 10.4, 10.5_

- [ ] 10. Integrate with scheduler and session management
  - [ ] 10.1 Hook signal evaluation into scheduler
    - Modify Scheduler_Tick to call SignalsBWISC_Evaluate during sessions
    - Add session predicate checking (London/NY) before signal evaluation
    - Integrate OR window updates with session management
    - _Requirements: 8.1, 8.2, 8.3_

  - [ ] 10.2 Add session lifecycle integration
    - Hook session start to reset OR stats and initialize session tracking
    - Integrate OR window completion with signal calculations
    - Add session end cleanup and cutoff hour enforcement
    - _Requirements: 8.1, 8.3, 8.4_
  
  - [ ] 10.4 Enforce NY Gate during NY session evaluation
    - Allow NY only if realized day loss ≤ NYGatePctOfDailyCap × DailyLossCapPct of today's server-day baseline
    - Log gating reason when NY is skipped (e.g., GATE_NY_REALIZED_LOSS)
    - _Requirements: Scheduler governance alignment_

  - [ ] 10.3 Integrate news blocking and spread checking (ELEVATED PRIORITY)
    - **Concrete Thresholds**: MaxSpreadPoints = 40, NewsBufferS = 300 seconds
    - Create stub news provider interface with MQL5 Calendar API primary, CSV fallback
    - Implement test fakes for news provider (high-impact events, buffer windows)
    - Add spread checking: SymbolInfoInteger(SYMBOL_SPREAD) <= MaxSpreadPoints
    - Code comprehensive session gating: time windows + news + spread conditions
    - **Rejection Reasons**: "Spread too wide: X > 40 points", "News blocked: event at T±300s"
    - _Requirements: 8.4, 8.5_

- [ ] 11. Update main EA and configuration
  - Include config_m2.mqh in main RPEA.mq5 file
  - Add input parameter validation for M2 constants
  - Ensure backward compatibility with M1 interfaces
  - _Requirements: All requirements integration_

- [ ] 11.5. Setup CI/CD pipeline
  - Create GitHub Actions workflow for M2 validation
  - Add MQL5 compilation job with error checking
  - Implement unit test runner and header linting
  - Gate all M2 PRs on green CI status
  - **Done Criteria**: CI passes compilation, unit tests, and linting checks
  - _Requirements: Code quality and integration assurance_
  - Compile with MetaEditor command-line (self-hosted Windows/macOS runner or Dockerized Windows image); publish EX5/test logs; fail build on warnings

- [ ] 12. Create comprehensive unit tests with specialized fixtures
  - [ ] 12.1 Test signal calculation components with edge cases
    - Write unit tests for BTR, SDR, ORE calculations with known inputs
    - Test bias formula with various component combinations
    - Verify setup determination logic with boundary conditions
    - **Fixtures**: ATR≈0 fallback (use _Point floor), weekend gaps in D1 data
    - **Pass/Fail Criteria**: All calculations within 0.0001 tolerance of expected values
    - _Requirements: 1.1, 1.2, 1.3, 1.5, 2.1, 2.2_

  - [ ] 12.2 Test risk management with symbol variations
    - Write unit tests for position sizing formulas and volume normalization
    - Test margin guard calculations and volume scaling
    - Verify budget gate math and second trade rules
    - **Fixtures**: FX vs metals (different tick values: EURUSD 0.00001, XAUUSD 0.01)
    - **Pass/Fail Criteria**: Correct volume normalization per symbol properties
    - _Requirements: 4.1, 4.2, 5.1, 5.5, 7.1, 7.2_

  - [ ] 12.3 Test session and timing with DST scenarios
    - Write unit tests for OR calculations and session lifecycle
    - Test indicator handle management and error recovery
    - Verify session statistics and timing functions
    - **Fixtures**: DST flip days (server time changes), session boundary conditions
    - **Pass/Fail Criteria**: Correct session detection across DST transitions
    - _Requirements: 3.1, 3.2, 3.5, 8.1, 8.2_

  - [ ] 12.4 Test requirement mapping validation
    - Map each unit test to specific requirement acceptance criteria
    - Verify all 11 requirements have corresponding test coverage
    - Add pass/fail criteria tied back to requirement success metrics
    - **Pass/Fail Criteria**: 100% requirement coverage, all tests pass
    - _Requirements: All requirements validation_

- [ ] 13. Perform integration testing and validation
  - [ ] 13.1 Test end-to-end signal evaluation flow
    - Verify complete signal evaluation from scheduler to allocator
    - Test session lifecycle with OR window management
    - Validate risk gate cascade and rejection handling
    - _Requirements: All requirements integration_

  - [ ] 13.2 Strategy Tester validation with session logging
    - **Log Full Sessions**: Capture one complete London session (07:00-16:00) and one NY session (12:00-16:00)
    - **Verify OR Timing**: Confirm OR window tracks first 60 minutes, finalizes at session_start + 60min
    - **Hand-Calc Verification**: Validate bias math against manual calculations for 5 known setups
    - **Budget Gate Invariants**: Assert budget gates across two sequential trades in same session
      - First trade: total_risk <= 0.9 * min(room_today, room_overall)
      - Second trade: total_risk <= 0.8 * min(room_today, room_overall)
    - **Pass Criteria**: All timing matches expected, bias calculations accurate, budget invariants hold
    - _Requirements: All requirements validation_
    - Verify NY Gate logic blocks/permits NY per realized day loss vs baseline

  - [ ] 13.3 Strategy Tester error simulation
    - Test system behavior with simulated indicator failures
    - Verify graceful degradation with missing price data
    - Validate error recovery and fallback mechanisms
    - **Pass Criteria**: System continues operating, errors logged, no crashes
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_
