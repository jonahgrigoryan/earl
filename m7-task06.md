# M7 Task 06 - Telemetry + Regime Detection Implementation

**Branch name**: Use the Phase 5 branch cut from `feat/m7-ensemble-integration` (e.g., `feat/m7-phase5-integration` per phase-branch convention).

**Source of truth**: `docs/m7-final-workflow.md` (Phase 5, Task 6, Steps 6.1-6.4). Steps 6.5-6.6 below are local integration notes for scheduler/order-engine wiring.

**Previous tasks completed**: Tasks 1-5 (EMRT, RL Agent, SignalMR, Pre-training, Meta-Policy)

## Objective

Implement Phase 5 Task 6: add market regime detection, enhanced meta-policy telemetry, and liquidity quantile gating. This provides decision context (trend/range/volatile), logs structured meta-policy decisions, and ensures unsafe liquidity conditions can gate entries before allocator execution is enabled in Task 7.

## Prerequisites

- **Task 5 (Meta-Policy)**: `MetaPolicy_Choose()` exists with decision-only gate enabled.
- **Phase 0 helpers**: `M7_GetATR_D1()`, `M7_GetATR_D1_Percentile()` from `m7_helpers.mqh`.
- **Logging**: `LogDecision()` from `logging.mqh`.
- **Indicator snapshot**: `Indicators_GetSnapshot()` from `indicators.mqh`.

## Files to Modify / Create

- `MQL5/Include/RPEA/regime.mqh` (extend stub with detection logic)
- `MQL5/Include/RPEA/telemetry.mqh` (add `LogMetaPolicyDecision`)
- `MQL5/Include/RPEA/liquidity.mqh` (rolling stats + quantile getters)
- `MQL5/Include/RPEA/meta_policy.mqh` (wire regime/quantiles + telemetry call)
- `MQL5/Include/RPEA/scheduler.mqh` (feed `Liquidity_UpdateStats` on each tick)
- `MQL5/Include/RPEA/order_engine.mqh` (feed slippage into stats when available)
- `Tests/RPEA/test_regime_telemetry.mqh` (new unit tests)
- `Tests/RPEA/run_automated_tests_ea.mq5` (register new test suite)

## Workflow

1. Implement code updates in repo workspace (`C:\Users\AWCS\earl-1`).
2. Sync files to MT5 data folder via `SyncRepoToTerminal.ps1`.
3. Compile EA to ensure MQL5 code compiles.
4. Run automated tests and verify new suite.

## Implementation Steps

### Step 6.1: Regime Detection (regime.mqh)

**Reference**: `docs/m7-final-workflow.md` -> Phase 5 -> Task 6 -> Step 6.1

Implement `REGIME_LABEL` enum and detection logic using ATR percentile + ADX:

- Add includes: `<RPEA/indicators.mqh>`, `<RPEA/m7_helpers.mqh>`, `<RPEA/app_context.mqh>`.
- Define:
  - `REGIME_UNKNOWN = 0`
  - `REGIME_TRENDING = 1`
  - `REGIME_RANGING = 2`
  - `REGIME_VOLATILE = 3`
- Cache ADX handle per active symbol (`g_adx_handle` + `g_adx_symbol`), re-init/release if symbol changes (call `IndicatorRelease()` before opening a new handle), and implement:
  - `bool Regime_Init(const string symbol)`
  - `double Regime_GetADX(const string symbol)`
  - `REGIME_LABEL Regime_Detect(const AppContext &ctx, const string symbol)`
    - If `atr_pct > 0.75` -> `REGIME_VOLATILE`
    - Else if `adx > 25.0` -> `REGIME_TRENDING`
    - Else -> `REGIME_RANGING`

**Compatibility**:
- Keep `Regime_Label()` and `Regime_Features()` for backward compatibility.
- Add `Regime_LabelCtx(const AppContext &ctx, const string symbol)` that maps `Regime_Detect(ctx, symbol)` to a string label.
- Keep the legacy `Regime_Label(const string symbol)` as a safe fallback (e.g., returns `"unknown"`) or call `Regime_LabelCtx(g_ctx, symbol)` only if you intentionally rely on the global context.

**Compile checkpoint**: Regime module compiles and returns safe defaults if indicators are missing.

### Step 6.2: Enhanced Telemetry (telemetry.mqh)

**Reference**: `docs/m7-final-workflow.md` -> Phase 5 -> Task 6 -> Step 6.2

Add `LogMetaPolicyDecision(...)` function using `LogDecision()` with required fields:

Required audit fields:
- `confidence`, `efficiency`, `rho_est`, `hold_time`, `gating_reason`, `news_window_state`
- Also include: `symbol`, `choice`, `bwisc_conf`, `mr_conf`, `bwisc_eff`, `mr_eff`, `emrt`, `spread_q`, `slippage_q`, `regime`

