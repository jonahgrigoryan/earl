You are an MQL5 EA engineering assistant working only on M2 (BWISC) for the RPEA project.

Branch and repo context:
- Work on branch: feat/m2-bwisc
- Entry point: MQL5/Experts/FundingPips/RPEA.mq5
- Include targets (M2 scope only):
  - MQL5/Include/RPEA/indicators.mqh
  - MQL5/Include/RPEA/sessions.mqh
  - MQL5/Include/RPEA/signals_bwisc.mqh
  - MQL5/Include/RPEA/risk.mqh
  - MQL5/Include/RPEA/equity_guardian.mqh
  - MQL5/Include/RPEA/allocator.mqh
  - (read-only) MQL5/Include/RPEA/scheduler.mqh for logging integration

Read first (authoritative):
- finalspec.md (locked spec; do not change decisions)
- m2.md (step-by-step M2 plan to implement)
- codex.md (compile-first loop, prompt patterns, definition of done)

Hard constraints (must follow):
- M2 is non-trading. Do NOT add any broker order placement (no OrderSend/Position* calls). Leave order_engine.mqh as stubs.
- Preserve all locked decisions in finalspec.md.
- Keep the EA compiling at all times. After each small change, compile RPEA.mq5 and stop to address errors.
- Do not modify files outside the M2 scope listed above.

Definition of done for M2 (summarized):
- Indicators live handles + refresh (ATR D1, EMA20 H1, RSI H1), session stats incl. OR, BWISC metrics (BTR/SDR/ORE/Bias + RSI guard), risk sizing by ATR distance, equity rooms, caps, budget gate; logging-only (no orders); compiles cleanly.
- **[Updated]** Session governance must respect locked rules (One-and-Done, NY Gate, UseLondonOnly) across the pipeline so downstream tasks see the right enable/disable flags.
- **[Updated]** Performance guardrails from finalspec/m2 hold: signal calculations stay <100 ms per symbol and EA CPU usage remains <2 % during active operation.

TASK 1 (small, compile-first): Implement real indicators (handles + refresh)
Files to edit:
- MQL5/Include/RPEA/indicators.mqh (implement)
- (optional small log hook) MQL5/Include/RPEA/scheduler.mqh (only to log indicator values after refresh; no logic changes)

Requirements:
- In indicators.mqh:
  - Create per-symbol handles: iATR(symbol, PERIOD_D1, 14), iMA(symbol, PERIOD_H1, 20, 0, MODE_EMA, PRICE_CLOSE), iRSI(symbol, PERIOD_H1, 14, PRICE_CLOSE).
  - **[Updated]** Add lightweight retry/backoff on handle creation (per spec) and log a WARN before exiting if a handle stays INVALID_HANDLE so downstream tasks can short-circuit safely.
  - Implement Indicators_Init(const AppContext&): create handles once, guard INVALID_HANDLE, prepare per-symbol context.
  - **[Updated]** Ensure AppDeinit/Indicators_Deinit releases all indicator handles to avoid leaks and clears per-symbol caches.
  - Implement Indicators_Refresh(const AppContext&, const string symbol): 
    - Fetch ATR_D1, EMA20_H1, RSI_H1 via CopyBuffer safely.
    - Provide helper to read yesterday’s D1 OHLC (O_D1[1], H_D1[1], L_D1[1], C_D1[1]) via CopyRates or iTime/Copy*; handle weekend gaps; return safe defaults when insufficient data.
    - Cache latest values in a per-symbol context accessible to BWISC.
    - **[Updated]** When symbol == XAUEUR (or other synthetic per finalspec), build synthetic candles from synchronized leg data (XAUUSD/EURUSD) before calculating ATR/EMA/RSI so BWISC sees the correct synthetic inputs.
  - Add getters (or expose through a small struct) to retrieve: atr_d1, ma20_h1, rsi_h1, open_d1[1], high_d1[1], low_d1[1], close_d1[1].
  - Lifecycle: no leaks; safe if called repeatedly; tolerate missing data.
