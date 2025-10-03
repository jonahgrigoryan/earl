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

## PHASE 2: TASK TEMPLATES

### Sequenced Runbook (use this exact order)
- Tasks 1 → 2 → 3 → 4, then HOLD POINT 1
- Tasks 5 → 6, then HOLD POINT 2
- Tasks 7 → 8 → 9, then HOLD POINT 3
- Tasks 10 → 11, then HOLD POINT 4
- Tasks 12 → 13 → 14 → 15 → 16 → 17 → 18, then HOLD POINT 5
- Tasks 19 → 20 → 21 → 22 → 23 → 24, then HOLD POINT 6

Note: Templates below are provided per task but may not appear strictly in numeric order. Always follow the Sequenced Runbook above and use the corresponding “Task X” template section.

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

CONFIG: MaxRetryAttempts=3, InitialRetryDelayMs=300, RetryBackoffMultiplier=2.0, QueuedActionTTLMin=5, MaxSlippagePoints=10.0, EnableExecutionLock=true, PendingExpiryGraceSeconds=60, AutoCancelOCOSibling=true, OCOCancellationTimeoutMs=1000

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

### HOLD POINT 2 (Q&A Agent after Tasks 5-6)
```
Audit Tasks 5-6 for compliance:

1. RetryManager applies MT5 error policies per design (fail-fast for NO_MONEY/TRADE_DISABLED, exponential for CONNECTION/TIMEOUT, linear for REQUOTE/PRICE_OFF) and respects MaxRetryAttempts, InitialRetryDelayMs, RetryBackoffMultiplier.
2. Market fallback enforces MaxSlippagePoints, logs rejection reason + slippage, and stops after three attempts with 300ms backoff as required in requirements 2.2-2.5.
3. Unit/integration tests for retry + market fallback pass and document which files were touched.
4. Config defaults for retry/slippage live in Include/RPEA/config.mqh and match design values.
```

### HOLD POINT 3 (Q&A Agent after Tasks 7-9)
```
Audit Tasks 7-9 for compliance:

1. AtomicOrderManager wraps multi-leg execution with execution locks and counter-order rollback; rollback attempts are logged with action + success flag.
2. OCO relationships store ticket pairs, expiry aligned to session cutoff, and risk-reduction cancellations fire immediately on fills per requirements 1.1-1.7.
3. Partial fill handler updates sibling volume inside OnTradeTransaction before the next timer tick using the documented fill ratio math.
4. Tests for atomic operations, OCO management, and partial fills (including dual-fill + last-share cases) all pass.
```

### HOLD POINT 4 (Q&A Agent after Tasks 10-11)
```
Audit Tasks 10-11 for compliance:

1. Budget gate takes position snapshots under a lock and logs open_risk, pending_risk, next_trade_risk, room_today, room_overall with 0.9 headroom, and logs gate_pass boolean.
2. Config keys BudgetGateLockMs and RiskGateHeadroom flow through config.mqh, and failures surface clear gating_reason messages.
3. News CSV fallback validates schema (timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min), enforces NewsCSVMaxAgeHours, and wires NewsCSVPath into news.mqh.
4. Budget gate concurrency tests and CSV parser tests pass.
```

### HOLD POINT 5 (Q&A Agent after Tasks 12-18)
```
Audit Tasks 12-18 for compliance:

1. SyntheticPriceManager builds P_synth with forward-fill and enforces QuoteMaxAgeMs, marking synthetic quotes STALE when either leg is too old.
2. Replication margin calculator applies the 20% buffer, downgrades to proxy on margin/quote failure, and coordinates with AtomicOrderManager for rollback.
3. Proxy + replication flows log execution_mode and pass aggregate worst-case risk through the budget gate.
4. Queue manager enforces MaxQueueSize/QueueTTLMinutes, implements prioritization, and only lets risk-reduction actions through during news windows.
5. Trailing activates at +1R, queues updates during news, re-validates preconditions post-news, and drops stale actions.
6. Audit logging outputs the full column set (intent_id, action_id, mode, risk metrics incl. gate_pass, rho_est, news_window_state) with schema verified.
7. Unit/integration tests for synthetic manager, queue manager, trailing, and audit logging all pass.
8. Replication implements NEWS_PAIR_PROTECT: if one leg hits SL/TP during a news window, immediately close the other leg and log NEWS_PAIR_PROTECT.
9. Downgrade decision tree validated: STALE quotes → proxy mode; margin shortfall → proxy mode; atomic failure → fail-fast with clear error.
```

