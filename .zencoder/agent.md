### M1-M2 Repo State Summary

The repository at https://github.com/jonahgrigoryan/earl on branch `feat/m2-bwisc` implements Milestones M1 and M2 for SPEC-003 per `finalspec.md`. The "Decisions & Constraints (LOCKED)" section remains unchanged, enforcing news policy (T±300s block on high-impact events with protective exits allowed), session order (London first, then NY), One-and-Done global rule, NY gate at 50% of daily cap, position caps (2 total/1 per symbol open, 2 pendings per symbol), server-day baseline persistence, kill-switch floors overriding all, session predicate without hour-equality, micro-fallback post-target only, R/win from persisted entry/SL/type, helper surface (e.g., `IsNewsBlocked`, `EquityRoomAllowsNextTrade`), and DST handling via offset.

**Milestone M1 Achievements:**
- **Project Structure and Compilation:** `MQL5/Experts/FundingPips/RPEA.mq5` is the main entry point with `#property strict`. Includes all core modules (e.g., `config.mqh`, `state.mqh`, `indicators.mqh`, `scheduler.mqh`, `equity_guardian.mqh`, `news.mqh`). Compiles successfully; initializes 30s `OnTimer` scheduler on chart attachment.
- **File System Initialization:** Creates `MQL5/Files/RPEA/` subdirs (`logs/`, `state/`, `news/`, etc.) and placeholders (e.g., `challenge_state.json`, `audit_YYYYMMDD.csv`).
- **Logging Mechanism:** Writes to `MQL5/Files/RPEA/logs/decisions_YYYYMMDD.csv` (indicator snapshots, gates) and `audit_YYYYMMDD.csv` (boot, rollover, shutdown). `LogDecision` and `LogAuditRow` capture JSON notes (e.g., ATR, RSI, news/spread/session status).
- **Persistence and Baseline:** Loads/saves `challenge_state.json` with `initial_baseline`, `baseline_today`, `gDaysTraded`, `server_midnight_ts`. `OnTimer` anchors server-day baseline at midnight (equity/balance max); `OnTradeTransaction` marks first `DEAL_ENTRY_IN` per day.
- **Indicators and Scheduler:** Refreshes ATR(D1), MA20(H1), RSI(H1), OHLC per symbol in `OnTimer`. `Scheduler_Tick` checks equity rooms/floors, news blocks (`News_IsBlocked`), spread (`Liquidity_SpreadOK`), sessions (`Sessions_InLondon`/`InNewYork`/`InORWindow`/`CutoffReached`), logs gates (e.g., "GATED" with JSON).
- **News Fallback:** Tolerant CSV loader for `MQL5/Files/RPEA/news/calendar_high_impact.csv` (schema: timestamp,impact,countries,symbols); stubs full integration.

**Milestone M2 Achievements:**
- **Signal Engine (BWISC):** `signals_bwisc.mqh` computes BTR (D1 body/true range), SDR (London open vs. MA20_H1 / ATR), ORE (OR range / ATR), RSI(H1) guard. Bias formula: 0.45*sign(C-O)*BTR + 0.35*sign(open-MA)*min(SDR,1) + 0.20*sign(C-O)*min(ORE,1). Setups: |Bias|≥0.6 → BC (stop beyond OR extreme, 2.2R target); |Bias|∈[0.35,0.6) & SDR≥0.35 → MSC (limit to MA20_H1, 1.8–2.2R). Outputs: `proposed_orders`, `expected_R` (clamped bias * Rtarget), `expected_hold` (max(ORMinutes,45m)), `confidence` (|Bias|), `worst_case_risk` (USD at SL).
- **Risk Management:** `risk.mqh`/`allocator.mqh` sizes lots via ATR distance: `risk_money = equity * RiskPct`, `sl_points = |entry-stop|/_Point`, `raw_volume = risk_money / (sl_points * tick_value)`. Enforces caps (`MaxOpenPositionsTotal`/per-symbol), margin ≤60% free. Budget gate: `open_risk + pending_risk + next_trade ≤ 0.9 * min(room_today, room_overall)`. `equity_guardian.mqh` computes rooms (`DailyFloor = baseline_today * (1 - DailyLossCapPct/100)`), floors (breach → close all, disable), One-and-Done (win ≥1.5R ends day), NY gate (realized loss ≤0.5*daily cap).
- **Meta-Policy Stub:** `meta_policy.mqh` routes to BWISC (primary); MR fallback if BWISC conf <0.70 & MR conf >0.80 & MR efficiency ≥ BWISC. BWISC replacement if ORE<p40 & ATR_D1<p50 & EMRT≤p40 (stub).
- **Governance Integration:** `scheduler.mqh` gates on rooms, floors, news, spread, sessions. Micro-mode stub (post +10%, 0.10% risk, 45m time-stop, 0.50% giveback cap).

