# Profitability Root-Cause Research Plan for RPEA

## Exact Baseline (source of truth)

Treat the following as **pinned** for v1 research. Stale merge or handoff markdown elsewhere in the repo is **not** a source of truth for this plan.

| Item | Value |
|------|--------|
| **Commit** | `master@d0e5558` |
| **Champion path** | `arch_mr_deterministic` -> `threshold_003` -> `stage3__baseline_artifacts__ql_enabled` |
| **Primary truth set** | Holdout eval summary: `.tmp/fundingpips_official_validation/master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c/collected/fundingpips_eval_summary.json` |
| **Primary stress artifact** | `.tmp/fundingpips_official_validation/master_phase5_holdout_rule3_20251101_20260228_stress_summary.json` |
| **Secondary corroboration** | **Contiguous public-rule3** official validation only: eval summary at `.tmp/fundingpips_official_validation/master_phase5_champion_contiguous_public_rule3_20250603_20251031__e2ac77d835c79480/collected/fundingpips_eval_summary.json` (and sibling artifacts from that run as needed) |

**Phase 5 walk-forward report-window artifacts** are **not** part of this baseline table. They are **rerun-validation inputs only** (see **Narrow validation search**), not corroboration for Phase A attribution.

Use **public-rule3** official validation for both holdout and contiguous runs; older runs (e.g. alternate daily-cap variants) are out of scope unless explicitly promoted.

## Summary

Review findings are treated as **verified**. Direction: hybrid, attribution-first research, not another blind HPO sweep. The prior plan overpromised trade reconstruction from collected logs alone, left candidate grain ambiguous, and was not specific enough about the merged baseline.

**Secondary corroboration** for the research baseline is **only** the **contiguous public-rule3** official validation artifact set. **Phase 5 report windows** stay valuable as **later rerun-validation** inputs after attribution surfaces concrete levers; they are **not** Phase A corroboration.

**v1 is artifact-first Phase A** pinned to the baseline above: **holdout** plus **contiguous public-rule3** official validation artifacts, their decision/event logs, eval summary/daily files, run manifests, and MT5 report **Orders** / **Deals** tables (champion path unchanged; see **Exact Baseline**).

**Phase B is explicit and deferred:** add one minimal close-side telemetry row and any missing runner log collection **only if** Phase A documents a specific impossible join or missing field. Phase B must use a **new instrumented rerun** and must **not** relabel that rerun as the untouched holdout.

Why this matters: the current winner is already breach-safe, but the untouched holdout is weak (`+0.7861%`) and turns slightly negative under moderate friction. Decision logs show heavy pre-trade opportunity loss (`Liquidity.GATED`, `MetaPolicy -> SKIP_NO_SETUP`, etc.). The clearest indicator of what to change is a **lost-expectancy waterfall** that separates:

1. opportunity lost before orders are placed,
2. expectancy lost after entries are placed,
3. fragility to spread/slippage/delay/commission.

The deliverable is a ranked change list with evidence, expected upside, and validation rules. Only after that do we run a narrow search on confirmed weak components.

## Phases

### Phase A (v1 default)

- Analyze only: **post-Phase-5 holdout** official validation artifacts, **contiguous public-rule3** official validation artifacts (secondary corroboration), and for each run the decision/event logs, eval summary/daily files, run manifests, and MT5 report `Orders` / `Deals` tables.
- Do **not** use Phase 5 report-window artifacts as Phase A inputs or corroboration; reserve them for the **later validation search** matrix.
- Build datasets per the contracts below; do not assume logs alone can reconstruct full trade truth without report deals.

### Phase B (conditional)

- Trigger only when Phase A records a **concrete** impossibility (e.g. missing report/deal join coverage, ambiguous multi-close trade pairing).
- Add minimal instrumentation; rerun is explicitly **not** the untouched holdout.
- **Block Phase B** unless the implementation documents that concrete gap; do not expand instrumentation speculatively.

## Key Changes

### 1. Freeze a single research baseline

- Use the merged Phase 5 champion path and pinned commit in **Exact Baseline** as the only baseline for diagnosis.
- Use the **holdout** official validation artifact set as the **primary** truth set.
- Use the **contiguous public-rule3** official validation artifact set as the **secondary corroboration** for attribution (not the deciding dataset).
- Use **Phase 5 report-window artifacts only in the later validation stage** (narrow search / candidate reruns), **not** as corroboration for Phase A attribution.
- Do not start with a broad retune or architecture branch expansion.

### 2. Dataset and grain contracts

#### 2a. `research_candidates` (replaces vague "one row per opportunity")

