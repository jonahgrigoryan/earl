# Task 15: Integration with Risk Management and XAUEUR Signal Mapping

## Overview

**Goal**: Fully integrate the Order Engine with existing risk management, equity guardian, news filter, and implement XAUEUR synthetic signal mapping to XAUUSD execution with proper SL/TP distance scaling. Includes Master account SL enforcement within 30 seconds.

**Expected Impact**: ~150 lines of code changes across multiple files

**Files Modified**:
- `Include/RPEA/order_engine.mqh` (integration methods, XAUEUR mapping functions)
- `Include/RPEA/allocator.mqh` (signal-to-execution mapping)
- `Experts/FundingPips/RPEA.mq5` (main EA integration)

**Dependencies**: 
- Tasks 1-14 completed (order engine scaffolding, idempotency, OCO management, budget gate, synthetic price manager, audit logging)
- Existing M1/M2 components (risk.mqh, equity_guardian.mqh, news.mqh, scheduler.mqh, signals_bwisc.mqh)

---

## Prerequisites Review

Before starting Task 15, verify these components are complete and functional:

### From Previous Tasks (1-14)

✅ **Task 1**: Order Engine scaffolding with event model (OnInit/OnTick/OnTradeTransaction/OnTimer/OnDeinit)
✅ **Task 2**: Idempotency system with intent journal  
✅ **Task 3**: Volume and price normalization system
✅ **Task 4**: Basic order placement with position limits
✅ **Task 5**: Retry policy system with MT5 error code mapping
✅ **Task 6**: Market order fallback with slippage protection
✅ **Task 7**: OCO relationship management with expiry enforcement
✅ **Task 8**: Partial fill handler with OCO volume adjustment
✅ **Task 9**: Budget gate with position snapshot locking
✅ **Task 10**: News CSV fallback system
✅ **Task 11**: Synthetic price manager (XAUEUR = XAUUSD / EURUSD) for signal generation
✅ **Task 12**: Queue manager with bounds and TTL management
✅ **Task 13**: Trailing stop management with queue integration
✅ **Task 14**: Comprehensive audit logging system

### From Existing M1/M2 Components

✅ **risk.mqh**: Risk sizing by ATR distance, margin calculations
✅ **equity_guardian.mqh**: Budget gate validation, equity rooms, position caps
✅ **news.mqh**: News CSV loader, blocking predicates
✅ **scheduler.mqh**: Timer orchestration, session detection
✅ **signals_bwisc.mqh**: BWISC signal generation with confidence
✅ **allocator.mqh**: Order plan builder, SL/TP calculation

---

## Implementation Steps

### Step 0: Validate Prerequisites (Blocking)

Before touching code, confirm Tasks 1-14 are merged and the supporting APIs exist. Run the checklist below and halt if any item fails:

- `Equity_CalcRiskDollars`, `Equity_EvaluateBudgetGate`, `Equity_CheckPositionCaps`, `Equity_Count*` exports present in `equity_guardian.mqh`.
- `News_IsBlocked`, `News_GetWindowState`, CSV fallback + force reload hooks available.
- Synthetic manager exposes `GetSyntheticPrice`, `BuildSyntheticBars`, and XAUEUR configuration constants.
- Allocator/order-engine intents compile cleanly on `feat/m3-phase3-risk-trailing`.
- `g_last_bwisc_context` contains `entry_price`, `direction`, `worst_case_risk`.
- Run `powershell -ExecutionPolicy Bypass -File run_tests.ps1` to ensure Tasks 1-14 tests still pass.

If any prerequisite is missing, resolve or create a blocking issue before proceeding; Task 15 assumes the above surfaces are stable.

### PHASE 1: Risk Management Integration (Steps 1-5)

#### Step 1: Add Risk Engine Integration Interface to OrderEngine

**Location**: `Include/RPEA/order_engine.mqh`

**Action**: Add private helper method for risk validation that integrates with existing risk.mqh and equity_guardian.mqh

```cpp
// Add to OrderEngine class private section
private:
   // Risk integration helper (Task 15)
   bool ValidateRiskConstraints(const OrderRequest &request,
                                const bool is_pending,
                                double &out_evaluated_risk,
                                string &out_rejection_reason);
```

**Implementation Details**:
- Call `Equity_CalcRiskDollars()` to compute worst-case risk for the proposed order
- Call `Equity_EvaluateBudgetGate()` (Task 9 export) or `Equity_RoomAllowsNextTrade()` to enforce `RiskGateHeadroom` × `min(room_today, room_overall)` threshold
- Call `Equity_CheckPositionCaps()` to verify MaxOpenPositionsTotal, MaxOpenPerSymbol, MaxPendingsPerSymbol
- Return false if any constraint fails, populate rejection_reason
- Log all constraint checks to audit log

**Dependencies**: 
- `#include <RPEA/risk.mqh>` (already included)
- `#include <RPEA/equity_guardian.mqh>` (already included)

**Acceptance**: 
- Method correctly computes risk using existing helpers
- Budget gate threshold enforced (0.9 × min room)
- Position caps respected
- Rejection reasons captured in audit log

---

#### Step 2: Integrate News Filter Blocking

**Location**: `Include/RPEA/order_engine.mqh`

