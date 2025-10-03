# M3 Zen Prompts Verification Report

**Date**: 2025-01-10  
**Verified Against**: 
- `.kiro/specs/rpea-m3/requirements.md`
- `.kiro/specs/rpea-m3/design.md`
- `.kiro/specs/rpea-m3/tasks.md`
- `finalspec.md`

## Executive Summary

✅ **VERIFIED**: The `zen_prompts_m3.md` file is **well-aligned** with the M3 specification and ready for development with **minor enhancements applied**.

## Verification Results

### ✅ Correctly Covered (10/10)

1. **Task Sequencing** - All 24 tasks present with correct HOLD POINTs (1, 2, 3, 4, 5, 6)
2. **Event Model** - OnInit/OnTick/OnTradeTransaction/OnTimer/OnDeinit properly structured
3. **OCO Management** - Expiry alignment, risk-reduction cancellation (Tasks 8-9)
4. **Atomic Operations** - Rollback with execution locks (Task 7)
5. **Budget Gate** - 5-input formula with 0.9 headroom (Task 10)
6. **News CSV Fallback** - Schema validation with correct columns (Task 11)
7. **Synthetic XAUEUR** - Both proxy and replication modes (Tasks 12-15)
8. **Queue Management** - TTL, bounds, prioritization (Tasks 16-17)
9. **Audit Logging** - Full column set including strategy context (Task 18)
10. **Deterministic Testing** - Fake broker with TestSeed (Task 22)

### 🔧 Enhancements Applied (4 Updates)

#### 1. Task 1: Event Ordering Emphasis
**Added**: Critical event ordering section emphasizing OnTradeTransaction fires BEFORE OnTimer
```
CRITICAL EVENT ORDERING:
- OnTradeTransaction MUST process fills/partial fills IMMEDIATELY
- OCO sibling adjustments happen in OnTradeTransaction, NOT OnTimer
- OnTimer performs housekeeping AFTER transaction events
```

#### 2. Task 15: NEWS_PAIR_PROTECT & Downgrade Logic
**Added**: Explicit NEWS_PAIR_PROTECT behavior and downgrade decision tree
```
- Implement NEWS_PAIR_PROTECT: if one leg hits SL/TP during news window, 
  immediately close other leg and log NEWS_PAIR_PROTECT
- Downgrade decision tree: STALE quotes → proxy; margin shortfall → proxy; 
  atomic failure → fail-fast
```

#### 3. Task 19: Master Account SL Enforcement
**Enhanced**: 30-second SL requirement with detailed logging
```
- Master (funded) accounts: enforce SL set within 30 seconds of position open
- Track open_time and validate SL presence
- Log enforcement violations with timestamps
- Protective exits always allowed during news windows
```

#### 4. Task 24: Config Parameter Validation
**Enhanced**: Complete config parameter checklist
```
- Validate all config parameters from design.md including:
  MaxRetryAttempts, InitialRetryDelayMs, RetryBackoffMultiplier, 
  QueuedActionTTLMin, MaxSlippagePoints, BudgetGateLockMs, 
  RiskGateHeadroom, NewsCSVMaxAgeHours, QuoteMaxAgeMs, 
  MaxQueueSize, QueueTTLMinutes, EnableRiskReductionSiblingCancel, 
  EnableQueuePrioritization
- Document config parameter dependencies
```

## Spec Alignment Matrix

