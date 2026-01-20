# M6 Task 04 -- Performance Profiling and Code Review Sweep

Branch name: `feat/m6-task04-perf-review` (cut from `feat/m6-hardening`)

Source of truth: `finalspec.md`, `prd.md`

## Objective
Add optional lightweight performance profiling for key loops and perform a focused code review sweep to reduce hot-loop overhead and log spam.

## Scope
- `MQL5/Include/RPEA/scheduler.mqh` (OnTimer cadence)
- `MQL5/Include/RPEA/order_engine.mqh` (order execution paths)
- `MQL5/Include/RPEA/logging.mqh` (throttled log patterns)
- `README.md` or `MQL5/Experts/FundingPips/README.md` if behavior changes

## Implementation Steps
1. **Add profiling toggle**
   - Introduce an input flag (e.g., `EnablePerfProfiling`) in `RPEA.mq5`.
   - Default to `false`.
   - If a new input is added, ensure Task01 validation remains accurate (no new invalid states).

2. **Instrument critical sections**
   - Use `GetMicrosecondCount()` to measure:
     - Scheduler tick work
     - Order execution paths
     - Any heavy calculations on session boundaries
   - Emit logs only when profiling is enabled and throttle output (e.g., aggregate and log once per N seconds).

3. **Throttle logging**
   - Avoid per-tick logs; use counters or time-based throttling.
   - Ensure profiling logs do not flood the journal.

4. **Review sweep**
   - Guard hot loops with early returns.
   - Remove redundant log lines or repeated string formatting.
   - Ensure expensive formatting is only done when needed.

5. **Documentation**
   - Note the profiling flag and intended usage.

## Tests
- No new unit tests required unless new logic is added that is testable.
- If a profiling utility is introduced, add a minimal smoke test only if feasible.

## Deliverables
- Profiling instrumentation guarded by a config flag.
- Reduced log spam in hot paths.
- Documentation update for profiling flag.

## Acceptance Checklist
- Profiling is off by default and low overhead.
- Logs do not spam per tick.
- Hot loops are guarded and readable.
- Docs mention the profiling flag if introduced.

## Hold Point
After changes are complete, stop and report results before merging back into `feat/m6-hardening`.
