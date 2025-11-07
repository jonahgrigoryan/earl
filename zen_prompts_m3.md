# Zencoder M3 Quick Implementation Guide

## START HERE: 3-Phase Workflow

### PHASE 1: Setup (1 hour)
1. **Repo-Info Agent** → Paste full context prompt (see below)
2. **Q&A Agent** → Run 5 validation queries to confirm understanding

### PHASE 2: Implement Tasks 1-24 (20 hours)
- **Pattern**: Coding Agent implements → Unit Testing Agent tests → Iterate
- **5 Implementation Phases**: Foundation (1-6) → OCO (7-8) → Risk/Trailing (9-13) → Integration (14-17) → Enhancements (21-24)
- **HOLD POINTs**: Q&A Agent audits at tasks 6, 8, 13, 17, 24

### PHASE 3: Integration (3 hours)
- **E2E Testing Agent** → Manual testing + optional integration tests

**Key Changes from Original Spec:**
- **24 tasks** (down from 28)
- **No atomic operations** (removed Task 7 - only needed for two-leg replication)
- **No replication mode** (removed Tasks 13-15 - XAUEUR is signal-only)
- **Simplified synthetic** (Task 11 - just price calculation for signals, execution maps to XAUUSD)

---

## PHASE 1 PROMPTS

### Repo-Info Agent — Context Seeding
```
Build RPEA M3 knowledge base. Analyze:

SPECS: finalspec.md, .kiro/specs/rpea-m3/{requirements.md, design.md, tasks.md}, m3_structure.md
M1/M2 CODE: RPEA.mq5, scheduler.mqh, signals_bwisc.mqh, risk.mqh, equity_guardian.mqh, news.mqh, persistence.mqh
STYLE: .cursor/rules/ea.mdc, .zencoder/rules/repo.md
TESTS: test_risk.mqh, test_signals_bwisc.mqh

KEY M3 SCOPE CHANGES:
- 24 tasks (not 28) - removed atomic operations and replication mode
- XAUEUR is signal-only (not execution) - Task 11 builds synthetic prices for BWISC signals
- When XAUEUR signal fires, execute on XAUUSD with SL/TP scaled by EURUSD rate (simple mapping in Task 15)
- No two-leg replication, no atomic rollback complexity
- 5-phase implementation: Foundation (1-6) → OCO (7-8) → Risk/Trailing (9-13) → Integration (14-17) → Enhancements (21-24)

Summarize: M1/M2 components, M3 simplified scope (Order Engine + XAUEUR signal generation), invariants (news, budget gate, OCO), MQL5 style (no static, no array alias, early returns).
```

### Q&A Agent — 5 Validation Queries
```
1. How does OnTimer scheduler interact with signal engines? Walk through flow.
2. Explain budget gate formula. What 5 inputs logged? Where does 0.9 headroom come from?
3. News compliance for Master accounts? OCO sibling cancellation during news?
4. How is XAUEUR used in M3? Is it executed as a pair or used for signals only?
5. MQL5 style constraints from .cursor/rules/ea.mdc?

EXPECTED ANSWER FOR #4:
XAUEUR is used as a SIGNAL SOURCE only. Task 11 builds synthetic prices (XAUUSD/EURUSD) and synthetic OHLC bars so BWISC can generate signals from XAUEUR data. When a signal fires, Task 15 maps execution to XAUUSD (proxy mode) with SL/TP distances scaled by current EURUSD rate. No two-leg replication, no atomic operations.
```

---

## PHASE 2: TASK TEMPLATES

### Sequenced Runbook (use this exact order)

**PHASE 1: Foundation (Tasks 1-6) - Days 1-4**
- Task 1: Order Engine scaffolding
- Task 2: Idempotency system
- Task 3: Volume/price normalization
- Task 4: Basic order placement
- Task 5: Simple retry logic
- Task 6: Market fallback + slippage
- **HOLD POINT 1** (Q&A Agent audit)

**PHASE 2: OCO + Partial Fills (Tasks 7-8) - Days 5-7**
- Task 7: OCO relationship management
- Task 8: Partial fill handler
- **HOLD POINT 2** (Q&A Agent audit)

**PHASE 3: Risk + Trailing + Queue (Tasks 9-13) - Days 8-11**
- Task 9: Budget gate with snapshot locking
- Task 10: News CSV fallback
- Task 11: Synthetic price manager (XAUEUR signals only)
- Task 12: Queue manager
- Task 13: Trailing stop management
- **HOLD POINT 3** (Q&A Agent audit)

**PHASE 4: Integration + Polish (Tasks 14-17) - Days 12-15**
- Task 14: Comprehensive audit logging
- Task 15: Integration + XAUEUR signal mapping
- Task 16: State recovery on startup
- Task 17: Error handling + resilience
- (Skip Tasks 18-20 for challenge - optional)
- **HOLD POINT 4** (Q&A Agent audit)

**PHASE 5: Performance Enhancements (Tasks 21-24) - Days 16-17**
- Task 21: Dynamic position sizing
- Task 22: Spread filter
- Task 23: Breakeven stop at +0.5R
- Task 24: Pending expiry optimization
- **HOLD POINT 5** (Q&A Agent audit)

**REMOVED TASKS (deferred post-challenge):**
- Original Task 7: Atomic Operation Manager (only needed for two-leg replication)
- Original Tasks 13-15: Replication Margin Calculator, Proxy Mode, Replication Mode (XAUEUR is signal-only)

---


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

CRITICAL EVENT ORDERING:
- OnTradeTransaction MUST process fills/partial fills IMMEDIATELY (before next OnTimer tick)
- OCO sibling adjustments and risk updates happen in OnTradeTransaction, NOT OnTimer
- OnTimer performs housekeeping, queued actions, and periodic checks AFTER transaction events

CONFIG: MaxRetryAttempts=3, InitialRetryDelayMs=300, RetryBackoffMultiplier=2.0, QueuedActionTTLMin=5, MaxSlippagePoints=10.0, EnableExecutionLock=true, MinHoldSeconds=120, AutoCancelOCOSibling=true, OCOCancellationTimeoutMs=1000, LogBufferSize=1000

