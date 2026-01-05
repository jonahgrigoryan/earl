# Task 21 Dynamic Position Sizing Based on Confidence

## Understanding

-   **Current Behavior**:
    -   `risk.mqh`: `Risk_SizingByATRDistanceForSymbol` calculates trade volume using a fixed `riskPct` (passed as argument) relative to account equity. It does not currently account for signal confidence.
    -   `allocator.mqh`: `Allocator_BuildOrderPlan` receives a `confidence` score (0.0-1.0) from the signal engine but ignores it for risk sizing, passing the static `RiskPct` config value directly.
-   **Goal**: Scale the `riskPct` used in calculation by the `confidence` factor (`effective_risk = RiskPct * confidence`).
-   **Validation**: Confidence must be sanitized (clamped 0.0-1.0). **Critical**: NaN values must be handled explicitly (fail safe to 0.0).
-   **Integration**: The `availableRoom` (daily/overall loss cap headroom) check must happen *after* the confidence scaling to ensure the reduced risk trade still fits within limits.
-   **Testing**: A new test suite `test_risk_sizing.mqh` is required. Since we cannot easily mock `SymbolInfoDouble`, we will use a standard symbol like "EURUSD" for tests, assuming the test environment has basic symbol data.

## References & Inputs

-   `.kiro/specs/rpea-m3/tasks.md`: Task 21 definition.
-   `.kiro/specs/rpea-m3/requirements.md`: Req 9.1, 9.4 (Risk management).
-   `MQL5/Include/RPEA/risk.mqh`: Target file for logic changes.
-   `MQL5/Include/RPEA/allocator.mqh`: Target file for integration.
-   `Tests/RPEA/run_automated_tests_ea.mq5`: Test runner to update.

## End-to-End Implementation Steps

1.  **Modify Risk Sizing Logic (`risk.mqh`)**
    -   **Location**: `Risk_SizingByATRDistanceForSymbol` (lines 17-177).
    -   **Action**:
        -   Update signature: `double Risk_SizingByATRDistanceForSymbol(..., double confidence = 1.0)`
        -   **Sanitization** (add after parameter validation, before risk_money calculation):
            ```cpp
            // Defense-in-depth: sanitize confidence even though allocator may have sanitized it
            if(!MathIsValidNumber(confidence)) confidence = 0.0; // Fail safe for NaN
            double effective_conf = MathMin(MathMax(confidence, 0.0), 1.0); // Clamp to [0.0, 1.0]
            ```
        -   Calculate effective risk: `double effective_risk_pct = riskPct * effective_conf;`
        -   Update `risk_money` calculation: `double risk_money = equity * (effective_risk_pct / 100.0);`
        -   **Available Room**: The existing logic `if(availableRoom >= 0) risk_money = MathMin(risk_money, availableRoom);` (lines 58-68) must remain **unchanged**. It correctly caps the *result* of the risk calculation. Do not add new plumbing for this.
        -   **Logging**: Update `LogDecision` JSON payload (around line 162-174).
            -   **Current Format** (line 163): `"{\"symbol\":\"%s\",\"entry\":%.5f,\"stop\":%.5f,\"risk_money\":%.2f,\"sl_points\":%.2f,\"raw_volume\":%.4f,\"final_volume\":%.4f,\"margin_used_pct\":%.2f,\"room_cap\":%.2f,\"clamped\":%s}"`
            -   **Updated Format**: Insert `\"confidence\":%.2f,\"effective_risk_pct\":%.2f,` after `\"risk_money\":%.2f,` (4th field)
            -   **New Format**: `"{\"symbol\":\"%s\",\"entry\":%.5f,\"stop\":%.5f,\"risk_money\":%.2f,\"confidence\":%.2f,\"effective_risk_pct\":%.2f,\"sl_points\":%.2f,\"raw_volume\":%.4f,\"final_volume\":%.4f,\"margin_used_pct\":%.2f,\"room_cap\":%.2f,\"clamped\":%s}"`
            -   **StringFormat Arguments** (line 164-173): Insert `effective_conf` and `effective_risk_pct` after `risk_money` (4th argument), so the order becomes: `symbol, entry, stop, risk_money, effective_conf, effective_risk_pct, sl_points, raw_volume, final_volume, log_margin, room_cap, clamped`

2.  **Update Risk Wrapper (`risk.mqh`)**
    -   **Location**: `Risk_SizingByATRDistance` (lines 179-183).
    -   **Action**: Update signature to accept `double confidence = 1.0` and pass it through to `Risk_SizingByATRDistanceForSymbol`.

3.  **Integrate in Allocator (`allocator.mqh`)**
    -   **Location**: `Allocator_BuildOrderPlan` (around line 354).
    -   **Action**:
        -   Pass the `confidence` argument (received by `Allocator_BuildOrderPlan` at line 102) into `Risk_SizingByATRDistanceForSymbol` as the last parameter.
        -   **Note**: `allocator.mqh` already sanitizes confidence at line 452 (`sanitized_confidence`), but the risk function will also sanitize as defense-in-depth. Passing `confidence` as-is is fine since both layers handle validation.

