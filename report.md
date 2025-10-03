# Section A: Repo State Summary (M1–M2)

**Scope reviewed:** `jonahgrigoryan/earl` branch `feat/m2-bwisc`, SPEC-003 `finalspec.md` (LOCKED items honored).

## What M1 delivered
- Project skeleton under `MQL5/{Experts,Include}/RPEA` with inputs, state, time helpers, sessions, indicators, logging, and scheduler tick loop.
- CSV logging scaffolding and file layout under `Files/RPEA/...` as per structure file.
- News CSV fallback parser stub and state persistence stubs created.

## What M2 delivered
- BWISC signal engine surface with BTR/SDR/ORE/RSI → Bias and BC/MSC setup proposals.
- Risk sizing pipeline present: per-trade risk from equity, ATR-scaled SL/TP, value-per-point calc, lot normalization.
- Budget gate and caps wired: counts open + pending risk before next trade, position/order caps evaluated.
- Margin guard present in risk flow.
- Allocator linkage from signal → proposed order plan.

## Gaps vs SPEC-003 after M2
- Order paths are stubs: no OCO pendings, no market fallback, no trailing queue, no partial-fill handling.
- Synthetic manager not implemented: no XAUEUR proxy/replication sizing, no two-leg atomicity.
- News-window enforcement is not yet integrated into order/modify paths; queuing of trailing/SL-TP absent.
- Persistence for `intents.json` and restart reconciliation not implemented.
- No Strategy Tester artifacts in repo (`.ini`, `.set` deltas) beyond structure notes.
- Calendar API integration and CEST mapping slated for M4 are not yet present (expected).

---

# Section B: M3 Plan — Order Engine + Synthetic Manager + Two‑Leg Atomicity

## 1) Files to create/modify
- **Create** `MQL5/Include/RPEA/order_engine.mqh` (full implementation).
- **Create** `MQL5/Include/RPEA/synthetic.mqh` (proxy + replication + atomic orchestrator).
- **Create** `MQL5/Include/RPEA/persistence.mqh` (order intents + queued actions; JSON IO).
- **Modify** `MQL5/Experts/FundingPips/RPEA.mq5` (wire `OnTradeTransaction`, housekeeping loop).
- **Modify** `MQL5/Include/RPEA/allocator.mqh` (emit `OrderPlan` including OCO legs and synthetic flags).
- **Modify** `MQL5/Include/RPEA/news.mqh` (expose `IsNewsBlocked(symbol)` with leg-aware check).
- **Modify** `MQL5/Include/RPEA/logging.mqh` (add OCO/atomicity reason codes and NEWS_* codes).
- **Modify** `MQL5/Include/RPEA/risk.mqh` (ensure worst-case risk includes both legs in replication and respects budget gate).
- **Modify** `MQL5/Include/RPEA/equity_guardian.mqh` (allow protective exits at floors during news locks).

## 2) Data structures

```cpp
// OrderEngine surface
struct OrderTicketInfo {
  long ticket_main;      // filled leg ticket
  long ticket_sibling;   // OCO sibling ticket (if any)
  long ticket_leg2;      // replication second leg (if any)
  int  retcode;          // last trade server code
};

enum OrderKind { ORDER_STOP, ORDER_LIMIT, ORDER_MARKET };
enum SetupKind { SETUP_BC, SETUP_MSC };
enum SyntheticMode { SYNTH_PROXY=0, SYNTH_REPL=1 };

struct PendingLeg {
  string symbol;
  OrderKind kind;
  double price;
  double sl;
  double tp;
  datetime expiry;
};

struct OrderPlan {
  string base_symbol;
  SetupKind setup;
  double volume_base;
  double entry_price;
  double sl_price;
  double tp_price;
  int    slippage_pts;
  bool   use_oco;
  PendingLeg sibling;         // opposite side for OCO, same symbol
  bool   is_synthetic;
  SyntheticMode synth_mode;
  // Replication parameters (if SYNTH_REPL)
  string leg2_symbol;         // e.g., EURUSD
  double volume_leg2;
  double sl_leg2;
  double tp_leg2;
  // Bookkeeping
  double worst_case_usd;      // combined WC at stops
  string reason;              // 'BC','MSC'
};
```

### Order intent journal
```cpp
struct QueuedAction {
  string kind;          // "TRAIL","SLTP_OPT","CANCEL_SIBLING"
  long   target_ticket;
  double new_sl;
  double new_tp;
  datetime created;
  int ttl_min;
};

struct OrderIntent {
  string id;            // uuid
  OrderPlan plan;
  long   ticket_pending;
  long   ticket_sibling;
  long   ticket_leg2;
  string state;         // "PENDING","FILLED","CANCELLED","ERROR"
  datetime created;
};
```

