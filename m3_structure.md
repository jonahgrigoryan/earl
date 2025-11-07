# M3 Implementation Strategy

## Overview

This document outlines the complete implementation strategy for RPEA M3 (Order Engine and Synthetic Signal Generation). The strategy is organized into 5 phases with clear dependencies, compile/test checkpoints, and branching workflow.

**Total Scope:** 24 tasks over ~17-22 days (3-4 weeks)

---

## Phase-Based Implementation

### Phase 1: Foundation (Tasks 1-6) - Days 1-4

**Goal:** Get basic order execution working end-to-end

**Tasks:**
1. Order Engine scaffolding + event model
2. Idempotency system (intent_id + action_id dedup + persistence)
3. Volume/price normalization
4. Basic order placement
5. Simple retry logic
6. Market fallback + slippage

**Dependencies:**
- Task 1 must be done first (everything depends on it)
- Tasks 2-6 can be done in parallel after Task 1
- Recommended sequential order: 1 → 3 → 4 → 5 → 6 → 2 (idempotency last)

**Compile/Test Checkpoint:**
```cpp
// After Phase 1, you should be able to:
- Place a market order on EURUSD
- See it execute with proper volume normalization
- Retry on transient errors
- Log the intent_id
- Verify slippage protection works
```

**Test in Strategy Tester:**
- Single market order placement
- Verify fills, check logs
- Test retry on simulated errors (disconnect broker briefly)

**Branch:** `feat/m3-phase1-foundation`

---

### Phase 2: OCO + Partial Fills (Tasks 7-8) - Days 5-7

**Goal:** Get OCO pendings working with partial fill handling

**Tasks:**
7. OCO relationship management
8. Partial fill handler

**Dependencies:**
- Requires Phase 1 complete (order placement must work)
- Task 7 must be done before Task 8
- Task 8 needs OnTradeTransaction from Task 1

**Compile/Test Checkpoint:**
```cpp
// After Phase 2, you should be able to:
- Place OCO pending orders (buy stop + sell stop)
- See one fill and the other cancel automatically
- Handle partial fills with OCO volume adjustment
- Verify expiry times are set correctly
```

**Test in Strategy Tester:**
- Place OCO pendings at OR high/low
- Trigger one side, verify other cancels
- Simulate partial fill (manually modify order volume in tester)
- Check OCO sibling volume adjusts correctly

**Branch:** `feat/m3-phase2-oco`

---

### Phase 3: Risk + Trailing + Queue (Tasks 9-13) - Days 8-11

**Goal:** Add risk management, trailing stops, and news queue

**Tasks:**
9. Budget gate with snapshot locking
10. News CSV fallback
11. Synthetic price manager (XAUEUR signals)
12. Queue manager
13. Trailing stop management

**Dependencies:**
- Task 9 can be done independently (just enhances existing budget gate)
- Task 10 can be done independently
- Task 11 can be done independently (just price calculation)
- Tasks 12-13 must be done together (trailing needs queue)

**Recommended Order:** 9 → 10 → 11 → 12 → 13

**Compile/Test Checkpoint:**
```cpp
// After Phase 3, you should be able to:
- See budget gate lock positions before validation
- Load news from CSV if API fails
- Generate BWISC signals from XAUEUR synthetic data
- Queue trailing updates during news windows
- Execute queued actions after news window expires
- See trailing activate at +1R
```

**Test in Strategy Tester:**
- Place trade, let it go to +1R, verify trailing activates
- Simulate news window, verify trailing queues
- After news window, verify queued action executes
- Test XAUEUR signal generation (check logs for synthetic prices)

**Branch:** `feat/m3-phase3-risk-trailing`

---

### Phase 4: Integration + Polish (Tasks 14-20) - Days 12-15

**Goal:** Wire everything together and add production features

**Tasks:**
14. Comprehensive audit logging
15. Integration with risk management + XAUEUR mapping
16. State recovery on startup
17. Error handling + resilience
18. Integration tests (optional - manual testing OK)
19. Performance optimization (optional)
20. Documentation (optional)

