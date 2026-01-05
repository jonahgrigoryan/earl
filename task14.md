# Task 14: Comprehensive Audit Logging – Implementation Plan

## Goal

Implement the Phase 4 audit logging requirements by emitting a production-ready CSV trail for every order-related activity (intent creation, submit/retry, fills, cancels, queue events, trailing adjustments, protective exits). Each row must include the FundingPips compliance fields: `timestamp,intent_id,action_id,symbol,mode(proxy|repl),requested_price,executed_price,requested_vol,filled_vol,remaining_vol,tickets[],retry_count,gate_open_risk,gate_pending_risk,gate_next_risk,room_today,room_overall,gate_pass,decision,confidence,efficiency,rho_est,est_value,hold_time,gating_reason,news_window_state`. Logs rotate daily under `Files/RPEA/logs/audit_YYYYMMDD.csv`, use buffered writes (`LogBufferSize`, default 1000), and remain writable even inside Strategy Tester. This work satisfies `.kiro/specs/rpea-m3/tasks.md` §14 and requirements.md §11.1–§11.7.

## References

- `.kiro/specs/rpea-m3/tasks.md` – Task 14 description and acceptance bullets
- `.kiro/specs/rpea-m3/requirements.md` – Requirement 11 Telemetry & Audit Logging
- `zen_prompts_m3.md` – Task 14 coding brief and checklist (columns + buffer expectations)
- `finalspec.md` & `README.md` – Extended logging field descriptions
- Existing modules: `MQL5/Include/RPEA/{logging,order_engine,queue,trailing,persistence,equity_guardian,news}.mqh`

## Current State Snapshot

- `logging.mqh` only appends simple CSV rows with columns `date,time,event,component,level,message,fields_json`.
- `LogAuditRow` is called across the EA (order intents, queue manager, scheduler boot), but no rows include risk metrics, news state, tickets list, or strategy context.
- `OrderIntent` persistence lacks telemetry attributes (confidence, efficiency, gating data), making it impossible to rebuild a compliant audit row after restart.
- Queue/trailing modules emit ad-hoc `LogAuditRow` messages that cannot be tied to the originating intent or compliance state.
- No buffering/rotation logic exists beyond per-write `FileOpen` calls; high-volume audit logging would thrash the disk.
- No automated tests validate CSV schema, header order, or buffer flush behavior.

## Implementation Steps

### Step 1: Inputs & Config Wiring (RPEA.mq5, config.mqh)
1. Add EA inputs near the existing logging/compliance block:
   - `input bool EnableDetailedLogging = DEFAULT_EnableDetailedLogging;`
   - `input int LogBufferSize = DEFAULT_LogBufferSize;`
   - `input string AuditLogPath = DEFAULT_AuditLogPath;`
2. Expose these values via externs (or inline getters) so `logging.mqh` can read them without duplicating globals.
3. Update `config.mqh` comments to note that `AuditLogPath` is relative to `MQL5/Files` and defaults to `Files/RPEA/logs/`.
4. Ensure `Persistence_EnsureFolders` creates the requested directory if the user overrides the default.

### Step 2: Extend Persistence Models for Telemetry (persistence.mqh)
1. Augment `struct OrderIntent` with the columns we must log/persist:
   - `double confidence`, `double efficiency`, `double rho_est`, `double est_value`, `double expected_hold_minutes`.
   - Budget gate snapshot: `double gate_open_risk`, `double gate_pending_risk`, `double gate_next_risk`, `double room_today`, `double room_overall`; `bool gate_pass`; `string gating_reason`.
   - Execution context: `string news_window_state`, `string decision_context` (free-form JSON), `ulong tickets_snapshot[]` (optional, or reuse existing `executed_tickets`), `double last_executed_price`, `double last_filled_volume`.
2. Add audit metadata for queue actions that may outlive the session:
   - Extend `PersistedQueuedAction` with `string intent_id`, `string intent_key`, `string news_window_state`, `double queued_confidence`, `double queued_efficiency`.
3. Update `Persistence_OrderIntentToJson` / `FromJson` and `Persistence_ActionToJson` / `FromJson` to serialize the new fields. Guard all reads with defaults so older `intents.json` files remain loadable (missing keys => zero/empty).
4. Provide helper routines:
   - `void Persistence_SetIntentTelemetry(OrderIntent &intent, const AuditTelemetry &src)`
   - `bool Persistence_GetIntentById(const string intent_id, OrderIntent &out_intent)`
   - `bool Persistence_UpdateIntent(const OrderIntent &intent)`