## 3) Public APIs (headers)

```cpp
// order_engine.mqh
bool OrderEngine_Init();
bool OrderEngine_Place(const OrderPlan &plan, OrderTicketInfo &out);
bool OrderEngine_Cancel(long ticket);
bool OrderEngine_ModifySLTP(long ticket, double sl, double tp);
bool OrderEngine_Queue(const QueuedAction &qa);    // store to intents.json
void OrderEngine_Housekeeping();                   // drain queues when news window clears
void OrderEngine_OnTradeTransaction(const MqlTradeTransaction &tt, const MqlTradeRequest &req, const MqlTradeResult &res);

// synthetic.mqh
bool Synth_BuildPlan(OrderPlan &plan);             // fill synth fields given UseXAUEURProxy
bool Synth_ValidateBudget(const OrderPlan &plan);  // WC across both legs within rooms
bool Synth_ExecuteAtomic(OrderPlan &plan, OrderTicketInfo &out); // replication with rollback
```

## 4) Mechanics and edge cases
- **OCO pendings:** place two opposite pendings with shared group id; on first fill, cancel sibling. If broker lacks native OCO, emulate: watch `OnTradeTransaction` for fill then `OrderDelete` sibling.
- **Expiry:** set to session cutoff or `CutoffHour`. Delete at expiry or session end.
- **Market fallback:** if pending rejected or price already through level by more than buffer but within `MaxSlippagePoints`, send market order with SL/TP attached. Otherwise abandon.
- **Partial fill:** if partials occur, immediately adjust sibling risk and SL/TP, or cancel sibling to avoid risk increase.
- **Trailing:** activate after +1R. If `IsNewsBlocked(symbol)` → **queue** trailing action; apply after window clears if ticket still valid and TTL not expired.
- **News window:** Block new orders/modify in `[T−NewsBufferS, T+NewsBufferS]` except allowed risk‑reducing actions (protective exits, OCO sibling cancel after unexpected fill, replication pair‑protect close).
- **Floors & kill-switch:** if a floor is breached, close all positions regardless of news window and disable new entries per locked rules.
- **Synthetic replication (XAUEUR):** execute leg1 then leg2 with retry/backoff; on leg2 failure, rollback leg1; if margin tight, **downgrade to proxy** before sending any order.
- **Position/order caps:** re-check caps just before send to avoid race.
- **Idempotency:** persist intents before sending; on restart, reconcile tickets and apply queued actions or clean up.

## 5) Test scaffolding & Strategy Tester hooks
- Add `Files/RPEA/sets/RPEA_10k_default.set` with current inputs.
- Add `Files/RPEA/strategy_tester/RPEA_10k_tester.ini` to run a 3–6 month smoke.
- Housekeeping test: simulate news window in Tester; verify that trailing updates are queued and later applied.
- Atomic replication test: force second-leg rejection and verify rollback.
- Budget-gate test: create plan where WC exceeds remaining room; expect refusal.
- OCO test: simulated fill cancels sibling within one tick.

## 6) Logging and persistence
- CSV `decisions_YYYYMMDD.csv` append fields: `action,kind,ticket,base_symbol,leg2_symbol,is_synth,synth_mode,oco,retcode,reason,news_state`.
- CSV `audit_YYYYMMDD.csv` append: `wc_usd_before, wc_usd_after, room_today, room_overall`.
- Persistence files:
  - `Files/RPEA/state/intents.json` for `OrderIntent[]` and `QueuedAction[]`.
  - Existing state file retains baselines, day counts, flags.

## 7) Preconditions from LOCKED decisions
- Respect news lock windows and exceptions.
- Apply global One-and-Done and NY Gate.
- Enforce position/order caps before any send/modify.
- Floors close all and allow protective exits during locks.
- Trade day counting from first `DEAL_ENTRY_IN` of server day.

---

# Section C: Acceptance Checklist

**Unit-level**
- Order sizing unit computes lot and WC risk within ±1% tolerance across XAUUSD/EURUSD.
- Synth plan builder maps XAUEUR proxy and replication correctly for 10 sample scenarios.
- Queue logic drops expired items after `QueuedActionTTLMin`.

**Integration**
- OCO: first fill cancels sibling within 1 tick; sibling non-existent afterward.
- Market fallback: pending miss → market send iff slippage ≤ `MaxSlippagePoints`.
- News gating: no OrderSend/Modify in blocked window; queued trailing applied after unblock.
- Floors: kill-switch closes open positions immediately and disables new entries until reset.
- Replication: leg2 failure triggers rollback leg1; WC budget computed on both legs.

