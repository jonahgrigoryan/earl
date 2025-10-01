# Zencoder M3 Quick Implementation Guide

## START HERE: 3-Phase Workflow

### PHASE 1: Setup (1 hour)
1. **Repo-Info Agent** → Paste full context prompt (see below)
2. **Q&A Agent** → Run 4 validation queries to confirm understanding

### PHASE 2: Implement Tasks 1-24 (20 hours)
- **Pattern**: Coding Agent implements → Unit Testing Agent tests → Iterate
- **HOLD POINTs**: Q&A Agent audits at tasks 4, 6, 9, 11, 18, 24

### PHASE 3: Integration (3 hours)
- **E2E Testing Agent** → Fake broker + full integration tests

---

## PHASE 1 PROMPTS

### Repo-Info Agent — Context Seeding
```
Build RPEA M3 knowledge base. Analyze:

SPECS: finalspec.md, .kiro/specs/rpea-m3/{requirements.md, design.md, tasks.md}
M1/M2 CODE: RPEA.mq5, scheduler.mqh, signals_bwisc.mqh, risk.mqh, equity_guardian.mqh, news.mqh, persistence.mqh
STYLE: .cursor/rules/ea.mdc, .zencoder/rules/repo.md
TESTS: test_risk.mqh, test_signals_bwisc.mqh

Summarize: M1/M2 components, M3 to-build (Order Engine, Synthetic Manager), invariants (news, budget gate, OCO, atomics), MQL5 style (no static, no array alias, early returns).
```

### Q&A Agent — 4 Validation Queries
```
1. How does OnTimer scheduler interact with signal engines? Walk through flow.
2. Explain budget gate formula. What 5 inputs logged? Where does 0.9 headroom come from?
3. News compliance for Master accounts? OCO sibling cancellation during news?
4. MQL5 style constraints from .cursor/rules/ea.mdc?
```

---

e# PHASE 2: TASK TEMPLATES

### Task 1: Order Engine Scaffolding (Coding Agent)
**Attach**: design.md, order_engine.mqh, config.mqh, RPEA.mq5

```
Implement Task 1 from tasks.md: "Create Order Engine Scaffolding"

GOAL: Event model (OnInit/OnTick/OnTradeTransaction/OnTimer/OnDeinit)

CLASS: OrderEngine
STRUCTS: OrderRequest {symbol, type, volume, price, sl, tp, magic, comment, is_oco_primary, oco_sibling_ticket, expiry}, OrderResult {success, ticket, error_message, executed_price, executed_volume, retry_count}, QueuedAction {type, ticket, new_value, validation_threshold, queued_time, expires_time, trigger_condition}
METHODS (stubs): PlaceOrder(), ModifyOrder(), CancelOrder(), EstablishOCO(), ProcessOCOFill(), UpdateTrailing(), QueueAction(), ProcessQueuedActions(), IsExecutionLocked(), SetExecutionLock(), ReconcileOnStartup()
STATE: map<ulong, OCORelationship>, vector<QueuedAction>, bool execution_locked

INTEGRATION (RPEA.mq5): OnInit→Init(), OnTradeTransaction→OnTradeTxn(), OnTimer→OnTimerTick(), OnDeinit→OnShutdown()

CONFIG: MaxRetryAttempts=3, InitialRetryDelayMs=300, RetryBackoffMultiplier=2.0, QueuedActionTTLMin=5, MaxSlippagePoints=10.0, EnableExecutionLock=true, PendingExpiryGraceSeconds=60, AutoCancelOCOSibling=true, OCOCancellationTimeoutMs=1000

STYLE: No static, early returns, explicit types, 1-2 nesting, [OrderEngine] logs

ACCEPTANCE: Inits without errors, OnTradeTransaction fires before timer, sequence correct, OnDeinit flushes

Expected: ~300 lines
```

### Task 1: Unit Tests (Unit Testing Agent)
**Attach**: order_engine.mqh, test_framework.mqh

```
Generate tests for Task 1: Order Engine Scaffolding
File: test_order_engine.mqh

Use test_risk.mqh pattern (ASSERT macros, bool return).

TESTS:
1. TestOrderEngine_Init(): Create instance, Init(), assert IsExecutionLocked()==false, queue empty
2. TestOrderEngine_EventSequence(): Init()→OnTradeTxn()→OnTimerTick()→OnShutdown(), assert no errors
3. TestOrderEngine_ExecutionLock(): Set(true), assert true, Set(false), assert false
4. TestOrderEngine_QueueAction(): Queue action TTL=5min, assert size 1, fast-forward 6min, ProcessQueue(), assert empty
5. TestOrderEngine_ReconcileOnStartup(): Mock 2 positions, Reconcile(), assert logs

Generate TestOrderEngine_RunAll() wrapper.
```