5. Until Task 21 delivers dynamic correlation, set `rho_est = CorrelationFallbackRho` (spec default 0.3) wherever intents are persisted or audit rows are emitted so downstream analytics have a stable field.
6. Update any tests referencing intent serialization (e.g., `Tests/RPEA/test_order_engine_intent.mqh`) to expect the new keys or mock them with defaults.

### Step 3: Audit Writer & Buffer (logging.mqh)
1. Introduce an `AuditRecord` struct mirroring the 25 required columns.
2. Add `struct AuditLoggerState` to hold:
   - `string base_path`, `string current_filename`, `datetime current_day_anchor`
   - `AuditRecord m_buffer[]` (or `string m_buffer[]` after formatting) sized via `LogBufferSize`
   - `int buffer_count`, `bool enabled`
3. Implement public APIs:
   - `void AuditLogger_Init(const string path, const int buffer_size, const bool enabled)`
   - `void AuditLogger_Log(const AuditRecord &record)` (push + flush when buffer full)
   - `void AuditLogger_Flush(bool force)`
   - `void AuditLogger_Shutdown()` (flush, close handle)
4. Handle daily rotation:
   - On each log call, compare `TimeCurrent()`’s YMD with `current_day_anchor`; if changed, flush buffer, reopen file `audit_YYYYMMDD.csv`, and rewrite header.
5. Formatting rules:
   - `timestamp` stored in ISO-8601 (`YYYY-MM-DDTHH:MM:SSZ`)
   - All doubles normalized via `DoubleToString(..., 5)` unless field expects integer counts.
   - `tickets[]` serialized as JSON array string (e.g., `"\"[12345,12346]\""`).
   - Strings sanitized by replacing quotes with single quotes before insertion.
6. Keep `LogAuditRow` and `LogDecision` for legacy usages:
   - Re-route `LogAuditRow` to a lightweight `events_YYYYMMDD.csv` so existing instrumentation stays intact but no longer collides with the new audit schema.
   - Document that all compliance-sensitive actions must use the new `AuditRecord` path, not `LogAuditRow`.

### Step 4: Audit Builder Helpers (new helper within logging.mqh or separate audit_helpers.mqh)
1. Define `struct AuditContext` capturing all the inputs needed to build a row (intent pointer, queue action metadata, gate snapshot, news state, decision string, prices/volumes, retry count, etc.).
2. Implement builder functions:
   - `AuditRecord Audit_BuildFromIntent(const OrderIntent &intent, const string action_id, const string decision, const double requested_price, const double executed_price, const double requested_vol, const double filled_vol, const double remaining_vol, const double hold_time_seconds, const string news_state, const ulong tickets[], const int retry_count)`
   - `AuditRecord Audit_BuildFromQueueAction(const QueuedAction &qa, const string decision, const string news_state, const double gate_open, ...)`
3. Provide utility helpers:
   - `string Audit_GenerateActionId(const string intent_id, const string suffix)` (e.g., `intent_id + ":PLACE"` / `":FILL"` / `"queue:<id>"`)
   - `string Audit_DetectNewsState(const string symbol, const bool protective)` returning `CLEAR`, `BLOCKED`, `PROTECTIVE_ONLY`, or `NEWS_FORCED_EXIT`.
   - `double Audit_ComputeHoldTimeSeconds(const OrderIntent &intent)` (TimeCurrent − intent.timestamp).
   - `double Audit_ComputeEfficiency(const OrderIntent &intent, const double realized_r)` fallback to predicted efficiency if the trade has not closed yet.
4. Ensure builder functions gracefully handle missing inputs (NaNs become 0, null pointers produce blanks).

### Step 5: Initialize/Flush Logger (RPEA.mq5)
1. After `Persistence_EnsureFolders()` inside `OnInit`, call `AuditLogger_Init(AuditLogPath, LogBufferSize, EnableDetailedLogging)` and bail out if the directory cannot be created (log a warning but don’t crash the EA).
2. In `OnDeinit`, invoke `AuditLogger_Shutdown()` before logging the shutdown message.
3. Update Strategy Tester helpers (if any) to call `AuditLogger_Flush(true)` after automated test suites so the JSON result file can inspect audit output.