4.  **Create Unit Tests (`Tests/RPEA/test_risk_sizing.mqh`)**
    -   **Location**: Create new file `Tests/RPEA/test_risk_sizing.mqh`.
    -   **Setup**:
        -   Include `RPEA/risk.mqh` and `RPEA/app_context.mqh`.
        -   **Symbol Data**: Use "EURUSD" for testing. Assume standard properties (`TICK_VALUE`, `TICK_SIZE`, `VOLUME_STEP`) are available. If `SymbolInfoDouble("EURUSD", ...)` fails in the test environment, use a fallback hardcoded calculation or `Test_SetSymbolInfo` if you can find/create a helper, but "EURUSD" is the standard expectation.
    -   **Test Cases**:
        -   `Test_Risk_Confidence_1_0`: `RiskPct`=1.0, `Conf`=1.0 -> Expect baseline volume.
        -   `Test_Risk_Confidence_0_5`: `RiskPct`=1.0, `Conf`=0.5 -> Expect ~50% volume.
        -   `Test_Risk_Confidence_0_0`: `Conf`=0.0 -> Expect 0 volume.
        -   `Test_Risk_Confidence_NaN`: `Conf`=NaN -> Expect 0 volume (Safe fail).
        -   `Test_Risk_Confidence_Clamp_High`: `Conf`=1.5 -> Expect same as 1.0.
        -   `Test_Risk_Confidence_Clamp_Low`: `Conf`=-0.5 -> Expect 0 volume.
        -   `Test_Risk_Default`: Call without `confidence` param -> Expect 1.0 behavior.

5.  **Register Test Suite (`run_automated_tests_ea.mq5`)**
    -   **Location**: `Tests/RPEA/run_automated_tests_ea.mq5`.
    -   **Action**:
        -   Add `#include "test_risk_sizing.mqh"` after line 85 (with other test includes).
        -   In `RunAllTests()` (after Task 17 suite, around line 337):
            ```cpp
            // Task 21: Dynamic Position Sizing Based on Confidence
            int suite21 = g_test_reporter.BeginSuite("Task21_Risk_Sizing");
            bool task21_result = TestRiskSizing_RunAll();
            g_test_reporter.RecordTest(suite21, "TestRiskSizing_RunAll", task21_result,
                                       task21_result ? "All risk sizing tests passed" : "Some risk sizing tests failed");
            g_test_reporter.EndSuite(suite21);
            ```

6.  **Validation via Strategy Tester**
    -   **Action**: Run `run_automated_tests_ea.mq5` in Strategy Tester.
    -   **Check**:
        -   `test_results.json`: Confirm Task 21 suite passed.
        -   `MQL5/Files/RPEA/logs/decision_*.log`: Verify `Risk` entries show `confidence` and `effective_risk_pct`.

## Questions & Answers

1.  **Where to pass confidence?** In `Allocator_BuildOrderPlan` (allocator.mqh), pass it as the last argument to `Risk_SizingByATRDistanceForSymbol`.
2.  **Wrapper vs New?** Modify `Risk_SizingByATRDistanceForSymbol` directly with an optional parameter `double confidence = 1.0`. Update the wrapper `Risk_SizingByATRDistance` to match.
3.  **Formula Implementation?** `effective_risk = riskPct * MathMin(MathMax(confidence, 0.0), 1.0)`.
4.  **Invalid Confidence?** **NaN must be handled**: `if(!MathIsValidNumber(confidence)) confidence = 0.0;`. Then clamp [0.0, 1.0].
5.  **Integration with `availableRoom`?** **No change needed.** The existing logic caps `risk_money` *after* it is calculated. This is correct. Do not modify `availableRoom` handling.
6.  **Unit Tests?** New file `Tests/RPEA/test_risk_sizing.mqh`. Use "EURUSD" for symbol data.
7.  **Logging/Audit?** Update `LogDecision` string format to include `confidence` and `effective_risk_pct`. No changes to audit CSVs.

## Implementation TODOs

- [ ] `MQL5/Include/RPEA/risk.mqh`: Update `Risk_SizingByATRDistanceForSymbol` signature, add NaN check, implement scaling, update `LogDecision` format.
- [ ] `MQL5/Include/RPEA/risk.mqh`: Update `Risk_SizingByATRDistance` wrapper.
- [ ] `MQL5/Include/RPEA/allocator.mqh`: Pass confidence in `Allocator_BuildOrderPlan`.
- [ ] `Tests/RPEA/test_risk_sizing.mqh`: Create test file with NaN and clamp tests.
- [ ] `Tests/RPEA/run_automated_tests_ea.mq5`: Register and run the new test suite.

## Acceptance Criteria Recap

-   **Scaled Risk**: Verified by unit tests showing volume scales linearly with confidence.
-   **Clamping & Safety**: Verified by unit tests with inputs 1.5, -0.5, and NaN.
-   **Logging**: Verified by manual inspection of logs after test run.
-   **Backward Compatibility**: Verified by `Test_Risk_Default` case.