### HOLD POINT 1 (Q&A Agent after Tasks 1-4)
```
Audit Tasks 1-4 for compliance:

1. OrderEngine class matches design.md lines 100-151? (structs, methods)
2. Idempotency system per design.md lines 221-260? (intent_id format, dedup)
3. Volume normalization per design.md lines 433-443? (SYMBOL_VOLUME_STEP, clamp)
4. Position limits match finalspec.md lines 31-34? (Max 2/1/2, enforce before OrderSend)
5. All unit tests passing? (22 total across 4 tasks)
6. MQL5 style? (no static, early returns, no array alias)

Provide pass/fail per item.
```

---

## TASK REFERENCE (2-24)

**For detailed prompts**, replicate Task 1 pattern using:
- **Specs**: `.kiro/specs/rpea-m3/{requirements.md (acceptance), design.md (implementation), tasks.md (scope)}`
- **Agent Flow**: Coding Agent → Unit Testing Agent → (HOLD POINT) → Q&A Agent

**Tasks 2-4**: Idempotency, Volume Norm, Order Placement  
**Tasks 5-6** → HOLD 2: Retry Policy, Market Fallback  
**Tasks 7-9** → HOLD 3: Atomics, OCO, Partial Fills  
**Tasks 10-11** → HOLD 4: Budget Gate, News CSV  
**Tasks 12-15**: Synthetics (Price Manager, Margin Calc, Proxy, Replication)  
**Tasks 16-18**: Queue Manager, Trailing, Audit Logging  
**Tasks 19-21**: Integration with risk/equity/news  
**Task 22**: E2E Tests + Fake Broker  
**Tasks 23-24**: Performance, Documentation

---

## PHASE 3: E2E TESTING

### E2E Testing Agent — Integration Tests
**Attach**: All M3 files

```
Generate E2E tests: integration_tests.mqh + fake_broker.mqh

FAKE BROKER: SetTestSeed(), SimulateOrderFill(), SimulateOrderReject(), SimulatePartialFill(), SimulateNetworkDelay(), SetMarketClosed(), SetInsufficientMargin()

TESTS:
1. Test_OCOFillAndCancel_EndToEnd: Place OCO, fill one, assert sibling cancelled, verify logs
2. Test_SyntheticReplicationRollback_EndToEnd: Two-leg XAUEUR, fail leg 2, assert leg 1 rollback
3. Test_NewsQueueProcessing_EndToEnd: Queue during news, execute post-news with revalidation
4. Test_PartialFillOCOAdjustment_EndToEnd: Partial fill 50%, assert sibling adjusted, OnTradeTxn before timer
5. Test_BudgetGateRejection_EndToEnd: Near limit, attempt order, assert rejection + log

Use TestSeed=12345. Pass 10 consecutive runs.
```

---

## AGENT HANDOFF TEMPLATES

### Coding → Unit Testing
```
@UnitTestingAgent Generate unit tests for Task X: [Name]
File: test_[component].mqh
Use test_risk.mqh pattern. TESTS: [list from tasks.md acceptance]
```

### Unit Testing → Coding (Fixes)
```
@CodingAgent Fix failing tests for Task X
FAILURES: [test_name: expected Y, got Z]
ROOT CAUSE: [analysis]
Fix [file].
```

### Q&A → Coding (Clarifications)
```
@CodingAgent Clarification for Task X
ISSUE: [desc]
SPEC: finalspec.md lines X-Y says "[quote]"
CURRENT: [what code does]
REQUIRED: [fix]
Update [file].
```

---

## TROUBLESHOOTING

**Agent loses context?**  
→ Re-invoke Repo-Info with summary request, prefix Coding prompt with context.

**MQL5 syntax errors?**  
→ Add to Coding prompt: `MQL5 CONSTRAINTS: Built-in types (string, int, double, datetime, bool), MQL5 containers (CArrayObj not std::vector), MqlTradeRequest/MqlTradeResult structs, no C++ STL.`

**Tests don't compile?**  
→ Attach test_framework.mqh, reference test_risk.mqh as template.

---

## BEST PRACTICES

✅ Run tests after every task  
✅ Commit after each HOLD POINT  
✅ Use `read_lints` after Coding Agent  
✅ Deterministic seeds for stress tests  
✅ Implement fake broker (Task 22) early  
✅ Never skip HOLD POINT reviews

---

## QUICK START

1. Phase 1: Repo-Info + Q&A validation (1 hour)
2. Tasks 1-4 → HOLD 1 → Audit → Proceed
3. Tasks 5-24 (repeat pattern) → HOLDs 2-4
4. Phase 3: E2E tests + Integration

**Total**: 20-30 hours agent-assisted (vs. 60-80 manual)  
**Human time**: 3-5 hours (reviews + final testing)

**Ready?** Start Phase 1: Repo-Info Agent. ✨