**Dependencies:**
- Task 14 can be done anytime (just logging)
- Task 15 requires all previous tasks (final integration)
- Task 16 requires Task 2 (idempotency)
- Task 17 enhances existing error handling
- Tasks 18-20 are polish

**Recommended Order:** 14 → 15 → 16 → 17 → (skip 18-20 for challenge)

**Compile/Test Checkpoint:**
```cpp
// After Phase 4, you should be able to:
- See complete audit logs with all fields
- Execute XAUEUR signals as XAUUSD trades
- Restart EA and see state recover
- Handle all error conditions gracefully
- Run end-to-end: signal → risk check → order → fill → trailing → close
```

**Test in Strategy Tester:**
- Full end-to-end test: London session, BWISC signal, OCO placement, fill, trailing, exit
- Test XAUEUR signal: verify it executes on XAUUSD with scaled SL/TP
- Restart EA mid-trade, verify state recovers
- Check audit logs have all required fields

**Branch:** `feat/m3-phase4-integration`

---

### Phase 5: Performance Enhancements (Tasks 21-24) - Days 16-17

**Goal:** Add the 4 performance boosters

**Tasks:**
21. Dynamic position sizing
22. Spread filter
23. Breakeven stop
24. Pending expiry optimization

**Dependencies:**
- All can be done independently
- But do them in order for logical flow

**Compile/Test Checkpoint:**
```cpp
// After Phase 5, you should be able to:
- See position sizes scale with confidence
- See trades rejected on wide spreads
- See SL move to breakeven at +0.5R
- See pendings expire after 45 minutes
```

**Test in Strategy Tester:**
- High confidence signal → larger position size
- Low confidence signal → smaller position size
- Wide spread → trade rejected
- Position at +0.5R → SL moves to breakeven
- Pending not filled in 45 min → expires

**Branch:** `feat/m3-phase5-enhancements`

---

## Branching Strategy

### Git Workflow Structure

```
main (or master)
  ├── feat/m2-bwisc (current - M2 complete)
  └── feat/m3-order-engine (base branch for M3)
       ├── feat/m3-phase1-foundation
       ├── feat/m3-phase2-oco
       ├── feat/m3-phase3-risk-trailing
       ├── feat/m3-phase4-integration
       └── feat/m3-phase5-enhancements
```

### Workflow Steps

**1. Create M3 base branch:**
```bash
git checkout feat/m2-bwisc
git checkout -b feat/m3-order-engine
git push -u origin feat/m3-order-engine
```

**2. For each phase:**
```bash
# Phase 1
git checkout feat/m3-order-engine
git checkout -b feat/m3-phase1-foundation

# Work on tasks 1-6
# Commit frequently with clear messages
git commit -m "Task 1: Order engine scaffolding"
git commit -m "Task 3: Volume normalization"
# etc.

# When phase complete and tested
git push origin feat/m3-phase1-foundation

# Merge to base
git checkout feat/m3-order-engine
git merge feat/m3-phase1-foundation
git push origin feat/m3-order-engine

# Phase 2
git checkout feat/m3-order-engine
git checkout -b feat/m3-phase2-oco
# Repeat...
```

**3. After all phases complete:**
```bash
git checkout feat/m2-bwisc
git merge feat/m3-order-engine
# Or create PR: feat/m3-order-engine → feat/m2-bwisc
```

### Branch Flow Diagram

```
feat/m3-order-engine (base - starts empty)
  ↓
Phase 1 branch → work → merge back to base
  ↓
feat/m3-order-engine (now has Phase 1 code)
  ↓
Phase 2 branch → work → merge back to base
  ↓
feat/m3-order-engine (now has Phase 1 + 2)
  ↓
Phase 3 branch → work → merge back to base
  ↓
feat/m3-order-engine (now has Phase 1 + 2 + 3)
  ↓
Phase 4 branch → work → merge back to base
  ↓
feat/m3-order-engine (now has Phase 1 + 2 + 3 + 4)
  ↓
Phase 5 branch → work → merge back to base
  ↓
feat/m3-order-engine (has all 5 phases - M3 complete)
  ↓
Merge to main/feat/m2-bwisc (M3 complete)
```

