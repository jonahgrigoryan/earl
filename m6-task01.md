# M6 Task 01 -- Parameter Validation

Branch name: `feat/m6-task01-parameter-validation` (cut from `feat/m6-hardening`)

Source of truth: `finalspec.md`, `prd.md`

## Objective
Add explicit input validation for EA inputs with consistent rules: clamp non-critical ranges, fail fast on invalid enums or impossible configurations. Validation runs early in `OnInit` before any trading logic.

## Scope
- Inputs defined/consumed in `MQL5/Experts/FundingPips/RPEA.mq5`
- Validation helpers in `MQL5/Include/RPEA/config.mqh` (or a small new module under `MQL5/Include/RPEA/`)
- Tests under `Tests/RPEA/`

## Implementation Steps
1. **Inventory all inputs**
   - List inputs in `RPEA.mq5`, plus any derived config values used across modules.
   - Categorize into: enums/flags, numeric ranges, risk caps, session windows, leverage overrides.

2. **Define validation rules**
   - Enums/flags: fail fast on invalid values (log and return `INIT_FAILED`).
   - Numeric ranges: clamp to safe bounds with explicit log.
   - Impossible configs: fail fast (e.g., `DailyLossCapPct <= 0`, `OverallLossCapPct <= 0`, `TargetProfitPct <= 0`, `InpSymbols` empty).

3. **Implement helper API**
   - Add a validation function (e.g., `Config_ValidateInputs(...)`) in `config.mqh`.
   - Return a `bool` for pass/fail and emit log entries for every correction.
   - Prefix log lines with `[Config]` and include key, invalid value, and action (clamped/rejected).

4. **Apply validation early**
   - Call validation at the top of `OnInit` in `RPEA.mq5` before any runtime setup.
   - On failure, return `INIT_FAILED` with a clear log trail.
   - Keep existing XAUEUR proxy checks intact; do not duplicate those validations.

5. **Specific checks to cover**
   - `ORMinutes` must be one of `{30,45,60,75}`:
     - Clamp to nearest allowed value with a `[Config]` log.
   - Risk caps: `DailyLossCapPct` and `OverallLossCapPct` must be > 0.
     - If `OverallLossCapPct < DailyLossCapPct`, clamp `DailyLossCapPct` down to match `OverallLossCapPct` and log it.
   - `TargetProfitPct` > 0.
   - `MinTradeDaysRequired` >= 1 (keep Micro-Mode assumptions intact).
   - `RiskPct`, `MicroRiskPct`, `RtargetBC`, `RtargetMSC`, `SLmult`, `TrailMult`, `GivebackCapDayPct`, `OneAndDoneR`:
     - Clamp to the ranges defined in `finalspec.md` (or the M5 optimization ranges) when specified.
     - Otherwise clamp to a safe positive minimum with a log.
   - Session hours: `StartHourLO`, `StartHourNY`, `CutoffHour` in `[0, 23]` (clamp).
   - Time windows: `MicroTimeStopMin` clamps to `[30, 60]`; `MinHoldSeconds`, `NewsBufferS`, `QueueTTLMinutes`,
     `StabilizationTimeoutMin`, `NewsCalendarLookbackHours` must be >= 0; `StabilizationBars`,
     `StabilizationLookbackBars`, `NewsCalendarLookaheadHours` must be >= 1 (clamp).
   - Spread/slippage: `MaxSlippagePoints`, `MaxSpreadPoints` must be >= 0 (clamp); `SpreadMultATR` must be > 0
     (clamp to default).
   - Queue/logging: `MaxQueueSize` and `LogBufferSize` must be >= 1 (clamp to defaults).
   - Leverage overrides: allow 0 (use account); if > 0 then clamp to `[1, 1000]` and log.
   - `InpSymbols` must not be empty; fail fast if empty.
   - Position/order caps: `MaxOpenPositionsTotal`, `MaxOpenPerSymbol`, `MaxPendingsPerSymbol` must be >= 0 (0 = unlimited).

## Tests
1. Create `Tests/RPEA/test_config_validation.mqh`.
2. Add scenarios for:
   - Valid inputs pass without changes.
   - Out-of-range numeric values are clamped with expected outcomes.
   - Invalid enums/flags fail fast.
   - `ORMinutes` handling (clamps to nearest allowed value).
   - `OverallLossCapPct < DailyLossCapPct` clamps daily down and logs the correction.
3. Wire test suite into `Tests/RPEA/run_automated_tests_ea.mq5`.

## Deliverables
- Validation logic in `config.mqh` (or new module).
- `OnInit` calls validation before any trading logic.
- New test suite for config validation.

## Acceptance Checklist
- Inputs are validated once on init with clear logs.
- Invalid enums/impossible configs fail fast.
- Non-critical range errors are clamped with `[Config]` logs.
- Tests pass and cover clamp + fail-fast paths.

## Hold Point
After tests pass locally, stop and report results before merging back into `feat/m6-hardening`.
