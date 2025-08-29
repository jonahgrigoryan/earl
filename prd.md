## PRD: FundingPips 10K RapidPass EA (RPEA) for MT5

### Objective
- Pass FundingPips 1-step $10,000 challenge by reaching +10% profit with zero drawdown-cap violations and at least 3 distinct trading days, ideally within 3–5 trading days.

### Success Metrics (Acceptance)
- Primary: Net P/L ≥ +$1,000 with 0 violations of daily and overall drawdown caps; trade days ≥ 3.
- Operational: No entries during blocked news windows; CPU < 2% on VPS; complete CSV audit logs.
- Backtesting/forward demo shows robust performance across recent months with low rule-violation risk.

### Scope
- Platform: MT5 (hedging or netting).
- Instruments: Multi-symbol (e.g., EURUSD, XAUUSD) with optional XAUEUR synthetic support (proxy default, replication optional).

### Users & Stakeholders
- Trader/Owner (configure and run EA; review results/logs).
- QA/Reviewer (verify compliance with FundingPips rules and auditability).
- Developer (maintain EA code and utilities).

### Assumptions & Constraints
- Daily cap anchored to CEST midnight based on baseline_today = max(balance_at_midnight_CEST, equity_at_midnight_CEST).
- Server-to-CEST offset must be configured (DST handling via input; manual update acceptable).
- News buffer ±120 seconds around high-impact events; protective exits always allowed.
- One EA instance active at a time.

### Functional Requirements

- Risk & Governance
  - Enforce configurable caps everywhere via inputs `DailyLossCapPct`, `OverallLossCapPct`.
  - Compute daily/overall rooms and apply a budget gate: open_risk + pending_risk + next_trade_worst_case ≤ 0.9 × min(room_today, room_overall).
  - Floors: `DailyFloor = baseline_today − DailyLossCapPct%`; `OverallFloor = initial_baseline − OverallLossCapPct%`. On breach: close all; disable (per-day or permanent) and allow protective exits even inside the news buffer.
  - Small-room guard: if room_today < `MinRiskDollar`, pause new trades for the day.
  - Micro-Mode: after +10% target and until `MinTradeDaysRequired` reached, trade one small-risk micro-fallback per day; then hard-stop.

- Sessions & Signal Logic
  - Evaluate London first, then New York. One-and-Done (global): if London win ≥ `OneAndDoneR`, end day (no NY on any symbol).
  - NY Gate: allow NY only if realized day loss ≤ `NYGatePctOfDailyCap × DailyLossCapPct` of today’s CEST baseline.
  - Entries: BWISC signals from bias based on D1 BTR, session SDR vs MA20_H1, OR energy, with RSI guard.
    - Burst Capture (BC): |Bias| ≥ 0.6 → stop beyond OR extreme; ATR-sized SL; TP = SL × `RtargetBC`.
    - Mean-Shift (MSC): |Bias| ∈ [0.35, 0.6) and SDR ≥ 0.35 → limit toward MA20_H1; SL beyond dislocation; TP = SL × `RtargetMSC`.
  - Trailing activates after +1R: trail by `ATR × TrailMult`.
  - Entry buffer: `EntryBufferPoints` applied to BC stops; respect `MinStopPoints`.
  - Position/order caps: enforce `MaxOpenPositionsTotal`, `MaxOpenPerSymbol`, `MaxPendingsPerSymbol` before placing orders.

- News Compliance (Policy)
  - Use MQL5 Economic Calendar; CSV fallback allowed.
  - Block entries from T−`NewsBufferS` to T+`NewsBufferS` for affected symbols/legs.
  - Protective exits (SL/TP/kill-switch/margin) always allowed.
  - Discretionary closes obey `MinHoldSeconds` unless kill-switch/margin requires immediate exit.
  - News-window behavior in [T−NewsBufferS, T+NewsBufferS]:
    - Blocked: no new orders, no PositionModify/OrderModify (incl. trailing, SL/TP moves, partial closes), no deletes except risk-reducing.
    - Queued: queue trailing or SL/TP optimizations; apply after T+NewsBufferS if still valid and not in a subsequent news window; drop stale items after `QueuedActionTTLMin` minutes.
    - Allowed exceptions: protective exits; broker SL/TP (log NEWS_FORCED_EXIT); OCO sibling cancel to reduce risk (log NEWS_RISK_REDUCE); replication pair-protect close (log NEWS_PAIR_PROTECT).