### HOLD POINT 6 (Q&A Agent after Tasks 19-24)
```
Audit Tasks 19-24 for compliance:

1. Order engine integrates with risk.mqh, equity guardian, and news filter without duplicating logic; gating matches finalspec caps and news windows.
2. Restart recovery restores intents/queued actions, reconciles broker state before new orders, and logs discrepancies.
3. Error handling/self-healing covers network outages, margin failures, and produces actionable logs.
4. Integration/E2E suites from Task 22 run clean with deterministic seed; fake broker covers OCO, replication rollback, news queue, budget gate rejection.
5. Performance checks confirm CPU <2% and queue/memory stay bounded; configuration validation rejects bad inputs and documentation updated.
6. On funded (Master) accounts, SL is set within 30 seconds of opening; late enforcement is logged.
```


### Task 7: Atomic Operation Manager (Coding Agent)
**Attach**: .kiro/specs/rpea-m3/design.md, .kiro/specs/rpea-m3/tasks.md, Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh

```
Implement Task 7 from tasks.md: "Create Atomic Operation Manager with Counter-Order Rollback"

GOAL: Atomic two-leg execution with execution lock + counter-order rollback.

FOCUS:
- Wire AtomicOrderManager skeleton into OrderEngine with BeginAtomicOperation/RollbackAtomicOperation helpers.
- Maintain operation_id, executed tickets/volumes, rollback logging per design sequences.
- Use MaxRetryAttempts + OCO lock to prevent duplicate leg placement.
- Ensure counter-order requests respect MaxSlippagePoints and log TRADE_RETCODE on rollback.

ACCEPTANCE: Second-leg failure triggers immediate rollback of first leg, no duplicate legs across 1,000 simulated runs, unit tests updated.
```

### Task 12: Synthetic Price Manager (Coding Agent)
**Attach**: .kiro/specs/rpea-m3/design.md, .kiro/specs/rpea-m3/tasks.md, Include/RPEA/synthetic.mqh, Include/RPEA/config.mqh

```
Implement Task 12 from tasks.md: "Create Synthetic Price Manager with Quote Staleness Detection"

GOAL: Build P_synth cache with freshness guard and mapping helpers.

FOCUS:
- Implement GetSyntheticPrice/BuildSyntheticBars with forward-fill up to MaxGapBars.
- Track last tick timestamps for XAUUSD/EURUSD and compare against QuoteMaxAgeMs.
- Return status codes for FRESH vs STALE price to drive replication gating.
- Include logging hooks for stale detection and fallback decisions.

ACCEPTANCE: Synthetic prices accurate, stale quotes flag replication for downgrade, unit/integration tests for staleness paths pass.
```

### Task 13: Replication Margin Calculator with 20% Buffer (Coding Agent)
**Attach**: Include/RPEA/synthetic.mqh, .kiro/specs/rpea-m3/tasks.md

```
Implement Task 13 from tasks.md: "Implement Replication Margin Calculator with 20% Buffer"

GOAL: Compute margin for both legs, apply 20% buffer, trigger downgrade when required.

FOCUS:
- Calculate combined margin for XAUUSD/EURUSD legs; apply 1.2× buffer; compare to free margin.
- If free_margin < required×1.2, abort replication and rollback first leg (coordinate with atomics).
- Unit/integration tests for margin threshold and downgrade scenarios.

ACCEPTANCE: Margin includes 20% buffer; downgrade/rollback triggers at correct thresholds.
```