- Optional minimal logging (preferred): After Indicators_Refresh in scheduler tick, write a decision log line:
  LogDecision("Indicators", "REFRESH", "{\"symbol\":\"<sym>\",\"atr\":X,\"ma20_h1\":Y,\"rsi_h1\":Z}");
- Do NOT modify any order/broker code. Do NOT add runtime heavy loops.

Acceptance for TASK 1:
- Project compiles (no warnings turning into errors). 
- On attach, no runtime errors; periodic logs show indicators populated or safe defaults if insufficient data.
- **[Updated]** Indicator handle lifecycles survive repeated init/deinit cycles without leaks; per-symbol refresh stays under the <100 ms latency target.

After implementing TASK 1:
- STOP and wait for my compile results from MetaEditor. I will paste exact errors (file:line), and you will address only those until clean.

Planned next tasks (do not implement yet):
- Task 2: Session stats & OR tracking in sessions.mqh (M5-based OR for ORMinutes; per-session reset).
- Task 3: BWISC metrics + SignalsBWISC_Propose in signals_bwisc.mqh (BTR w/ D1[1], SDR, ORE, Bias, RSI guard; detailed logging).
- Task 4: Risk sizing in risk.mqh (ATR-distance, normalization, ≤60% margin guard).
- Task 5: Equity rooms in equity_guardian.mqh (room_today, room_overall).
- Task 6: Caps + budget gate in allocator.mqh (no order send; plan struct OK).
- Scheduler remains logging-only.

Commit format:
- “M2: indicators: add ATR/EMA/RSI handles, refresh; compile; no orders”





TASK 2 (M2): Session stats & Opening Range (OR) tracking – logging-only

Context (read first):
- finalspec.md (locked spec; do not change decisions)
- m2.md (M2 step-by-step plan; this task is §5.2)
- codex.md (compile-first loop and guardrails)
- Branch: feat/m2-bwisc
- Entry point: MQL5/Experts/FundingPips/RPEA.mq5

Scope (files to edit only):
- MQL5/Include/RPEA/sessions.mqh  (implement OR tracking & getters)
- (optional minimal logs) MQL5/Include/RPEA/scheduler.mqh (log OR states only; no logic changes)

Requirements:
- OR window: first ORMinutes from session start (London & NY). Respect UseLondonOnly and CutoffHour.
- **[Updated]** Integrate session governance: pull One-and-Done state and NY gate allowances from AppContext/equity guardian, expose `session_enabled` flags per session, and skip OR evaluation when a session is disabled while logging the gating reason.
- Compute OR on M5:
  - Track per-symbol/session state: session label ("LO"/"NY"), session_open_price, or_start_time, or_end_time, OR_High, OR_Low, or_complete flag.
  - During OR window: update OR_High/OR_Low from M5 bars (use CopyRates or iHigh/iLow). Tolerate insufficient bars with safe defaults and log WARN once.
  - On OR window close: freeze OR_High/OR_Low and set or_complete=true.
- Reset logic: on new session start, reset OR fields and capture session_open_price.
- Getters: add small helpers to expose OR_High, OR_Low, session_open_price, or_complete for BWISC (signals_bwisc.mqh).
- Performance: no heavy loops; bounded CopyRates window; return early if outside session or already complete.
- Logging (decision log):
  - When OR completes: LogDecision("Sessions","OR_COMPLETE", {"symbol":..., "session":"LO/NY","or_high":X,"or_low":Y})
  - Optional lightweight heartbeat when in OR window: LogDecision("Sessions","OR_TICK", {"symbol":...,"session":"...","or_h":X,"or_l":Y})
  - **[New]** When a session is gated off (One-and-Done/NY gate/UseLondonOnly), emit LogDecision("Sessions","SESSION_BLOCKED", {"session":"...","reason":"..."}).