- One row per lineage that reaches **`Allocator.ORDER_PLAN`** (plan-capable candidate only).
- Define **`candidate_id`** as: `decision_ts + symbol + strategy + setup_type + entry_price + sl + tp + comment` (normalized as implemented).
- Attach **`intent_id`** from `INTENT_ACCEPT`.
- Attach **`entry_ticket`** from `EXECUTE_ORDER_SUCCESS` / `PLACE_OK`.

#### 2b. `research_gate_intervals` (normalized dedupe contract)

- One row per **collapsed** repeated gate/skip interval, **not** one row per tick.
- **Separate normalized keys** (implementers must use these fields exactly; do not invent alternate dedupe rules):

| Source | Normalized interval key (concatenate / hash as implemented; order of fields fixed) |
|--------|----------------------------------------------------------------------------------------|
| **`Liquidity.GATED`** | `symbol` + `reason` |
| **`Scheduler.GATED`** | `symbol` + `news` + `spread_ok` + `in_session` + `in_or` + `anomaly_block` + `anomaly_action` |
| **`MetaPolicy.EVAL` with `choice=Skip`** | `symbol` + `choice` + `gating_reason` + `regime` + `news_window_state` |

- **Collapse** consecutive log rows that share the **same** normalized key for the same gate family into **one** interval (track interval `start_ts`, `end_ts`, and row count).
- **Start a new interval** when the normalized key **changes**, **or** when the symbol transitions into a **plan-capable lineage** (e.g. reaches `Allocator.ORDER_PLAN`), whichever ends the prior streak first.
- Use this table for gate frequency and time-in-state only, **not** for counterfactual trade replay.

#### 2c. `research_trades` (Phase-A-buildable)

**Inputs must explicitly include** MT5 report **`Orders`** / **`Deals`** parsing, not decision/event logs alone.

**Required v1 fields:** `candidate_id`, `intent_id`, `entry_ticket`, `symbol`, `strategy`, `entry_time`, `exit_time`, `entry_price`, `exit_price`, `volume`, `realized_pnl`, `hold_minutes`, `theoretical_r`, `realized_r`, `friction_r`, `exit_reason_class`, `exit_reason_exact`, `close_source`.

**Derivations:**

- Build **`theoretical_r`** from entry `sl` / `tp` (per locked policy).
- Build **`realized_r`** from realized PnL divided by **logged** worst-case risk.
- Build **`friction_r`** as `max(theoretical_r - realized_r, 0)`.

**Exit reasons:**

- Set **`exit_reason_exact`** only when explicitly observable (e.g. `MR_TIMESTOP` in decision logs, or `sl ...` in the MT5 report).
- Otherwise `exit_reason_exact=null` and `exit_reason_class=unknown` (do not guess).

### 3. Report / deal join rules (Phase A)

- Use report **`Deals`** rows as the **close-side truth** source in Phase A.
- Join entry rows to decision logs by **`entry_ticket == report order id`**; valid for the current baseline because the holdout report shows entry order IDs matching `EXECUTE_ORDER_SUCCESS` tickets.
- Pair each entry `in` row with the **next matching `out`** row for the same symbol as one trade.
- **Stop** the implementation if baseline artifacts violate: `MaxOpenPerSymbol=1`, no simultaneous same-symbol positions, or non-paired partial closes **as assumed by this pairing rule**. Escalate to Phase B instead of silently approximating.

### 4. Counterfactual scope in v1 (narrowed)

- Allow replay only for rows with a fully formed **`research_candidates`** row containing plan geometry and worst-case risk.
- Do **not** replay pure `SKIP_NO_SETUP`, session gates, or spread-only gates in v1; surface those via **`research_gate_intervals`** and aggregate opportunity-cost counts first.

### 5. Build pipeline (logs + reports)

- Parse existing decision/event logs collected by [fundingpips_mt5_runner.py](../../tools/fundingpips_mt5_runner.py).
- Produce normalized tables per contracts above plus **`research_daily`** (server-day rollup).

### 6. Three attribution studies (unchanged intent; Phase-A data first)

- **Gate opportunity-cost study**  
  Quantify opportunity lost by rejection path. For skipped/gated paths, prefer aggregates from **`research_gate_intervals`** in v1; defer rich counterfactual path replay to rows with full candidate geometry only.

- **Entry-quality study**  
  Segment executed trades by symbol, session, regime, confidence decile, EMRT/RL state, spread/slippage quantiles; identify edge vs dilution slices.

- **Exit-leakage study**  
  Compare realized R to theoretical R; attribute leakage using observable exit signals and report deals; avoid inventing exit labels not in logs/report.