### Task 3: Volume and Price Normalization (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, .kiro/specs/rpea-m3/design.md, .kiro/specs/rpea-m3/tasks.md

```
Implement Task 3 from tasks.md: "Create Volume and Price Normalization System"

GOAL: SYMBOL_VOLUME_STEP rounding and symbol point normalization with validation.

FOCUS:
- Implement OE_NormalizeVolume(symbol, volume): round to SYMBOL_VOLUME_STEP; clamp to min/max.
- Implement OE_NormalizePrice(symbol, price): round to symbol point; respect SYMBOL_TRADE_STOPS_LEVEL.
- Add unit tests: rounding, boundary conditions, invalid inputs.

ACCEPTANCE: All volumes rounded to valid steps; prices normalized to symbol points.
```

### Task 4: Basic Order Placement with Position Limits (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, .kiro/specs/rpea-m3/tasks.md

```
Implement Task 4 from tasks.md: "Implement Basic Order Placement with Position Limits"

GOAL: Enforce MaxOpenPositionsTotal, MaxOpenPerSymbol, MaxPendingsPerSymbol on placement.

FOCUS:
- Implement limit checks before any OrderSend; emit clear error messages on violations.
- Respect broker min/max volume and stops level via normalization helpers.
- Unit tests for limit enforcement and successful placement paths.

ACCEPTANCE: Orders respect position limits; proper error messages for violations.
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

### Task 8: OCO Relationship Management (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, .kiro/specs/rpea-m3/tasks.md

```
Implement Task 8 from tasks.md: "Implement OCO Relationship Management"

GOAL: OCO creation, expiry alignment, sibling cancel/resize.

FOCUS:
- Track OCO pairs with expiry aligned to session cutoff; store metadata.
- On fill: immediate sibling cancel or risk-reduction resize.
- Log OCO actions and expiry metadata.

ACCEPTANCE: OCO relations behave per acceptance; metadata tracked.
```

### Task 9: Partial Fill Handler (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, .kiro/specs/rpea-m3/design.md

```
Implement Task 9 from tasks.md: "Create Partial Fill Handler with OCO Volume Adjustment"

GOAL: Adjust sibling volume on partials via OnTradeTransaction.

FOCUS:
- Detect partial fills; compute remaining and sibling volume with exact math.
- Apply before next timer cycle; aggregate multiple fills.

ACCEPTANCE: Partial fills adjust sibling before next timer; aggregation works.
```

### Task 10: Budget Gate (Coding Agent)
**Attach**: Include/RPEA/risk.mqh, Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh

```
Implement Task 10 from tasks.md: "Implement Budget Gate with Position Snapshot Locking"

GOAL: Enforce open+pending+next ≤ 0.9 × min(room_today, room_overall) under a lock.

FOCUS:
- Lock position snapshot; compute five inputs; log gate_pass boolean and gating_reason.
- Expose BudgetGateLockMs, RiskGateHeadroom=0.90.

ACCEPTANCE: Snapshot locking used; five inputs and gate_pass logged.
```

### Task 11: News CSV Fallback (Coding Agent)
**Attach**: Include/RPEA/news.mqh, Include/RPEA/config.mqh

```
Implement Task 11 from tasks.md: "Create News CSV Fallback System"

GOAL: Parse CSV fallback with schema and staleness checks.

FOCUS:
- Required columns: timestamp_utc,symbol,impact,source,event,prebuffer_min,postbuffer_min.
- Enforce NewsCSVMaxAgeHours; read path from NewsCSVPath; reject bad schema.
- Integrate block predicate for affected symbols/legs.

ACCEPTANCE: CSV fallback works when API fails; stale data rejected.
```

### Task 14: XAUEUR Proxy Mode (Coding Agent)
**Attach**: Include/RPEA/synthetic.mqh, .kiro/specs/rpea-m3/design.md

```
Implement Task 14 from tasks.md: "Create XAUEUR Proxy Mode Implementation"