---

## Task-by-Task Verification Strategy

### For Each Task:

**1. Write the interface first (stub)**
```cpp
// Example: Task 3 - Volume normalization
double OE_NormalizeVolume(const string symbol, const double volume) {
    // TODO: implement
    return volume; // stub
}
```

**2. Compile and verify it links**
```bash
# In MetaEditor: Compile (F7)
# Should compile with no errors
```

**3. Implement the logic**
```cpp
double OE_NormalizeVolume(const string symbol, const double volume) {
    double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    double min_vol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double max_vol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    
    double normalized = MathRound(volume / step) * step;
    return MathMax(min_vol, MathMin(max_vol, normalized));
}
```

**4. Add logging for verification**
```cpp
double OE_NormalizeVolume(const string symbol, const double volume) {
    double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    // ... implementation ...
    
    PrintFormat("[OE] NormalizeVolume: %s raw=%.4f normalized=%.4f step=%.4f", 
                symbol, volume, normalized, step);
    return normalized;
}
```

**5. Test in isolation (if possible)**
```cpp
// In OnInit or test function
void TestVolumeNormalization() {
    double test1 = OE_NormalizeVolume("EURUSD", 0.03); // Should round to 0.01
    double test2 = OE_NormalizeVolume("XAUUSD", 0.015); // Should round to 0.01
    PrintFormat("[TEST] Volume norm: %.4f, %.4f", test1, test2);
}
```

**6. Commit**
```bash
git add Include/RPEA/order_engine.mqh
git commit -m "Task 3: Implement volume normalization with SYMBOL_VOLUME_STEP"
```

---

## Dependency Map (Critical Path)

### Task Dependencies

```
Task 1 (Scaffolding)
  ├── Task 3 (Normalization) → Task 4 (Order placement)
  ├── Task 5 (Retry) → Task 6 (Market fallback)
  ├── Task 4 → Task 7 (OCO) → Task 8 (Partial fills)
  ├── Task 7 → Task 12 (Queue) → Task 13 (Trailing)
  ├── Task 11 (Synthetic) → Task 15 (Integration)
  └── Task 2 (Idempotency) → Task 16 (State recovery)

Independent (can do anytime):
- Task 9 (Budget gate)
- Task 10 (News CSV)
- Task 14 (Audit logging)
- Task 17 (Error handling)
- Tasks 21-24 (Enhancements)
```

### Critical Path

The longest dependency chain determines minimum timeline:
```
Task 1 → Task 4 → Task 7 → Task 12 → Task 13 → Task 15
(Scaffolding → Order placement → OCO → Queue → Trailing → Integration)
```

This is the critical path - delays here delay the entire project.

---

## Compile/Test Frequency

### Compile After Every Task
```bash
# In MetaEditor
F7 (Compile)
# Fix any errors immediately
```

### Test in Strategy Tester After Each Phase
- **Phase 1:** Test basic order placement
- **Phase 2:** Test OCO functionality
- **Phase 3:** Test trailing + queue
- **Phase 4:** Test full end-to-end
- **Phase 5:** Test enhancements