### Step 6: Capture Telemetry When Building Intents (allocator.mqh, risk.mqh, equity_guardian.mqh, order_engine.mqh)
1. Extend `OrderPlan` (allocator.mqh) with telemetry fields: `double confidence`, `double expected_R`, `double expected_hold`, `double rho_est` (use `CorrelationFallbackRho` until Task 21 introduces dynamic values), `double est_value` (set to `expected_R`), `double efficiency` (expected_R / worst_case_risk).
2. When `Allocator_BuildOrderPlan` succeeds, populate those fields from `g_last_bwisc_context` and pass them into `OrderEngine::PlaceOrder` (add fields to `OrderRequest` or add a side-car struct).
3. Before invoking `Equity_EvaluateBudgetGate`, collect and persist the returned snapshot (`gate_open_risk` etc.) plus `gating_reason`; store inside the `OrderIntent` record once the intent is created.
4. Introduce helper(s) in `order_engine.mqh`:
   - `void OrderEngine_AttachTelemetry(OrderIntent &intent, const OrderPlan &plan, const EquityBudgetGateResult &gate, const string news_state)`
   - `void OrderEngine_UpdateExecutionStats(OrderIntent &intent, const double executed_price, const double executed_volume, const double remaining)`
5. Normalize `news_window_state` using the helper from Step 4 at the moment the intent is evaluated, so replays after restart still know whether the original decision happened during a blocked window.

### Step 7: Order Lifecycle Logging (order_engine.mqh)
Instrument every major branch with `AuditLogger_Log` using the builder helpers:
1. **Intent lifecycle**
   - On duplicate detection → `decision="INTENT_DUPLICATE"` with gate metrics from the found intent.
   - On acceptance → `decision="INTENT_CREATED"` (`action_id = intent_id + ":intent"`).
   - On cap/gate/risk rejection → `decision="CAP_BLOCK"`, `"BUDGET_BLOCK"`, `"RISK_BLOCK"` with the failing reason in `gating_reason`.
2. **Send/Retry**
   - Before each `ExecuteOrderWithRetry` send attempt (`action_id = intent_id + ":sendXX"`) record the planned price/volume.
   - On each broker retcode failure log `decision="SEND_FAIL"` with `retry_count`.
   - On fallback path log `"MARKET_FALLBACK_TRIGGER"` and include both requested and fallback prices.
3. **Success/Failure**
   - When `result.success` is true, log `"ORDER_EXECUTED"` capturing `executed_price`, `executed_volume`, updated `tickets[]`, and recomputed `remaining_vol`.
   - When final failure occurs, log `"ORDER_FAILED"` with `gating_reason` or MT5 retcode.
4. **OCO / Cancel / Modify**
   - After establishing or cancelling OCO siblings, write rows (`decision="OCO_ESTABLISH"`, `"OCO_CANCEL"`, `"OCO_RESIZE"`) referencing both tickets in the `tickets[]` column.
   - When pending orders auto-cancel due to expiry or news overlays, log `"ORDER_CANCELLED"` with `remaining_vol`.
5. Always include the latest gate snapshot, telemetry, and news state pulled from the associated `OrderIntent`. Provide helper `OrderEngine_FindIntentForTicket` so OnTradeTransaction and queue code can fetch the data.

### Step 8: Fill/Close/TradeTransaction Logging (order_engine.mqh)
1. Inside `OrderEngine_OnTradeTransaction`:
   - When `trans.type == DEAL_ADD`, log `"DEAL_ADD"` rows capturing the `DEAL_ENTRY`, price, volume, and updated `remaining_vol`.
   - For `DEAL_ENTRY_OUT`, log `"POSITION_CLOSED"` rows (tickets array should list closed ticket + any OCO sibling).
   - Compute realized hold time via `TimeCurrent() - PositionGetInteger(POSITION_TIME)` (fallback to `intent.timestamp` when position handle missing).
   - Update `OrderIntent`’s telemetry (filled volume, remaining, hold_time) so future logs (e.g., trailing adjustments) have up-to-date numbers.
2. For partial fills:
   - After adjusting sibling volumes, log `"PARTIAL_FILL_ADJUST"` with `filled_vol` and updated queue state.
3. Ensure protective exits triggered by floors/kill switches log `"PROTECTIVE_CLOSE"` rows even if they bypass budget gate, with `gating_reason="protective_exit"`.

### Step 9: Queue & Trailing Logging (queue.mqh, trailing.mqh)
1. **Queue enqueue path**:
   - When `Queue_Add` admits/updates an action, build an `AuditRecord` referencing `intent_id` / `intent_key` (use the new persisted fields) and log `decision="QUEUE_ENQUEUE"` or `"QUEUE_UPDATE"`.
   - On back-pressure rejections/evictions log `"QUEUE_OVERFLOW_REJECT"` / `"QUEUE_OVERFLOW_EVICT"`.
   - Include TTL, priority tier, `queued_confidence`, and `news_window_state`.
