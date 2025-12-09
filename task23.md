# Task23 Breakeven Implementation Outline (Final)

## Current Phase-5 State

- Task 21 (confidence-based sizing) live in `risk.mqh` / `allocator.mqh`.
- Task 22 (ATR-based spread filter) live in `liquidity.mqh` with `Config_GetSpreadMultATR` default 0.005.
- Task 23 (+0.5R breakeven) not implemented; trailing still starts at +1R in `trailing.mqh`.
- Task 24 (45m pending expiry) not present; pendings still align to session/grace in `order_engine.mqh`.

## Step-by-Step Plan

1) **Breakeven Config Helper** – Add a small helper/default for spread buffer in `Include/RPEA/config.mqh` (non-breaking). Define spread buffer concretely: `spread_price = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT)`; breakeven SL uses entry ± `spread_price` (long:+, short:−), rounded to symbol digits; optionally allow a tiny additive buffer constant if desired.
2) **Breakeven Manager Module** – Add a dedicated helper (new `Include/RPEA/breakeven.mqh`; if co-locating, a contained section inside `Include/RPEA/trailing.mqh`) that:

- Tracks per-ticket baseline R (|entry − entry_sl_at_open|) and a one-shot `breakeven_applied` flag; no trigger if baseline_r ≤ 0.
- Detects +0.5R using current price vs entry; SL target = entry ± spread buffer; never widens SL beyond current (monotonic toward breakeven only); round to symbol digits.
- Uses `OrderEngine_RequestModifySLTP` to apply; when `News_IsBlocked`, enqueue via existing queue path; mark flag after queued or applied; update timestamps.
- Provides `Breakeven_Init/HandleOnTickOrTimer/OnPositionClosed/Test_Reset` mirroring trailing hooks.
3) **Order Engine Wiring** – Integrate into `Include/RPEA/order_engine.mqh` lifecycle:
- Include/init alongside trailing inside `OrderEngine_RestoreStateOnInit`.
- Call `Breakeven_HandleOnTickOrTimer` before `Trail_HandleOnTickOrTimer` in `OrderEngine_ProcessQueueAndTrailing` so trailing still activates at +1R after breakeven.
- On position close in `OrderEngine_OnTradeTransaction`, call `Breakeven_OnPositionClosed` (plus existing queue coalesce) to clear state.
4) **Unit Tests for Breakeven** – Add `Tests/RPEA/test_order_engine_breakeven.mqh` covering:
- Trigger at +0.5R (long/short) moves SL to entry ± spread buffer; below +0.5R no move.
- SL monotonic: does not widen vs current SL.
- News window queues (using `Queue_Test_SetNewsBlocked`, `Queue_Test_RegisterPosition`), post-news apply succeeds.
- Trailing still eligible at +1R after breakeven (no regression to `Trail_ShouldActivateFromState`).
5) **Runner Wiring** – Wire the breakeven test into `Tests/RPEA/run_automated_tests_ea.mq5` (drop `run_order_engine_tests.mq5` scope).

## Implementation Todos

- add-config: Add optional breakeven spread buffer helper/default (config.mqh).
- implement-breakeven: +0.5R breakeven manager with detection/SL compute/news-aware apply.
- wire-order-engine: Hook breakeven init/handler/cleanup into order_engine.mqh lifecycle.
- add-tests-runner: Add breakeven unit tests and wire into run_automated_tests_ea.mq5.