**Action**: Add news blocking check to order placement flow with explicit semantics.

```cpp
enum NewsGateState
{
   NEWS_GATE_CLEAR = 0,
   NEWS_GATE_BLOCKED,
   NEWS_GATE_PROTECTIVE_ALLOWED
};

NewsGateState EvaluateNewsGate(const string signal_symbol,
                               const bool is_protective_exit,
                               string &out_detail);
```

**Implementation Details**:
- Call `News_IsBlocked()` (single-argument API) and `News_GetWindowState()` for each execution leg. For XAUEUR, check both XAUUSD and EURUSD and populate `out_detail` with which leg triggered the block (`"XAUUSD_BLOCKED"` / `"EURUSD_BLOCKED"`).
- Return `NEWS_GATE_CLEAR` when both legs clear, `NEWS_GATE_BLOCKED` when entries must be rejected, and `NEWS_GATE_PROTECTIVE_ALLOWED` when only protective exits (SL/TP, kill-switch) may proceed.
- Rename usages in `PlaceOrder()` to make intent obvious: e.g., `const NewsGateState gate = EvaluateNewsGate(signal_symbol, is_protective, news_state); bool allowed = (gate != NEWS_GATE_BLOCKED);`.
- To mitigate time-of-check/time-of-use drift, re-run `EvaluateNewsGate()` right before `ExecuteOrderWithRetry()` if more than 5 seconds elapsed since the original gate result.

**Dependencies**:
- `#include <RPEA/news.mqh>` (already included)

**Acceptance**:
- News blocking enforced for entries during high-impact events with unambiguous enum semantics.
- Protective exits always allowed (SL/TP, kill-switch) and audited as `PROTECTED_EXIT_ALLOWED`.
- XAUEUR checks both constituent symbols.
- Orders that spend >5 seconds in pre-placement checks re-validate the news gate before execution.

---

#### Step 3: Wire Budget Gate to PlaceOrder

**Location**: `Include/RPEA/order_engine.mqh`

**Action**: Integrate budget gate validation into PlaceOrder() flow

**Modification**: Update PlaceOrder() method to:
1. Call ValidateRiskConstraints() **after** the intent record is created (`intent_id = GenerateIntentId(...)`) and **after** position caps pass, but **before** risk dollars are computed inline and before `ExecuteOrderWithRetry()`.
2. If validation fails, reject order immediately and log audit entry.
3. If validation passes, proceed with ExecuteOrderWithRetry().
4. Pass evaluated_risk to audit logging for gate metrics.
5. Extend `OrderRequest` with `signal_symbol` (defaults to `symbol` when not provided) so downstream methods (news gate, audit logging) can distinguish XAUEUR-originated orders.

**Code Location**: `OrderEngine::PlaceOrder()` — insert the new block right after the log line that begins with `Position caps OK for %s (%s)` (search for `"Position caps OK"`), so the flow becomes: caps pass → `ValidateRiskConstraints` → risk calc / market quote normalization → execution.

**Key Integration Point**:
```cpp
OrderResult OrderEngine::PlaceOrder(const OrderRequest &request)
{
   // ... existing setup code ...
   
   // Task 15: Risk constraint validation
   double evaluated_risk = 0.0;
   string rejection_reason = "";
   if(!ValidateRiskConstraints(request, is_pending, evaluated_risk, rejection_reason))
   {
      result.success = false;
      result.error_message = rejection_reason;
      result.intent_id = intent_id;
      
      // Audit the rejection
      Audit_LogIntentEvent(intent, "REJECTED", "risk_gate_fail",
                           request.price, 0.0, request.volume, 0.0, 0.0, 0,
                           rejection_reason, "CLEAR");
      return result;
   }
   
   // ... proceed with existing execution flow ...
}
```

**Acceptance**:
- Budget gate called before every order
- Failed gates logged with gating_reason
- Successful gates proceed to execution

---

#### Step 4: Integrate Position Limit Enforcement

**Location**: `Include/RPEA/order_engine.mqh`

**Action**: Ensure position caps are enforced through existing Equity_CheckPositionCaps()

**Verification Steps**:
1. Confirm PlaceOrder() calls Equity_CheckPositionCaps() (should exist from Task 4)
2. Verify caps: MaxOpenPositionsTotal=2, MaxOpenPerSymbol=1, MaxPendingsPerSymbol=2
3. Ensure violations are logged with clear rejection reasons
4. Test with multiple symbols to verify per-symbol vs total enforcement

**Implementation Note**: This should already be implemented in Task 4, but needs verification that it integrates cleanly with the risk constraint validation flow.

**Acceptance**:
- Position limits enforced before order placement
- Violations logged with specific cap type (total/symbol/pending)
- Limits checked atomically with risk validation

---

#### Step 5: Master Account SL Enforcement

**Location**: `Include/RPEA/order_engine.mqh`

**Action**: Add SL enforcement tracking for Master (funded) accounts

```cpp
// Add to OrderEngine class private section
private:
   struct SLEnforcementEntry
   {
      ulong    ticket;
      datetime open_time;
      datetime sl_set_time;
      bool     sl_set_within_30s;
      string   status;  // "ON_TIME", "LATE", "PENDING"
   };
   
   SLEnforcementEntry m_sl_enforcement_queue[];
   int                m_sl_enforcement_count;
   
   // Master account SL enforcement helper (Task 15)
   void TrackSLEnforcement(const ulong ticket, const datetime open_time);
   void CheckPendingSLEnforcement();
   bool IsMasterAccount() const;
```