GOAL: Execute via XAUUSD with synthetic SL distance mapping.

FOCUS:
- Map sl_xau ≈ sl_synth * EURUSD_rate; size volume using mapped distance.
- Log execution_mode=proxy; validate budget gate and caps.

ACCEPTANCE: Proxy mode maps distances correctly; executes single-leg orders.
```

### Task 16: Queue Manager (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/config.mqh

```
Implement Task 16 from tasks.md: "Create Queue Manager with Bounds and TTL Management"

GOAL: News-window action queuing with bounds and TTL.

FOCUS:
- Enforce MAX_QUEUE_SIZE; TTL expiration; prioritization policy.
- Allow only risk-reduction during news; revalidate preconditions post-news.

ACCEPTANCE: Queue bounds respected; TTL works; precondition validation enforced.
```

### Task 17: Trailing Stop Management (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, .kiro/specs/rpea-m3/design.md

```
Implement Task 17 from tasks.md: "Implement Trailing Stop Management with Queue Integration"

GOAL: Trailing activates at +1R; queues during news; revalidates afterward.

FOCUS:
- Activate when ≥ +1R; move SL by ATR*TrailMult; integrate with queue manager.
- Drop stale queued actions per TTL.

ACCEPTANCE: Trailing/queue behavior matches acceptance; tests pass.
```

### Task 18: Comprehensive Audit Logging (Coding Agent)
**Attach**: Include/RPEA/logging.mqh, Files/RPEA/logs/

```
Implement Task 18 from tasks.md: "Create Comprehensive Audit Logging System"

GOAL: Output full CSV row per placement/adjust/cancel with required fields.

FOCUS:
- Columns: timestamp,intent_id,action_id,symbol,mode(proxy|repl),requested_price,executed_price,requested_vol,filled_vol,remaining_vol,tickets[],retry_count,gate_open_risk,gate_pending_risk,gate_next_risk,room_today,room_overall,gate_pass,decision,confidence,efficiency,rho_est,est_value,hold_time,gating_reason,news_window_state.
- Rotate daily; schema-validate in tests.

ACCEPTANCE: CSV matches schema; all activities logged.
```

### Task 19: Integration with Risk/Equity/News (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, Experts/FundingPips/RPEA.mq5

```
Implement Task 19 from tasks.md: "Integrate Order Engine with Existing Risk Management"

GOAL: Integrate with risk engine, equity guardian, news filter.

FOCUS:
- Respect caps and rooms; use News_IsBlocked; no duplication of logic.
- Master (funded) accounts: enforce SL set within 30 seconds of position open; track open_time and validate SL presence.
- Log enforcement violations with [OrderEngine] prefix: "Master SL enforcement: ticket X, opened at Y, SL set at Z (Δt=N seconds)".
- Protective exits (SL/TP/kill-switch) always allowed during news windows per finalspec.md Decision 1.

ACCEPTANCE: Integration seamless; Master SL ≤30s enforcement tracked and logged with timestamps; protective exits bypass news restrictions; all risk/equity/news checks flow through existing modules without duplication.
```

### Task 20: State Recovery and Reconciliation (Coding Agent)
**Attach**: Include/RPEA/persistence.mqh, Include/RPEA/order_engine.mqh

```
Implement Task 20 from tasks.md: "Implement State Recovery and Reconciliation on Startup"

GOAL: Restore intents/queued actions; reconcile broker state before actions.

FOCUS:
- Load intent journal; dedup queued actions via action_id; reconcile open positions/orders.
- Log discrepancies and corrections.

ACCEPTANCE: Full recovery on restart; broker reconciliation correct.
```

### Task 21: Error Handling and Resilience (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh

```
Implement Task 21 from tasks.md: "Add Comprehensive Error Handling and Resilience Features"

GOAL: Self-healing behaviors for transient failures.

FOCUS:
- Classify errors; retries, circuit breakers, backoff; safe aborts on irrecoverable states.
- Actionable logs and metrics.