STYLE: No static, early returns, explicit types, 1-2 nesting, [OrderEngine] logs

ACCEPTANCE: Inits without errors, OnTradeTransaction dispatches BEFORE OnTimer housekeeping, event sequence validated in unit tests, OnDeinit flushes journals and logs

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

### Task 2: Idempotency System with Intent Journal (Coding Agent)
**Attach**: Include/RPEA/persistence.mqh, Files/RPEA/state/intents.json, .kiro/specs/rpea-m3/tasks.md

```
Implement Task 2 from tasks.md: "Implement Idempotency System with Intent Journal"

GOAL: intent_id/action_id deduplication and state persistence for orders and queued actions.

FOCUS:
- Generate deterministic intent_id + action_id values; persist expiry, validation_threshold, retry_count.
- Restore intents on startup, drop duplicates, and ignore stomps using accept_once keys.
- Provide interfaces used by OrderEngine (create/update/query) and log dedup hits.

ACCEPTANCE: Duplicate intents rejected, queued duplicates ignored across restarts, metadata persisted in Files/RPEA/state/intents.json.
```

### Task 2: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/persistence.mqh, test_framework.mqh

```
Generate tests for Task 2: Idempotency System
File: test_persistence_intents.mqh

TESTS:
1. CreateIntent_DuplicateRejects(): create same intent twice -> second returns false.
2. PersistAndRestore_Intents(): write intents.json, reload, validate fields (expiry, validation_threshold, retry_count).
3. QueueAction_Dedup(): enqueue action with same action_id after restart -> ignored.
4. AcceptOnceKey_Protects(): unique key prevents replay when accept_once mismatched.
5. JournalFlush_WritesFile(): ensure file handle present and schema matches design document.

Provide TestPersistenceIntents_RunAll() wrapper.
```

### Task 3: Volume & Price Normalization (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, .kiro/specs/rpea-m3/design.md, .kiro/specs/rpea-m3/tasks.md

```
Implement Task 3 from tasks.md: "Create Volume and Price Normalization System"

GOAL: SYMBOL_VOLUME_STEP / SYMBOL_POINT compliant normalization helpers.

FOCUS:
- Implement OE_NormalizeVolume / OE_NormalizePrice per design (step rounding, clamps, stops-level guards).
- Add helper validations for volume range and point alignment.
- Wire logging for invalid inputs, return normalized values.

ACCEPTANCE: Volumes rounded to broker step and clamped to min/max; prices snap to point and respect SYMBOL_TRADE_STOPS_LEVEL.
```

### Task 3: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, test_framework.mqh

```
Generate tests for Task 3: Volume/Price Normalization
File: test_order_engine_normalization.mqh

TESTS:
1. NormalizeVolume_RoundsStep(): verify rounding to SYMBOL_VOLUME_STEP.
2. NormalizeVolume_ClampRange(): values below min or above max clamp properly.
3. NormalizePrice_RoundsPoint(): price snaps to grid.
4. NormalizePrice_StopsLevel(): reject price inside stops level distance.
5. ValidateVolumeRange_InvalidThrows(): invalid inputs flagged/logged.

Provide TestOrderEngineNormalization_RunAll().
```

### Task 4: Basic Order Placement with Position Limits (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/risk.mqh, .kiro/specs/rpea-m3/tasks.md

```
Implement Task 4 from tasks.md: "Implement Basic Order Placement with Position Limits"

GOAL: Place pending/market stubs with position + pending caps enforced.

FOCUS:
- Count open positions/pending orders per symbol + total before scheduling placement.
- Surface descriptive error when caps hit; integrate with risk checks.
- Stub OrderSend integration points for later tasks.

ACCEPTANCE: Orders blocked when limits exceeded and produce clear log entries; successful path respects cap counts.
```

### Task 4: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, test_framework.mqh

```
Generate tests for Task 4: Order Placement Limits
File: test_order_engine_limits.mqh

TESTS:
1. PlaceOrder_TotalCapBlocked(): simulate MaxOpenPositionsTotal reached -> expect failure.
2. PlaceOrder_SymbolCapBlocked(): per-symbol cap prevents new order.
3. PlaceOrder_PendingCapBlocked(): pending limit enforced.
4. PlaceOrder_SucceedsWithinCaps(): order allowed when under limits.
5. PlaceOrder_LogsReason(): verify log message includes cap type.

Provide TestOrderEngineLimits_RunAll().
```

### Task 5: Retry Policy System (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh, .kiro/specs/rpea-m3/design.md

```
Implement Task 5 from tasks.md: "Create Retry Policy System with MT5 Error Code Mapping"

GOAL: Centralized RetryManager with error-class policies.

FOCUS:
- Fail-fast for TRADE_DISABLED and NO_MONEY.
- Defaults: MaxRetryAttempts=3, InitialRetryDelayMs=300, RetryBackoffMultiplier=2.0.
- Exponential for CONNECTION/TIMEOUT; linear for REQUOTE/PRICE_OFF.
- Log retry_count and last retcode.

ACCEPTANCE: Error codes trigger correct retry behavior; backoff timing accurate.
```

### Task 5: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh, test_framework.mqh

```
Generate tests for Task 5: Retry Policy System
File: test_order_engine_retry.mqh

Use test_risk.mqh pattern.

TESTS:
1. Retry_FailFast_TradeDisabled(): TRADE_DISABLED returns false on first attempt.
2. Retry_FailFast_NoMoney(): NO_MONEY returns false on first attempt.
3. Retry_ExponentialBackoff(): CONNECTION code schedules ≤3 attempts with 300ms→600ms delays.
4. Retry_LinearBackoff(): REQUOTE uses linear step (300ms each) and stops at attempt 3.
5. Retry_PolicyLookup_Default(): Unknown code falls back to linear backoff.
6. Retry_LogIncludesLastRetcode(): Verify retry log captures retcode and attempt count.

Provide TestOrderEngineRetry_RunAll().
```

### Task 6: Market Order Fallback with Slippage (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh, .kiro/specs/rpea-m3/tasks.md