**Outstanding Items Relative to the Spec:**
- **Order Execution:** No OCO pendings, market fallbacks, trailing, partial fills, or `OnTradeTransaction` beyond day-marking. `order_engine.mqh` is stubbed (no placements).
- **Synthetic XAUEUR:** `synthetic.mqh` unloaded; no proxy (XAUUSD-only with EURUSD-mapped SL) or replication (two-leg delta sizing, atomic ops, rollback).
- **News Full Integration:** Stubs block logic; no queuing for trailing/SLTP during T±300s, CSV schema/staleness checks, post-news revalidation/TTL drops.
- **Advanced Risk/Logging:** No comprehensive audit (missing tickets/volumes/prices/retry_count/mode/context/budget snapshots). No MR engine (EMRT/RL stubs in `emrt.mqh`/`rl_agent.mqh`), bandit (`bandit.mqh`), adaptive (`adaptive.mqh`), liquidity/anomaly full hooks.
- **Persistence/Telemetry:** Basic state; no order intents journal, SLO monitoring (hit-rate, hold, efficiency, friction).
- **Testing:** No unit/integration; Strategy Tester `.ini` exists but unvalidated.

### Zencoder.ai Agent Setup for M3 Execution

Use zencoder.ai for code generation and task execution in software projects as follows:

- **Platform Overview:** Zencoder.ai is an AI-powered code agent platform that automates development tasks by generating, editing, testing, and verifying code based on natural language descriptions. It integrates with IDEs like Cursor/VS Code and supports multi-step workflows for complex projects like RPEA M3.