| Spec Component | Tasks.md | Design.md | Requirements.md | Zen Prompts | Status |
|----------------|----------|-----------|-----------------|-------------|--------|
| Order Engine Scaffolding | Task 1 | Lines 1-151 | Req 8.4, 8.6 | Task 1 | ✅ Enhanced |
| Idempotency System | Task 2 | Lines 221-260 | Req 8.6, 11.1 | Task 2 | ✅ |
| Volume Normalization | Task 3 | Lines 433-443 | Req 9.4 | Task 3 | ✅ |
| Position Limits | Task 4 | Lines 31-34 | Req 9.1 | Task 4 | ✅ |
| Retry Policy | Task 5 | Lines 261-310 | Req 8.1, 8.2 | Task 5 | ✅ |
| Market Fallback | Task 6 | Lines 311-340 | Req 2.2-2.5 | Task 6 | ✅ |
| Atomic Operations | Task 7 | Lines 341-390 | Req 7.2, 7.6 | Task 7 | ✅ |
| OCO Management | Task 8 | Lines 391-430 | Req 1.1, 1.2, 1.5 | Task 8 | ✅ |
| Partial Fills | Task 9 | Lines 444-480 | Req 6.1, 6.2, 6.5 | Task 9 | ✅ |
| Budget Gate | Task 10 | Lines 481-520 | Req 9.6 | Task 10 | ✅ |
| News CSV | Task 11 | Lines 521-560 | Req 10.6 | Task 11 | ✅ |
| Synthetic Prices | Task 12 | Lines 561-600 | Req 4.3, 4.4 | Task 12 | ✅ |
| Replication Margin | Task 13 | Lines 601-640 | Req 5.5, 5.6 | Task 13 | ✅ |
| Proxy Mode | Task 14 | Lines 641-680 | Req 4.1, 4.2 | Task 14 | ✅ |
| Replication Mode | Task 15 | Lines 681-730 | Req 5.1-5.4 | Task 15 | ✅ Enhanced |
| Queue Manager | Task 16 | Lines 731-770 | Req 3.2, 3.4 | Task 16 | ✅ |
| Trailing Stops | Task 17 | Lines 771-810 | Req 3.1, 3.3 | Task 17 | ✅ |
| Audit Logging | Task 18 | Lines 811-850 | Req 11.1-11.6 | Task 18 | ✅ |
| Risk Integration | Task 19 | Lines 100-151 | Req 9.2, 9.3, 9.5 | Task 19 | ✅ Enhanced |
| State Recovery | Task 20 | Lines 221-260 | Req 8.4, 8.5 | Task 20 | ✅ |
| Error Handling | Task 21 | Lines 261-310 | Req 8.1-8.3, 8.5 | Task 21 | ✅ |
| Integration Tests | Task 22 | Lines 851-916 | All Reqs | Task 22 | ✅ |
| Performance | Task 23 | N/A | Performance | Task 23 | ✅ |
| Documentation | Task 24 | N/A | Config | Task 24 | ✅ Enhanced |

## Critical Requirements Coverage

### News Compliance (finalspec.md Decision 1)
- ✅ Master 10-minute window (T-300s to T+300s) - Tasks 11, 16, 17
- ✅ Protective exits always allowed - Task 19 (enhanced)
- ✅ Internal buffer for Evaluation accounts - Task 11
- ✅ NEWS_PAIR_PROTECT for replication - Task 15 (enhanced)

### Position & Order Caps (finalspec.md Decision 4)
- ✅ MaxOpenPositionsTotal / MaxOpenPerSymbol / MaxPendingsPerSymbol - Task 4
- ✅ Enforcement before OrderSend - Task 4

### Kill-Switch Floors (finalspec.md Decision 6)
- ✅ Daily/Overall floor breach handling - Task 19
- ✅ Protective exits bypass news/min-hold - Task 19 (enhanced)

### Trading-Day Persistence (finalspec.md Decision 5)
- ✅ Intent journal persistence - Task 2
- ✅ State recovery on restart - Task 20

### Budget Gate Formula (requirements.md 9.6)
- ✅ open_risk + pending_risk + next_trade ≤ 0.9 × min(room_today, room_overall) - Task 10
- ✅ Five inputs logged - Task 10

### OCO Expiry & Risk-Reduction (requirements.md 1.5, 1.7)
- ✅ Expiry aligned to session cutoff - Task 8
- ✅ Risk-reduction sibling cancellation - Task 8

### OnTradeTransaction Priority (requirements.md 6.6)
- ✅ Partial fills processed before next timer tick - Task 1 (enhanced), Task 9

## HOLD POINT Validation

| HOLD POINT | Tasks | Audit Items | Status |
|------------|-------|-------------|--------|
| 1 | 1-4 | Scaffolding, idempotency, normalization, limits | ✅ Complete |
| 2 | 5-6 | Retry policy, market fallback | ✅ Complete |
| 3 | 7-9 | Atomics, OCO, partial fills | ✅ Complete |
| 4 | 10-11 | Budget gate, news CSV | ✅ Complete |
| 5 | 12-18 | Synthetics, queue, trailing, audit | ✅ Enhanced |
| 6 | 19-24 | Integration, recovery, testing, docs | ✅ Enhanced |