**Implementation Details**:
- `IsMasterAccount()`: Return true only when `AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL` **and** `AccountInfoDouble(ACCOUNT_BALANCE) >= 25000`. Document that 10K–25K (challenge) accounts will not trigger Master enforcement.
- `TrackSLEnforcement()`: Called after successful order placement, adds ticket to enforcement queue **and** writes the entry to `Files/RPEA/state/sl_enforcement.json`. Persist `{ticket, open_time, sl_set_time (0), status:"PENDING"}` so restarts resume enforcement tracking.
- `CheckPendingSLEnforcement()`: Called from OnTimer, loads any persisted queue (if not already loaded), and for each entry:
  - If position no longer exists, drop entry with status `UNKNOWN_POSITION`.
  - If SL == 0 and elapsed < 30s → keep `status="PENDING"` (no log yet).
  - If SL == 0 and elapsed ≥ 30s → log `status="MISSING"` and mark late.
  - If SL > 0, compute elapsed between `open_time` and `TimeCurrent()`; `<=30s` is `ON_TIME`, `>30s` is `LATE`.
  - When SL first detected, update `sl_set_time`, log `[OrderEngine] Master SL set: ... status=ON_TIME|LATE`, and remove from queue + persistence.
- Persist queue on `OnDeinit` and reload on `Init()` so outages do not lose enforcement data.

**Integration Point**: Add call to TrackSLEnforcement() in ExecuteOrderWithRetry() after successful placement:
```cpp
if(result.success && result.ticket > 0)
{
   if(IsMasterAccount() && !is_pending_request)
   {
      TrackSLEnforcement(result.ticket, TimeCurrent());
      SaveSLEnforcementState(); // new helper persists queue immediately
   }
}
```

**Acceptance**:
- Master accounts tracked for SL enforcement, even across crashes/restarts.
- 30-second window enforced with statuses `ON_TIME`, `LATE`, `MISSING`, `UNKNOWN_POSITION`.
- Demo/challenge accounts not tracked thanks to deterministic threshold.

---

### PHASE 2: XAUEUR Signal Mapping (Steps 6-10)

#### Step 6: Add Signal-to-Execution Mapping Helper

**Location**: New module `Include/RPEA/symbol_bridge.mqh`

**Action**: Create a lightweight helper (no class state) that both allocator and order engine can include without circular dependencies.

```cpp
// symbol_bridge.mqh
#ifndef RPEA_SYMBOL_BRIDGE_MQH
#define RPEA_SYMBOL_BRIDGE_MQH

string SymbolBridge_GetExecutionSymbol(const string signal_symbol);
bool   SymbolBridge_MapDistance(const string signal_symbol,
                                const string exec_symbol,
                                const double distance_signal,
                                double &out_distance_exec,
                                double &out_eurusd_rate);
#endif
```

**Implementation Notes**:
- For XAUEUR return `exec_symbol = "XAUUSD"`; otherwise passthrough.
- `SymbolBridge_MapDistance` multiplies XAUEUR SL/TP distances by the latest EURUSD bid. If the EURUSD quote is stale/invalid, set `out_distance_exec = -1.0`, return `false`, and **never** fall back to the XAUEUR distance.
- When the mapping succeeds, log once via `LogDecision("SymbolBridge","XAUEUR_MAP", ...)` including signal distance and EURUSD quote.
- This module lives alongside other lightweight helpers (`config.mqh` neighbors) so allocator/order engine can `#include <RPEA/symbol_bridge.mqh>` without needing each other.
- OrderEngine should also include this helper to double-check incoming requests (e.g., fail-fast if a manual XAUEUR request bypasses allocator).

**Acceptance**:
- Helper compiles standalone (no dependency on OrderEngine or AppContext).
- Failure returns `false` so callers can reject the order rather than place it with incorrect stops.
- Successful mapping reports the EURUSD rate used for traceability.

---

#### Step 7: Update Allocator to Use Signal Mapping

> **Prerequisite:** Complete Step 6 (`symbol_bridge.mqh`) and ensure it compiles before starting this step; allocator now depends on the helper.

**Location**: `Include/RPEA/allocator.mqh`

**Action**: Modify `Allocator_BuildOrderPlan()` to translate XAUEUR signals via the helper instead of calling `g_order_engine`.

**Modification**:
```cpp
#include <RPEA/symbol_bridge.mqh>

OrderPlan Allocator_BuildOrderPlan(...)
{
   // ... existing setup code ...
   const string signal_symbol = symbol;
   const string exec_symbol = SymbolBridge_GetExecutionSymbol(signal_symbol);

   double mapped_sl_points = (double)slPoints;
   double mapped_tp_points = (double)tpPoints;
   double mapping_rate = 0.0;

   if(signal_symbol != exec_symbol)
   {
      if(!SymbolBridge_MapDistance(signal_symbol,
                                   exec_symbol,
                                   (double)slPoints,
                                   mapped_sl_points,
                                   mapping_rate) || mapped_sl_points <= 0.0)
      {
         rejection = "xaueur_distance_unavailable";
      }
      if(!SymbolBridge_MapDistance(signal_symbol,
                                   exec_symbol,
                                   (double)tpPoints,
                                   mapped_tp_points,
                                   mapping_rate) || mapped_tp_points <= 0.0)
      {
         rejection = "xaueur_distance_unavailable";
      }
      plan.comment = "XAUEUR→XAUUSD";
   }
```
   // Continue with `exec_symbol` for contract queries and cast `mapped_*` back to ints.