**Notes**:
- Prefer computing `hold_time_min` and `rho_est` in `meta_policy.mqh` and pass them into telemetry to keep `telemetry.mqh` lightweight.
- If you compute them inside `LogMetaPolicyDecision()`, include `<RPEA/emrt.mqh>` and `<RPEA/config.mqh>` in `telemetry.mqh` (in addition to `<RPEA/logging.mqh>` and `<RPEA/regime.mqh>`).
- Populate `confidence` / `efficiency` as the chosen strategy's values (`BWISC` or `MR`). Use `0.0` when choice is `"Skip"`.
- Use `Config_GetCorrelationFallbackRho()` for `rho_est` (until a live correlation estimator exists).
- Use strategy-based `hold_time_min`:
  - `MR`: `(int)MathRound(EMRT_GetP50("XAUEUR"))`
  - `BWISC`: `(int)MathRound(MathMax((double)Config_GetORMinutes(), 45.0))`
  - `Skip`: `0`
- Emit `hold_time_min` in minutes to satisfy the required `hold_time` audit field.
- Use `REGIME_LABEL` -> string label mapping in telemetry.
- Log via `LogDecision("MetaPolicy", "EVAL", fields)`.

**Compile checkpoint**: Telemetry compiles and uses existing logging infrastructure.

### Step 6.3: Liquidity Quantiles (liquidity.mqh)

**Reference**: `docs/m7-final-workflow.md` -> Phase 5 -> Task 6 -> Step 6.3

Extend liquidity module to maintain rolling stats and quantile getters:

**API**:
- Update the existing stub signature from `void Liquidity_UpdateStats(const string symbol)` to:
  - `bool Liquidity_UpdateStats(const string symbol, double spread_pts, double slippage_pts);`
- `double Liquidity_GetSpreadQuantile(const string symbol);`
- `double Liquidity_GetSlippageQuantile(const string symbol);`

**Implementation guidance**:
- Track rolling window per symbol (e.g., last 200 samples).
- Ignore invalid values (NaN). Treat `spread_pts <= 0` as invalid. Treat `slippage_pts < 0` as invalid (0 is valid and should be retained).
- Return `0.5` when no data is available (safe default).
- Quantile = rank percentile of current value in the window (clamped to [0,1]).

**Compile checkpoint**: Liquidity helpers compile and return safe defaults when no stats exist.

### Step 6.4: Efficiency Tracking (meta_policy.mqh or telemetry.mqh)

**Reference**: `docs/m7-final-workflow.md` -> Phase 5 -> Task 6 -> Step 6.4

Add efficiency helpers with safe defaults:
- `double MetaPolicy_GetBWISCEfficiency();`
- `double MetaPolicy_GetMREfficiency();`

**Guidance**:
- Return `0.0` until a real rolling efficiency tracker exists.
- Use these helpers to populate `mpc.bwisc_efficiency` and `mpc.mr_efficiency` in `MetaPolicy_Choose`.

**Compile checkpoint**: Efficiency helpers compile and return safe defaults.

### Step 6.5: Wire Quantiles + Regime into Meta-Policy (meta_policy.mqh)

- Ensure includes exist:
  - `<RPEA/liquidity.mqh>`
  - `<RPEA/regime.mqh>`
  - `<RPEA/telemetry.mqh>`
- Replace placeholder values:
  - `mpc.spread_quantile = Liquidity_GetSpreadQuantile(symbol)`
  - `mpc.slippage_quantile = Liquidity_GetSlippageQuantile(symbol)`
  - `mpc.regime_label = Regime_Detect(ctx, symbol)`
  - `mpc.bwisc_efficiency = MetaPolicy_GetBWISCEfficiency()`
  - `mpc.mr_efficiency = MetaPolicy_GetMREfficiency()`
- Determine `news_window_state` for telemetry:
  - `news_window_state = News_GetWindowStateDetailed(symbol, false)` (non-protective entry context)
- Determine `gating_reason` with an explicit rule mapping (mirror deterministic rules):
  - Rule 0: `entry_blocked` -> `"RULE_0_ENTRY_BLOCKED"`
  - Rule 0b: spread/slippage quantile gate -> `"RULE_0B_LIQUIDITY_Q"`
  - Rule 1: session cap -> `"RULE_1_SESSION_CAP"`
  - Rule 2: MR lock -> `"RULE_2_MR_LOCK"`
  - Rule 3: confidence tie -> `"RULE_3_CONF_TIE"`
  - Rule 4: BWISC replacement -> `"RULE_4_BWISC_REPLACE"`
  - Rule 5: BWISC qualified -> `"RULE_5_BWISC"`
  - Rule 6: MR fallback -> `"RULE_6_MR_FALLBACK"`
  - Default (no setups): `"SKIP_NO_SETUP"`
- Ensure `gating_reason` is set even when `hard_blocked` short-circuits bandit selection.
- If bandit selection is enabled in a later phase, set a distinct reason such as `"BANDIT_CHOICE"` (and optionally include the bandit policy in telemetry).
- Compute telemetry scalars before logging:
  - `rho_est = Config_GetCorrelationFallbackRho()`
  - `hold_time_min` based on choice (see Step 6.2 notes)
  - `confidence` / `efficiency` based on chosen strategy