- XAUEUR Synthetic Support
  - Proxy (default): signals on XAUEUR; execution on XAUUSD; map synthetic SL via current EURUSD.
  - Replication (optional): two legs (XAUUSD and EURUSD) sized by `K = risk_money / SL_synth`; pre-check combined worst-case risk and margin against rooms; execute via two-leg protocol (retry/rollback) with unified budget gate.
  - Synthetic data: build XAUEUR M1 from synchronized XAUUSD/EURUSD M1; aggregate synthetic D1/H1 for ATR/MA/RSI; forward-fill short gaps.

- Order Engine & Reliability
  - OCO pendings and immediate sibling cancel on fill; partial fill handling.
  - Market fallbacks with `MaxSlippagePoints`. Retries/backoff: default 3 attempts, 300 ms; fail fast on REJECT/NO_MONEY/TRADE_DISABLED; rollback first leg if second leg fails in replication.

- Equity Guardian & Persistence
  - Persist: `initial_baseline`, `gDaysTraded`, `last_counted_cest_date`, mode flags (trading enabled, micro-mode), day peak equity.
  - Restart-safe: restore state and prevent double-counting of trade days.

- Logging & Audit
  - CSV audit rows for every decision: timestamp, account, symbol, baseline_today, room_today, room_overall, existing_risk, planned_risk, action, reason codes (incl. news, governance, floors, OCO), signal components (bias parts), session, and results.

### Non-Functional Requirements
- Performance: CPU < 2% on typical VPS; memory stable.
- Resilience: idempotent order reconciliation on init; clean handling of market closure and broker errors.
- Security/Privacy: logs exclude secrets; minimal PII.

### Inputs (Configuration)
- Risk & governance: `DailyLossCapPct` (3.0), `OverallLossCapPct` (6.0), `MinTradeDaysRequired` (3), `TradingEnabledDefault` (true), `MinRiskDollar` ($10), `OneAndDoneR` (1.5), `NYGatePctOfDailyCap` (0.50).
- Sessions & micro-mode: `UseLondonOnly` (false), `StartHourLO` (7), `StartHourNY` (12), `ORMinutes` (60), `CutoffHour` (16), `RiskPct` (1.5), `MicroRiskPct` (0.10), `MicroTimeStopMin` (45), `GivebackCapDayPct` (0.50).
- Compliance: `NewsBufferS` (120), `MaxSpreadPoints` (40), `MaxSlippagePoints` (10), `MinHoldSeconds` (120), `QueuedActionTTLMin` (5).
- Timezone: `ServerToCEST_OffsetMinutes` (0; update on DST as needed).
- Symbols & leverage: `InpSymbols` ("EURUSD;XAUUSD"), `UseXAUEURProxy` (true), `LeverageOverrideFX` (50), `LeverageOverrideMetals` (20).
- Targets & mechanics: `RtargetBC` (2.2), `RtargetMSC` (2.0), `SLmult` (1.0), `TrailMult` (0.8), `EntryBufferPoints` (3), `MinStopPoints` (1), `MagicBase` (990200).
- Position/order caps: `MaxOpenPositionsTotal` (2), `MaxOpenPerSymbol` (1), `MaxPendingsPerSymbol` (2).

### Flows (High-Level)
- Scheduler (OnTimer 30–60s): check rooms and news; evaluate sessions; compute stats; signal decide; risk/lot sizing; place OCO/market; apply governance; queue news-window modifications; trailing; cutoff micro-mode.
- Trade transactions: OCO cancellation on entry; governance on close (R calculation, One-and-Done/NY gate updates); mark first deal per CEST day.

### Milestones (Delivery)
- M1: Skeleton, inputs, state structs, scheduler, logging; indicator handles; news fallback parser; persistence scaffolding.
- M2: Signal engine (BWISC) and stats; risk sizing; margin guard; position caps; budget gate.
- M3: Order engine (OCO, slippage, trailing, partial fill); synthetic manager; two-leg atomicity.
- M4: Compliance polish (calendar integration; CEST day tracking; kill-switch floors; disable flags; persistence hardening).
- M5: Strategy Tester artifacts (.set for $10k; optimization ranges; walk-forward; CSV audit/reporting).
- M6: Hardening (market closure, rejects; parameter validation; restart/idempotency; perf profiling; code review).

### Risks & Mitigations
- News compliance ambiguity → Explicit news-window policy with blocked/queued/allowed actions and TTL.
- DST/server time misalignment → Clear offset input; document DST updates.
- Overfitting signals → Use bounded ranges; walk-forward validation.
- Replication atomicity → Retry/rollback protocol; default to proxy mode when margin or budget insufficient.

### Out of Scope (MVP)
- Grid/martingale/HFT/latency arbitrage.
- Auto-DST computation (manual offset acceptable for MVP).