```

**Key Changes**:
- Allocator now includes `symbol_bridge.mqh` instead of touching `OrderEngine`.
- If mapping fails (helper returns `false`), reject the plan with a descriptive reason; do **not** place orders with unmapped SL/TP.
- When rejection occurs, surface `xaueur_distance_unavailable` so logs/audits show the EURUSD quote failure.
- Set `plan.symbol = exec_symbol` and store the original signal symbol in `plan.comment` or a dedicated field for audit context.
- Extend `OrderPlan` and `OrderRequest` structures with `source_symbol` so the signal origin flows through to audit logging, news gating, and SL enforcement heuristics.

**Acceptance**:
- XAUEUR signals produce XAUUSD orders only when EURUSD data is available; otherwise allocator cleanly rejects.
- Direct symbols bypass the helper and behave as before.
- Decision log shows `XAUEUR_MAPPING` entries sourced from either allocator or the helper for traceability.

---

#### Step 8: Integrate XAUEUR Synthetic Price Manager

**Location**: `Include/RPEA/order_engine.mqh`, integration with signals_bwisc.mqh

**Action**: Ensure BWISC signal generation can use XAUEUR synthetic prices from Task 11

**Verification Steps**:
1. Confirm `SyntheticManager::GetSyntheticPrice("XAUEUR", PRICE_CLOSE)` works (implemented in Task 11)
2. Confirm `SyntheticManager::BuildSyntheticBars("XAUEUR", PERIOD_M1, count)` builds bars (implemented in Task 11)
3. Verify BWISC can calculate ATR/MA/RSI from XAUEUR synthetic bars
4. Test signal generation: XAUEUR signal → allocator maps to XAUUSD → order engine places XAUUSD order

**Integration Note**: This step is primarily verification. The synthetic manager should already be functional from Task 11. The key is ensuring the signal→execution flow works end-to-end.

**Test Scenario**:
```cpp
// In test or manual verification:
// 1. BWISC generates signal on XAUEUR synthetic data
// 2. Signal context: symbol="XAUEUR", direction=1, sl_distance=50 pips
// 3. Allocator maps to: exec_symbol="XAUUSD", exec_sl_distance=50*1.08=54 pips
// 4. Order placed on XAUUSD with 54 pip SL
```

**Acceptance**:
- BWISC generates signals from XAUEUR synthetic data
- Signals contain signal_symbol="XAUEUR"
- Allocator correctly maps to XAUUSD execution
- No two-leg orders (XAUUSD only, not XAUUSD + EURUSD)

---

#### Step 9: Add XAUEUR News Blocking

**Location**: `Include/RPEA/order_engine.mqh`

**Action**: Ensure `EvaluateNewsGate()` handles XAUEUR composite blocking

**Modification**:
```cpp
NewsGateState OrderEngine::EvaluateNewsGate(...)
{
   if(signal_symbol == "XAUEUR")
   {
      const bool xau_blocked = News_IsBlocked("XAUUSD");
      const bool eur_blocked = News_IsBlocked("EURUSD");
      if(xau_blocked || eur_blocked)
      {
         out_detail = (xau_blocked ? "XAUUSD_BLOCKED" : "EURUSD_BLOCKED");
         return (is_protective_exit ? NEWS_GATE_PROTECTIVE_ALLOWED : NEWS_GATE_BLOCKED);
      }
      out_detail = "CLEAR";
      return NEWS_GATE_CLEAR;
   }

   if(News_IsBlocked(signal_symbol))
   {
      out_detail = (is_protective_exit ? "PROTECTED_EXIT_ALLOWED" : "BLOCKED");
      return (is_protective_exit ? NEWS_GATE_PROTECTIVE_ALLOWED : NEWS_GATE_BLOCKED);
   }

   out_detail = "CLEAR";
   return NEWS_GATE_CLEAR;
}
```

**Acceptance**:
- XAUEUR signals blocked if XAUUSD OR EURUSD has news.
- Direct symbols use single check.
- Protective exits always allowed with explicit enum state.
- News state logged shows which leg blocked and whether the allowance was for a protective exit.

---

#### Step 10: Update Audit Logging for XAUEUR

**Location**: `Include/RPEA/order_engine.mqh`

**Action**: Ensure audit log captures XAUEUR mapping details across **all** related rows (intent creation, execution, partial fills, cancels).

**Modification**: Update `Audit_LogIntentEvent()` and any other audit writers to include:
- `mode` field: `"PROXY"` for XAUEUR-derived orders, `"DIRECT"` for native symbols. Store this on the intent when the plan/request is created so every row (including partial fills from Task 8) emits the same mode.
- Add `intent.signal_symbol` (new field) and persist it in the gating reason/comment or a dedicated CSV column. Include EURUSD rate used for scaling.
- When partial fills occur, ensure the audit row still references `"PROXY"` and the XAUEUR context; do not drop the metadata when `record.partial_fills` is populated.

**Example Audit Row**:
```csv
rpea_20240115_103000_001,2024-01-15 10:30:00,XAUUSD,ORDER_PLACE,12345,0.10,0.10,2050.50,2050.45,2040.00,2070.00,0,PROXY,150.50,75.25,105.00,400.00,600.00,true,0.82,0.78,0.95,1.95,540,"XAUEUR→XAUUSD eurusd=1.0821",CLEAR
```

**Key Fields**:
- `symbol`: XAUUSD (execution symbol)
- `mode`: PROXY (indicates XAUEUR source)
- `gating_reason`: "XAUEUR→XAUUSD eurusd=1.0821" (includes mapping info)

**Acceptance**:
- Audit log shows XAUEUR-derived orders as mode=PROXY on **every** row tied to that intent (creation, execution, partial fills, cancels).
- Mapping details captured in gating_reason or comment with EURUSD rate for traceability.

---

### PHASE 3: EA Integration (Steps 11-13)

#### Step 11: Update RPEA.mq5 OnTimer Integration

**Location**: `Experts/FundingPips/RPEA.mq5`

**Action**: Ensure OnTimer calls Order Engine integration points

**Current State**: OnTimer already calls:
- `Scheduler_OnTimer()` for session management
- Signal engines for trade generation
- Allocator for order planning
- Order engine for execution

**Required Additions**:
1. In `OnInit()`, call `g_order_engine.LoadSLEnforcementState()` (new helper) after `g_order_engine.Init()` so any persisted entries are restored before trading resumes.
2. In `OnTimer()`, call `g_order_engine.CheckPendingSLEnforcement()`:
```cpp
void OnTimer()
{
   // ... existing scheduler and signal logic ...
   
   // Task 15: Check pending Master SL enforcement
   g_order_engine.CheckPendingSLEnforcement();
   
   // ... rest of existing logic ...
}
```

**Acceptance**:
- Master SL enforcement state restored on startup before new orders are processed.
- Timer tick checks queue every 30s, logging ON_TIME/LATE/MISSING appropriately.
- No impact on existing timer flow.

---

#### Step 12: Update Signal Generation Flow

**Location**: `Experts/FundingPips/RPEA.mq5`, scheduler.mqh integration

**Action**: Ensure signal generation supports XAUEUR

**Verification**:
1. Confirm BWISC signal engine can process XAUEUR symbol
2. Verify synthetic price manager is called for XAUEUR data
3. Check that signals include signal_symbol field
4. Test end-to-end flow: XAUEUR signal → allocator → order engine

**No Code Changes Required**: This should already work if:
- InpSymbols input includes "XAUEUR" (user configuration)
- Synthetic manager is initialized in OnInit (done in Task 11)
- BWISC signal engine iterates configured symbols

**Test Scenario**:
```cpp
// Add to InpSymbols input:
// input string InpSymbols = "EURUSD;XAUUSD;XAUEUR";