**Backtest smoke**
- 3-month test over EURUSD/XAUUSD runs without error dialogs; CSVs produced; CPU stays low.
- No actions recorded inside blocked news windows.
- At least one OCO cycle and one queued trailing applied in logs.

**PR artifacts**
- Diff summary with touched files.
- 2 CSV samples (`audit`, `decisions`) committed under `Files/RPEA/reports/` for review.
- `.set` and `.ini` files added under `Files/RPEA/{sets,strategy_tester}`.

---

# Section D: Zen Agent Task Graph

Topological order (each = one agent run).

1. **Scaffold Order Engine file**
   - Files: `order_engine.mqh`
   - Diff: header + stubs for APIs.
   - Cmd: compile EA.
   - Success: builds clean.

2. **Add OrderPlan in allocator**
   - Files: `allocator.mqh`
   - Diff: emit `OrderPlan` fields from BWISC proposal.
   - Success: compile; unit logs show plan fields populated.

3. **Implement OCO pending placement**
   - Files: `order_engine.mqh`
   - Diff: `OrderEngine_Place` path for two pendings with expiry; sibling cancel on fill via `OnTradeTransaction`.
   - Success: backtest shows OCO cancel behavior.

4. **Market fallback with slippage**
   - Files: `order_engine.mqh`
   - Diff: pending→market path with `MaxSlippagePoints` check.
   - Success: backtest case triggers fallback.

5. **Queued trailing + SL/TP modify**
   - Files: `order_engine.mqh`, `persistence.mqh`
   - Diff: add `QueuedAction`, JSON IO, housekeeping loop.
   - Success: news-window simulation shows queued then applied.

6. **Wire `OnTradeTransaction`**
   - Files: `RPEA.mq5`
   - Diff: forward to `OrderEngine_OnTradeTransaction`.
   - Success: OCO cancel and partial-fill updates work.

7. **Synthetic manager: proxy mode**
   - Files: `synthetic.mqh`, `risk.mqh` (WC calc)
   - Diff: map XAUEUR SL to XAUUSD; validate budget; set plan fields.
   - Success: proxy trades placed; WC reflected in audit.

8. **Synthetic replication: sizing + atomic send**
   - Files: `synthetic.mqh`, `order_engine.mqh`
   - Diff: leg1→leg2 with rollback; retries/backoff.
   - Success: forced failure rolls back leg1.

9. **News-window enforcement and exceptions**
   - Files: `news.mqh`, `order_engine.mqh`, `logging.mqh`
   - Diff: guard rails; log `NEWS_FORCED_EXIT`, `NEWS_RISK_REDUCE`, `NEWS_PAIR_PROTECT`.
   - Success: no illegal actions during window.

10. **Persistence: intents.json reconciliation on init**
    - Files: `persistence.mqh`, `RPEA.mq5`
    - Diff: load, reconcile, drop stale.
    - Success: restart-safe behavior verified.

11. **Strategy Tester assets**
    - Files: `Files/RPEA/sets/..., strategy_tester/...`
    - Diff: add `.set`, `.ini`.
    - Success: CI/backtest instructions run locally.

12. **Telemetry & CSV enrichment**
    - Files: `logging.mqh`
    - Diff: new columns for order engine actions and WC numbers.
    - Success: sample CSVs captured.

---

# Section E: PR Plan

- **Branch:** `feat/m3-order-engine`
- **Commits:** 8–12 small commits mirrored to tasks above.
- **PR template:**
  - Summary: Implements M3 order engine + synthetic manager per SPEC-003.
  - Checkboxes:
    - [ ] OCO placement + cancel on fill
    - [ ] Market fallback with slippage
    - [ ] Trailing queue with TTL + housekeeping
    - [ ] News-window enforcement and exceptions
    - [ ] Synthetic proxy + replication atomic send
    - [ ] Budget gate across both legs
    - [ ] intents.json persistence + restart reconciliation
    - [ ] Strategy Tester assets + sample CSVs
  - Test notes: attach backtest smoke summary and paths to CSV samples.
  - Risks: broker differences on OCO, partial fills; margin constraints on metals.

---

## Open Questions
- Confirm broker supports native OCO. If not, keep emulation path only.
- Confirm partial-fill semantics on your broker for pendings on metals.
- Confirm desired default for `UseXAUEURProxy` at M3 (proxy recommended).