### Don't Wait Until Everything is Done
- Compile frequently (after each task)
- Test after each phase (not each task)
- Fix bugs immediately (don't accumulate technical debt)

---

## Time Estimates (Realistic)

| Phase | Tasks | Days | Cumulative |
|-------|-------|------|------------|
| Phase 1 | 1-6 | 4 days | Day 4 |
| Phase 2 | 7-8 | 3 days | Day 7 |
| Phase 3 | 9-13 | 4 days | Day 11 |
| Phase 4 | 14-17 | 4 days | Day 15 |
| Phase 5 | 21-24 | 2 days | Day 17 |
| **Total** | **24 tasks** | **17 days** | **~3 weeks** |

**Buffer:** Add 3-5 days for debugging, testing, unexpected issues = **20-22 days total**

### Weekly Breakdown
- **Week 1:** Phases 1-2 (foundation + OCO)
- **Week 2:** Phases 3-4 (risk/trailing + integration)
- **Week 3:** Phase 5 + testing + bug fixes

---

## Pro Tips

### 1. Use Print Statements Liberally
```cpp
PrintFormat("[OE] Task 4: Placing order %s vol=%.2f sl=%.5f tp=%.5f", 
            symbol, volume, sl, tp);
```

### 2. Create a Test Mode
```cpp
input bool TestMode = false;

if(TestMode) {
    // Run test functions
    TestVolumeNormalization();
    TestOCOLogic();
    return;
}
```

### 3. Comment Out Complex Logic Initially
```cpp
// Task 7: OCO - Start simple
void PlaceOCO() {
    // Step 1: Just place two orders (no linking)
    PlaceOrder(buy_request);
    PlaceOrder(sell_request);
    
    // TODO: Add OCO linking logic
    // TODO: Add expiry
    // TODO: Add sibling cancellation
}
```

### 4. Use the Hold Points
Your tasks have 5 hold points. **Actually stop and review** at each one:
- **Hold Point 1** (after Task 6): Review foundation
- **Hold Point 2** (after Task 8): Review OCO and partial fills
- **Hold Point 3** (after Task 13): Review budget/news/synthetic/queue/trailing
- **Hold Point 4** (after Task 17): Review integration, recovery, resilience
- **Hold Point 5** (after Task 24): Review performance enhancements

### 5. Keep M2 Working
Don't break existing BWISC functionality. Test that M2 still works after each phase.

### 6. Commit Message Format
```bash
# Good commit messages
git commit -m "Task 3: Implement volume normalization with SYMBOL_VOLUME_STEP"
git commit -m "Task 7: Add OCO relationship tracking and sibling cancellation"
git commit -m "Task 13: Implement trailing stop activation at +1R"

# Bad commit messages
git commit -m "updates"
git commit -m "fix"
git commit -m "wip"
```

---

## Critical Success Factors

### Must Do
✅ Compile after every task (catch errors early)
✅ Test after every phase (don't wait until the end)
✅ Use logging extensively (visibility into what's happening)
✅ Follow the dependency map (don't skip prerequisites)
✅ Commit often (easy to rollback if needed)
✅ Merge phases to base branch when complete

### Don't Do
❌ Skip compilation until "everything is done"
❌ Work on multiple phases simultaneously (unless experienced)
❌ Ignore the hold points
❌ Break M2 functionality
❌ Accumulate bugs (fix immediately)

---

## Getting Started

### Step 1: Create M3 Base Branch
```bash
git checkout feat/m2-bwisc
git checkout -b feat/m3-order-engine
git push -u origin feat/m3-order-engine
```

### Step 2: Create Phase 1 Branch
```bash
git checkout feat/m3-order-engine
git checkout -b feat/m3-phase1-foundation
```

### Step 3: Start Task 1
Open `MQL5/Include/RPEA/order_engine.mqh` and begin implementing the Order Engine scaffolding.

---

## Summary

**Implementation Strategy:**
- Work in 5 phases
- Create phase branches off base M3 branch
- Compile after every task
- Test after every phase
- Merge phases back to base when complete
- Follow dependency map
- Use hold points for review

**Timeline:**
- 17 days of focused work
- 20-22 days with buffer
- 3-4 weeks total

**Success Criteria:**
- All 24 tasks complete
- EA compiles without errors
- All phases tested in Strategy Tester
- M2 functionality still works
- Ready for challenge attempt

**Next Step:** Begin Phase 1, Task 1 - Order Engine Scaffolding