```
Implement Task 6 from tasks.md: "Implement Market Order Fallback with Slippage Protection"

GOAL: Controlled market execution when pendings fail.

FOCUS:
- Enforce MaxSlippagePoints; reject excessive slippage.
- Integrate RetryManager defaults (≤3 attempts, 300ms backoff); stop on fail-fast codes.
- Log requested vs executed price, slippage, retry_count.

ACCEPTANCE: Market orders reject excessive slippage; retry logic works correctly.
```

### Task 6: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh, test_framework.mqh

```
Generate tests for Task 6: Market Order Fallback
File: test_order_engine_market.mqh

Use test_risk.mqh pattern.

TESTS:
1. MarketFallback_RejectsHighSlippage(): Reject when slippage > MaxSlippagePoints.
2. MarketFallback_RetriesTransientError(): CONNECTION error retries ≤3 times with backoff.
3. MarketFallback_StopsOnFailFast(): NO_MONEY aborts immediately and surfaces error.
4. MarketFallback_StopsOnTradeDisabled(): TRADE_DISABLED aborts immediately without retry.
5. MarketFallback_LogsRequestedVsExecuted(): Log contains requested/executed price + slippage.
6. MarketFallback_SucceedsWithinLimits(): Successful path places market order when slippage acceptable.

Provide TestOrderEngineMarket_RunAll().
```

### HOLD POINT 1 (Q&A Agent after Tasks 1-6 - Phase 1 Complete)
```
Audit Phase 1 (Foundation) for compliance:

1. OrderEngine class matches design.md? (structs: OrderRequest, OrderResult, QueuedAction; methods: PlaceOrder, ModifyOrder, CancelOrder, etc.)
2. Event model correct? (OnInit→Init, OnTradeTransaction→OnTradeTxn BEFORE OnTimer, OnDeinit→OnShutdown)
3. Idempotency system working? (intent_id generation, dedup, persistence to Files/RPEA/state/intents.json)
4. Volume normalization per design? (SYMBOL_VOLUME_STEP rounding, min/max clamps)
5. Price normalization per design? (SYMBOL_POINT rounding, SYMBOL_TRADE_STOPS_LEVEL validation)
6. Position limits enforced? (MaxOpenPositionsTotal=2, MaxOpenPerSymbol=1, MaxPendingsPerSymbol=2)
7. Retry logic working? (MaxRetryAttempts=3, InitialRetryDelayMs=300, fail-fast on NO_MONEY/TRADE_DISABLED)
8. Market fallback working? (MaxSlippagePoints enforcement, retry integration)
9. All unit tests passing? (Tasks 1-6)
10. MQL5 style? (no static, early returns, no array alias, explicit types)
11. Compiles without errors?

Provide pass/fail per item. If any fail, specify which task needs fixes.
```

### Task 7: OCO Relationship Management (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, .kiro/specs/rpea-m3/tasks.md

```
Implement Task 7 from tasks.md: "Implement OCO Relationship Management"

GOAL: OCO creation, expiry alignment, sibling cancel/resize.

FOCUS:
- Track OCO pairs with expiry aligned to session cutoff; store metadata.
- On fill: immediate sibling cancel or risk-reduction resize.
- Log OCO actions and expiry metadata.

CONFIG: AutoCancelOCOSibling=true, OCOCancellationTimeoutMs=1000, EnableRiskReductionSiblingCancel=true

ACCEPTANCE: OCO relations behave per acceptance; metadata tracked.
```

### Task 7: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh, test_framework.mqh

```
Generate tests for Task 7: OCO Relationship Management
File: test_order_engine_oco.mqh

Use test_risk.mqh pattern.

TESTS:
1. OCO_EstablishStoresMetadata(): Establish pair, verify expiry and sibling tickets tracked.
2. OCO_FillCancelsSibling(): Fill primary, assert sibling cancelled within OCOCancellationTimeoutMs.
3. OCO_RiskReductionResize(): Enable risk reduction, assert sibling volume resized accurately.
4. OCO_ReestablishAfterCancel(): Ensure cancelled sibling clears relationship state.
5. OCO_LogsActions(): Verify logs include establishment, cancellation, and resize entries.

Provide TestOrderEngineOCO_RunAll().
```

### Task 8: Partial Fill Handler (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, .kiro/specs/rpea-m3/design.md

```
Implement Task 8 from tasks.md: "Create Partial Fill Handler with OCO Volume Adjustment"

GOAL: Adjust sibling volume on partials via OnTradeTransaction.

FOCUS:
- Detect partial fills; compute remaining and sibling volume with exact math.
- Apply before next timer cycle; aggregate multiple fills.

ACCEPTANCE: Partial fills adjust sibling before next timer; aggregation works.
```

### Task 8: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, test_framework.mqh

```
Generate tests for Task 8: Partial Fill Handler
File: test_order_engine_partialfills.mqh

Use test_risk.mqh pattern.

TESTS:
1. PartialFill_AdjustsSiblingVolume(): 50% fill shrinks sibling volume using exact ratio math.
2. PartialFill_AggregatesMultipleEvents(): Multiple partials accumulate correctly before completion.
3. PartialFill_CompletesOnLastShare(): Final fill clears partial state and fires completion logic.
4. PartialFill_RejectedIfNoSibling(): Ensure handler guards when sibling missing.
5. PartialFill_LogsAdjustments(): Verify log entries capture fill volume and sibling adjustment.

Provide TestOrderEnginePartialFills_RunAll().
```

### HOLD POINT 2 (Q&A Agent after Tasks 7-8 - Phase 2 Complete)
```
Audit Phase 2 (OCO + Partial Fills) for compliance:

1. OCO relationships tracked? (ticket pairs, expiry aligned to session cutoff, metadata stored)
2. OCO sibling cancellation working? (fill triggers immediate cancel of opposite side)
3. OCO expiry working? (pendings expire at session cutoff or after configured TTL)
4. Risk-reduction safety working? (if fill would exceed risk limits, sibling cancelled/resized)
5. Partial fill detection working? (OnTradeTransaction processes fills immediately)
6. OCO volume adjustment working? (sibling volume adjusted using fill ratio math: sibling_vol × (filled/requested))
7. Partial fill aggregation working? (multiple partials tracked correctly)
8. OnTradeTransaction fires BEFORE OnTimer? (critical for OCO adjustments)
9. All unit tests passing? (Tasks 7-8)
10. Integration test: Place OCO, fill one side, verify other cancels?

Provide pass/fail per item. Test OCO in Strategy Tester before proceeding.
```

