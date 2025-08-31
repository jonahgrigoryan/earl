## PRD: FundingPips 10K RapidPass EA (RPEA) for MT5

### Objective
- Pass FundingPips 1-step $10,000 challenge by reaching +10% profit with zero drawdown-cap violations and at least 3 distinct trading days, ideally within 3–5 trading days.
- Utilize hybrid ensemble architecture combining BWISC (primary) and MR (EMRT/RL) strategies for enhanced adaptability across market regimes.

### Success Metrics (Acceptance)
- Primary: Net P/L ≥ +$1,000 with 0 violations of daily and overall drawdown caps; trade days ≥ 3.
- Operational: No entries during blocked news windows; CPU < 2% on VPS; complete CSV audit logs.
- Backtesting/forward demo shows robust performance across recent months with low rule-violation risk.
- Ensemble produces ≥1 qualified setup/day (median) in forward demo; SLO targets met (58-62% MR hit-rate, median hold ≤2.5h, efficiency ≥0.8).

### Scope
- Platform: MT5 (hedging or netting).
- Instruments: Multi-symbol (e.g., EURUSD, XAUUSD) with optional XAUEUR synthetic support (proxy default, replication optional).
- Ensemble trading system with dual signal engines: BWISC (Burst-Weighted Imbalance) and MR (Mean Reversion with EMRT/RL).

### Users & Stakeholders
- Trader/Owner (configure and run EA; review results/logs).
- QA/Reviewer (verify compliance with FundingPips rules and auditability).
- Developer (maintain EA code and utilities).

### Assumptions & Constraints
- Daily cap anchored to server midnight based on baseline_today = max(balance_at_server_midnight, equity_at_server_midnight); map to CEST only for reporting if needed.
- Server-to-CEST offset must be configured (DST handling via input; manual update acceptable).
- News buffer varies by account type: Master accounts ±300s (5min before/after); Evaluation accounts use internal buffer for safety.
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
  - Account-type specific restrictions:
    - **Evaluation (Student) accounts**: No provider news restrictions; apply internal buffer `NewsBufferS` for safety.
    - **Master (funded) accounts**: Enforce high-impact news lock T−300s to T+300s (5min before/after). Profits from trades opened/closed inside this window won't count unless opened ≥5h prior.
  - Block entries from T−`NewsBufferS` to T+`NewsBufferS` for affected symbols/legs.
  - Protective exits (SL/TP/kill-switch/margin) always allowed.
  - Discretionary closes obey `MinHoldSeconds` unless kill-switch/margin requires immediate exit.
  - News-window behavior in [T−NewsBufferS, T+NewsBufferS]:
    - Blocked: no new orders, no PositionModify/OrderModify (incl. trailing, SL/TP moves, partial closes), no deletes except risk-reducing.
    - Queued: queue trailing or SL/TP optimizations; apply after T+NewsBufferS if still valid and not in a subsequent news window; drop stale items after `QueuedActionTTLMin` minutes.
    - Allowed exceptions: protective exits; broker SL/TP (log NEWS_FORCED_EXIT); OCO sibling cancel to reduce risk (log NEWS_RISK_REDUCE); replication pair-protect close (log NEWS_PAIR_PROTECT).