- **Setup and Authentication:**
  - Install the Zencoder extension in Cursor (search "Zencoder" in extensions marketplace) or access via web at zencoder.ai.
  - Sign up/login with GitHub or email; link your repo (https://github.com/jonahgrigoryan/earl) and select branch `feat/m2-bwisc`.
  - Configure workspace: Set root to `/Users/jonahkesoyan/earl`, enable MQL5 compiler integration (MetaEditor path), and add rules from `.zencoder/rules/` (e.g., repo.md for RPEA conventions).

- **Executing the M3 Task Graph:**
  - For each task in Section D (e.g., Task 1: OCO Pendings), create a new agent session:
    1. Input: Paste the full task description (Goal, Dependencies, Exact File Edits, Code-Diff Sketch, Commands/Scripts, Success Criteria).
    2. Attach files: Use tool calls or upload current versions (e.g., `order_engine.mqh`, `RPEA.mq5`).
    3. Prompt: "Implement this M3 task following RPEA rules: Preserve indentation/style, no LOCKED changes, add tests. Use code-diff sketch as guide."
  - Agent Workflow:
    - **Generation:** Agent proposes edits using `edit_file` format (e.g., target_file, instructions, code_edit with `// ... existing code ...` for unchanged).
    - **Execution:** Runs commands (e.g., compile RPEA.mq5, Strategy Tester for units) in background shell; handles non-interactive (e.g., `--yes` for installs).
    - **Verification:** Checks success criteria (e.g., grep for APIs, run tests, assert logs); if fail, iterates up to 3x (fix linter, retest).
    - **Branching:** Auto-creates feature branch (e.g., `feat/m3-oco-pendings`), commits with message "M3: [Task] — [Scope]", pushes to PR.
  - Parallelism: Run multiple agents for independent tasks (e.g., proxy and replication); merge via PRs.
  - Monitoring: View session logs in zencoder dashboard; intervene if ambiguity (e.g., "Clarify: Use CTrade for mocks?").

- **Best Practices for RPEA M3:**
  - Reference specs: Attach `finalspec.md`, `requirements.md`, memories (e.g., no statics in helpers, no array ref aliasing).
  - Tool Integration: Agents use codebase_search/grep for exploration, edit_file for changes, run_terminal_cmd for compiles/tests.
  - Error Handling: If agent hits HOLD POINT (e.g., from tasks.md), pause and notify; ensure deterministic tests (fake broker).
  - Output: Each task ends with verified PR ready for review; aggregate M3 completion with full backtest report.

This setup enables atomic, verifiable implementation of M3 tasks without manual coding, ensuring compliance and quality.

### Section B: M3 Plan

1. **Extend Order Engine for OCO Pending Orders (`MQL5/Include/RPEA/order_engine.mqh` creation/update):**
   - Public APIs: `bool PlaceOCOOrders(string symbol, double volume, double buy_price, double sell_price, double sl, double tp, datetime expiry);` `void OnOCOFill(int filled_ticket, double filled_volume);` `bool AdjustSiblingVolume(int sibling_ticket, double adjust_volume);`
   - Data structures: `struct OCOGroup { int buy_ticket, sell_ticket; double orig_volume; bool active; };` Track in global array `OCOGroup g_oco_groups[];`.
   - Flow from M2: In `Scheduler_Tick`, after BWISC/MR proposal, call `PlaceOCOOrders` if dual setups; expiry = session cutoff or `ORMinutes + TTL`. On `OnTradeTransaction` (DEAL_ENTRY_IN for pending), detect fill, call `OnOCOFill` to cancel sibling via `CTrade::OrderDelete`, adjust partials via `AdjustSiblingVolume` (resize remaining). Edge cases: Broker expiry ≤ cutoff (log `EXPIRED`); partial fill → resize sibling proportionally; unexpected fill exceeding risk → cancel/resize sibling (log `RISK_REDUCE`). Fail → fallback to single market order.

2. **Implement Market Fallback with Slippage (`MQL5/Include/RPEA/order_engine.mqh` update):**
   - Public APIs: `bool ExecuteMarketFallback(string symbol, ENUM_ORDER_TYPE type, double volume, double sl, double tp, int slippage_points);` `bool RetryMarketOrder(ulong request_id, int attempt);`
   - Data structures: Use `MqlTradeRequest`/`MqlTradeResult` for retries; track `struct RetryInfo { ulong req_id; int attempts; datetime last_try; };`.
   - Flow from M2: If OCO/pending fails (e.g., `TRADE_RETCODE_INVALID`/`REJECT`), call `ExecuteMarketFallback` with `MaxSlippagePoints=10`. Set `deviation=slippage_points` in `CTrade`. On fail, `RetryMarketOrder` up to 3x (300ms `Sleep`), backoff exponential. Permanent fails (TRADE_DISABLED/NO_MONEY) → log `FAIL_FAST`, abort. Edge: High spread → reject if >`MaxSpreadPoints`; log slippage actual vs. limit.

3. **Add Trailing Stop Management (`MQL5/Include/RPEA/order_engine.mqh` update):**
   - Public APIs: `bool ActivateTrailing(int position_ticket, double entry, double sl_orig, double atr_current);` `void QueueTrailingUpdate(int ticket, double new_sl);` `bool ApplyQueuedTrailing(const AppContext& ctx);`
   - Data structures: `struct QueuedAction { int ticket; double new_sl; datetime queued_at; ENUM_ACTION_TYPE type; };` Global queue `QueuedAction g_trailing_queue[];`.
   - Flow from M2: In `OnTimer`, for open positions, if profit ≥1R (from persisted entry/SL), call `ActivateTrailing` (initial trail at ATR*`TrailMult=0.8`). On favorable move, compute new SL, if in news (`News_IsBlocked`), `QueueTrailingUpdate` (TTL=`QueuedActionTTLMin=5min`). Post-news (`ApplyQueuedTrailing`): revalidate position exists, profit ≥1R, not in new window → `PositionModify`; else drop (log `STALE_DROP`). Edge: News queue during T±300s; floors override (allow exit); partial positions use actual volume.

4. **Implement Synthetic XAUEUR Proxy Mode (`MQL5/Include/RPEA/synthetic.mqh` creation):**
   - Public APIs: `double ComputeSyntheticPrice(string xau, string eur);` `bool BuildSyntheticBars(string symbol, int timeframe, MqlRates& rates[]);` `double MapProxySL(double synth_sl_dist, string eur);` `bool PlaceProxyOrder(string xau, double synth_volume, double sl, double tp);`
   - Data structures: `struct SyntheticOHLC { double open, high, low, close, volume; datetime time; };` Sync M1 bars from XAUUSD/EURUSD.
   - Flow from M2: For XAUEUR signals (`UseXAUEURProxy=true`), compute `P_synth = XAUUSD_bid / EURUSD_bid`; build M1 synthetic bars (forward-fill gaps ≤1bar); compute indicators (ATR/MA/RSI) on synth. Map SL: `sl_xau = synth_sl_dist * current_EURUSD`; size XAUUSD volume. Block if news on either leg (`NewsBufferS=300s`). Integrate in `signals_bwisc.mqh`/`signals_mr.mqh` for XAUEUR. Edge: Gaps → forward-fill; news on EURUSD → block XAUUSD proxy.

5. **Implement Synthetic XAUEUR Replication Mode (`MQL5/Include/RPEA/synthetic.mqh` update, `order_engine.mqh` integration):**
   - Public APIs: `bool ComputeReplicationVolumes(double K_risk, double P_synth, double E_eur, double& V_xau, double& V_eur);` `bool ExecuteTwoLegAtomic(string xau, string eur, ENUM_ORDER_TYPE xau_type, ENUM_ORDER_TYPE eur_type, double V_xau, double V_eur, double sl_xau, double sl_eur);` `void RollbackLeg(int failed_leg_ticket, ENUM_LEG_TYPE leg);`
   - Data structures: `enum LEG_TYPE { XAU, EUR };` `struct ReplicationPair { int xau_ticket, eur_ticket; double target_delta; };` Global `ReplicationPair g_repl_pairs[];`.
   - Flow from M2: If `UseXAUEURProxy=false`, for XAUEUR signal: `K = risk_money / |SL_synth|`; `V_xau = K / (100 * E)` (ContractXAU=100), `V_eur = K * (P/E²) / 100000` (ContractFX=100k). Simulate combined SL loss ≤ budget. Atomic: Lock (`static bool g_execution_lock=false`), place first leg, if success place second; fail second → `RollbackLeg` (close first). Count both in caps/rooms/margin (downgrade to proxy if >60% margin). News: Block if either leg affected. Edge: Partial on one leg → adjust other for delta; failure → rollback within 1s.

6. **Handle Partial Fills and OnTradeTransaction Integration (`MQL5/Include/RPEA/order_engine.mqh` update):**
   - Public APIs: `void OnPartialFill(const MqlTradeTransaction& trans);` `bool RebalancePartialOCO(int group_id, double filled_vol);`
   - Data structures: Extend `OCOGroup` with `double filled_buy_vol, filled_sell_vol;`.
   - Flow from M2: In `OnTradeTransaction` (TRADE_TRANSACTION_DEAL_ADD, DEAL_ENTRY_IN), if partial (`HistoryDealGetDouble(DEAL_VOLUME) < requested`), call `OnPartialFill`: Update position volume, adjust OCO sibling (`OrderModify` volume), rebalance replication delta if synth. For trailing, use actual volume. Process before `OnTimer` to avoid tick-delay. Edge: Multiple partials → cumulative; log `requested_volume, filled_volume, remaining, sibling_adjust`.

7. **Error Handling, Reentrancy, and Self-Healing (`MQL5/Include/RPEA/order_engine.mqh` update, `persistence.mqh` integration):**
   - Public APIs: `bool WithReentrancyLock(bool (*func)(void* data), void* data);` `void ReconcileOrdersOnInit(const AppContext& ctx);`
   - Data structures: `struct OrderIntent { string symbol; ENUM_ORDER_TYPE type; double volume; double price; datetime intent_time; bool executed; };` Persist in `intents.json`.
   - Flow from M2: Wrap placements/modifies in `WithReentrancyLock` (static mutex). OnInit: Load intents, query open positions/pendings (`PositionsTotal`/`OrdersTotal`), idempotently cancel stale/unexecuted (expiry passed), recreate if needed. Retries: 3x for transient (`INVALID_STOPS` etc.), fail-fast permanent. Edge: Restart mid-OCO → reconcile siblings; log `retry_count, execution_mode` (OCO/market/proxy/repl).

8. **Budget Gate and Caps Enforcement (`MQL5/Include/RPEA/risk.mqh` update, `order_engine.mqh` integration):**
   - Public APIs: `bool ValidateBudgetGate(double next_trade_risk, const EquityRooms& rooms);` `bool CheckPositionCaps(string symbol);`
   - Flow from M2: Before any placement, compute `open_risk` (sum SL distances * volumes), `pending_risk` (similar for pendings), `next_trade` (worst-case). Assert ≤0.9*min(rooms.today, rooms.overall); log inputs/pass-fail. Caps: Query `PositionsTotalByMagic`/`OrdersTotalByMagic` before place. For repl: Count both legs. Edge: Partial → dynamic recaps; floors override (close all on breach).

9. **News Compliance for Orders (`MQL5/Include/RPEA/news.mqh` update, `order_engine.mqh` integration):**
   - Public APIs: `bool IsOrderActionAllowed(ENUM_ORDER_ACTION action, string symbol);` `void QueueNewsAction(struct QueuedAction act);`
   - Flow from M2: In news window: Block new orders/modifies (`TRADE_TRANSACTION_ORDER_*`); queue trailing/SLTP (`QueueNewsAction`, TTL=5min). Post-window: Revalidate (position exists, precondition holds) → apply; else drop. Allow: Protective exits (floors/margin), OCO risk-reduce cancels, repl pair-protect closes (log `NEWS_RISK_REDUCE`/`NEWS_PAIR_PROTECT`). CSV fallback: Parse on API fail, check staleness (<7 days). Edge: Queue during Master T±300s; internal buffer on eval.

10. **Logging and Persistence for Orders (`MQL5/Include/RPEA/logging.mqh` update, `persistence.mqh` update):**
    - Public APIs: `void LogOrderIntent(const OrderIntent& intent);` `void LogBudgetGateSnapshot(double open_r, double pend_r, double next_r, double room_t, double room_o, bool pass);`
    - Flow from M2: Extend audit CSV: Add `tickets, requested_vol, filled_vol, price, retry_count, execution_mode` (OCO/market/proxy/repl), strategy context (`confidence, efficiency, est_value=expected_R*volume, hold_time, gating_reason, news_window_state`). Persist intents/queues in `intents.json` (JSON array). On close: Log realized R from persisted. Edge: Partial → multi-row (intent + fills + adjusts).

11. **Test Scaffolding and Strategy Tester Hooks (`MQL5/Experts/FundingPips/Tests/OrderEngineTests.mq5` creation, `MQL5/Files/RPEA/strategy_tester/RPEA_10k_tester.ini` update):**
    - Public APIs: In test file: `void TestOCOFullFill();` `void TestPartialFillAdjust();` `void TestTwoLegRollback();` `void TestTrailingQueueNews();`
    - Flow from M2: Use fake broker mode (mock `CTrade` responses). Unit: Deterministic seeds for OCO fills, partials (50%), repl fail (50% second leg). Integration: Full flow from signal → order → transaction → log. Hooks: `.ini` with $10k deposit, 1:50/1:20 leverage, every-tick model, symbols=EURUSD;XAUUSD. Smoke: Run 1-week backtest, assert no cap breaches, logs contain required fields. Edge: News-sim (mock blocks), floor breach (mock equity drop).

**Preconditions from LOCKED (Must Remain True):**
- News: Block opens/holds/modifies in T±300s (Master); queue non-protective; allow exits/OCO reduces/repl protects; CSV fallback.
- Floors: Daily/Overall breach → close all, disable (day/permanent); override news/min-hold.
- Sessions: London first; One-and-Done global ≥1.5R ends day; NY only if loss ≤0.5*daily cap; predicate interval-based (no hour==).
- Caps: Enforce 2 total/1/symbol open, 2 pendings/symbol before place.
- Budget Gate: Aggregate open+pending+next ≤0.9*min(daily/overall room); server-day baseline; micro post-target only; R from persisted (not inferred).

### Section C: Acceptance Checklist

- **Unit Tests (in `OrderEngineTests.mq5`):**
  - `TestOCOFullFill`: Place OCO, simulate full buy fill → sell cancels; assert sibling deleted, log contains tickets/volumes.
  - `TestPartialFillAdjust`: Partial buy (0.5 vol) → sell resizes to 0.5; assert volume match, risk recalced.
  - `TestMarketRetryFailFast`: 3 retries on slippage exceed → abort; TRADE_DISABLED → no retry.
  - `TestTrailingActivateQueue`: +1R → trail; news → queue; post-news revalidate → apply if valid, drop stale.
  - `TestProxySLMap`: Synth SL=10 → XAU SL=10*EURUSD; assert volume scales.
  - `TestReplicationAtomic`: First leg success, second fail → rollback; margin>60% → downgrade proxy.
  - `TestBudgetGateFail`: open+pending+next>0.9*room → reject, log snapshot.
  - All pass with 100% coverage (deterministic mocks); no leaks in queues/groups.

- **Integration Tests:**
  - Full BWISC → OCO place → partial fill → trail queue (news mock) → post-news apply → close (log R calc).
  - XAUEUR repl: Two-leg place → second fail → rollback; news on EUR → block entire.
  - Restart: Persist intents → OnInit reconcile → no duplicates; OCO mid-fill → adjust on resume.
  - Error paths: 3 retries → fail-fast; floor breach → close all (override news).

- **Backtest Smoke Runs:**
  - Strategy Tester: $10k, every-tick, 1-month (include news week), symbols=EURUSD;XAUUSD; UseXAUEURProxy=true/false.
  - Assert: No cap/news violations; ≥1 OCO/day median; logs have all fields (e.g., budget snapshot, context); no unhandled transactions; CPU<2%; 3+ trade days post-target micro.
  - Edge: Simulate partials (custom script), news blocks (mock calendar), margin tight → downgrade.

- **PR Artifacts:**
  - Diff summary: Highlight new `order_engine.mqh`/`synthetic.mqh`, updates to `scheduler.mqh`/`risk.mqh`/`logging.mqh`/`persistence.mqh`; no LOCKED changes.
  - Sample CSV logs: `audit_YYYYMMDD.csv` rows for OCO intent/fill/adjust, repl rollback, budget gate fail, trailing queue/apply (with confidence=0.75, efficiency=1.2, est_value=15, hold=45m, gating=news, window=blocked).
  - .set file delta: Update `RPEA_10k_default.set` with new inputs (e.g., `UseXAUEURProxy=true`, `QueuedActionTTLMin=5`); add to PR.

### Section D: Zen Agent Task Graph

Tasks in topological order (dependencies noted). Each sized for one agent run: ~1-2 files, focused goal, verifiable success. Use zencoder.ai for code gen/execution: Input task desc + files; agent generates/edits code, runs compile/test commands, verifies criteria.

1. **Task: Implement OCO Pending Orders**
   - **Goal:** Enable OCO placement and sibling cancellation/adjustment for dual setups.
   - **Dependencies:** None (builds on M2 stubs).
   - **Exact File Edits:** Create/update `MQL5/Include/RPEA/order_engine.mqh` (add `PlaceOCOOrders`, `OnOCOFill`, `AdjustSiblingVolume`, `OCOGroup` struct); hook in `RPEA.mq5::OnTradeTransaction`.
   - **Code-Diff Sketch:**
     ```
     // In order_engine.mqh
     struct OCOGroup { int buy_ticket=-1, sell_ticket=-1; double orig_volume; bool active=true; };
     static OCOGroup g_oco_groups[10]; // fixed size

     bool PlaceOCOOrders(string symbol, double volume, double buy_price, double sell_price, double sl, double tp, datetime expiry) {
       // ... existing code ...
       // Use CTrade to send ORDER_TYPE_BUY_LIMIT/SELL_LIMIT
       // On success, populate g_oco_groups[id] = {buy_ticket, sell_ticket, volume, true};
       // LogOrderIntent for both
       return true;
     }

     void OnOCOFill(int filled_ticket, double filled_volume) {
       // Find group containing filled_ticket
       // If partial, AdjustSiblingVolume(sibling, volume - filled_volume)
       // Else, CTrade.OrderDelete(sibling); g_oco.active=false;
       // LogAuditRow("OCO_FILL", symbol, filled_volume, ...);
     }
     ```
   - **Commands/Scripts:** Compile `RPEA.mq5` (`#include <Trade\Trade.mqh>`); run unit test `TestOCOFullFill` in Strategy Tester (mock fills); `grep -i "OCO" MQL5/Include/RPEA/order_engine.mqh` to verify APIs.
   - **Success Criteria:** Compiles without errors; unit test passes (full/partial fill → sibling cancel/adjust, log contains tickets/volumes); no statics in helpers; audit CSV has OCO rows.

2. **Task: Add Market Fallback and Slippage**
   - **Goal:** Fallback from pendings to market with retry/slippage guards.
   - **Dependencies:** Task 1 (use in OCO fail path).
   - **Exact File Edits:** Update `MQL5/Include/RPEA/order_engine.mqh` (add `ExecuteMarketFallback`, `RetryMarketOrder`, `RetryInfo`); integrate in `PlaceOCOOrders` fail branch.
   - **Code-Diff Sketch:**
     ```
     bool ExecuteMarketFallback(string symbol, ENUM_ORDER_TYPE type, double volume, double sl, double tp, int slippage) {
       CTrade trade; trade.SetDeviationInPoints(slippage);
       // Send ORDER_TYPE_BUY/SELL
       if(trade.ResultRetcode() != TRADE_RETCODE_DONE) {
         return RetryMarketOrder(trade.RequestID(), 1); // start retries
       }
       return true;
     }

     bool RetryMarketOrder(ulong req_id, int attempt) {
       if(attempt > 3) return false;
       Sleep(300 * attempt); // backoff
       // Resend similar request
       if(HistoryOrderGetInteger(req_id, ORDER_STATE) == ORDER_STATE_REJECTED &&
          (trade.ResultRetcode() == TRADE_RETCODE_TRADE_DISABLED || == TRADE_RETCODE_NO_MONEY)) {
         LogAuditRow("FAIL_FAST", ...); return false;
       }
       return true;
     }
     ```
   - **Commands/Scripts:** Compile; test `TestMarketRetryFailFast` (mock rejects, assert 3 retries then abort, log slippage); `rg --type mqh "slippage|retry" .` to confirm.
   - **Success Criteria:** Unit passes (retry 3x, fail-fast on permanent); log has `retry_count=2, execution_mode=market`; no alias refs to arrays.

3. **Task: Implement Trailing Stops with News Queuing**
   - **Goal:** Activate trails at +1R, queue during news, revalidate post-window.
   - **Dependencies:** Tasks 1-2 (integrate with OCO/positions).
   - **Exact File Edits:** Update `MQL5/Include/RPEA/order_engine.mqh` (add `ActivateTrailing`, `QueueTrailingUpdate`, `ApplyQueuedTrailing`, `QueuedAction`); hook in `OnTimer`; update `news.mqh` for `IsOrderActionAllowed(TRAIL)`.
   - **Code-Diff Sketch:**
     ```
     struct QueuedAction { int ticket; double new_sl; datetime queued_at; };
     static QueuedAction g_trailing_queue[50];

     bool ActivateTrailing(int ticket, double entry, double sl_orig, double atr) {
       double profit = PositionGetDouble(POSITION_PROFIT);
       double r_current = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? (Bid-entry):(entry-Ask)) / (entry-sl_orig);
       if(r_current >= 1.0) {
         double trail_sl = /* compute ATR*TrailMult from current price */;
         if(News_IsBlocked(symbol)) QueueTrailingUpdate(ticket, trail_sl);
         else return PositionModify(ticket, trail_sl, tp);
       }
       return true;
     }

     void ApplyQueuedTrailing(const AppContext& ctx) {
       for(int i=0; i<ArraySize(g_trailing_queue); i++) {
         if(TimeCurrent() - g_trailing_queue[i].queued_at > QueuedActionTTLMin*60) { /* drop */ continue; }
         // Revalidate position exists, r>=1.0, not news
         if(/* valid */) PositionModify(...); else Log("STALE_DROP");
       }
     }
     ```
   - **Commands/Scripts:** Compile; test `TestTrailingQueueNews` (mock news, queue → post apply, assert SL moved, stale dropped); background run 1min `OnTimer` sim.
   - **Success Criteria:** Unit passes (queue during block, apply post, drop TTL>5min); log has `news_window_state=queued`; early returns, ≤2 nesting.

4. **Task: Synthetic Proxy Mode**
   - **Goal:** XAUEUR signals via XAUUSD proxy with SL mapping.
   - **Dependencies:** Task 3 (news block integration).
   - **Exact File Edits:** Create `MQL5/Include/RPEA/synthetic.mqh` (add `ComputeSyntheticPrice`, `BuildSyntheticBars`, `MapProxySL`, `PlaceProxyOrder`); update `signals_bwisc.mqh` to call for XAUEUR.
   - **Code-Diff Sketch:**
     ```
     double ComputeSyntheticPrice(string xau, string eur) {
       double xau_bid = SymbolInfoDouble(xau, SYMBOL_BID);
       double eur_bid = SymbolInfoDouble(eur, SYMBOL_BID);
       return xau_bid / eur_bid;
     }

     bool BuildSyntheticBars(string symbol, int tf, MqlRates& rates[]) {
       // If symbol=="XAUEUR", sync M1 from XAUUSD/EURUSD
       MqlRates xau_rates[], eur_rates[];
       CopyRates("XAUUSD", tf, 0, 100, xau_rates);
       CopyRates("EURUSD", tf, 0, 100, eur_rates);
       // Forward-fill gaps: for each bar, rates[i].close = xau.close / eur.close; etc.
       return true;
     }

     double MapProxySL(double synth_sl, string eur) {
       return synth_sl * SymbolInfoDouble(eur, SYMBOL_BID);
     }

     // In signals_bwisc: if(symbol=="XAUEUR" && UseXAUEURProxy) { sl = MapProxySL(synth_sl, "EURUSD"); PlaceProxyOrder("XAUUSD", volume, sl, tp); }
     ```
   - **Commands/Scripts:** Compile; test `TestProxySLMap` (assert sl_xau = 10*1.08=10.8); mock bars, verify forward-fill.
   - **Success Criteria:** Unit passes (synth price calc, bars built, SL mapped); news block on EUR → no XAU order; log `execution_mode=proxy`.

5. **Task: Synthetic Replication Mode**
   - **Goal:** Two-leg atomic XAUEUR with delta sizing/rollback.
   - **Dependencies:** Task 4 (proxy fallback).
   - **Exact File Edits:** Update `MQL5/Include/RPEA/synthetic.mqh` (add `ComputeReplicationVolumes`, `ExecuteTwoLegAtomic`, `RollbackLeg`, `ReplicationPair`); integrate in proxy `PlaceProxyOrder` if !proxy.
   - **Code-Diff Sketch:**
     ```
     bool ComputeReplicationVolumes(double K, double P, double E, double& V_xau, double& V_eur) {
       V_xau = K / (100.0 * E); // ContractXAU=100
       V_eur = K * (P / (E*E)) / 100000.0; // ContractFX=100k
       // Simulate combined SL risk <= budget
       return true;
     }

     bool ExecuteTwoLegAtomic(string xau, string eur, ENUM_ORDER_TYPE xau_type, ENUM_ORDER_TYPE eur_type, double V_xau, double V_eur, double sl_xau, double sl_eur) {
       if(g_execution_lock) return false; g_execution_lock=true;
       // Place XAU first
       CTrade trade; if(!trade.PositionOpen(xau, xau_type, V_xau, 0, sl_xau, 0)) { g_execution_lock=false; return false; }
       int xau_ticket = trade.ResultOrder();
       // Place EUR
       if(!trade.PositionOpen(eur, eur_type, V_eur, 0, sl_eur, 0)) {
         RollbackLeg(xau_ticket, XAU); g_repl_pairs[].xau_ticket=-1; // clear
         Log("REPL_ROLLBACK"); g_execution_lock=false; return false;
       }
       g_repl_pairs[].xau_ticket = xau_ticket; g_repl_pairs[].eur_ticket = trade.ResultOrder();
       // Check margin, downgrade if >60%
       g_execution_lock=false; return true;
     }
     ```
   - **Commands/Scripts:** Compile; test `TestReplicationAtomic` (mock second fail → rollback, assert both closed, log rollback); margin mock >60% → call proxy.
   - **Success Criteria:** Unit passes (volumes calc, atomic place/fail→rollback, margin downgrade); caps count both legs; log `execution_mode=repl`.

6. **Task: Partial Fills and Transaction Handling**
   - **Goal:** Process partials in OCO/repl, rebalance before timer.
   - **Dependencies:** Tasks 1,5 (extend OCO/repl structs).
   - **Exact File Edits:** Update `MQL5/Include/RPEA/order_engine.mqh` (add `OnPartialFill`, `RebalancePartialOCO`); enhance `OnTradeTransaction` in `RPEA.mq5`.
   - **Code-Diff Sketch:**
     ```
     void OnPartialFill(const MqlTradeTransaction& trans) {
       double filled_vol = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
       string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
       // If pending fill, find OCO group
       int group_id = FindOCOGroups(symbol, trans.order);
       if(group_id >=0) RebalancePartialOCO(group_id, filled_vol);
       // For repl, adjust other leg volume proportionally
       if(IsReplicationLeg(symbol)) AdjustReplicationDelta(/* partner leg */);
       LogAuditRow("PARTIAL_FILL", symbol, requested_vol, filled_vol, remaining=requested-filled, ...);
     }

     // In RPEA.mq5::OnTradeTransaction
     if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal_type == DEAL_ENTRY_IN) {
       if(/* partial */) OnPartialFill(trans);
       else OnOCOFill(trans.order, filled_vol); // full
     }
     ```
   - **Commands/Scripts:** Compile; test `TestPartialFillAdjust` (partial 0.5 → sibling resize 0.5, delta maintained); sim transaction in tester.
   - **Success Criteria:** Unit passes (OCO adjust, repl rebalance, log requested/filled/remaining); process in transaction (no tick delay).

7. **Task: Error Handling and Reentrancy**
   - **Goal:** Lock executions, reconcile on init, retry transients.
   - **Dependencies:** Tasks 1-6 (wrap all places/modifies).
   - **Exact File Edits:** Update `MQL5/Include/RPEA/order_engine.mqh` (add `WithReentrancyLock`, `ReconcileOrdersOnInit`); call in `OnInit` of `RPEA.mq5`; update `persistence.mqh` for `intents.json`.
   - **Code-Diff Sketch:**
     ```
     static bool g_execution_lock = false;

     bool WithReentrancyLock(bool (*func)(void* data), void* data) {
       if(g_execution_lock) return false;
       g_execution_lock = true;
       bool result = func(data);
       g_execution_lock = false;
       return result;
     }

     void ReconcileOrdersOnInit(const AppContext& ctx) {
       // Load OrderIntent[] from intents.json
       for each intent in loaded {
         if(!intent.executed && TimeCurrent() < intent.intent_time + expiry) {
           // Idempotent: if open/pending exists with magic, skip; else recreate
           if(OrdersTotalByMagic(intent.symbol, MagicBase) == 0) PlaceOrder(intent);
         }
       }
       // Clear stale queues
     }
     ```
   - **Commands/Scripts:** Compile; test reconcile (mock persist, restart sim → no dups); lock test (concurrent mock → block second).
   - **Success Criteria:** No reentrancy crashes; init reconciles (log `RECONCILE_SKIP`/`RECREATE`); intents persist/restore.

8. **Task: Budget Gate, Caps, and News Order Integration**
   - **Goal:** Enforce gates/caps before place; queue news actions.
   - **Dependencies:** Tasks 1-7 (call before all executions).
   - **Exact File Edits:** Update `MQL5/Include/RPEA/risk.mqh` (add `ValidateBudgetGate`, `CheckPositionCaps`); `news.mqh` (add `IsOrderActionAllowed`, `QueueNewsAction`); integrate pre-place in `order_engine.mqh`.
   - **Code-Diff Sketch:**
     ```
     bool ValidateBudgetGate(double next_risk, const EquityRooms& rooms) {
       double open_r = Risk_ComputeOpenRisk(); // sum |entry-sl|*vol*tick_value
       double pend_r = Risk_ComputePendingRisk();
       if(open_r + pend_r + next_risk > 0.9 * MathMin(rooms.today, rooms.overall)) {
         LogBudgetGateSnapshot(open_r, pend_r, next_risk, rooms.today, rooms.overall, false);
         return false;
       }
       LogBudgetGateSnapshot(..., true); return true;
     }

     bool IsOrderActionAllowed(ENUM_ORDER_ACTION action, string symbol) {
       if(News_IsBlocked(symbol) && action != PROTECTIVE_EXIT && action != OCO_REDUCE && action != REPL_PROTECT) {
         if(action == TRAIL || action == SLTP_MOD) { QueueNewsAction(...); return false; }
         return false;
       }
       return true;
     }
     ```
   - **Commands/Scripts:** Compile; test gate fail (mock risks>0.9*room → reject, log snapshot); news queue (mock block → queue trail).
   - **Success Criteria:** Pre-place assert (reject + log if fail); caps query before place; news allows reduces/exits; CSV fallback parse (mock file).

9. **Task: Enhanced Order Logging and Persistence**
   - **Goal:** Extend audit with order fields/context; persist intents/queues.
   - **Dependencies:** Tasks 1-8 (hook all logs/persists).
   - **Exact File Edits:** Update `MQL5/Include/RPEA/logging.mqh` (add `LogOrderIntent`, `LogBudgetGateSnapshot`); extend CSV headers; `persistence.mqh` for `intents.json` (JSON serialize OrderIntent/QueuedAction).
   - **Code-Diff Sketch:**
     ```
     void LogOrderIntent(const OrderIntent& intent) {
       string row = StringFormat("%s,%s,%s,%.5f,%.5f,%.5f,%d,%s,%s,%.2f,%.2f,%.2f,%d,%s,%s",
         TimeToString(TimeCurrent()), intent.symbol, EnumToString(intent.type), intent.volume, intent.price, sl, tp,
         retry_count=0, execution_mode="OCO", confidence=0.75, efficiency=1.2, est_value=15.0, hold_time=2700, gating_reason="budget_pass", news_window="clear");
       FileWrite(audit_handle, row);
     }

     // In persistence.mqh
     void PersistIntents() {
       string json = "[";
       for each intent in g_intents { json += "{\"symbol\":\"" + intent.symbol + "\", ...}"; }
       json += "]";
       int file = FileOpen("intents.json", FILE_WRITE|FILE_TXT);
       FileWriteString(file, json); FileClose(file);
     }
     ```
   - **Commands/Scripts:** Compile; generate sample log (run 1min, assert CSV has new cols); persist test (write/read JSON, assert restore).
   - **Success Criteria:** Audit CSV extended (new fields populated); intents JSON valid (parse with mock); strategy context in rows (e.g., confidence from signal).

10. **Task: Test Scaffolding and Integration**
    - **Goal:** Unit/integration tests for order engine; tester hooks.
    - **Dependencies:** All prior (test full components).
    - **Exact File Edits:** Create `MQL5/Experts/FundingPips/Tests/OrderEngineTests.mq5` (add all Test* funcs); update `RPEA_10k_tester.ini` (add symbols, model=every_tick).
    - **Code-Diff Sketch:**
      ```
      //+------------------------------------------------------------------+
      //| OrderEngineTests.mq5                                             |
      //+------------------------------------------------------------------+
      #property strict
      #include <RPEA/order_engine.mqh>
      #include <Trade\Trade.mqh> // for mocks

      void OnStart() {
        TestOCOFullFill();
        TestPartialFillAdjust();
        // ... all tests
        Print("All M3 tests passed");
      }

      void TestOCOFullFill() {
        // Mock CTrade responses: place OCO, simulate DEAL_ADD full vol
        // Assert: sibling deleted, g_oco.active=false, log has tickets
        // Use deterministic: srand(42);
      }

      // Similar for others: mock news (return true), equity drop (floors), etc.
      ```
    - **Commands/Scripts:** Compile test file; run in Strategy Tester (1min, symbols=EURUSD, assert "All M3 tests passed"); smoke backtest 1-week (no violations, logs complete); `rg -i "test" MQL5/Experts/FundingPips/Tests/`.
    - **Success Criteria:** All units pass (coverage via mocks); integration: signal→order→txn→log; backtest: 0 breaches, CPU<2%, ≥3 days; .ini updated.