// Verify in logs:
// [BWISC] Generating signal for XAUEUR using synthetic prices
// [Allocator] XAUEUR signal mapped: signal_sl=50, exec_sl=54, eurusd=1.0821
// [OrderEngine] Placing order on XAUUSD for XAUEUR signal
```

**Acceptance**:
- XAUEUR can be added to InpSymbols
- BWISC generates signals using synthetic data
- Signals correctly mapped to XAUUSD execution

---

#### Step 13: Add Configuration Validation

**Location**: `Experts/FundingPips/RPEA.mq5`, OnInit()

**Action**: Add validation for XAUEUR configuration

```cpp
int OnInit()
{
   // ... existing init code ...
   
   // Task 15: Validate XAUEUR configuration
   bool has_xaueur = false;
   for(int i = 0; i < g_ctx.symbols_count; i++)
   {
      if(g_ctx.symbols[i] == "XAUEUR")
      {
         has_xaueur = true;
         break;
      }
   }
   
   if(has_xaueur)
   {
      // Ensure constituent symbols are available
      if(!SymbolSelect("XAUUSD", true) || !SymbolSelect("EURUSD", true))
      {
         Print("[RPEA] ERROR: XAUEUR requires XAUUSD and EURUSD symbols");
         return INIT_FAILED;
      }
      
      // Verify UseXAUEURProxy is enabled (proxy mode only for M3)
      if(!UseXAUEURProxy)
      {
         Print("[RPEA] ERROR: XAUEUR requires UseXAUEURProxy=true in M3 (replication mode unsupported).");
         return INIT_FAILED;
      }
      
      Print("[RPEA] XAUEUR signal mapping enabled: XAUEUR → XAUUSD (proxy mode)");
   }
   
   // ... rest of existing init ...
}
```

**Acceptance**:
- XAUEUR configuration validated on startup.
- Missing constituent symbols or UseXAUEURProxy=false cause `INIT_FAILED`.
- Proxy mode enforced (no replication in M3).
- Validation messages logged.

---

### PHASE 4: Testing Integration (Steps 14-16)

#### Step 14: Add Integration Test Cases

**Location**: Create `Tests/RPEA/test_order_engine_integration.mqh`

**Test Cases** (as specified in tasks.md and zen_prompts_m3.md):

```cpp
// Test 1: XAUEUR mapping to XAUUSD
bool Test_Integration_XAUEURMapsToXAUUSD()
{
   // Setup: Create XAUEUR signal with known SL distance
   // Expected: XAUUSD order with EURUSD-scaled SL/TP
   // Verify: exec_symbol="XAUUSD", sl_scaled correctly
}