### Task 9: Budget Gate (Coding Agent)
**Attach**: Include/RPEA/risk.mqh, Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh

```
Implement Task 9 from tasks.md: "Implement Budget Gate with Position Snapshot Locking"

GOAL: Enforce open+pending+next ≤ 0.9 × min(room_today, room_overall) under a lock.

FOCUS:
- Lock position snapshot; compute five inputs; log gate_pass boolean and gating_reason.

CONFIG: BudgetGateLockMs=1000, RiskGateHeadroom=0.90

ACCEPTANCE: Snapshot locking used; five inputs and gate_pass logged.
```

### Task 9: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh, test_framework.mqh

```
Generate tests for Task 9: Budget Gate Snapshot
File: test_order_engine_budgetgate.mqh

Use test_risk.mqh pattern.

TESTS:
1. BudgetGate_PassesWithinHeadroom(): Proposed risk below 0.9 × min(room_today, room_overall) passes.
2. BudgetGate_BlocksOverHeadroom(): Exceeding threshold rejects with gating_reason logged.
3. BudgetGate_UsesSnapshotLock(): Validate lock acquired/released and snapshot frozen during check.
4. BudgetGate_LogsFiveInputs(): Verify log prints open_risk, pending_risk, next_trade, room_today, room_overall.
5. BudgetGate_LockTimeout(): Simulate lock contention → ensure fallback handling/logging.

Provide TestOrderEngineBudgetGate_RunAll().
```

### Task 10: News CSV Fallback (Coding Agent)
**Attach**: Include/RPEA/news.mqh, Include/RPEA/config.mqh

```
Implement Task 10 from tasks.md: "Create News CSV Fallback System"

GOAL: Parse CSV fallback with schema and staleness checks.

FOCUS:
- Required columns: timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min.
- Enforce NewsCSVMaxAgeHours; read path from NewsCSVPath; reject bad schema.
- Integrate block predicate for affected symbols/legs.

CONFIG: NewsCSVPath="Files/RPEA/news/calendar_high_impact.csv", NewsCSVMaxAgeHours=24

ACCEPTANCE: CSV fallback works when API fails; stale data rejected.
```

### Task 10: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/news.mqh, Include/RPEA/config.mqh, test_framework.mqh

```
Generate tests for Task 10: News CSV Fallback
File: test_news_csv_fallback.mqh

Use test_risk.mqh pattern.

TESTS:
1. CSVParser_ValidSchemaLoads(): Valid CSV with required columns loads successfully.
2. CSVParser_InvalidSchemaRejected(): Missing column triggers schema failure.
3. CSVParser_StaleFileRejected(): File older than NewsCSVMaxAgeHours rejected.
4. CSVParser_ParsesPrePostBuffers(): prebuffer/postbuffer minutes parsed correctly.
5. CSVParser_LogsLoadResult(): Verify log includes path and event count on success/failure.

Provide TestNewsCSVFallback_RunAll().
```



### Task 11: Synthetic Price Manager for Signal Generation (Coding Agent)
**Attach**: .kiro/specs/rpea-m3/design.md, .kiro/specs/rpea-m3/tasks.md, Include/RPEA/synthetic.mqh, Include/RPEA/indicators.mqh

```
Implement Task 11 from tasks.md: "Create Synthetic Price Manager for Signal Generation"

GOAL: Build XAUEUR synthetic prices and bars for BWISC signal generation (NOT for execution).

FOCUS:
- Implement GetSyntheticPrice: XAUEUR = XAUUSD / EURUSD (use consistent bid/bid or ask/ask)
- Implement BuildSyntheticBars: synchronize M1 bars from XAUUSD and EURUSD, forward-fill gaps (max MaxGapBars=5)
- Cache synthetic OHLC bars for ATR/MA/RSI calculations (SyntheticBarCacheSize=1000)
- Quote staleness check: reject if either XAUUSD or EURUSD quote age > QuoteMaxAgeMs (5000ms)
- NO execution logic - this is signal generation only
- Log synthetic price calculations for debugging

CONFIG: SyntheticBarCacheSize=1000, ForwardFillGaps=true, MaxGapBars=5, QuoteMaxAgeMs=5000

CRITICAL: XAUEUR is used as a SIGNAL SOURCE only. When BWISC generates a signal from XAUEUR data, Task 15 will map execution to XAUUSD (proxy mode). Do NOT implement two-leg execution or replication logic.

ACCEPTANCE: XAUEUR synthetic prices calculated correctly (XAUUSD/EURUSD), synthetic OHLC bars available for ATR/MA/RSI, forward-fill works with max 5 gap bars, quote staleness enforced, BWISC can generate signals from XAUEUR data, no execution code present.

Expected: ~200 lines
```

### Task 11: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/synthetic.mqh, Include/RPEA/config.mqh, test_framework.mqh

```
Generate tests for Task 11: Synthetic Price Manager
File: test_synthetic_manager.mqh

Use test_risk.mqh pattern.

TESTS:
1. SyntheticPrice_ComputesXAUEUR(): Verify XAUEUR = XAUUSD / EURUSD using bid prices.
2. SyntheticBars_BuildsWithForwardFill(): Missing bars ≤ MaxGapBars forward-filled correctly.
3. SyntheticBars_RejectsLargeGaps(): Gaps > MaxGapBars cause failure/log warning.
4. SyntheticQuotes_StalenessCheck(): Quote age > QuoteMaxAgeMs rejected.
5. SyntheticCache_ReusesData(): Consecutive requests served from cache within timeframe.

Provide TestSyntheticManager_RunAll().
```



### Task 12: Queue Manager (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh

```
Implement Task 12 from tasks.md: "Create Queue Manager with Bounds and TTL Management"

GOAL: News-window action queuing with bounds and TTL.

FOCUS:
- Enforce MaxQueueSize; reject or evict actions when limit reached using back-pressure policy (drop oldest non-risk-reduction first).
- TTL expiration governed by QueueTTLMinutes; expired actions auto-removed with log entries.
- Prioritize risk-reduction actions; allow trailing/SLTP modifications only post-news revalidation.
- Preconditions validated before execution (price drift, position still open, intent not stale).

CONFIG: MaxQueueSize=1000, QueueTTLMinutes=5, EnableQueuePrioritization=true, EnableRiskReductionSiblingCancel=true

ACCEPTANCE: Queue bounds respected; TTL works; precondition validation enforced.
```

### Task 12: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh, test_framework.mqh

```
Generate tests for Task 12: Queue Manager
File: test_order_engine_queue.mqh

Use test_risk.mqh pattern.

TESTS:
1. Queue_EnforcesMaxSize(): Hitting MaxQueueSize triggers overflow policy (evict oldest non-risk reduction).
2. Queue_DropsExpiredActions(): Actions exceeding QueueTTLMinutes removed and logged.
3. Queue_PrioritizesRiskReduction(): Risk-reduction actions executed before trailing updates.
4. Queue_RevalidatesPreconditions(): Invalidated action (position closed) skipped with log.
5. Queue_AllowsPostNewsExecution(): Action queued during news executes after window closes.

Provide TestOrderEngineQueue_RunAll().
```

### Task 13: Trailing Stop Management (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, .kiro/specs/rpea-m3/design.md

```
Implement Task 13 from tasks.md: "Implement Trailing Stop Management with Queue Integration"

GOAL: Trailing activates at +1R; queues during news; revalidates afterward.

FOCUS:
- Activate when ≥ +1R; move SL by ATR*TrailMult; integrate with queue manager.
- Drop stale queued actions per TTL.

ACCEPTANCE: Trailing/queue behavior matches acceptance; tests pass.
```

### Task 13: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, test_framework.mqh

```
Generate tests for Task 13: Trailing Stop Management
File: test_order_engine_trailing.mqh

Use test_risk.mqh pattern.

TESTS:
1. Trailing_ActivatesAtOneR(): Reaches +1R → trailing adjustment queued/applied.
2. Trailing_RespectsNewsQueue(): During news, adjustment queued rather than executed.
3. Trailing_RevalidatesAfterNews(): Post-news execution rechecks price conditions before modifying.
4. Trailing_DropsExpiredQueuedAction(): Stale queued trailing update expires per TTL.
5. Trailing_LogsAdjustments(): Verify log captures old/new SL values and reason.

Provide TestOrderEngineTrailing_RunAll().
```

### HOLD POINT 3 (Q&A Agent after Tasks 9-13 - Phase 3 Complete)
```
Audit Phase 3 (Risk + Trailing + Queue) for compliance:

1. Budget gate uses position snapshots? (locks positions before calculating risk)
2. Budget gate formula correct? (open_risk + pending_risk + next_trade ≤ 0.9 × min(room_today, room_overall))
3. Budget gate logs 5 inputs? (open_risk, pending_risk, next_trade, room_today, room_overall + gate_pass boolean)
4. Config keys present? (BudgetGateLockMs, RiskGateHeadroom=0.90)
5. News CSV fallback working? (schema validation, staleness check, NewsCSVMaxAgeHours enforcement)
6. News CSV schema correct? (timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min)
7. Synthetic price manager working? (XAUEUR = XAUUSD / EURUSD calculation)
8. Synthetic bars building? (forward-fill for gaps with MaxGapBars=5, available for ATR/MA/RSI)
9. Quote staleness enforced? (reject if XAUUSD or EURUSD quote age > QuoteMaxAgeMs=5000ms)
10. XAUEUR used for SIGNALS ONLY? (not execution - verify no two-leg orders)
11. Queue manager working? (MAX_QUEUE_SIZE, TTL expiration, prioritization)
12. Trailing activates at +1R? (moves SL by ATR × TrailMult)
13. Trailing queues during news? (updates queued, executed post-news with precondition checks)
14. All unit tests passing? (Tasks 9-13)

Provide pass/fail per item. Test trailing + queue in Strategy Tester.
```

### Task 14: Comprehensive Audit Logging (Coding Agent)
**Attach**: Include/RPEA/logging.mqh, Files/RPEA/logs/

```
Implement Task 14 from tasks.md: "Create Comprehensive Audit Logging System"

GOAL: Output full CSV row per placement/adjust/cancel with required fields.

FOCUS:
- Columns: timestamp,intent_id,action_id,symbol,mode(proxy|repl),requested_price,executed_price,requested_vol,filled_vol,remaining_vol,tickets[],retry_count,gate_open_risk,gate_pending_risk,gate_next_risk,room_today,room_overall,gate_pass,decision,confidence,efficiency,rho_est,est_value,hold_time,gating_reason,news_window_state
- Rotate daily; schema-validate in tests
- Buffer size: LogBufferSize=1000 entries before flush

CONFIG: AuditLogPath="Files/RPEA/logs/", LogBufferSize=1000, EnableDetailedLogging=true

ACCEPTANCE: CSV matches schema exactly (including rho_est column); all activities logged; daily rotation works; buffer flushes correctly.
```

### Task 15: Integration with Risk Management and XAUEUR Signal Mapping (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/allocator.mqh, Experts/FundingPips/RPEA.mq5, .kiro/specs/rpea-m3/tasks.md

