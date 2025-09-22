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
- Setup Detection Logic:
  - BC (Breakout Continuation): |Bias| ≥ 0.6 → Stop beyond OR extreme, ATR SL, target 2.2R
  - MSC (Mean Reversion): |Bias| ∈ [0.35,0.6) AND SDR ≥ 0.35 → Limit toward MA20_H1, SL beyond dislocation, target 1.8-2.2R
- RSI Guard: Check RSI_H1 overextension (default ranges [35,70]); strong dislocation can override (SDR ≥ 0.8)
- SignalsBWISC_Propose() complete implementation:
  - Input: AppContext, symbol
  - Output: hasSetup, setupType, slPoints, tpPoints, bias, confidence via reference parameters
  - Confidence = clamp(|Bias|, 0, 1)
  - Error handling: safe defaults on calculation failures
  - **NEW**: Stage allocator-facing context (expected_R, expected_hold, worst_case_risk) for Task 6 consumption
- Data dependencies: Use Indicators_GetSnapshot() for ATR/MA/RSI; Sessions_GetORSnapshot() for OR levels and session governance flags
- Session governance integration: Use snapshot.session_enabled; skip evaluation if session disabled
- Performance: efficient calculations, early returns for invalid data; target <100ms per symbol; no heavy loops
- Logging (decision log):
  - For each symbol evaluation: LogDecision("BWISC","EVAL", {"symbol":...,"btr":X,"sdr":Y,"ore":Z,"bias":W,"setup":"BC/MSC/None","confidence":C})
  - Include gating reasons (session_disabled, rsi_guard, insufficient_data, etc.)
  - **NEW**: Include "blocked_by" field with specific reason when session/news/room gates prevent proposal
- Prerequisites: Assumes Task 1 (indicators) and Task 2 (sessions) are complete for data availability

Implementation Pseudocode:

```
FUNCTION SignalsBWISC_Propose(ctx, symbol, OUT hasSetup, OUT setupType, OUT slPoints, OUT tpPoints, OUT bias, OUT confidence):
    // 1. Get data via existing getters (Task 1 & 2 prerequisites)
    indicator_snap = Indicators_GetSnapshot(symbol)
    // Choose active/enabled session: prefer London if active/enabled, else New York; if neither, exit
    snap_lo = Sessions_GetORSnapshot(ctx, symbol, "LO")
    snap_ny = Sessions_GetORSnapshot(ctx, symbol, "NY")
    session_label = ""
    if snap_lo.session_active && snap_lo.session_enabled then
        session_snap = snap_lo; session_label = "LO"
    else if snap_ny.session_active && snap_ny.session_enabled then
        session_snap = snap_ny; session_label = "NY"
    else
        hasSetup = false; setupType = "None"; bias = 0.0; confidence = 0.0
        LogDecision("BWISC", "EVAL", {"symbol":symbol, "blocked_by":"no_active_session"})
        RETURN

    // 2. Session governance check (from snapshot)
    IF !session_snap.session_enabled THEN
        hasSetup = false; setupType = "None"; bias = 0.0; confidence = 0.0
        LogDecision("BWISC", "EVAL", {"symbol":symbol, "blocked_by":"session_disabled", "session":session_label})
        RETURN

    // 3. Data validation
    IF !indicator_snap.has_atr OR !indicator_snap.has_ma OR !indicator_snap.has_ohlc OR !session_snap.has_or_values THEN
        hasSetup = false; setupType = "None"; bias = 0.0; confidence = 0.0
        LogDecision("BWISC", "EVAL", {"symbol":symbol, "blocked_by":"insufficient_data", "session":session_label,
                      "has_atr":indicator_snap.has_atr, "has_ma":indicator_snap.has_ma, "has_ohlc":indicator_snap.has_ohlc, "has_or":session_snap.has_or_values})
        RETURN

    // 4. Calculate core metrics (exact finalspec formulas)
    btr = MathAbs(indicator_snap.close_d1_prev - indicator_snap.open_d1_prev) / MathMax(indicator_snap.high_d1_prev - indicator_snap.low_d1_prev, _Point)
    sdr = MathAbs(session_snap.session_open_price - indicator_snap.ma20_h1) / indicator_snap.atr_d1
    ore = (session_snap.or_high - session_snap.or_low) / indicator_snap.atr_d1

    // 5. Calculate bias (exact weights from finalspec)
    c1_minus_o1 = indicator_snap.close_d1_prev - indicator_snap.open_d1_prev
    open_lo_minus_ma = session_snap.session_open_price - indicator_snap.ma20_h1
    bias = 0.45 * MathSign(c1_minus_o1) * btr + \
           0.35 * MathSign(open_lo_minus_ma) * MathMin(sdr, 1.0) + \
           0.20 * MathSign(c1_minus_o1) * MathMin(ore, 1.0)

    // 6. Setup detection (exact thresholds from finalspec)
    abs_bias = MathAbs(bias)
    setup_detected = false
    IF abs_bias >= 0.6 THEN
        setupType = "BC"
        setup_detected = true
    ELSE IF abs_bias >= 0.35 AND sdr >= 0.35 THEN
        setupType = "MSC"
        setup_detected = true
    END

    IF !setup_detected THEN
        hasSetup = false; setupType = "None"; confidence = 0.0
        LogDecision("BWISC", "EVAL", {"symbol":symbol, "session":session_label, "btr":btr, "sdr":sdr, "ore":ore, "bias":bias,
                      "setup":"None", "confidence":0.0, "reason":"bias_below_threshold"})
        RETURN

    // 7. RSI Guard (ranges [35,70], strong dislocation SDR >= 0.8 override)
    IF (indicator_snap.rsi_h1 < 35.0 OR indicator_snap.rsi_h1 > 70.0) AND sdr < 0.8 THEN
        hasSetup = false; setupType = "None"; confidence = 0.0
        LogDecision("BWISC", "EVAL", {"symbol":symbol, "session":session_label, "btr":btr, "sdr":sdr, "ore":ore, "bias":bias,
                      "setup":"None", "confidence":0.0, "blocked_by":"rsi_guard", "rsi":indicator_snap.rsi_h1})
        RETURN

    // 8. Calculate SL/TP distances and entry prices (ATR-based per finalspec)
    sl_atr_distance = indicator_snap.atr_d1 * SLmult  // ATR * SLmult for SL distance
    r_target = (setupType == "BC") ? RtargetBC : RtargetMSC  // 2.2R for BC, 2.0R for MSC
    tp_atr_distance = sl_atr_distance * r_target

    // Convert ATR distances to points and enforce MinStopPoints
    slPoints = (int)MathMax(sl_atr_distance / _Point, (double)MinStopPoints)
    tpPoints = (int)(slPoints * r_target)

    // Calculate entry price based on setup type (for allocator context)
    entry_price = 0.0
    IF setupType == "BC" THEN
        // Stop entry beyond OR extreme in bias direction
        direction = (bias > 0) ? 1 : -1  // Follow bias sign
        IF direction > 0 THEN
            entry_price = session_snap.or_high + (EntryBufferPoints * _Point)
        ELSE
            entry_price = session_snap.or_low - (EntryBufferPoints * _Point)
    ELSE // MSC
        // Limit entry toward MA20_H1 (opposite to dislocation)
        direction = (session_snap.session_open_price > indicator_snap.ma20_h1) ? -1 : 1  // Opposite to SDR sign
        IF direction > 0 THEN
            entry_price = indicator_snap.ma20_h1 + (EntryBufferPoints * _Point)
        ELSE
            entry_price = indicator_snap.ma20_h1 - (EntryBufferPoints * _Point)

    // 9. Prepare allocator-facing context (NEW: for Task 6 consumption)
    double expected_R = r_target * MathMin(abs_bias, 1.0)  // Heuristic prior per finalspec
    double expected_hold = MathMax((double)ORMinutes, 45.0)  // Max(ORMinutes, 45 min)
    double worst_case_risk = AccountInfoDouble(ACCOUNT_EQUITY) * (RiskPct / 100.0)  // Approx risk money at current risk pct (M2)

    // Store in global context for allocator (implementation detail)
    g_last_bwisc_context.expected_R = expected_R
    g_last_bwisc_context.expected_hold = expected_hold
    g_last_bwisc_context.worst_case_risk = worst_case_risk
    g_last_bwisc_context.entry_price = entry_price
    g_last_bwisc_context.direction = direction

    // 10. Set outputs
    hasSetup = true
    confidence = MathMin(abs_bias, 1.0)  // clamp(|Bias|, 0, 1) per finalspec

    // 11. Log complete evaluation with all metrics (comprehensive audit trail)
    LogDecision("BWISC", "EVAL", {
        "symbol": symbol,
        "session": session_label,
        "btr": btr,
        "sdr": sdr,
        "ore": ore,
        "bias": bias,
        "setup": setupType,
        "confidence": confidence,
        "rsi_h1": indicator_snap.rsi_h1,
        "direction": direction,
        "entry_price": entry_price,
        "sl_atr_distance": sl_atr_distance,
        "tp_atr_distance": tp_atr_distance,
        "sl_points": slPoints,
        "tp_points": tpPoints,
        "expected_R": expected_R,
        "expected_hold": expected_hold,
        "worst_case_risk": worst_case_risk,
        "atr_d1": indicator_snap.atr_d1,
        "ma20_h1": indicator_snap.ma20_h1,
        "or_high": session_snap.or_high,
        "or_low": session_snap.or_low
    })
```