- Call `LogMetaPolicyDecision(...)` inside the decision-only block (before returning `"Skip"`).
- Keep `M7_DECISION_ONLY` enabled in Task 6 (no execution yet).

**Compile checkpoint**: Meta-policy compiles with telemetry wiring and explicit gating reasons.

### Step 6.6: Feed Liquidity Stats (scheduler.mqh, order_engine.mqh)

**Scheduler**:
- Immediately after `bool spread_ok = Liquidity_SpreadOK(sym, spread_val, spread_thresh);`, compute spread points and call:
  - `double point = SymbolInfoDouble(sym, SYMBOL_POINT);`
  - `double spread_pts = (point > 0.0 ? spread_val / point : (double)SymbolInfoInteger(sym, SYMBOL_SPREAD));`
  - `Liquidity_UpdateStats(sym, spread_pts, -1.0);`

**Order Engine (recommended)**:
- In `ExecuteOrderWithRetry(...)` after `executed_slippage_pts` is computed on success, call:
  - `Liquidity_UpdateStats(request.symbol, -1.0, executed_slippage_pts);`
- Optional: if slippage is rejected, you may also record `last_slippage_points` (if > 0).

This makes quantiles real rather than constant defaults.

**Compile checkpoint**: Scheduler + order engine compile with Liquidity_UpdateStats callsites updated.

## Tests (Recommended)

Even though the workflow does not mandate tests, adding a light test suite validates safe defaults and wiring.

### New tests: `Tests/RPEA/test_regime_telemetry.mqh`

Suggested test cases:
- **Regime_DefaultRanging**: With neutral ATR percentile and no ADX, `Regime_Detect()` returns `REGIME_RANGING`.
- **Liquidity_DefaultQuantiles**: `Liquidity_GetSpreadQuantile()` and `Liquidity_GetSlippageQuantile()` return `0.5` with no stats.
- **Telemetry_Smoke**: Call `LogMetaPolicyDecision()` with dummy values (assert no failure).

### Register in runner

Update `Tests/RPEA/run_automated_tests_ea.mq5`:
- Add `#include "test_regime_telemetry.mqh"`
- Add forward declaration: `bool TestRegimeTelemetry_RunAll();`
- Add suite execution block immediately after the `M7-Task05: Meta-Policy Tests` block (after `TestMetaPolicy_RunAll()`).

## Compile / Test Checklist

1. Sync repo to MT5:
   - `powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1`
2. Compile EA (run from MT5 data folder or use full path to MetaEditor):
   - `& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log`
3. Run tests:
   - `powershell -ExecutionPolicy Bypass -File run_tests.ps1`
4. Verify results:
   - `MQL5/Files/RPEA/test_results/test_results.json` includes Task 06 suite
   - `compile_rpea.log` shows 0 errors

## File Sync Mappings (Repo -> MT5)

Use `SyncRepoToTerminal.ps1`, but ensure these files map to the MT5 data folder:

- `C:\Users\AWCS\earl-1\MQL5\Include\RPEA\regime.mqh`
  -> `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Include\RPEA\regime.mqh`
- `C:\Users\AWCS\earl-1\MQL5\Include\RPEA\telemetry.mqh`
  -> `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Include\RPEA\telemetry.mqh`
- `C:\Users\AWCS\earl-1\MQL5\Include\RPEA\liquidity.mqh`
  -> `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Include\RPEA\liquidity.mqh`
- `C:\Users\AWCS\earl-1\MQL5\Include\RPEA\meta_policy.mqh`
  -> `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Include\RPEA\meta_policy.mqh`
- `C:\Users\AWCS\earl-1\MQL5\Include\RPEA\scheduler.mqh`
  -> `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Include\RPEA\scheduler.mqh`
- `C:\Users\AWCS\earl-1\MQL5\Include\RPEA\order_engine.mqh`
  -> `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Include\RPEA\order_engine.mqh`
- `C:\Users\AWCS\earl-1\Tests\RPEA\test_regime_telemetry.mqh`
  -> `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\Tests\RPEA\test_regime_telemetry.mqh`
- `C:\Users\AWCS\earl-1\Tests\RPEA\run_automated_tests_ea.mq5`
  -> `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\Tests\RPEA\run_automated_tests_ea.mq5`

## Results

- Compile (MetaEditor): 0 errors, 5 warnings.
- Warning: `logging.mqh(12,9)` macro `LEGACY_LOG_FLUSH_THRESHOLD` redefinition
- Warning: `breakeven.mqh(12,9)` macro `BREAKEVEN_TRIGGER_R_MULTIPLE` redefinition
- Warning: `breakeven.mqh(13,9)` macro `EPS_SL_CHANGE` redefinition
- Warning: `queue.mqh(131,34)` possible loss of data due to type conversion from `ushort` to `uchar`
- Warning: `rl_agent.mqh(200,24)` sign mismatch
- Tests: `test_results.json` timestamp `2026-02-03T10:43:41Z` shows 33/33 passed, `M7Task06_RegimeTelemetry` passed.
