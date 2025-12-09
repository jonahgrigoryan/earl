# Task 22: Add Spread Filter to Liquidity Check - Implementation Outline

## Goal
Implement a dynamic spread filter in the Liquidity module to reject trades when the current spread exceeds a configurable fraction of the daily ATR. This protects the strategy from executing during periods of poor liquidity.

**Formula**: `MaxSpread = ATR(D1) * SpreadMultATR`
**Default**: `0.005` (0.5% of Daily ATR)

---

## 1. Input Wiring
**Files**: `MQL5/Experts/FundingPips/RPEA.mq5`, `MQL5/Include/RPEA/config.mqh`

- [ ] **Update `RPEA.mq5`**:
    - Add input parameter in the "Risk & governance" section (around line 68):
        ```cpp
        input double SpreadMultATR = 0.005; // Max spread as fraction of Daily ATR
        ```

- [ ] **Update `config.mqh`**:
    - Add default macro:
        ```cpp
        #define DEFAULT_SpreadMultATR 0.005
        ```
    - Add getter function with robust guard:
        ```cpp
        inline double Config_GetSpreadMultATR()
        {
        #ifdef RPEA_TEST_RUNNER
           // In test runner, inputs are defined as macros.
           // Guard against missing macro definition.
           #ifdef SpreadMultATR
              return SpreadMultATR;
           #else
              return DEFAULT_SpreadMultATR;
           #endif
        #else
           // In EA, inputs are global variables visible to included files.
           return SpreadMultATR;
        #endif
        }
        ```

---

## 2. Liquidity Module Implementation
**File**: `MQL5/Include/RPEA/liquidity.mqh`

- [ ] **Update `Liquidity_SpreadOK`**:
    - **Signature**: `bool Liquidity_SpreadOK(const string symbol, double &out_spread, double &out_threshold)`
    - **Dependencies**: Include `config.mqh`, `indicators.mqh`, `logging.mqh`.
    - **Logic**:
        1.  Get `SpreadMultATR` via `Config_GetSpreadMultATR()`.
        2.  Get Spread and Point:
            - `long spread_pts = SymbolInfoInteger(symbol, SYMBOL_SPREAD);`
            - `double point = SymbolInfoDouble(symbol, SYMBOL_POINT);`
            - `out_spread = spread_pts * point;`
        3.  Get ATR:
            - Use `Indicators_GetSnapshot(symbol, snapshot)`.
            - `double atr = snapshot.atr_d1;`
        4.  Calculate Threshold:
            - `out_threshold = atr * SpreadMultATR;`
        5.  **Check**:
            - If `atr <= 0` or `point <= 0`:
                - **Log**: `LogDecision("Liquidity", "WARNING", "ATR/Point unavailable, allowing trade");`
                - Return `true` (fail open).
            - If `out_spread > out_threshold`:
                - **Log**: `LogDecision("Liquidity", "GATED", StringFormat("Spread too wide: %d pts (%.5f) vs ATR %.5f (threshold %.5f)", spread_pts, out_spread, atr, out_threshold));`
                - Return `false`.
            - Return `true`.

---

## 3. Scheduler Integration
**File**: `MQL5/Include/RPEA/scheduler.mqh`

- [ ] **Update `Scheduler_Tick`**:
    - **Location**: Around line 37 where `Liquidity_SpreadOK(sym)` is currently called.
    - **Change**:
        ```cpp
        double spread_val=0.0, spread_thresh=0.0;
        bool spread_ok = Liquidity_SpreadOK(sym, spread_val, spread_thresh);
        ```
    - **Logging**: Update the `note` JSON string to include spread details if useful.

---

## 4. Allocator Integration
**File**: `MQL5/Include/RPEA/allocator.mqh`

- [ ] **Modify `Allocator_BuildOrderPlan`**:
    - **Location**: Before `Risk_SizingByATRDistanceForSymbol` (around line 354).
    - **Logic**:
        ```cpp
        double spread_val=0.0, spread_thresh=0.0;
        if(rejection == "" && !Liquidity_SpreadOK(exec_symbol, spread_val, spread_thresh))
        {
           rejection = "spread_filter";
        }
        ```

---

## 5. Unit Testing
**File**: `Tests/RPEA/test_liquidity.mqh` (New File)

- [ ] **Mocking Strategy**:
    - Use preprocessor macros to intercept API calls **before** including `liquidity.mqh`.
    - **Mocks Needed**: `SymbolInfoInteger`, `SymbolInfoDouble`, `Indicators_GetSnapshot`.
    - **Implementation**:
        ```cpp
        // Mock State
        long g_mock_spread = 10;
        double g_mock_point = 0.00001;
        double g_mock_atr = 0.0100;
        
        // Mock Functions
        long MockSymbolInfoInteger(string s, ENUM_SYMBOL_INFO_INTEGER p) { return g_mock_spread; }
        double MockSymbolInfoDouble(string s, ENUM_SYMBOL_INFO_DOUBLE p) { return g_mock_point; }
        bool MockIndicators_GetSnapshot(string s, IndicatorSnapshot &out) { 
            out.atr_d1 = g_mock_atr; 
            return true; 
        }
        
        // Inject Mocks
        #define SymbolInfoInteger MockSymbolInfoInteger
        #define SymbolInfoDouble MockSymbolInfoDouble
        #define Indicators_GetSnapshot MockIndicators_GetSnapshot
        
        #include <RPEA/liquidity.mqh>
        
        // CLEANUP MOCKS
        #undef SymbolInfoInteger
        #undef SymbolInfoDouble
        #undef Indicators_GetSnapshot
        ```

- [ ] **Test Cases**:
    - **Test 1: Normal Spread**: `spread=20pts`, `ATR=1000pts` (0.0100), `Mult=0.005` -> `Thresh=50pts`. Result: `true`.
    - **Test 2: Wide Spread**: `spread=60pts`, `ATR=1000pts`, `Mult=0.005` -> `Thresh=50pts`. Result: `false`.
    - **Test 3: Zero ATR**: `ATR=0`. Result: `true` (Fail Open).

---

## 6. Test Harness Registration
**File**: `Tests/RPEA/run_automated_tests_ea.mq5`

- [ ] **Add Input Macro**:
    - Add `#define SpreadMultATR 0.005` to the inputs section (around line 40).

- [ ] **Register Suite**:
    - Add `#include "test_liquidity.mqh"` alongside other includes (around line 86).
    - In `RunAllTests()`:
        ```cpp
        Print("=================================================================");
        Print("RPEA Liquidity Filter Tests - Task 22");
        Print("=================================================================");
        int suite22 = g_test_reporter.BeginSuite("Task22_Liquidity_Filter");
        bool task22_result = TestLiquidity_RunAll();
        g_test_reporter.RecordTest(suite22, "TestLiquidity_RunAll", task22_result,
                                    task22_result ? "Liquidity filter tests passed" : "Liquidity filter tests failed");
        g_test_reporter.EndSuite(suite22);
        ```

---

## 7. Verification
- [ ] **Compile**: Ensure `run_automated_tests_ea.mq5` compiles with the new macro and include.
- [ ] **Test**: Run `run_automated_tests_ea` in Strategy Tester.
- [ ] **Audit**: Verify `rejection_reason="spread_filter"` appears in logs when spread is wide.
