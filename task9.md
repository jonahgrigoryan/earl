# Task 9: Budget Gate with Position Snapshot Locking - Implementation Plan

## Goal

Implement budget gate validation with locked position snapshots, exact formula implementation, and complete logging per Task 9 acceptance criteria. Support runtime input parameters with config defaults as fallback.

## Current State

- Budget gate exists in `equity_guardian.mqh` (`Equity_EvaluateBudgetGate`)
- Missing: snapshot locking, proper logging (5 inputs + gate_pass + gating_reason), RiskGateHeadroom config
- Hardcoded 0.9 multiplier, logs "approved" instead of "gate_pass"
- Logs only 4 inputs (missing separate room_today and room_overall)

## Implementation Steps

### Step 1: Add Input Parameters to RPEA.mq5

**File**: `MQL5/Experts/FundingPips/RPEA.mq5`

- Add inputs near other compliance settings:
- `input int BudgetGateLockMs = 1000;`
- `input double RiskGateHeadroom = 0.90;`
- Ensure headers expose these as externs for downstream usage

### Step 2: Add Default Constants (Fallback)

**File**: `MQL5/Include/RPEA/config.mqh`

- Retain existing `DEFAULT_BudgetGateLockMs` (line 96)
- Add `#define DEFAULT_RiskGateHeadroom 0.90` after line 96
- These serve as fallback when inputs are unset

### Step 3: Add Snapshot Structure and Lock State Variables

**File**: `MQL5/Include/RPEA/equity_guardian.mqh`

- After line 50 (after `g_equity_pending_risk`), add:
- `struct BudgetGateSnapshot` with fields:
 - `datetime snapshot_time`
 - `double open_risk`
 - `double pending_risk`
 - `double room_today` (captured during snapshot)
 - `double room_overall` (captured during snapshot)
 - Arrays of structs for positions/pendings:
 - `struct PositionSnapshot { string symbol; ENUM_POSITION_TYPE type; double volume; double price_open; double sl; ulong ticket; }`
 - `struct PendingSnapshot { string symbol; ENUM_ORDER_TYPE type; double volume; double price; double sl; ulong ticket; }`
 - `PositionSnapshot position_snapshots[]`
 - `PendingSnapshot pending_snapshots[]`
 - `bool is_locked`
- Static lock state variables:
 - `static bool g_budget_gate_locked = false`
 - `static ulong g_budget_gate_lock_time_ms = 0` (milliseconds timestamp)

### Step 4: Update EquityBudgetGateResult Structure

**File**: `MQL5/Include/RPEA/equity_guardian.mqh` (lines 16-24)

- Add fields:
- `bool gate_pass` (primary boolean for pass/fail)
- `string gating_reason` (e.g., "pass", "insufficient_room", "lock_timeout", "calc_error")
- `double room_today` (separate field)
- `double room_overall` (separate field)
- Keep `approved` field for backward compatibility (set `approved = gate_pass`)

### Step 5: Implement Snapshot Capture Function

**File**: `MQL5/Include/RPEA/equity_guardian.mqh`

- Create `BudgetGateSnapshot Equity_TakePositionSnapshot()` function:

1. Create snapshot with `snapshot_time = TimeCurrent()`, `is_locked = false`
2. Capture all open positions into `position_snapshots[]` array with symbol, type, volume, price_open, sl, ticket
3. Capture all pending orders into `pending_snapshots[]` array with symbol, type, volume, price, sl, ticket
4. Compute `open_risk` from captured position snapshots
5. Compute `pending_risk` from captured pending snapshots
6. Capture `room_today` and `room_overall` from `g_equity_last_rooms` (ensure rooms computed first)
7. Return snapshot with all fields populated

### Step 6: Implement Lock Management with Millisecond Timing

**File**: `MQL5/Include/RPEA/equity_guardian.mqh`

- Create `bool Equity_AcquireBudgetGateLock(const int timeout_ms)`:
- Use `GetTickCount64()` to track elapsed milliseconds
- Check if lock is held: if `g_budget_gate_locked == true`
- Check timeout: if `(GetTickCount64() - g_budget_gate_lock_time_ms) > timeout_ms`, allow takeover
- Set `g_budget_gate_locked = true` and `g_budget_gate_lock_time_ms = GetTickCount64()`
- Return true on success, false on timeout
- Create `void Equity_ReleaseBudgetGateLock()`:
- Set `g_budget_gate_locked = false`
- Set `g_budget_gate_lock_time_ms = 0`

### Step 7: Rewrite Equity_EvaluateBudgetGate Function

**File**: `MQL5/Include/RPEA/equity_guardian.mqh` (lines 462-519)

- Replace implementation with locked snapshot logic:

1. Resolve `lock_ms` from input parameter (fallback to `DEFAULT_BudgetGateLockMs`)
2. Resolve `headroom` from input parameter (fallback to `DEFAULT_RiskGateHeadroom`)
3. Acquire lock using `Equity_AcquireBudgetGateLock(lock_ms)`:

 - On failure: set `result.gate_pass = false`, `result.gating_reason = "lock_timeout"`, log timeout, return

4. Ensure rooms computed: call `Equity_ComputeRooms(ctx)` if needed
5. Take position snapshot: `BudgetGateSnapshot snapshot = Equity_TakePositionSnapshot()`
6. Mark snapshot as locked: `snapshot.is_locked = true` (indicates frozen state)
7. Use snapshot data (not live broker state):

 - `open_risk = snapshot.open_risk`
 - `pending_risk = snapshot.pending_risk`
 - `room_today = snapshot.room_today`
 - `room_overall = snapshot.room_overall`

8. Calculate `min_room = MathMin(snapshot.room_today, snapshot.room_overall)`
9. Calculate `gate_threshold = headroom * min_room` (use resolved headroom parameter)
10. Calculate `total_required = snapshot.open_risk + snapshot.pending_risk + next_trade_worst_case`
11. Set `gate_pass = (total_required <= gate_threshold + 1e-6)` (epsilon tolerance)
12. Set `result.approved = gate_pass` (backward compatibility)
13. Set `gating_reason`:

 - If `gate_pass == true`: `"pass"`
 - Else if calculation error: `"calc_error"`
 - Else: `"insufficient_room"`

14. Populate result fields: `open_risk`, `pending_risk`, `next_worst_case`, `room_today`, `room_overall`, `gate_pass`, `gating_reason`
15. Log structured JSON with all 5 inputs + gate_pass + gating_reason:

 - Format: `{"open_risk":X,"pending_risk":Y,"next_trade":Z,"room_today":A,"room_overall":B,"gate_pass":true/false,"gating_reason":"..."}`

16. Release lock: `Equity_ReleaseBudgetGateLock()` in finally-style guard (always execute, even on early return)

### Step 8: Error Handling and Calculation Flags

**File**: `MQL5/Include/RPEA/equity_guardian.mqh`

- Ensure `Equity_TakePositionSnapshot()` sets `calc_ok` flags
- On calculation failure: set `gate_pass = false`, `gating_reason = "calc_error"`, log diagnostic, release lock
- Handle invalid inputs (NaN, negative values) with error flags
- Ensure lock is always released even on error paths

### Step 9: Update Callers

**Files**: `MQL5/Include/RPEA/allocator.mqh`, `MQL5/Include/RPEA/order_engine.mqh`

- Update callers to read `result.gate_pass` instead of `result.approved` (primary field)
- Update callers to read `result.gating_reason` for detailed rejection reasons
- Preserve backward compatibility by keeping `approved` field usage where needed
- Verify all call sites handle new result structure fields

### Step 10: Update Logging Utilities

**File**: `MQL5/Include/RPEA/logging.mqh` (if needed)

- Ensure logging helpers accept new fields (`gate_pass`, `gating_reason`)
- Maintain JSON formatting consistency
- Verify `LogDecision()` can handle expanded field set

## Acceptance Criteria Validation

- [ ] Budget gate uses locked snapshots (snapshot structure populated before calculation, snapshot.is_locked=true)
- [ ] Formula: `open_risk + pending_risk + next_trade ≤ RiskGateHeadroom × min(room_today, room_overall)`
- [ ] Logs 5 inputs: `open_risk`, `pending_risk`, `next_trade`, `room_today`, `room_overall`
- [ ] Logs `gate_pass` boolean (true/false)
- [ ] Logs `gating_reason` string ("pass", "insufficient_room", "lock_timeout", "calc_error")
- [ ] Config keys: `BudgetGateLockMs` (input + default) and `RiskGateHeadroom` (input + default 0.90) implemented
- [ ] Lock timeout enforced using millisecond timing (`GetTickCount64()`)
- [ ] Snapshot captures rooms during snapshot creation (not recomputed from live state)

## Testing Considerations

- Unit tests should verify snapshot locking prevents concurrent modifications
- Verify lock timeout behavior with millisecond precision
- Verify all 5 inputs + gate_pass + gating_reason logged correctly
- Verify snapshot captures frozen state correctly
- Test input parameter resolution (input vs default fallback)

## Files Modified

1. `MQL5/Experts/FundingPips/RPEA.mq5` - Add input parameters
2. `MQL5/Include/RPEA/config.mqh` - Add RiskGateHeadroom default
3. `MQL5/Include/RPEA/equity_guardian.mqh` - Main implementation (snapshot, locking, budget gate rewrite)
4. `MQL5/Include/RPEA/allocator.mqh` - Update caller to use gate_pass and gating_reason
5. `MQL5/Include/RPEA/order_engine.mqh` - Update caller if needed
6. `MQL5/Include/RPEA/logging.mqh` - Verify logging utilities support new fields