### 7. Convert attribution into a ranked change list

- Score every proposed change on: expected holdout return delta, confidence, breach headroom, mild/moderate stress, implementation risk.
- Only promote the top 2-4 levers into rerun candidates.
- Likely lever classes if attribution confirms: spread/friction gating, session/OR timing, MR acceptance/thresholds, time-stop/exit stack, RL/threshold dependence.

### 8. Narrow validation search only on confirmed levers

- Small design matrix around top-ranked weak components.
- Keep architecture fixed unless attribution proves architecture is the problem; no new HPO or architecture expansion until attribution ranks concrete weak levers.
- **Rerun-validation matrix (unchanged):** validate every promoted candidate on **untouched holdout**, **Phase 5 report windows**, **mild stress**, and **moderate stress**.
- Reject improvements that are in-sample-only or buy return with unacceptable drawdown headroom.

## Interfaces and Outputs

- No public EA behavior change in Phase A.
- New research outputs:
  - `research_candidates.csv` or `.parquet` -- plan-capable candidate lineages only.
  - `research_gate_intervals.csv` or `.parquet` -- collapsed repeated gate/skip intervals.
  - `research_trades.csv` or `.parquet` -- executed trades from decision logs **plus** MT5 report deals.
  - `research_daily.csv` -- server-day rollup from eval daily plus aggregated trade/gate metrics.
  - `research_attribution_summary.json`
  - `research_change_rankings.md`
- **`research_attribution_summary.json`** and **`research_change_rankings.md`** must state whether each conclusion came from **Phase A** artifact analysis or **Phase B** instrumentation.
- Required decision report format for each recommended change: problem observed, evidence, exact parameter/module, expected delta, risk to pass reliability, validation rerun needed.

## Test Plan

- **Doc consistency:** Baseline and research sections treat **contiguous public-rule3** as the **only** secondary corroboration; **no** wording uses Phase 5 report windows as Phase A corroboration or baseline corroboration.
- **Validation matrix:** The doc still places **Phase 5 report windows** **only** in the **later** rerun-validation matrix (with untouched holdout and stress), not in Phase A.
- **Reconciliation:** Phase A must reconcile `research_trades` to **holdout** artifacts: exact trade count **107**, realized PnL within tight tolerance of **+$78.61**, daily totals matching the official daily CSV.
- **Candidate lineage:** On a known executed trade, validate the `2025-11-03 02:16:59` XAUUSD sequence: `MetaPolicy.EVAL` -> `Risk.SIZING` -> `Allocator.ORDER_PLAN` -> `INTENT_ACCEPT` -> `EXECUTE_ORDER_SUCCESS` -> `PLACE_OK`.
- **Gate dedupe:** Repeated `Liquidity.GATED`, `Scheduler.GATED`, and `MetaPolicy choice=Skip` bursts collapse per **section 2b** normalized keys so two independent implementers produce the **same** interval rows (one interval per unchanged key streak; new interval on key change or plan-capable lineage).
- **Exit reasons:** Phase A partial labels are intentional -- `MR_TIMESTOP` and report `sl ...` are exact/inferred; everything else stays `unknown` rather than guessed.
- **Phase B gate:** No Phase B unless implementation records a concrete Phase A impossibility (e.g. missing report/deal join, ambiguous multi-close pairing).
- Reproduce gating **interval** counts and aggregates consistent with raw logs (after dedupe contract).
- Counterfactual replay on fully formed **candidate** rows with current policy must reconcile to realized outcomes within tolerance where replay is in scope.
- No recommended change is accepted unless positive on untouched holdout and non-negative under moderate stress, without increasing breach frequency or materially worsening daily-loss headroom.

## Assumptions and Defaults

- Optimize for FundingPips pass reliability first, then higher return.
- Hybrid method: attribution first, narrow search second.
- The **official public-rule3 holdout** (pinned artifacts above) remains the **deciding dataset** for promotion decisions.
- The **contiguous public-rule3** official validation run is **corroboration for attribution**, not the deciding dataset.
- **Phase 5 report windows** remain valuable **only** as **later rerun-validation** inputs after attribution identifies concrete levers.
- **Success criterion:** a decision-ranked change list backed by **Phase A** evidence, with **no** untouched-holdout rerun unless Phase A proves a specific missing field or join.
- **Trade pairing** in v1 is safe only while baseline invariants hold; if they fail, stop and escalate to Phase B instead of approximating.
- Do not run a broad new HPO phase until the attribution report identifies specific weak components.