```
Implement Task 15 from tasks.md: "Integrate Order Engine with Existing Risk Management and XAUEUR Signal Mapping"

GOAL: Full integration with risk/equity/news + XAUEUR synthetic signal mapping to XAUUSD execution.

FOCUS:
- Integrate with risk.mqh, equity_guardian.mqh, news.mqh (no logic duplication)
- Respect caps and rooms; use News_IsBlocked
- **Master Account SL Enforcement**: On funded (Master) accounts, SL must be set within 30 seconds of opening; log enforcement status (on-time vs late) with timestamp
- **XAUEUR Signal Mapping**: When signal_symbol == "XAUEUR", execute on "XAUUSD" with SL/TP distances scaled by current EURUSD rate
- Implement GetExecutionSymbol(signal_symbol) → returns "XAUUSD" for "XAUEUR", otherwise returns signal_symbol
- Implement MapSLDistance(signal_symbol, exec_symbol, sl_distance) → multiplies by EURUSD rate for XAUEUR signals
- Log XAUEUR signal mapping: "[OrderEngine] XAUEUR signal mapped to XAUUSD: sl_synth=X, eurusd=Y, sl_xau=Z"
- Log Master SL enforcement: "[OrderEngine] Master SL set: ticket=X, elapsed=Ys, status=ON_TIME|LATE"
- Protective exits (SL/TP/kill-switch) always allowed during news windows

CRITICAL: XAUEUR signals execute as single-leg XAUUSD orders (proxy mode). No two-leg replication, no atomic operations.

ACCEPTANCE: Order engine respects all risk constraints; XAUEUR signals map to XAUUSD execution with proper SL/TP distance scaling (multiply by EURUSD rate); Master accounts set SL within 30s and log enforcement status (on-time vs late with timestamp); integration seamless.

Expected: ~150 lines
```

### Task 15: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/allocator.mqh, Include/RPEA/config.mqh, test_framework.mqh

```
Generate tests for Task 15: Integration + XAUEUR Mapping
File: test_order_engine_integration.mqh

Use test_risk.mqh pattern.

TESTS:
1. Integration_XAUEURMapsToXAUUSD(): XAUEUR signal produces XAUUSD order with EURUSD-scaled SL/TP.
2. Integration_MasterSLEnforced(): Master account sets SL within 30s; late enforcement flagged/logged.
3. Integration_RiskRespectRoom(): Order rejected when budget gate denies allocation.
4. Integration_NewsBlocksEntries(): News filter blocks entries during news while allowing protective exits.
5. Integration_LogsMapping(): Verify log entry contains sl_synth, eurusd, sl_xau values.

Provide TestOrderEngineIntegration_RunAll().
```

### Task 16: State Recovery and Reconciliation (Coding Agent)
**Attach**: Include/RPEA/persistence.mqh, Include/RPEA/order_engine.mqh

```
Implement Task 16 from tasks.md: "Implement State Recovery and Reconciliation on Startup"

GOAL: Restore intents/queued actions; reconcile broker state before actions.

FOCUS:
- Load intent journal; dedup queued actions via action_id; reconcile open positions/orders.
- Log discrepancies and corrections.

ACCEPTANCE: Full recovery on restart; broker reconciliation correct.
```

### Task 16: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/persistence.mqh, Include/RPEA/order_engine.mqh, test_framework.mqh

```
Generate tests for Task 16: State Recovery
File: test_order_engine_recovery.mqh

Use test_risk.mqh pattern.

TESTS:
1. Recovery_RestoresIntents(): Persisted intents reload into engine state on init.
2. Recovery_DedupsQueuedActions(): Duplicate action_id ignored after restart.
3. Recovery_ReconcilesBrokerPositions(): Broker tickets missing from journal get reattached/logged.
4. Recovery_HandlesCorruptIntent(): Invalid JSON entry skipped with warning.
5. Recovery_LogsSummary(): Startup logs include counts of intents, queued actions, and reconciled tickets.

Provide TestOrderEngineRecovery_RunAll().
```

### Task 17: Error Handling and Resilience (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh

```
Implement Task 17 from tasks.md: "Add Comprehensive Error Handling and Resilience Features"

GOAL: Self-healing behaviors for transient failures.

FOCUS:
- Classify errors; retries, circuit breakers, backoff; safe aborts on irrecoverable states.
- Actionable logs and metrics.

ACCEPTANCE: Handles error conditions gracefully; self-heals when possible.
```

### Task 17: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh, test_framework.mqh

```
Generate tests for Task 17: Error Handling & Resilience
File: test_order_engine_errors.mqh

Use test_risk.mqh pattern.

TESTS:
1. ErrorHandling_ClassifiesFailFast(): TRADE_DISABLED/NO_MONEY trigger fail-fast path.
2. ErrorHandling_TriggersCircuitBreaker(): Consecutive failures trip circuit breaker and pause execution.
3. ErrorHandling_RetriesRecoverable(): CONNECTION errors retry with backoff, then succeed.
4. ErrorHandling_LogsAlerts(): Critical errors emit actionable log entries.
5. ErrorHandling_ResetsAfterRecovery(): After successful execution, circuit breaker resets.

Provide TestOrderEngineErrors_RunAll().
```

### HOLD POINT 4 (Q&A Agent after Tasks 14-17 - Phase 4 Complete)
```
Audit Phase 4 (Integration + Polish) for compliance:

1. Audit logging complete? (all required CSV columns present: timestamp, intent_id, action_id, symbol, mode, prices, volumes, tickets, retry_count, gate metrics, confidence, efficiency, rho_est, news_window_state)
2. CSV schema matches spec? (verify column order and format, including rho_est)
3. Log buffer working? (LogBufferSize=1000, flushes correctly)
4. Integration with risk/equity/news working? (no logic duplication, uses existing modules)
5. XAUEUR signal mapping working? (when signal_symbol=="XAUEUR", executes on "XAUUSD" with SL/TP scaled by EURUSD rate)
6. XAUEUR mapping logic in Task 15? (verify GetExecutionSymbol and MapSLDistance functions)
7. Master account SL enforcement? (SL set within 30 seconds on funded accounts, enforcement status logged with timestamp: ON_TIME vs LATE)
8. State recovery working? (intents/queued actions restored on restart, broker reconciliation)
9. Error handling comprehensive? (network outages, margin failures, actionable logs)
10. All unit tests passing? (Tasks 14-17)
11. End-to-end test passes? (signal → risk check → order → fill → trailing → close)
12. XAUEUR end-to-end test passes? (XAUEUR signal → XAUUSD execution with scaled SL/TP)

Provide pass/fail per item. Run full end-to-end test in Strategy Tester.
```

### Task 18: Integration Tests (Testing Agent) - OPTIONAL
**Attach**: Tests/RPEA/integration_tests.mqh, Include/RPEA/order_engine.mqh