- **Ensemble Strategy Logic**
  - **Primary Strategy**: BWISC remains default with session-based bias calculations and BC/MSC setups.
  - **Secondary Strategy**: MR (Mean Reversion) engine using EMRT formation and RL trading policy.
  - **Meta-Policy Controller**: Routes between BWISC and MR based on confidence tie-breakers and market conditions.
    - Confidence tie-breaker: If BWISC_conf < 0.70 AND MR_conf > 0.80 AND efficiency(MR) ≥ efficiency(BWISC), choose MR.
    - Conditional replacement: Replace BWISC when ORE < p40, ATR_D1 < p50, EMRT ≤ H*, session age <2h, no overlaps, no high-impact news ±15m.
    - Hysteresis: Once switched to MR, stay until session end to prevent strategy thrashing.
  - **Risk Boundaries**: MR engine defaults to 0.8–1.0% risk per trade (below BWISC's 1.5%); skip MR if symbol overlap with active BWISC position.

- **Adaptive & Learning Enhancements**
  - **Market Regime Detection**: Classify each symbol/session into trend/range/volatile/illiquid using ATR/σ bands, ADX, Hurst/ACF decay, OR Energy, and rolling spread percentiles. Adapt `Rtarget`, `SLmult`, `EntryBufferPoints`, trailing aggressiveness, and MR enable/disable by regime.
  - **Contextual Bandit Meta-Policy**: Choose BWISC vs MR vs Skip using a bandit (Thompson/LinUCB) based on context (regime vector, ORE/SDR, EMRT rank, recent efficiency, spread/slippage quantiles, news proximity). Exploration off in live; persist posterior/weights.
  - **Adaptive Risk Allocator**: Scale risk by regime and predicted efficiency while honoring daily/overall rooms and minimum equity floor buffers. Planner limits to top 1–2 opportunities expected to respect floor after worst-case.
  - **Liquidity Intelligence**: Maintain rolling spread and slippage quantiles per symbol/session; gate entries above p75–p90; auto-pause symbols with repeated adverse slippage; resume on normalization.
  - **Anomaly/Shock Detector**: EWMA z‑scores on returns, spread spikes, and tick gap frequency; 5–6σ triggers widen buffers, cancel pendings, or flatten. Detect calendar/API drift; auto-switch to CSV fallback and widen internal buffers during outages.
  - **Post-news Re-engagement**: After T+`NewsBufferS`, require stabilization (e.g., 3 bars with spread ≤ p60 and realized σ ≤ p70) before re‑enabling entries.
  - **Online Learning & Calibration**: MR optional online Q‑table updates with capped step and decay; freeze on SLO breach. BWISC weekly percentile-based recalibration of Bias/SDR cuts; persist to `calibration.json` and load at runtime. Persist bandit posterior.
  - **Symbol/Day Selector**: Choose a single best symbol per session/day via bandit expected efficiency; avoid correlated simultaneous exposure.
  - **Self-healing Order Intent Journal**: Persist intents for pendings and queued trailing/SL‑TP updates; reconcile idempotently on restart before any order actions.

- **MR (EMRT/RL) Engine**
  - **EMRT Formation**: Model-free metric quantifying duration for spreads to revert from local extremes to sample mean.
    - Rolling 60–90 trading days lookback; refresh weekly.
    - Grid search β ∈ [EMRT_BetaGridMin, EMRT_BetaGridMax] to minimize EMRT with variance cap.
    - Apply to FX spread universe including synthetic XAUEUR via synchronized M1 bars.
  - **RL Trading Policy**: Q-learning with 256-state space (l=4 periods, k=3% thresholds).
    - Reward function: r_{t+1} = A_t·(θ − Y_t) − c·|A_t| with barrier penalties for floors and +10% target.
    - Epsilon-greedy action selection: exploration during training (ε=0.1), exploitation during live trading (ε=0).
    - Pre-training: Use simulated OU processes and synthetic spread scenarios to build robust Q-table.
  - **Time-stops**: 60–90 minutes default; integrates with existing news compliance and session governance.

- XAUEUR Synthetic Support
  - **Goal**: Compute signals on XAUEUR = XAUUSD / EURUSD and execute via proxy or replication.
  - **Proxy (default)**: Execute only XAUUSD, size using synthetic SL distance mapped via current EURUSD rate.
  - **Replication (optional)**: Two legs to approximate XAUEUR delta:
    - Long XAUEUR ≈ Long XAUUSD + Short EURUSD; Short XAUEUR ≈ Short XAUUSD + Long EURUSD
    - Delta-based sizing: Choose K (USD P&L per 1.0 XAUEUR unit) from `risk_money = K × |SL_synth|`
    - Volume calculations: `V_xau = K / (ContractXAU × E)`; `V_eur = K × (P/E²) / ContractFX`
    - ContractXAU=100 oz/lot, ContractFX=100,000
    - Count both legs toward drawdown/margin room; validate worst-case combined loss at SL
  - **Synthetic data**: Build on-the-fly synthetic candles from synchronized M1 OHLC; forward-fill short gaps for ATR/MA/RSI calculations.
  - **News compliance**: Block entries if either leg (USD or EUR) has high-impact event within the news buffer window.

- Order Engine & Reliability
  - OCO pendings and immediate sibling cancel on fill; partial fill handling.
  - Market fallbacks with `MaxSlippagePoints`. Retries/backoff: default 3 attempts, 300 ms; fail fast on REJECT/NO_MONEY/TRADE_DISABLED; rollback first leg if second leg fails in replication.

- Equity Guardian & Persistence
  - Persist: `initial_baseline`, `gDaysTraded`, `last_counted_server_date`, mode flags (trading enabled, micro-mode), day peak equity.
  - Restart-safe: restore state and prevent double-counting of trade days.
  - Trading-day counting: A trade day counts on the first `DEAL_ENTRY_IN` between platform/server-day midnights.
  - Learning artifacts & stats: persist `calibration/calibration.json`, `bandit/posterior.json`, `liquidity/spread_slippage_stats.json`, `qtable/mr_qtable.bin`, and `state/intents.json`.

- Logging & Audit
  - CSV audit rows for every decision: timestamp, account, symbol, baseline_today, room_today, room_overall, existing_risk, planned_risk, action, reason codes (incl. news, governance, floors, OCO), signal components (bias parts), session, and results.
  - Telemetry additions: regime label, liquidity/anomaly flags, context vector, bandit choice and posterior snapshot, adaptive risk multiplier, and post-news stabilization checks.

### Non-Functional Requirements
- Performance: CPU < 2% on typical VPS; memory stable.
- Resilience: idempotent order reconciliation on init; clean handling of market closure and broker errors.
- Security/Privacy: logs exclude secrets; minimal PII.

### Inputs (Configuration)
- Risk & governance: `DailyLossCapPct` (4.0), `OverallLossCapPct` (6.0), `MinTradeDaysRequired` (3), `TradingEnabledDefault` (true), `MinRiskDollar` ($10), `OneAndDoneR` (1.5), `NYGatePctOfDailyCap` (0.50).
- Sessions & micro-mode: `UseLondonOnly` (false), `StartHourLO` (7), `StartHourNY` (12), `ORMinutes` (60), `CutoffHour` (16), `RiskPct` (1.5), `MicroRiskPct` (0.10), `MicroTimeStopMin` (45), `GivebackCapDayPct` (0.50).
  - **Micro-Mode details**: Triggered when equity ≥ +10% vs initial baseline; enables small-risk trades (0.05-0.20% per trade, default 0.10%) with one trade only per remaining day until MinTradeDaysRequired met; includes time-stop (30-60min default 45min) and giveback cap (0.25-0.50% peak-to-current drawdown, default 0.50%).
- Compliance: `NewsBufferS` (300), `MaxSpreadPoints` (40), `MaxSlippagePoints` (10), `MinHoldSeconds` (120), `QueuedActionTTLMin` (5).
- Timezone: `ServerToCEST_OffsetMinutes` (0; update on DST as needed).
- Symbols & leverage: `InpSymbols` ("EURUSD;XAUUSD"), `UseXAUEURProxy` (true), `LeverageOverrideFX` (50), `LeverageOverrideMetals` (20).
- Targets & mechanics: `RtargetBC` (2.2), `RtargetMSC` (2.0), `SLmult` (1.0), `TrailMult` (0.8), `EntryBufferPoints` (3), `MinStopPoints` (1), `MagicBase` (990200).
- Position/order caps: `MaxOpenPositionsTotal` (2), `MaxOpenPerSymbol` (1), `MaxPendingsPerSymbol` (2).

**MR/Ensemble Inputs**
- Ensemble control: `BWISC_ConfCut` (0.70), `MR_ConfCut` (0.80), `EMRT_FastThresholdPct` (40), `CorrelationFallbackRho` (0.50).
- MR parameters: `MR_RiskPct_Default` (0.90), `MR_TimeStopMin` (60), `MR_TimeStopMax` (90), `MR_LongOnly` (false).
- EMRT formation: `EMRT_ExtremeThresholdMult` (2.0), `EMRT_VarCapMult` (2.5), `EMRT_BetaGridMin/Max` (-2.0/+2.0).
- Q-Learning: `QL_LearningRate` (0.10), `QL_DiscountFactor` (0.99), `QL_EpsilonTrain` (0.10), `QL_TrainingEpisodes` (10000), `QL_SimulationPaths` (1000).

### Flows (High-Level)
- Scheduler (OnTimer 30–60s): check rooms and news; evaluate sessions; compute stats; meta-policy routing between BWISC/MR; signal decide; risk/lot sizing; place OCO/market; apply governance; queue news-window modifications; trailing; cutoff micro-mode.
- Trade transactions: OCO cancellation on entry; governance on close (R calculation from persisted entry/sl/type values, One-and-Done/NY gate updates); mark first deal per server day; telemetry updates for SLO monitoring.

### Milestones (Delivery)
- M1: Skeleton, inputs, state structs, scheduler, logging; indicator handles; news fallback parser; persistence scaffolding.
- M2: Signal engine (BWISC) and stats; risk sizing; margin guard; position caps; budget gate.
- M3: Order engine (OCO, slippage, trailing, partial fill); synthetic manager; two-leg atomicity.
- M4: Compliance polish (calendar integration; CEST day tracking; kill-switch floors; disable flags; persistence hardening).
- M5: Strategy Tester artifacts (.set for $10k; optimization ranges; walk-forward; CSV audit/reporting).
- M6: Hardening (market closure, rejects; parameter validation; restart/idempotency; perf profiling; code review).
- M7: Ensemble integration (EMRT formation job; SignalMR module; Meta-Policy chooser; allocator updates; telemetry pipeline; RL agent pre-training; Q-table initialization; forward-demo plan).

### Risks & Mitigations
- News compliance ambiguity → Explicit news-window policy with blocked/queued/allowed actions and TTL.
- DST/server time misalignment → Clear offset input; document DST updates.
- Overfitting signals → Use bounded ranges; walk-forward validation.
- Replication atomicity → Retry/rollback protocol; default to proxy mode when margin or budget insufficient.
- Strategy thrashing → Hysteresis prevents frequent ensemble switching; absolute cap of 2 entries per session.
- MR model drift → Auto risk reduction (25%) on SLO breaches; pre-trained Q-table with diverse scenarios.
- Ensemble complexity → Feature flags for staged rollout; shadow mode testing; comprehensive QA checklist.

### Out of Scope (MVP)
- Grid/martingale/HFT/latency arbitrage.
- Auto-DST computation (manual offset acceptable for MVP).