Hard constraints:
- Non-trading (no order placement).
- Keep compile green after each small change; fix errors before proceeding.
- Do not modify files outside this scope.

Acceptance:
- EA compiles in MetaEditor.
- On live/tester run, logs show OR_COMPLETE per session with OR_High/OR_Low; no runtime errors.
- **[Updated]** Session enablement follows One-and-Done/NY gate rules exactly and blocked sessions produce the expected SESSION_BLOCKED logs.

After implementation:
- STOP and wait for my compile/run feedback (I'll paste exact errors/warnings if any).


TASK 3 (M2): BWISC Signal Engine Implementation – logging-only

Context (read first):
- finalspec.md (locked spec; do not change decisions)
- m2.md (M2 step-by-step plan; this task is §2 BWISC Signal Engine)
- codex.md (compile-first loop and guardrails)
- Branch: feat/m2-bwisc
- Entry point: MQL5/Experts/FundingPips/RPEA.mq5

Scope (files to edit only):
- MQL5/Include/RPEA/signals_bwisc.mqh (implement full BWISC engine)
- (optional minimal logs) MQL5/Include/RPEA/scheduler.mqh (log BWISC signals only; no logic changes)

Requirements:
- Implement complete BWISC calculations per finalspec.md:
  - BTR (Body-to-TrueRange): |C_D1[1]-O_D1[1]| / max(H_D1[1]-L_D1[1], point) using yesterday's D1 OHLC
  - SDR (Session Dislocation Ratio): |Open_LO - MA20_H1| / ATR(D1) using session open vs MA20
  - ORE (Opening Range Energy): (or_high - or_low) / ATR(D1) using OR levels from sessions.mqh
  - Bias Score: 0.45*sign(C1−O1)*BTR + 0.35*sign(Open_LO − MA20_H1)*min(SDR,1) + 0.20*sign(C1−O1)*min(ORE,1)
  - **[Updated]** Always pull session open/OR snapshots and session-enabled flags from Sessions_GetORSnapshot()/Sessions_CurrentState so BWISC never evaluates a disabled or stale session.
- Setup Detection Logic:
  - BC (Breakout Continuation): |Bias| ≥ 0.6 → Stop beyond OR extreme, ATR SL, target 2.2R
  - MSC (Mean Reversion): |Bias| ∈ [0.35,0.6) AND SDR ≥ 0.35 → Limit toward MA20_H1, SL beyond dislocation, target 1.8-2.2R
  - **[Updated]** Compute slPoints/tpPoints with locked ATR-based formulas (include EntryBufferPoints, SLMult, RtargetBC/RtargetMSC) and return them through SignalsBWISC_Propose.
- RSI Guard: Check RSI_H1 overextension (default ranges [35,70]); strong dislocation can override
- SignalsBWISC_Propose() complete implementation:
  - Input: AppContext, symbol
  - Output: hasSetup, setupType, slPoints, tpPoints, bias, confidence via reference parameters
  - Confidence = clamp(|Bias|, 0, 1)
  - Error handling: safe defaults on calculation failures
  - **[New]** Stage allocator-facing context (expected_R, expected_hold, worst_case_risk) alongside the returned bias/confidence so Task 6 can consume without recomputing.
- Data dependencies: Use Indicators_GetSnapshot() for ATR/MA/RSI; Sessions_GetORSnapshot() for OR levels
- Performance: efficient calculations, early returns for invalid data
- Logging (decision log):
  - For each symbol evaluation: LogDecision("BWISC","EVAL", {"symbol":...,"btr":X,"sdr":Y,"ore":Z,"bias":W,"setup":"BC/MSC/None","confidence":C})
  - Include gating reasons (RSI guard, insufficient data, etc.)
  - **[New]** When a setup is blocked by session/news/room gates, add a `"blocked_by"` field with the specific reason per finalspec compliance logging.

Hard constraints:
- Non-trading (no order placement).
- Keep compile green after each small change; fix errors before proceeding.
- Do not modify files outside this scope.
- Use exact formulas from finalspec.md - no approximations.

Acceptance:
- EA compiles in MetaEditor.
- On live/tester run, logs show BWISC evaluations with BTR/SDR/ORE/Bias calculations and setup detection; no runtime errors.
- Setup detection triggers correctly for BC (|Bias| ≥ 0.6) and MSC (|Bias| ∈ [0.35,0.6) AND SDR ≥ 0.35).
- **[Updated]** Allocator snapshot data (expected_R/hold/worst_case_risk) is available and session/news gating prevents proposals when blocked.

After implementation:
- STOP and wait for my compile/run feedback (I'll paste exact errors/warnings if any).


TASK 4 (M2): Risk Sizing & ATR-Based Volume Calculation – logging-only

Context (read first):
- finalspec.md (locked spec; do not change decisions)
- m2.md (M2 step-by-step plan; this task is §3 Risk Management)
- codex.md (compile-first loop and guardrails)
- Branch: feat/m2-bwisc
- Entry point: MQL5/Experts/FundingPips/RPEA.mq5

Scope (files to edit only):
- MQL5/Include/RPEA/risk.mqh (implement ATR-based sizing)
- (optional minimal logs) MQL5/Include/RPEA/scheduler.mqh (log risk calculations only; no logic changes)

Requirements:
- Implement ATR-Based Position Sizing per finalspec.md formulas:
  - risk_money = equity * risk_pct
  - sl_points = max(|entry - stop| / _Point, MinStopPoints)  
  - value_per_point = (SYMBOL_TRADE_TICK_VALUE) / (SYMBOL_TRADE_TICK_SIZE / _Point)
  - raw_volume = risk_money / (sl_points * value_per_point)
- Volume Normalization:
  - Round to SYMBOL_VOLUME_STEP
  - Respect SYMBOL_VOLUME_MIN and SYMBOL_VOLUME_MAX
  - Apply leverage limits (1:50 FX, 1:20 metals per symbol properties)
- Margin Guard Implementation:
  - Ensure position uses ≤60% of available margin
  - Use OrderCalcMargin() for accurate estimation
  - Fallback logic: reduce volume if margin insufficient
  - Return 0 volume if margin constraints cannot be met
- Risk_SizingByATRDistance() function enhancement:
  - Input: entry price, stop price, symbol, risk_pct
  - Output: normalized volume respecting all constraints
  - Handle edge cases: invalid prices, insufficient margin, symbol properties errors
  - **[Updated]** Accept optional available-room inputs so `risk_money` is clamped to `min(room_today, room_overall)` before sizing (align with equity guardian budget rules) and note any clamp in the logs.
- Integration with existing stubs: enhance existing function, don't replace entirely
- Error handling: safe defaults, comprehensive logging of calculation steps
- Performance: efficient calculations, cache symbol properties where beneficial
- Logging (decision log):
  - For each sizing calculation: LogDecision("Risk","SIZING", {"symbol":...,"entry":X,"stop":Y,"risk_money":Z,"sl_points":W,"raw_volume":V,"final_volume":F,"margin_used_pct":M})
  - Log margin guard actions and volume reductions
  - **[New]** When room clamping occurs, include `"room_cap":min_room` and `"clamped":true` in the payload.

Hard constraints:
- Non-trading (no order placement).
- Keep compile green after each small change; fix errors before proceeding.
- Do not modify files outside this scope.
- Use exact formulas from finalspec.md.
- Respect all symbol properties and broker limitations.

Acceptance:
- EA compiles in MetaEditor.
- Risk sizing calculations produce reasonable volumes for typical setups.
- Margin guard prevents excessive margin usage (≤60%).
- Volume normalization respects broker constraints.
- Logs show complete sizing calculation chain with all intermediate values.
- **[Updated]** Room-based clamps are honored when provided and reflected in the risk logs.

After implementation:
- STOP and wait for my compile/run feedback (I'll paste exact errors/warnings if any).


TASK 5 (M2): Equity Guardian & Room Calculations – logging-only

Context (read first):
- finalspec.md (locked spec; do not change decisions)
- m2.md (M2 step-by-step plan; this task is §4 Equity Guardian Enhancements)
- codex.md (compile-first loop and guardrails)
- Branch: feat/m2-bwisc
- Entry point: MQL5/Experts/FundingPips/RPEA.mq5

Scope (files to edit only):
- MQL5/Include/RPEA/equity_guardian.mqh (implement real room calculations)
- (optional minimal logs) MQL5/Include/RPEA/scheduler.mqh (log room states only; no logic changes)

Requirements:
- Implement Real Room Calculations per finalspec.md formulas:
  - Room today: (DailyLossCapPct/100) * baseline_today − (baseline_today − current_equity)
  - Room overall: (OverallLossCapPct/100) * initial_baseline − (initial_baseline − current_equity)
  - Use server-day anchored baseline_today from AppContext
- Budget Gate Implementation (M2 scope):
  - Current exposure: Sum open position risk + pending order risk  
  - Next trade validation: open_risk + pending_risk + next_trade_worst_case ≤ 0.9 * min(room_today, room_overall)
  - Query actual MT5 positions/orders for real-time risk calculation
- **[Updated]** Surface session governance helpers: compute One-and-Done achieved, NY gate eligibility, and floor breach flags so sessions.mqh/scheduler can gate sessions without duplicating equity calculations.
- Position/Order Caps Enforcement:
  - Before any order check: OpenPositionsTotal < MaxOpenPositionsTotal
  - OpenPositionsBySymbol(sym) < MaxOpenPerSymbol
  - OpenPendingsBySymbol(sym) < MaxPendingsPerSymbol
  - Implement helper functions to count positions/orders by symbol
- Equity_ComputeRooms() enhancement:
  - Replace stub implementation with real calculations
  - Return EquityRooms struct with room_today, room_overall values
  - Handle edge cases: negative rooms, invalid baselines
- Small-room guard: if room_today < MinRiskDollar, return pause signal
- Error handling: safe defaults when unable to calculate rooms or count positions
- Performance: efficient position/order counting, avoid heavy loops
- Logging (decision log):
  - Room calculations: LogDecision("Equity","ROOMS", {"room_today":X,"room_overall":Y,"current_equity":Z,"baseline_today":W})
  - Budget gate checks: LogDecision("Equity","BUDGET_GATE", {"open_risk":X,"pending_risk":Y,"next_worst_case":Z,"room_available":W,"approved":true/false})
  - Position cap violations: LogDecision("Equity","CAP_VIOLATION", {"type":"total/symbol/pending","current":X,"limit":Y})
  - **[New]** When floors trigger or sessions are disabled (One-and-Done/NY gate), log LogDecision("Equity","SESSION_GOV", {"reason":"one_and_done/ny_gate/floor","value":...}).

Hard constraints:
- Non-trading (no order placement).
- Keep compile green after each small change; fix errors before proceeding.
- Do not modify files outside this scope.
- Use exact formulas from finalspec.md.
- Query real MT5 positions/orders for accurate counts.

Acceptance:
- EA compiles in MetaEditor.
- Room calculations produce reasonable values based on current equity and baselines.
- Budget gate correctly prevents trades that would exceed 90% of available room.
- Position/order caps are enforced before any theoretical order placement.
- Logs show complete room calculations and budget gate decisions.
- **[Updated]** Session governance helpers and floor flags are available to other modules and emit SESSION_GOV logs when triggered.

After implementation:
- STOP and wait for my compile/run feedback (I'll paste exact errors/warnings if any).


TASK 6 (M2): Order Plan Generation & Allocator Integration – logging-only

Context (read first):
- finalspec.md (locked spec; do not change decisions)
- m2.md (M2 step-by-step plan; this task is §7 Allocator Integration)
- codex.md (compile-first loop and guardrails)
- Branch: feat/m2-bwisc
- Entry point: MQL5/Experts/FundingPips/RPEA.mq5

Scope (files to edit only):
- MQL5/Include/RPEA/allocator.mqh (implement OrderPlan generation)
- (optional minimal logs) MQL5/Include/RPEA/scheduler.mqh (log order plans only; no logic changes)

Requirements:
- Enhance OrderPlan Structure (if needed):
  - Ensure struct has: valid, symbol, order_type, volume, price, sl, tp, comment, magic
  - Add any missing fields required for complete order specification
- Allocator_BuildOrderPlan() Complete Implementation:
  - Input: AppContext, strategy choice, symbol, slPoints, tpPoints, confidence
  - Signal integration: Take BWISC setup parameters (BC/MSC type, entry direction)
  - Risk sizing: Apply ATR-based volume calculation from risk.mqh
  - Price calculation: Determine entry price (market vs pending based on setup type)
  - SL/TP setting: Apply ATR multiples and R targets (RtargetBC=2.2, RtargetMSC=2.0)
  - Validation: Ensure plan passes all gates (budget, caps, margin) from equity_guardian.mqh
  - Magic number: Generate from MagicBase + symbol_index or similar deterministic method
  - Comment: Include setup type, bias value, timestamp for audit trail
- Integration Flow:
  - Call BWISC signal engine → get setup parameters
  - Call risk sizing → get volume
  - Call equity guardian → validate against caps/budget
  - Generate complete OrderPlan with all fields populated
- Error handling: Return invalid OrderPlan on any validation failure
- Setup-specific logic:
  - BC setup: pending stop order beyond OR extreme with EntryBufferPoints
  - MSC setup: limit order toward MA20_H1 
  - Direction: follow bias sign for BC, opposite for MSC
- Performance: efficient plan generation, minimal redundant calculations
- Logging (decision log):
  - For each plan generation: LogDecision("Allocator","ORDER_PLAN", {"symbol":...,"setup_type":"BC/MSC","entry_price":X,"volume":Y,"sl":Z,"tp":W,"valid":true/false,"rejection_reason":"..."})
  - Include all plan details for audit trail

Hard constraints:
- Non-trading (NO OrderSend calls - this is plan generation only).
- Keep compile green after each small change; fix errors before proceeding.
- Do not modify files outside this scope.
- Plans must pass all validation gates before being marked valid.
- Use exact R targets from finalspec.md (BC=2.2R, MSC=2.0R).

Acceptance:
- EA compiles in MetaEditor.
- OrderPlan generation produces complete, valid plans for BWISC setups.
- Plans correctly reflect setup type (BC pending stops, MSC limits).
- All validation gates are checked (budget, caps, margin).
- SL/TP distances match R target specifications.
- Logs show complete order plan details and validation results.

After implementation:
- STOP and wait for my compile/run feedback (I'll paste exact errors/warnings if any).

---

TASK SEQUENCE NOTES:
- Tasks 3-6 should be completed in order as each builds on the previous
- Task 3 (BWISC) provides setup parameters for Task 6 (Allocator)
- Task 4 (Risk) provides volume calculations for Task 6 (Allocator)  
- Task 5 (Equity) provides validation gates for Task 6 (Allocator)
- After Task 6, M2 milestone will be complete with full signal-to-plan pipeline
- All tasks remain logging-only; no actual order placement until M3

DEFINITION OF DONE FOR M2:
- All 6 tasks completed and compiling cleanly
- Complete signal flow: Indicators → Sessions → BWISC → Risk → Equity → Allocator
- Comprehensive logging of all calculations and decisions
- No order placement (logging-only validation)
- Ready for M3 Order Engine implementation
