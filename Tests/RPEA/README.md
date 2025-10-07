# RPEA Order Engine Tests

This directory contains the M3 Task 1 unit tests for the Order Engine scaffolding.

## Test Files

### test_order_engine.mqh
Spec-compliant test suite covering initialization, five-event sequencing, execution lock handling, queued-action TTL, and state reconciliation. Tests follow the `test_risk.mqh` macro pattern and expose the `TestOrderEngine_RunAll()` entry point.

### run_order_engine_tests.mq5
Script runner that loads `test_order_engine.mqh`, executes `TestOrderEngine_RunAll()`, and reports pass/fail status in the MetaTrader log.

## Usage

### In MetaEditor
1. Open `run_order_engine_tests.mq5`
2. Compile the script (F7)
3. Run the script in MetaTrader 5

### From MetaTrader 5
1. Go to Navigator -> Scripts
2. Locate `run_order_engine_tests`
3. Drag to a chart or double-click to execute

## Expected Output

- PASS/FAIL lines for each assertion
- Event-order validation confirming trade transactions precede timer housekeeping
- Summary totals with pass/fail counts and an overall status message

## Notes

- Tests assume the Order Engine scaffolding from M3 Task 1 is present.
- Stubs for later tasks still return defaults; corresponding assertions are aware of current behavior.
- The runner returns `false` when any assertion fails so CI scripts can act on the result.