ACCEPTANCE: Handles error conditions gracefully; self-heals when possible.
```

### Task 23: Performance Optimization (Coding Agent)
**Attach**: Include/RPEA/order_engine.mqh, Include/RPEA/synthetic.mqh

```
Implement Task 23 from tasks.md: "Implement Performance Optimization and Memory Management"

GOAL: Keep CPU <2%, memory bounded.

FOCUS:
- Cache hot paths; avoid redundant symbol property calls; cap queue sizes.
- Leak checks; micro-optimizations where profiling indicates.

ACCEPTANCE: CPU remains low; memory stable; no regressions.
```

### Task 24: Documentation and Configuration Validation (Coding Agent)
**Attach**: Include/RPEA/config.mqh, README.md

```
Implement Task 24 from tasks.md: "Create Documentation and Configuration Validation"

GOAL: Validate parameters and document configuration.

FOCUS:
- Startup validation for inputs (ranges, dependencies); clear error messages.
- README updates with configuration keys and defaults.
- Validate all config parameters from design.md including: MaxRetryAttempts, InitialRetryDelayMs, RetryBackoffMultiplier, QueuedActionTTLMin, MaxSlippagePoints, BudgetGateLockMs, RiskGateHeadroom, NewsCSVMaxAgeHours, QuoteMaxAgeMs, MaxQueueSize, QueueTTLMinutes, EnableRiskReductionSiblingCancel, EnableQueuePrioritization.
- Document config parameter dependencies (e.g., QueueTTLMinutes must be ≤ NewsBufferS/60).

ACCEPTANCE: All parameters validated on startup with range checks; documentation includes complete config reference with defaults, ranges, and dependencies; validation failures produce actionable error messages.
```

### Task 15: XAUEUR Replication Mode (Coding Agent)
**Attach**: .kiro/specs/rpea-m3/design.md, .kiro/specs/rpea-m3/tasks.md, Include/RPEA/synthetic.mqh, Include/RPEA/order_engine.mqh

```
Implement Task 15 from tasks.md: "Implement XAUEUR Replication Mode with Two-Leg Coordination"

GOAL: Delta-accurate two-leg execution with automatic downgrade when replication unsafe.

FOCUS:
- Calculate leg volumes using replication formulas (ContractXAU/ContractFX, EURUSD rate).
- Use AtomicOrderManager for Begin/Commit/Rollback and share execution lock.
- Validate margin via ReplicationMarginCalculator (20% buffer) and downgrade to proxy when required.
- Persist execution_mode and leg tickets for audit + recovery.
- Implement NEWS_PAIR_PROTECT: if one leg hits SL/TP during news window, immediately close other leg and log NEWS_PAIR_PROTECT.
- Downgrade decision tree: STALE quotes → proxy; margin shortfall → proxy; atomic failure → fail-fast.

ACCEPTANCE: Replication succeeds when margin/quotes valid, downgrades cleanly to proxy on STALE/margin issues, NEWS_PAIR_PROTECT closes orphaned leg during news, tests for rollback + downgrade scenarios added.
```

### Task 22: Integration Tests & Fake Broker (Testing Agent)
**Attach**: Tests/RPEA/integration_tests.mqh, Tests/RPEA/fake_broker.mqh, Include/RPEA/order_engine.mqh, Include/RPEA/synthetic.mqh

```
Implement Task 22 from tasks.md: "Create Integration Tests for End-to-End Order Flows"

GOAL: Deterministic E2E suite covering OCO, replication rollback, news queues, budget gate rejection.

FOCUS:
- Build FakeBroker with SetTestSeed, SimulateOrderFill/Reject/Partial, slippage + margin toggles.
- Cover scenarios listed in tasks.md (OCO cancel, synthetic rollback, news queue release, partial fill adjustment, budget gate rejection).
- Ensure TestSeed=12345 yields stable runs and log paths mirror production audit format.

ACCEPTANCE: Five integration tests pass 10 consecutive runs, failure output actionable, suite callable from CI harness.
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