2. **Queue maintenance**:
   - `Queue_CancelExpired` → `decision="QUEUE_EXPIRE"`.
   - `Queue_RevalidateAndApply` → emit rows for `"QUEUE_APPLY_OK"`, `"QUEUE_APPLY_RETRY"`, `"QUEUE_APPLY_FAIL"`, `"QUEUE_NEWS_BLOCK"`.
   - For each log, include the gate metrics from the linked intent (look up via helper that loads `OrderIntent` by `intent_id`; when only `intent_key` is available, call `OrderEngine_GetIntentByKey(intent_key)` to retrieve telemetry before logging).
3. **Trailing manager**:
   - When trailing activates (≥ +1R) log `"TRAIL_ACTIVATE"` with the baseline R, ATR step, and new SL.
   - When trailing enqueues due to news, log `"TRAIL_QUEUE"` referencing the queue action id.
   - When trailing applies immediately, log `"TRAIL_APPLY"` with `decision` and updated risk metrics.
4. **Protective/Manual SLTP modifications**:
   - `OrderEngine_RequestModifySLTP` needs to call the audit builder whether it queues or applies immediately.
   - `OrderEngine_RequestProtectiveClose` logs `"PROTECTIVE_EXIT_REQUEST"` even if the broker call fails (include reason).

### Step 10: News Window State Helper (news.mqh)
1. Implement `string News_GetWindowState(const string symbol, const bool is_protective)` returning:
   - `"BLOCKED"` when `News_IsBlocked(symbol)` is true and `is_protective` is false.
   - `"PROTECTIVE_ONLY"` when blocked but the caller flagged the action as protective/risk-reducing.
   - `"CLEAR"` when the symbol is not blocked.
   - `"NEWS_FORCED_EXIT"` when a broker-side SL/TP closes during news (set in OnTradeTransaction using deal metadata).
2. Cache the latest state per symbol to avoid repeated CSV reloads within the same tick; update when `News_ReloadIfChanged()` returns true.
3. Use this helper in all audit builder calls so the `news_window_state` column is consistent, passing `true` for protective exits, queued trailing actions, and other risk-reduction flows.

### Step 11: Testing & Tooling Updates
1. Add `Tests/RPEA/test_logging.mqh`:
   - Test that `AuditLogger_Init` creates `audit_YYYYMMDD.csv` with the exact header.
   - Test buffered writes: enqueue > `LogBufferSize` rows, assert file contains all rows after forced flush.
   - Test ISO timestamps, numeric formatting, and `tickets[]` JSON serialization.
2. Extend existing suites:
   - In `Tests/RPEA/test_order_engine.mqh`, mock an intent and verify that `OrderEngine` emits `AuditRecord`s for success and failure cases (use dependency injection or a test double for `AuditLogger_Log`).
   - In `Tests/RPEA/test_queue_manager.mqh`, assert that queue enqueue/apply paths call the audit builder with the correct `decision` code.
   - In `Tests/RPEA/test_trailing.mqh`, assert that activating/queuing trailing events logs the required fields.
3. Update `Tests/RPEA/run_automated_tests_ea.mq5` to register the new logging suite.
4. Provide a sample audit row in `README.md` under the logging section so reviewers know what to expect.

## Acceptance & Validation Checklist

- [ ] `audit_YYYYMMDD.csv` contains the exact header and column ordering mandated by Task 14 / Requirement 11.
- [ ] Every placement, retry, cancellation, queue admission/expiry, trailing adjustment, and protective exit writes one row with populated gate & strategy context.
- [ ] `gate_*` columns mirror the latest `EquityBudgetGateResult` for that action; `gating_reason` matches the enums used in Task 9.
- [ ] `news_window_state` correctly distinguishes CLEAR vs BLOCKED vs PROTECTIVE_ONLY vs NEWS_FORCED_EXIT.
- [ ] Buffer obeys `LogBufferSize`, rotates daily, and flushes on `OnDeinit`.
- [ ] Duplicate intents, gate rejections, and MT5 retcode failures still log rows (even if no order was sent).
- [ ] Automated tests cover logger formatting, queue logging, and representative order-engine paths.

## Deliverables

1. Updated modules: `logging.mqh`, `order_engine.mqh`, `queue.mqh`, `trailing.mqh`, `news.mqh`, `persistence.mqh`, `allocator.mqh`, `equity_guardian.mqh`, `RPEA.mq5`.
2. New/updated tests under `Tests/RPEA/` plus harness registration.
3. Documentation updates (`README.md` logging section) describing the schema and configuration knobs.
4. Sample audit CSV captured during testing (attach or reference path) demonstrating compliant rows.

With these steps, Coding Agent work for Task 14 will have a deterministic blueprint that maps directly to the production-grade audit requirements.