// Test 2: Master SL enforcement
bool Test_Integration_MasterSLEnforced()
{
   // Setup: Master account, place order
   // Expected: SL set within 30s, logged as ON_TIME
   // Test late case: SL set after 35s, logged as LATE
}

// Test 3: Risk gate respects room
bool Test_Integration_RiskRespectsRoom()
{
   // Setup: Set room_today = 100, open_risk = 80, next_trade = 30
   // Expected: Budget gate denies (80 + 30 > 0.9 × 100)
   // Verify: Order rejected, gating_reason logged
}

// Test 4: News blocks entries
bool Test_Integration_NewsBlocksEntries()
{
   // Setup: High-impact news on XAUUSD within NewsBufferS
   // Expected: XAUEUR signal blocked (XAUUSD blocked)
   // Verify: Entry rejected, protective exits allowed
}

// Test 5: Logging captures mapping
bool Test_Integration_LogsMapping()
{
   // Setup: Place XAUEUR-derived order
   // Expected: Audit log shows mode=PROXY, signal mapping details
   // Verify: CSV contains sl_synth, eurusd, sl_xau values
}
```

**Run Tests**: Execute via `Tests/RPEA/run_order_engine_tests.mq5`

**Acceptance**:
- All 5 test cases pass
- No regressions in existing tests
- XAUEUR mapping verified end-to-end

---

#### Step 15: Manual Strategy Tester Verification

**Action**: Run full EA in Strategy Tester with XAUEUR enabled

**Test Configuration**:
- Symbols: "EURUSD;XAUUSD;XAUEUR"
- UseXAUEURProxy = true
- NewsBufferS = 300
- MaxOpenPositionsTotal = 2
- Date range: 1 month of data

**Verification Checklist**:
1. ✅ XAUEUR signals generated using synthetic prices
2. ✅ Orders placed on XAUUSD (not XAUEUR)
3. ✅ SL/TP distances scaled by EURUSD rate
4. ✅ Budget gate enforced before placement
5. ✅ News blocking works for XAUEUR (checks both legs)
6. ✅ Master SL enforcement tracked (if applicable)
7. ✅ Audit log shows mode=PROXY for XAUEUR orders
8. ✅ No two-leg orders (single XAUUSD order only)
9. ✅ Position limits respected
10. ✅ No errors or crashes

**Test Scenarios**:
- **Scenario 1**: XAUEUR signal when both XAUUSD and EURUSD clear → order placed
- **Scenario 2**: XAUEUR signal when XAUUSD has news → order blocked
- **Scenario 3**: XAUEUR signal when EURUSD has news → order blocked
- **Scenario 4**: XAUEUR signal near budget cap → order rejected by gate
- **Scenario 5**: Multiple XAUEUR fills → verify audit log completeness

**Acceptance**:
- All scenarios behave as expected
- No logic errors in Strategy Tester logs
- Performance metrics reasonable

---

#### Step 16: Code Review and Documentation

**Action**: Final review and documentation updates

**Review Checklist**:
1. ✅ All integration points follow existing code patterns
2. ✅ No logic duplication (uses existing risk.mqh, equity_guardian.mqh, news.mqh)
3. ✅ XAUEUR mapping is clear and maintainable
4. ✅ Master SL enforcement non-intrusive
5. ✅ Logging comprehensive but not excessive
6. ✅ No MQL5 style violations (no static, early returns, explicit types)
7. ✅ All acceptance criteria met (see Section 4)

**Documentation Updates**:
- Update README.md with XAUEUR configuration instructions
- Add comments to integration methods explaining flow
- Document Master SL enforcement behavior
- Update config parameter descriptions

**Acceptance**:
- Code passes review standards
- Documentation complete
- Ready for production use

---

## Key Integration Points Summary

### 1. Risk Management Flow

```
Signal Generated (BWISC)
  ↓
Allocator_BuildOrderPlan()
  → Maps XAUEUR → XAUUSD (if applicable)
  → Scales SL/TP by EURUSD rate
  ↓
OrderEngine::PlaceOrder()
  → ValidateRiskConstraints()
    → Equity_CalcRiskDollars() [compute risk]
    → Equity_ValidateBudgetGate() [0.9 × min room check]
    → Equity_CheckPositionCaps() [verify limits]
  → CheckNewsBlocking()
    → News_IsBlocked() [for XAUEUR, check both legs]
  → ExecuteOrderWithRetry()
    → TrackSLEnforcement() [if Master account]
  → Audit_LogIntentEvent()
    → Log with mode=PROXY, mapping details
```

### 2. XAUEUR Signal-to-Execution Flow

```
BWISC Signal Engine
  ↓
Reads XAUEUR synthetic prices (Task 11)
  → GetSyntheticPrice("XAUEUR", PRICE_CLOSE)
  → BuildSyntheticBars("XAUEUR", M1, count)
  ↓