Hard constraints:
- Non-trading (no order placement).
- Keep compile green after each small change; fix errors before proceeding.
- Do not modify files outside this scope.
- Use exact formulas from finalspec.md - no approximations.

Acceptance:
- EA compiles in MetaEditor.
- On live/tester run, logs show BWISC evaluations with BTR/SDR/ORE/Bias calculations and setup detection; no runtime errors.
- Setup detection triggers correctly for BC (|Bias| ≥ 0.6) and MSC (|Bias| ∈ [0.35,0.6) AND SDR ≥ 0.35).
- **[Updated]** Session governance properly blocks evaluations when sessions are disabled (One-and-Done, NY gate, etc.) with appropriate SESSION_BLOCKED logs.
- **[Updated]** RSI guard applies default ranges [35,70] with SDR ≥ 0.8 override for strong dislocations.
- **[Updated]** Entry prices calculated correctly: BC stops beyond OR extreme in bias direction; MSC limits toward MA20_H1 opposite to dislocation.
- **[Updated]** Direction determination: BC follows bias sign; MSC opposes SDR sign.
- **[Updated]** Allocator context (expected_R, expected_hold, worst_case_risk) is staged for Task 6 consumption.
- **[Updated]** Comprehensive logging includes all metrics, gating reasons, and "blocked_by" fields when applicable.

Implementation Notes:
- Add global BWISC context structure for allocator consumption:
  ```cpp
  struct BWISC_Context {
      double expected_R;
      double expected_hold;
      double worst_case_risk;
      double entry_price;
      int direction;  // 1 for long, -1 for short
  };
  BWISC_Context g_last_bwisc_context;
  ```
- Ensure Sessions_CurrentState() returns session_enabled flag and block_reason for proper governance integration.
- Performance: All calculations should complete in <100ms per symbol with early returns on invalid data.

After implementation:
- STOP and wait for my compile/run feedback (I'll paste exact errors/warnings if any).