```
Implement Task 18 from tasks.md: "Create Integration Tests for End-to-End Order Flows"

NOTE: This task is optional for challenge. Manual testing in Strategy Tester is acceptable.

GOAL: E2E suite covering OCO, news queues, budget gate rejection, XAUEUR signal mapping.

FOCUS:
- Test OCO fill and cancel
- Test news queue processing
- Test partial fill adjustment
- Test budget gate rejection
- Test XAUEUR signal → XAUUSD execution mapping

ACCEPTANCE: Integration tests pass, or manual testing in Strategy Tester confirms all scenarios work.
```

### Task 19: Performance Optimization (Coding Agent) - OPTIONAL
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/synthetic.mqh

```
Implement Task 19 from tasks.md: "Implement Performance Optimization and Memory Management"

NOTE: This task is optional for challenge. Skip if time-constrained.

GOAL: Keep CPU <2%, memory bounded.

FOCUS:
- Cache hot paths; avoid redundant symbol property calls; cap queue sizes.
- Leak checks; micro-optimizations where profiling indicates.

ACCEPTANCE: CPU remains low; memory stable; no regressions.
```

### Task 20: Documentation and Configuration Validation (Coding Agent) - OPTIONAL
**Attach**: Include/RPEA/config.mqh, README.md

```
Implement Task 20 from tasks.md: "Create Documentation and Configuration Validation"

NOTE: This task is optional for challenge. Skip if time-constrained.

GOAL: Validate parameters and document configuration.

FOCUS:
- Startup validation for inputs (ranges, dependencies); clear error messages.
- README updates with configuration keys and defaults.
- Validate all config parameters from design.md including: MaxRetryAttempts, InitialRetryDelayMs, RetryBackoffMultiplier, QueuedActionTTLMin, MaxSlippagePoints, BudgetGateLockMs, RiskGateHeadroom, NewsCSVMaxAgeHours, QuoteMaxAgeMs, MaxQueueSize, QueueTTLMinutes, EnableRiskReductionSiblingCancel, EnableQueuePrioritization.
- Document config parameter dependencies (e.g., QueueTTLMinutes must be ≤ NewsBufferS/60).

ACCEPTANCE: All parameters validated on startup with range checks; documentation includes complete config reference with defaults, ranges, and dependencies; validation failures produce actionable error messages.
```



### Task 21: Dynamic Position Sizing (Coding Agent)
**Attach**: Include/RPEA/risk.mqh, Include/RPEA/allocator.mqh

```
Implement Task 21 from tasks.md: "Implement Dynamic Position Sizing Based on Confidence"

GOAL: Scale risk by BWISC confidence to increase size on high-confidence setups.

FOCUS:
- Formula: effective_risk = RiskPct × confidence
- High confidence (|Bias| ≥ 0.8) → larger position (e.g., 0.9 conf → 1.35% risk)
- Low confidence (|Bias| = 0.6) → smaller position (e.g., 0.7 conf → 1.05% risk)
- Unit tests for risk scaling at different confidence levels

ACCEPTANCE: Position sizes scale with confidence; high-confidence setups get larger sizes.

Expected: ~10 lines
```

### Task 21: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/risk.mqh, Include/RPEA/allocator.mqh, test_framework.mqh

```
Generate tests for Task 21: Dynamic Position Sizing
File: test_risk_dynamic_sizing.mqh

Use test_risk.mqh pattern.

TESTS:
1. DynamicSizing_HighConfidenceUpsizes(): |Bias|=0.9 increases effective risk as expected.
2. DynamicSizing_LowConfidenceDownsizes(): |Bias|=0.6 reduces effective risk proportionally.
3. DynamicSizing_FloorsAtZero(): Confidence=0 yields zero additional risk allocation.
4. DynamicSizing_CapsAtMaxRisk(): Confidence=1.0 respects configured RiskPct ceiling.
5. DynamicSizing_LogsAdjustment(): Verify log outputs original vs scaled risk.

Provide TestRiskDynamicSizing_RunAll().
```

### Task 22: Spread Filter (Coding Agent)
**Attach**: Include/RPEA/liquidity.mqh

```
Implement Task 22 from tasks.md: "Add Spread Filter to Liquidity Check"

GOAL: Reject trades when spread exceeds threshold relative to ATR.

FOCUS:
- Logic: Reject if current_spread > ATR × 0.005 (0.5% of ATR, configurable)
- Get current spread: SymbolInfoInteger(symbol, SYMBOL_SPREAD) × SymbolInfoDouble(symbol, SYMBOL_POINT)
- Compare to ATR threshold
- Log rejection with spread value

ACCEPTANCE: Wide spreads (e.g., XAUUSD > 50 points during news) block entry; normal spreads allow entry.

Expected: ~15 lines
```

### Task 22: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/liquidity.mqh, Include/RPEA/config.mqh, test_framework.mqh

```
Generate tests for Task 22: Spread Filter
File: test_liquidity_spread_filter.mqh

Use test_risk.mqh pattern.

TESTS:
1. SpreadFilter_BlocksWideSpread(): Spread > ATR×0.005 rejects trade.
2. SpreadFilter_AllowsNormalSpread(): Spread below threshold permits trade.
3. SpreadFilter_LogsRejectionReason(): Log includes spread value and threshold used.
4. SpreadFilter_RespectsConfigMultiplier(): Adjusting multiplier changes threshold outcome.
5. SpreadFilter_HandlesMissingATR(): Missing ATR data triggers safe rejection/log warning.

Provide TestLiquiditySpreadFilter_RunAll().
```

### Task 23: Breakeven Stop (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh

```
Implement Task 23 from tasks.md: "Implement Breakeven Stop at +0.5R"

GOAL: Move SL to breakeven at +0.5R profit to protect winners early.

FOCUS:
- At +0.5R → move SL to entry + spread buffer
- At +1R → activate trailing (existing logic)
- Unit tests for breakeven trigger
- Integration tests for SL modification

ACCEPTANCE: Positions move to breakeven at +0.5R; trailing activates at +1R; converts potential losers to breakevens.

Expected: ~20 lines
```