Generates signal: signal_symbol="XAUEUR", sl_distance=50 pips
  ↓
Allocator_BuildOrderPlan()
  → exec_symbol = GetExecutionSymbol("XAUEUR") → "XAUUSD"
  → exec_sl = MapSLDistance("XAUEUR", "XAUUSD", 50) → 50 × 1.08 = 54 pips
  → OrderPlan: symbol="XAUUSD", sl_points=54, comment="XAUEUR→XAUUSD"
  ↓
OrderEngine::PlaceOrder()
  → Places single-leg XAUUSD order with 54 pip SL
  → Logs mode=PROXY in audit
```

### 3. Master SL Enforcement Flow

```
OrderEngine::ExecuteOrderWithRetry()
  ↓
Order placed successfully
  ↓
IsMasterAccount()? → Yes
  ↓
TrackSLEnforcement(ticket, open_time)
  → Add to m_sl_enforcement_queue[]
  ↓
OnTimer() calls CheckPendingSLEnforcement()
  → For each pending entry:
    → Elapsed = TimeCurrent() - open_time
    → SL set? → Yes
      → If elapsed ≤ 30s → Log "ON_TIME"
      → If elapsed > 30s → Log "LATE"
    → Remove from queue
```

### 4. News Blocking Flow

```
OrderEngine::CheckNewsBlocking(symbol, is_protective_exit)
  ↓
Is XAUEUR?
  → Yes: Check XAUUSD AND EURUSD
    → Either blocked? → Reject entry (allow protective exits)
  → No: Check symbol directly
    → Blocked? → Reject entry (allow protective exits)
  ↓
