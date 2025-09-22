# Codex (GPT‑5) Usage Guide for M2 – Structured, Compile‑First Workflow

This guide defines how to use Codex (GPT‑5) to implement M2 (BWISC engine, session stats, risk sizing, caps, budget gate) in small, compiling increments on branch `feat/m2-bwisc`.

## Guardrails (must follow)
- Follow `finalspec.md` strictly; do not alter locked decisions.
- M2 is non‑trading: no broker order placement (no `OrderSend`, etc.). Order engine remains stubbed.
- Keep the EA compiling after every small change. If a change breaks compilation, fix before proceeding.
- File‑scoped edits only; avoid refactors outside the declared scope of a request.

## Development loop (repeat per small task)
1) Plan a tiny change (≤1 function or ≤~50 lines).
2) Ask Codex with a precise change request (see templates), including:
   - File path(s), function name(s), minimal code context, and exact acceptance criteria (compiles; no behavior beyond scope).
3) Apply the edit and immediately compile `MQL5/Experts/FundingPips/RPEA.mq5` in MetaEditor.
4) If errors/warnings appear, copy the exact messages with file path/line numbers and 8–12 lines of nearby code back to Codex.
5) Iterate until clean compile, then commit.

## Prompt templates for Codex

### A) New implementation (small scope)
```
Goal: Implement <feature> for M2 (non‑trading).
Files:
- <path/to/file1.mqh>
Change:
- In <function or section>, add <specific logic>.
Constraints:
- Compile must succeed.
- No order placement. Keep existing public interfaces.
Acceptance:
- EA compiles; logs show <metric/decision>.
```

### B) Fix compile error
```
Context: After last edit, compile failed.
Compiler output (exact):
<file>(<line>): <error text>
...
Nearby code:
```cpp
// path: <file>
<8–12 lines around the error>
```
Task: Correct only what’s necessary to resolve these errors. Keep behavior within M2 scope; no refactors.
```

## Step‑by‑step build order for M2

1) Indicators – real handles and refresh (`Include/RPEA/indicators.mqh`)
- Create handles per symbol: ATR(D1,14), EMA20(H1), RSI14(H1).
- Add `Indicators_Refresh(...)` to fetch current values safely.
- Handle lifecycle: create once; release on deinit. If insufficient bars, return safe defaults and log.
- Log: write current ATR/MA/RSI values once per timer tick (info level).

2) Session stats & OR tracking (`Include/RPEA/sessions.mqh`)
- Compute Opening Range (OR) on M5 during first `ORMinutes` of each active session (London/NY).
- Store `OR_High`, `OR_Low`, session open price, and mark OR completion.
- Reset stats at session start. Keep pure helpers; no orders.

3) BWISC calculations (`Include/RPEA/signals_bwisc.mqh`)
- BTR (D1 yesterday): `|C_D1[1] − O_D1[1]| / max(H_D1[1] − L_D1[1], _Point)`.
- SDR: `|Open_LO − MA20_H1| / ATR_D1`.
- ORE: `(OR_High − OR_Low) / ATR_D1`.
- Bias (per spec weights). Implement `SignalsBWISC_Propose(...)` to compute metrics, setup type (BC/MSC/None), SL/TP points, and confidence (clamp |Bias|). Keep hasSetup allowed to be false until validated.
- RSI guard: use defaults [35,70] (or [30,68] variant). Allow override on strong SDR.
- Logging: log BTR/SDR/ORE/RSI/Bias/setup/confidence and gating reason.

4) Risk sizing (`Include/RPEA/risk.mqh`)
- Implement ATR‑distance sizing:
  - `risk_money = equity * (RiskPct/100)`
  - `sl_points = max(|entry − stop|/_Point, MinStopPoints)`
  - `value_per_point = SYMBOL_TRADE_TICK_VALUE / (SYMBOL_TRADE_TICK_SIZE/_Point)`
  - `raw_volume = risk_money / (sl_points * value_per_point)`
- Normalize to broker limits (min/max/step). Add ≤60% free‑margin guard using `OrderCalcMargin()` for estimation only.
- Return 0 volume if constraints fail.

5) Equity rooms & budget gate (`Include/RPEA/equity_guardian.mqh`)
- Implement real room formulas (spec):
  - Room today = `(DailyLossCapPct/100)*baseline_today − (baseline_today − current_equity)`
  - Room overall = `(OverallLossCapPct/100)*initial_baseline − (initial_baseline − current_equity)`
- Budget gate: `open_risk + pending_risk + next_trade_WC ≤ 0.9 * min(room_today, room_overall)`
- Surface session governance helpers: compute One-and-Done achieved, NY gate eligibility, floor breach flags
- Position/order caps: enforce total/per-symbol limits by counting actual MT5 positions/orders
- Small-room guard: pause if room_today < MinRiskDollar
- Keep kill‑switch floors to M4; M2 uses rooms for clamps only.

6) Order planning & caps integration (`Include/RPEA/allocator.mqh`)
- Build `OrderPlan` structure with volume from risk sizing, entry prices from BWISC, validation against budget gate and caps
- Caps enforcement: total positions, per‑symbol positions, per‑symbol pendings (using equity_guardian helpers)
- For M2: build plans but do not send orders; it’s OK to return `hasPlan=false` pending M3.

7) Scheduler integration (logging‑only)
- Keep `Scheduler_Tick(...)` unchanged except to log BWISC proposals and allocator outcomes.
- Ensure no order placement paths execute in M2.

8) Testing & compile cadence
- After each file/function, compile the EA in MetaEditor.
- Use Strategy Tester (1‑minute OHLC) for quick plumbing checks; switch to “Every tick based on real ticks” only for validation.
- Keep logs clean; verify decision rows contain new metrics.

## Commit & PR discipline
- Small commits (one logical change). Message template:
  - `M2: <component>: <short change>; compiles; no orders`
- Open PR from `feat/m2-bwisc` to `master` once BWISC metrics, sizing, rooms, and budget gate compile and log correctly.

## Definition of done (M2)
- EA compiles with indicators, session stats, BWISC metrics, risk sizing, rooms, caps, and budget gate wired.
- No order placement in runtime.
- Decision logs contain BTR/SDR/ORE/RSI/Bias/setup/confidence and budget/caps gating notes.
- Strategy Tester runs without errors; CPU remains low; no handle leaks observed.