### Task 23: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, test_framework.mqh

```
Generate tests for Task 23: Breakeven Stop
File: test_order_engine_breakeven.mqh

Use test_risk.mqh pattern.

TESTS:
1. Breakeven_TriggersAtHalfR(): Profit reaches +0.5R → SL moves to entry + spread buffer.
2. Breakeven_DoesNotTriggerEarly(): Profit < +0.5R leaves SL untouched.
3. Breakeven_PassesControlAtOneR(): Profit ≥ +1R activates trailing without duplicate adjustments.
4. Breakeven_LogsUpdate(): Log includes previous SL, new SL, and buffer applied.
5. Breakeven_ProtectsProfit(): After breakeven, price reversal exits at break-even rather than loss.

Provide TestOrderEngineBreakeven_RunAll().
```

### Task 24: Pending Expiry Optimization (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh

```
Implement Task 24 from tasks.md: "Optimize Pending Order Expiry Timing"

GOAL: Expire pending orders after 45 minutes if not filled to avoid stale fills.

FOCUS:
- Set pending expiry to TimeCurrent() + (45 × 60) instead of session cutoff
- Apply to all pending orders (OCO and single)
- Unit tests for expiry time calculation

ACCEPTANCE: Pending orders expire 45 minutes after placement if not filled; prevents stale fills.

Expected: ~5 lines
```

### Task 24: Unit Tests (Unit Testing Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh, test_framework.mqh

```
Generate tests for Task 24: Pending Expiry Optimization
File: test_order_engine_pending_expiry.mqh

Use test_risk.mqh pattern.

TESTS:
1. PendingExpiry_Sets45Minutes(): Expiry equals TimeCurrent() + 45×60 seconds.
2. PendingExpiry_AppliesToAllPendings(): OCO legs and singles receive same expiry window.
3. PendingExpiry_AutoCancelsExpired(): Expired pending orders cancelled and logged.
4. PendingExpiry_HonorsCustomExpiry(): Manual expiry override preserved when provided.
5. PendingExpiry_LogsExpirySet(): Log entry records new expiry timestamp and rationale.

Provide TestOrderEnginePendingExpiry_RunAll().
```

### HOLD POINT 5 (Q&A Agent after Tasks 21-24 - Phase 5 Complete)
```
Audit Phase 5 (Performance Enhancements) for compliance:

1. Dynamic position sizing working? (effective_risk = RiskPct × confidence)
2. High confidence setups get larger sizes? (|Bias| ≥ 0.8 → larger position)
3. Low confidence setups get smaller sizes? (|Bias| = 0.6 → smaller position)
4. Spread filter working? (rejects when current_spread > ATR × 0.005)
5. Wide spreads blocked? (e.g., XAUUSD > 50 points during news)
6. Breakeven stop working? (SL moves to entry + buffer at +0.5R)
7. Trailing still activates at +1R? (after breakeven)
8. Pending expiry optimization working? (expires after 45 minutes if not filled)
9. All unit tests passing? (Tasks 21-24)
10. Performance tests pass? (position sizing scales correctly, spread filter blocks bad fills, breakeven protects winners)

Provide pass/fail per item. Test enhancements in Strategy Tester with various scenarios.
```

---

## TASK REFERENCE (2-24)

**For detailed prompts**, replicate Task 1 pattern using:
- **Specs**: `.kiro/specs/rpea-m3/{requirements.md (acceptance), design.md (implementation), tasks.md (scope)}`
- **Agent Flow**: Coding Agent → Unit Testing Agent → (HOLD POINT) → Q&A Agent

**Tasks 1-4**: Scaffolding, intents, normalization, placement  
**Tasks 5-6** → HOLD 1: Retry policy, market fallback  
**Tasks 7-8** → HOLD 2: OCO management, partial fills  
**Tasks 9-13** → HOLD 3: Budget gate, news fallback, synthetic signals, queue, trailing  
**Tasks 14-17** → HOLD 4: Audit logging, integration, recovery, resilience  
**Task 18**: Integration tests (optional)  
**Tasks 19-20**: Performance + documentation polish (optional)  
**Tasks 21-24** → HOLD 5: Confidence sizing, spread filter, breakeven, expiry

---

## PHASE 3: E2E TESTING

### E2E Testing Agent — Integration Tests
**Attach**: All M3 files

```
Generate E2E tests: integration_tests.mqh + fake_broker.mqh

FAKE BROKER: SetTestSeed(), SimulateOrderFill(), SimulateOrderReject(), SimulatePartialFill(), SimulateNetworkDelay(), SetMarketClosed(), SetInsufficientMargin()

TESTS:
1. Test_OCOFillAndCancel_EndToEnd: Place OCO, fill one, assert sibling cancelled, verify logs
2. Test_XAUEURProxyMapping_EndToEnd: Fire XAUEUR signal, verify XAUUSD order with EURUSD-scaled SL/TP
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
✅ Implement fake broker (Task 18) early  
✅ Never skip HOLD POINT reviews

---

## QUICK START

1. **Phase 1: Setup** → Repo-Info + Q&A validation (1 hour)
2. **Phase 1: Foundation** → Tasks 1-6 → HOLD 1 → Audit
3. **Phase 2: OCO** → Tasks 7-8 → HOLD 2 → Audit
4. **Phase 3: Risk/Trailing** → Tasks 9-13 → HOLD 3 → Audit
5. **Phase 4: Integration** → Tasks 14-17 → HOLD 4 → Audit
6. **Phase 5: Enhancements** → Tasks 21-24 → HOLD 5 → Audit
7. **Phase 3: Testing** → Manual testing in Strategy Tester

**Total**: 17-22 days (20-30 hours agent-assisted vs. 60-80 manual)  
**Human time**: 3-5 hours (reviews + final testing)

**Key Simplifications:**
- 24 tasks (not 28) - removed atomic operations and replication
- XAUEUR is signal-only (Task 11) - execution maps to XAUUSD (Task 15)
- No two-leg replication complexity
- Optional tasks: 18-20 (can skip for challenge)

**Ready?** Start Phase 1: Repo-Info Agent. ✨