Return (allowed, news_state)
```

---

## Acceptance Criteria (from tasks.md)

✅ **1. Order engine respects all existing risk constraints**
- Budget gate: open_risk + pending_risk + next_trade ≤ 0.9 × min(room_today, room_overall)
- Position limits: MaxOpenPositionsTotal=2, MaxOpenPerSymbol=1, MaxPendingsPerSymbol=2
- Margin requirements: Uses existing Risk_SizingByATRDistance() and margin validation

✅ **2. XAUEUR signals map to XAUUSD execution with proper SL/TP distance scaling**
- Signal: signal_symbol="XAUEUR", sl_distance=50 pips
- Execution: exec_symbol="XAUUSD", exec_sl_distance=50 × EURUSD_rate
- Example: EURUSD=1.08 → 50 × 1.08 = 54 pip SL on XAUUSD
- No two-leg orders (XAUUSD only, not XAUUSD + EURUSD)

✅ **3. Master accounts set SL within 30 seconds and log enforcement status**
- Master detection: AccountInfoInteger(ACCOUNT_TRADE_MODE) == REAL && balance > threshold
- Tracking: Order placed → timestamp recorded → SL set → elapsed checked
- Logging: `[OrderEngine] Master SL set: ticket=X, elapsed=Ys, status=ON_TIME|LATE`
- On-time: SL set ≤ 30s → status=ON_TIME
- Late: SL set > 30s → status=LATE

✅ **4. Integration seamless with existing M1/M2 components**
- No logic duplication (uses risk.mqh, equity_guardian.mqh, news.mqh)
- Follows existing patterns (logging, error handling, retry logic)
- No breaking changes to existing interfaces
- All previous tests still pass

✅ **5. Audit logging captures all integration details**
- XAUEUR orders: mode=PROXY, signal mapping logged
- Budget gate: open_risk, pending_risk, next_risk, room_today, room_overall logged
- News state: CLEAR, BLOCKED, PROTECTED_EXIT_ALLOWED
- Master SL: elapsed time and status logged

---

## Dependencies and Validation

### Before Starting Task 15

1. ✅ Verify Tasks 1-14 complete and passing all tests
2. ✅ Confirm synthetic manager (Task 11) can generate XAUEUR prices
3. ✅ Verify budget gate (Task 9) calculates correctly
4. ✅ Confirm audit logging (Task 14) writes complete CSV rows
5. ✅ Check news filter (Task 10) loads CSV and blocks correctly

### External Dependencies

1. ✅ risk.mqh: Risk_SizingByATRDistanceForSymbol()
2. ✅ equity_guardian.mqh: Equity_ValidateBudgetGate(), Equity_CheckPositionCaps()
3. ✅ news.mqh: News_IsBlocked()
4. ✅ signals_bwisc.mqh: BWISC signal generation with confidence
5. ✅ allocator.mqh: Allocator_BuildOrderPlan()

---

## Expected Code Diff Summary

**Total: ~150 lines across 3 files**

### order_engine.mqh (~100 lines)
- ValidateRiskConstraints() method: 30 lines
- CheckNewsBlocking() method: 25 lines
- GetExecutionSymbol() method: 5 lines
- MapSLDistance() method: 15 lines
- MapTPDistance() method: 5 lines
- TrackSLEnforcement() method: 10 lines
- CheckPendingSLEnforcement() method: 10 lines

### allocator.mqh (~30 lines)
- XAUEUR signal mapping in Allocator_BuildOrderPlan(): 20 lines
- Logging and validation: 10 lines

### RPEA.mq5 (~20 lines)
- XAUEUR configuration validation in OnInit(): 15 lines
- Master SL check in OnTimer(): 5 lines

---

## Testing Strategy

### Unit Tests (test_order_engine_integration.mqh)

1. **Test_Integration_XAUEURMapsToXAUUSD**: Verify signal mapping
2. **Test_Integration_MasterSLEnforced**: Verify SL enforcement
3. **Test_Integration_RiskRespectsRoom**: Verify budget gate
4. **Test_Integration_NewsBlocksEntries**: Verify news blocking
5. **Test_Integration_LogsMapping**: Verify audit logging

**Expected Runtime**: ~2 minutes for full test suite

### Integration Tests (Strategy Tester)

1. **End-to-end XAUEUR flow**: Signal → allocator → order → fill
2. **Budget gate rejection**: Verify orders rejected when room insufficient
3. **News blocking**: Verify entries blocked, exits allowed
4. **Master SL tracking**: Verify enforcement logged correctly
5. **Multi-symbol**: Verify EURUSD + XAUUSD + XAUEUR all work simultaneously

**Expected Runtime**: ~10 minutes for 1 month backtest

### Regression Tests

1. Run all existing M1/M2 tests
2. Verify no breaking changes
3. Check performance (no significant slowdown)

**Expected**: All previous tests pass, <5% performance impact

---

## Rollback Procedure (Safety Net)

If any blocking issue emerges mid-task (e.g., missing prerequisite, unimplemented dependency), follow these steps to revert safely:
1. Work on a feature branch (e.g., `cursor/task15-risk-xaueur`) rebased on `feat/m3-phase3-risk-trailing`.
2. Commit checkpoints per phase (risk integration, XAUEUR bridge, SL enforcement) so partial work can be cherry-picked or reverted cleanly.
3. If aborting, `git reset --hard` is **not** allowed; instead `git revert <commit_range>` on the feature branch, then push/PR the revert or discard the branch locally.
4. Restore `Files/RPEA/state/sl_enforcement.json` from the previous commit if persistence migrations fail.
5. Document rollback reason in the PR or task tracker so future work picks up from the last stable checkpoint.

---

## Troubleshooting Common Issues

### Issue 1: XAUEUR signals not generating
**Cause**: Synthetic manager not building bars correctly
**Fix**: Verify Task 11 complete, check QuoteMaxAgeMs setting, ensure XAUUSD and EURUSD symbols available

### Issue 2: Budget gate always failing
**Cause**: Room calculation incorrect or headroom too low
**Fix**: Check RiskGateHeadroom=0.90 setting, verify Equity_ValidateBudgetGate() returns correct rooms

### Issue 3: Master SL always showing LATE
**Cause**: SL not being set properly or tracking timestamp incorrect
**Fix**: Verify SL set immediately after order placement, check IsMasterAccount() detection

### Issue 4: News blocking not working for XAUEUR
**Cause**: Only checking XAUUSD, not EURUSD
**Fix**: Ensure CheckNewsBlocking() checks BOTH constituent symbols for XAUEUR

### Issue 5: Audit log missing XAUEUR mapping details
**Cause**: mode field not set to PROXY or logging incomplete
**Fix**: Verify Audit_LogIntentEvent() includes mode="PROXY" and gating_reason contains mapping info

---

## Post-Task 15 Checklist

- [ ] All 5 unit tests pass
- [ ] Strategy Tester runs without errors
- [ ] XAUEUR signals map to XAUUSD orders
- [ ] SL/TP distances scaled by EURUSD rate
- [ ] Budget gate enforced before all orders
- [ ] News blocking works for XAUEUR (both legs)
- [ ] Master SL enforcement tracked and logged
- [ ] Audit log complete with mode=PROXY
- [ ] No two-leg orders (single XAUUSD only)
- [ ] Code review passed
- [ ] Documentation updated

---

## Known Limitations & Edge Cases

1. **EURUSD Quotes**: XAUEUR mappings fail fast when `SymbolBridge_MapDistance` cannot fetch a fresh EURUSD quote (weekends, outages). Expect allocator rejections rather than risk incorrect SL/TP math.
2. **Offline Master Enforcement**: If the terminal stays offline past 30 seconds, restored tickets may immediately log `MISSING` even if the broker auto-applied SL. Record this behavior in operations docs.
3. **News Gate Drift**: Despite re-validating after 5 seconds, broker execution latency may still allow fills seconds into a blocked window. Use audit timestamps to reconcile any disputes.
4. **Config Consistency**: Switching `UseXAUEURProxy` at runtime is unsupported and will leave allocator/order engine out of sync; enforce the input at startup only.

**When complete, proceed to Task 16: State Recovery and Reconciliation**

---

## References

- `.kiro/specs/rpea-m3/tasks.md` § Task 15
- `.kiro/specs/rpea-m3/requirements.md` § Requirement 9 (Risk Integration), § Requirement 4 (XAUEUR Proxy)
- `.kiro/specs/rpea-m3/design.md` § Synthetic Manager Interface, § Risk Integration Interface
- `zen_prompts_m3.md` § Task 15 prompt and unit test specifications
- Existing files: risk.mqh, equity_guardian.mqh, news.mqh, allocator.mqh, order_engine.mqh, RPEA.mq5

---

**END OF TASK 15 OUTLINE**