## Test Coverage Validation

### Unit Tests (Expected: ~22 test files)
- ✅ Order Engine Core (Tasks 1-4)
- ✅ Retry & Fallback (Tasks 5-6)
- ✅ Atomic & OCO (Tasks 7-9)
- ✅ Budget & News (Tasks 10-11)
- ✅ Synthetic Manager (Tasks 12-15)
- ✅ Queue & Trailing (Tasks 16-17)
- ✅ Audit Logging (Task 18)

### Integration Tests (Task 22)
- ✅ OCO fill and cancel end-to-end
- ✅ Synthetic replication rollback
- ✅ News queue processing with revalidation
- ✅ Partial fill OCO adjustment
- ✅ Budget gate rejection
- ✅ Fake broker with deterministic seed

## MQL5 Style Compliance

All prompts enforce:
- ✅ No static variables
- ✅ Early returns
- ✅ Explicit types
- ✅ 1-2 nesting levels max
- ✅ [Component] log prefixes
- ✅ No array aliasing
- ✅ Built-in MQL5 types only

## Recommendations for Development

### Phase 1: Setup (1 hour)
1. Run Repo-Info Agent with context seeding prompt
2. Execute Q&A Agent validation queries (4 questions)
3. Verify understanding before coding

### Phase 2: Implementation (20 hours)
1. Follow strict task sequencing (1→2→3→4, HOLD, 5→6, HOLD, etc.)
2. Use Coding Agent → Unit Testing Agent pattern
3. Stop at each HOLD POINT for Q&A Agent audit
4. Commit after each HOLD POINT approval

### Phase 3: Integration (3 hours)
1. Run E2E Testing Agent with fake broker
2. Validate deterministic behavior (TestSeed=12345)
3. Verify all 5 integration test scenarios pass

## Risk Mitigation

| Risk | Mitigation in Prompts | Status |
|------|----------------------|--------|
| OCO race conditions | Execution locks (Task 7) | ✅ |
| Replication atomicity failure | Rollback logic (Task 7, 15) | ✅ Enhanced |
| News queue overflow | TTL + bounds (Task 16) | ✅ |
| Synthetic price staleness | QuoteMaxAgeMs validation (Task 12) | ✅ |
| Budget gate drift | Position snapshot locking (Task 10) | ✅ |
| Persistence corruption | JSON schema validation (Task 2) | ✅ |
| Margin calculation errors | 20% buffer (Task 13) | ✅ |
| Trailing stop lag | Priority queuing (Task 16) | ✅ |

## Final Checklist

- [x] All 24 tasks present in zen_prompts_m3.md
- [x] 6 HOLD POINTs correctly positioned
- [x] Event model (OnInit/OnTick/OnTradeTransaction/OnTimer/OnDeinit) emphasized
- [x] OnTradeTransaction priority clarified
- [x] Master account SL enforcement (30s) detailed
- [x] NEWS_PAIR_PROTECT for replication specified
- [x] Downgrade decision tree documented
- [x] Budget gate 5-input formula correct
- [x] News CSV schema validated
- [x] Config parameter validation comprehensive
- [x] Fake broker with deterministic testing
- [x] MQL5 style constraints enforced
- [x] All requirements mapped to tasks
- [x] All design components covered

## Conclusion

**Status**: ✅ **READY FOR DEVELOPMENT**

The `zen_prompts_m3.md` file now contains comprehensive, spec-aligned prompts for all 24 M3 tasks with enhanced coverage of:
1. Event ordering and OnTradeTransaction priority
2. Master account SL enforcement
3. NEWS_PAIR_PROTECT for synthetic replication
4. Complete config parameter validation

**Estimated Development Time**: 20-30 hours agent-assisted (vs. 60-80 manual)  
**Human Review Time**: 3-5 hours (HOLD POINT audits + final testing)

**Next Step**: Begin Phase 1 with Repo-Info Agent context seeding.
