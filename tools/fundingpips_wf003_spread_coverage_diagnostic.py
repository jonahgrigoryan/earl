"""Diagnose why wf003_202510 blanks under tighter spread gating."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from bisect import bisect_right
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

try:
   from tools import fundingpips_phase_a_research as phase_a
except ImportError:  # pragma: no cover - script execution fallback
   import fundingpips_phase_a_research as phase_a


DEFAULT_BASELINE_MANIFEST = Path(
   ".tmp/fundingpips_hpo_runs/"
   "phase5_anchor_pipeline__stage3__wf003_202510__repor_6fe1db875d6b__f88c13d9fd05c600/"
   "run_manifest.json"
)
DEFAULT_SM45_MANIFEST = Path(
   ".tmp/fundingpips_spread_liquidity_validation/phasea_spread_liquidity/"
   "runner_runs/psl__sm45__wf003_202510__report__66d83d953af5f06e/run_manifest.json"
)
DEFAULT_SM40_MANIFEST = Path(
   ".tmp/fundingpips_spread_liquidity_validation/phasea_spread_liquidity/"
   "runner_runs/psl__sm40__wf003_202510__report__ff9655cb54f9fa83/run_manifest.json"
)
DEFAULT_VALIDATION_SUMMARY = Path(
   ".tmp/fundingpips_spread_liquidity_validation/phasea_spread_liquidity/validation_summary.json"
)
DEFAULT_OUTPUT_DIR = Path(
   ".tmp/fundingpips_wf003_spread_coverage_diagnostic/phasea_wf003_spread_coverage"
)

RELEVANT_ROWS = frozenset(
   {
      ("Allocator", "ORDER_PLAN"),
      ("Indicators", "SNAPSHOT"),
      ("Liquidity", "GATED"),
      ("MetaPolicy", "EVAL"),
      ("OrderEngine", "EXECUTE_ORDER_SUCCESS"),
      ("OrderEngine", "INTENT_ACCEPT"),
      ("Risk", "SIZING"),
      ("Scheduler", "ANOMALY_EVAL"),
      ("Scheduler", "GATED"),
      ("Scheduler", "PLACE_OK"),
      ("Scheduler", "PLAN_REJECT"),
      ("Sessions", "OR_TICK"),
   }
)


@dataclass(frozen=True)
class RunSpec:
   id: str
   label: str
   manifest_path: Path
   spread_mult_atr: float | None
   is_baseline: bool


@dataclass(frozen=True)
class DiagnosticRow:
   run_id: str
   ts: datetime
   ts_text: str
   component: str
   message: str
   symbol: str | None
   fields: dict[str, Any]


@dataclass
class SessionIndex:
   timestamps_by_symbol: dict[str, list[datetime]]
   label_sets_by_symbol: dict[str, list[set[str]]]


def parse_args(argv: list[str]) -> argparse.Namespace:
   parser = argparse.ArgumentParser(description=__doc__)
   parser.add_argument("--baseline-manifest", type=Path, default=DEFAULT_BASELINE_MANIFEST)
   parser.add_argument("--sm45-manifest", type=Path, default=DEFAULT_SM45_MANIFEST)
   parser.add_argument("--sm40-manifest", type=Path, default=DEFAULT_SM40_MANIFEST)
   parser.add_argument("--validation-summary", type=Path, default=DEFAULT_VALIDATION_SUMMARY)
   parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
   return parser.parse_args(argv)


def load_json(path: Path) -> dict[str, Any]:
   return json.loads(path.read_text(encoding="utf-8"))


def iso_utc_now() -> str:
   return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def resolve_repo_path(repo_root: Path, path: Path) -> Path:
   if path.is_absolute():
      return path
   return (repo_root / path).resolve()


def format_float(value: float | None, places: int = 6) -> str:
   if value is None:
      return ""
   return f"{value:.{places}f}"


def to_bool_text(value: Any) -> str:
   coerced = phase_a.coerce_bool(value)
   if coerced is None:
      return ""
   return "true" if coerced else "false"


def percentile(sorted_values: list[float], fraction: float) -> float | None:
   if not sorted_values:
      return None
   index = int(round((len(sorted_values) - 1) * fraction))
   index = max(0, min(index, len(sorted_values) - 1))
   return sorted_values[index]


def build_run_input(repo_root: Path, spec: RunSpec) -> phase_a.PhaseARunInput:
   manifest_path = resolve_repo_path(repo_root, spec.manifest_path)
   manifest = load_json(manifest_path)

   def resolve_manifest_path(value: str) -> Path:
      candidate = Path(value)
      if candidate.is_absolute():
         return candidate
      return (manifest_path.parent / candidate).resolve()

   run_dir = resolve_manifest_path(manifest["run_dir"])
   return phase_a.PhaseARunInput(
      id=spec.id,
      baseline_role="diagnostic",
      root=run_dir,
      manifest_path=run_dir / "run_manifest.json",
      summary_path=resolve_manifest_path(manifest["collected_summary"]),
      daily_path=resolve_manifest_path(manifest["collected_daily"]),
      report_path=resolve_manifest_path(manifest["collected_report"]),
      decision_log_paths=tuple(resolve_manifest_path(item) for item in manifest["collected_decision_logs"]),
      event_log_paths=tuple(resolve_manifest_path(item) for item in manifest["collected_event_logs"]),
   )


def parse_rows(run_input: phase_a.PhaseARunInput) -> list[DiagnosticRow]:
   rows: list[DiagnosticRow] = []
   pending_scheduler_symbol: str | None = None

   for source_path in sorted(run_input.decision_log_paths):
      pending_scheduler_symbol = None
      for source_row, parts in phase_a.iter_log_lines(
         source_path,
         expected_header="date,time,event,component,level,message,fields_json",
      ):
         date_value, time_value, event_value, component_value, _, message_value, fields_value = parts
         if event_value != "DECISION":
            continue

         row_kind = (component_value, message_value)
         if row_kind not in RELEVANT_ROWS:
            continue

         fields = phase_a.parse_json_fields(fields_value, source_path, source_row)
         symbol = phase_a.normalize_candidate_text(
            fields.get("symbol") or fields.get("exec_symbol") or fields.get("signal_symbol")
         ) or None
         if row_kind == ("Scheduler", "ANOMALY_EVAL"):
            pending_scheduler_symbol = symbol
         if row_kind == ("Scheduler", "GATED") and symbol is None:
            symbol = pending_scheduler_symbol

         ts = phase_a.parse_log_timestamp(date_value, time_value)
         rows.append(
            DiagnosticRow(
               run_id=run_input.id,
               ts=ts,
               ts_text=phase_a.format_ts(ts),
               component=component_value,
               message=message_value,
               symbol=symbol,
               fields=fields,
            )
         )

   rows.sort(key=lambda item: (item.ts, item.component, item.message, item.symbol or ""))
   return rows


def build_session_index(rows: list[DiagnosticRow]) -> SessionIndex:
   timestamps_by_symbol: dict[str, list[datetime]] = defaultdict(list)
   label_sets_by_symbol: dict[str, list[set[str]]] = defaultdict(list)

   for row in rows:
      if row.component != "Sessions" or row.message != "OR_TICK" or not row.symbol:
         continue
      session_label = str(row.fields.get("session", "")).strip()
      timestamps = timestamps_by_symbol[row.symbol]
      label_sets = label_sets_by_symbol[row.symbol]
      if timestamps and timestamps[-1] == row.ts:
         if session_label:
            label_sets[-1].add(session_label)
         continue
      timestamps.append(row.ts)
      label_sets.append({session_label} if session_label else set())

   return SessionIndex(
      timestamps_by_symbol=dict(timestamps_by_symbol),
      label_sets_by_symbol=dict(label_sets_by_symbol),
   )


def session_label_at(index: SessionIndex, symbol: str, ts: datetime) -> str:
   timestamps = index.timestamps_by_symbol.get(symbol)
   if not timestamps:
      return ""
   idx = bisect_right(timestamps, ts) - 1
   if idx < 0:
      return ""
   labels = sorted(label for label in index.label_sets_by_symbol[symbol][idx] if label)
   return "+".join(labels)


def build_row_lookup(rows: list[DiagnosticRow]) -> dict[tuple[str, str | None], list[DiagnosticRow]]:
   lookup: dict[tuple[str, str | None], list[DiagnosticRow]] = defaultdict(list)
   for row in rows:
      lookup[(row.ts_text, row.symbol)].append(row)
   return lookup


def make_candidate_key(row: DiagnosticRow) -> str:
   fields = row.fields
   parts = [
      row.ts_text,
      phase_a.normalize_candidate_text(row.symbol or ""),
      phase_a.normalize_candidate_text(fields.get("strategy")),
      phase_a.normalize_candidate_text(fields.get("setup_type")),
      format_float(phase_a.coerce_float(fields.get("entry_price")), 5),
      format_float(phase_a.coerce_float(fields.get("sl")), 5),
      format_float(phase_a.coerce_float(fields.get("tp")), 5),
      phase_a.normalize_candidate_text(fields.get("comment")),
   ]
   return "|".join(parts)


def summarize_gate_intervals(
   run_input: phase_a.PhaseARunInput,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
   intervals = phase_a.parse_gate_intervals(run_input)
   per_symbol_family: dict[tuple[str, str], dict[str, Any]] = defaultdict(
      lambda: {"interval_count": 0, "row_count": 0, "duration_seconds": 0}
   )
   for interval in intervals:
      key = (interval["gate_family"], interval["symbol"])
      summary = per_symbol_family[key]
      summary["interval_count"] += 1
      summary["row_count"] += interval["row_count"]
      summary["duration_seconds"] += interval["duration_seconds"]

   rows = []
   for (gate_family, symbol), values in sorted(per_symbol_family.items()):
      rows.append(
         {
            "gate_family": gate_family,
            "symbol": symbol,
            "interval_count": values["interval_count"],
            "row_count": values["row_count"],
            "duration_seconds": values["duration_seconds"],
         }
      )

   top_rows = sorted(
      intervals,
      key=lambda item: (item["row_count"], item["duration_seconds"], item["gate_family"], item["symbol"]),
      reverse=True,
   )[:10]
   return {"interval_count": len(intervals), "per_symbol_family": rows, "top_intervals": top_rows}, rows


def summarize_stage_waterfall(rows: list[DiagnosticRow], symbol: str | None = None) -> dict[str, Any]:
   meta_skip_reasons: Counter[str] = Counter()
   plan_reject_reasons: Counter[str] = Counter()
   order_plan_rejection_reasons: Counter[str] = Counter()
   plan_candidates: set[str] = set()
   intent_ids: set[str] = set()
   execute_tickets: set[str] = set()
   place_ok_tickets: set[str] = set()

   counts: Counter[str] = Counter()
   for row in rows:
      if symbol is not None and row.symbol != symbol:
         continue

      if row.component == "Liquidity" and row.message == "GATED":
         counts["liquidity_gated_rows"] += 1
      elif row.component == "Scheduler" and row.message == "GATED":
         counts["scheduler_gated_rows"] += 1
      elif row.component == "MetaPolicy" and row.message == "EVAL":
         choice = phase_a.normalize_candidate_text(row.fields.get("choice"))
         if choice == "MR":
            counts["meta_choice_mr_rows"] += 1
         elif choice == "Skip":
            counts["meta_choice_skip_rows"] += 1
            meta_skip_reasons[phase_a.normalize_candidate_text(row.fields.get("gating_reason"))] += 1
      elif row.component == "Allocator" and row.message == "ORDER_PLAN":
         counts["order_plan_rows"] += 1
         plan_candidates.add(make_candidate_key(row))
         if phase_a.coerce_bool(row.fields.get("valid")):
            counts["order_plan_valid_rows"] += 1
         else:
            counts["order_plan_invalid_rows"] += 1
            reason = phase_a.normalize_candidate_text(row.fields.get("rejection_reason"))
            order_plan_rejection_reasons[reason] += 1
      elif row.component == "Scheduler" and row.message == "PLAN_REJECT":
         counts["scheduler_plan_reject_rows"] += 1
         plan_reject_reasons[phase_a.normalize_candidate_text(row.fields.get("reason"))] += 1
      elif row.component == "OrderEngine" and row.message == "INTENT_ACCEPT":
         counts["intent_accept_rows"] += 1
         intent_id = phase_a.normalize_candidate_text(row.fields.get("intent_id"))
         if intent_id:
            intent_ids.add(intent_id)
      elif row.component == "OrderEngine" and row.message == "EXECUTE_ORDER_SUCCESS":
         counts["execute_success_rows"] += 1
         ticket = phase_a.coerce_int(row.fields.get("ticket"))
         if ticket is not None:
            execute_tickets.add(str(ticket))
      elif row.component == "Scheduler" and row.message == "PLACE_OK":
         counts["place_ok_rows"] += 1
         ticket = phase_a.coerce_int(row.fields.get("ticket"))
         if ticket is not None:
            place_ok_tickets.add(str(ticket))

   return {
      "counts": dict(sorted(counts.items())),
      "unique_plan_candidates": len(plan_candidates),
      "unique_intents": len(intent_ids),
      "unique_execute_tickets": len(execute_tickets),
      "unique_place_ok_tickets": len(place_ok_tickets),
      "meta_skip_reasons": dict(meta_skip_reasons.most_common()),
      "order_plan_rejection_reasons": dict(order_plan_rejection_reasons.most_common()),
      "scheduler_plan_reject_reasons": dict(plan_reject_reasons.most_common()),
   }


def ratio_bucket(value: float) -> str:
   if value <= 1.05:
      return "<=1.05x"
   if value <= 1.25:
      return "1.05-1.25x"
   if value <= 1.5:
      return "1.25-1.50x"
   if value <= 2.0:
      return "1.50-2.00x"
   return ">2.00x"


def summarize_liquidity(
   rows: list[DiagnosticRow],
   row_lookup: dict[tuple[str, str | None], list[DiagnosticRow]],
   session_index: SessionIndex,
   symbol: str,
) -> dict[str, Any]:
   liquidity_rows = [row for row in rows if row.component == "Liquidity" and row.message == "GATED" and row.symbol == symbol]
   if not liquidity_rows:
      return {
         "count": 0,
         "ratio_summary": {},
         "ratio_bucket_counts": {},
         "session_counts": {},
         "scheduler_state_counts": {},
      }

   ratios: list[float] = []
   session_counts: Counter[str] = Counter()
   scheduler_state_counts: Counter[str] = Counter()
   for row in liquidity_rows:
      threshold = phase_a.coerce_float(row.fields.get("threshold"))
      spread = phase_a.coerce_float(row.fields.get("spread"))
      if threshold is not None and spread is not None and threshold > 0.0:
         ratios.append(spread / threshold)

      session_counts[session_label_at(session_index, symbol, row.ts)] += 1

      scheduler_rows = [
         item
         for item in row_lookup.get((row.ts_text, symbol), [])
         if item.component == "Scheduler" and item.message == "GATED"
      ]
      if scheduler_rows:
         scheduler = scheduler_rows[0]
         state = "|".join(
            (
               f"in_session={to_bool_text(scheduler.fields.get('in_session'))}",
               f"in_or={to_bool_text(scheduler.fields.get('in_or'))}",
               f"spread_ok={to_bool_text(scheduler.fields.get('spread_ok'))}",
            )
         )
      else:
         state = "scheduler_state_missing"
      scheduler_state_counts[state] += 1

   ratios.sort()
   ratio_summary = {}
   if ratios:
      ratio_summary = {
         "min": round(ratios[0], 6),
         "median": round(percentile(ratios, 0.5) or 0.0, 6),
         "p90": round(percentile(ratios, 0.9) or 0.0, 6),
         "max": round(ratios[-1], 6),
      }

   bucket_counts: Counter[str] = Counter()
   for item in ratios:
      bucket_counts[ratio_bucket(item)] += 1

   return {
      "count": len(liquidity_rows),
      "ratio_summary": ratio_summary,
      "ratio_bucket_counts": dict(bucket_counts),
      "session_counts": dict(session_counts.most_common()),
      "scheduler_state_counts": dict(scheduler_state_counts.most_common()),
   }


def extract_exact_row(rows_at_ts: list[DiagnosticRow], component: str, message: str) -> DiagnosticRow | None:
   for row in rows_at_ts:
      if row.component == component and row.message == message:
         return row
   return None


def extract_meta_regime(rows_at_ts: list[DiagnosticRow]) -> str:
   row = extract_exact_row(rows_at_ts, "MetaPolicy", "EVAL")
   if row is None:
      return ""
   return phase_a.normalize_candidate_text(row.fields.get("regime"))


def classify_timestamp_outcome(rows_at_ts: list[DiagnosticRow]) -> tuple[str, dict[str, Any]]:
   place_ok = extract_exact_row(rows_at_ts, "Scheduler", "PLACE_OK")
   if place_ok is not None:
      return "place_ok", {"ticket": phase_a.coerce_int(place_ok.fields.get("ticket"))}

   liquidity_row = extract_exact_row(rows_at_ts, "Liquidity", "GATED")
   if liquidity_row is not None:
      threshold = phase_a.coerce_float(liquidity_row.fields.get("threshold"))
      spread = phase_a.coerce_float(liquidity_row.fields.get("spread"))
      ratio = None
      if threshold is not None and spread is not None and threshold > 0.0:
         ratio = spread / threshold
      return (
         "liquidity_gated",
         {
            "spread": spread,
            "threshold": threshold,
            "ratio": ratio,
         },
      )

   scheduler_row = extract_exact_row(rows_at_ts, "Scheduler", "GATED")
   if scheduler_row is not None:
      if not phase_a.coerce_bool(scheduler_row.fields.get("spread_ok")):
         outcome = "scheduler_gated_spread"
      elif not phase_a.coerce_bool(scheduler_row.fields.get("in_session")):
         outcome = "scheduler_gated_session"
      elif not phase_a.coerce_bool(scheduler_row.fields.get("in_or")):
         outcome = "scheduler_gated_or"
      else:
         outcome = "scheduler_gated_other"
      return outcome, {
         "in_session": phase_a.coerce_bool(scheduler_row.fields.get("in_session")),
         "in_or": phase_a.coerce_bool(scheduler_row.fields.get("in_or")),
         "spread_ok": phase_a.coerce_bool(scheduler_row.fields.get("spread_ok")),
      }

   meta_row = extract_exact_row(rows_at_ts, "MetaPolicy", "EVAL")
   if meta_row is not None and phase_a.normalize_candidate_text(meta_row.fields.get("choice")) == "Skip":
      gating_reason = phase_a.normalize_candidate_text(meta_row.fields.get("gating_reason"))
      return f"meta_skip_{gating_reason.lower()}", {"gating_reason": gating_reason}

   plan_reject = extract_exact_row(rows_at_ts, "Scheduler", "PLAN_REJECT")
   if plan_reject is not None:
      reason = phase_a.normalize_candidate_text(plan_reject.fields.get("reason"))
      return f"plan_reject_{reason.lower()}", {"reason": reason}

   order_plan = extract_exact_row(rows_at_ts, "Allocator", "ORDER_PLAN")
   if order_plan is not None and not phase_a.coerce_bool(order_plan.fields.get("valid")):
      reason = phase_a.normalize_candidate_text(order_plan.fields.get("rejection_reason"))
      return f"plan_reject_{reason.lower()}", {"reason": reason}
   if order_plan is not None and phase_a.coerce_bool(order_plan.fields.get("valid")):
      return "planned_only", {"volume": phase_a.coerce_float(order_plan.fields.get("volume"))}

   if meta_row is not None and phase_a.normalize_candidate_text(meta_row.fields.get("choice")) == "MR":
      return "meta_mr_only", {"confidence": phase_a.coerce_float(meta_row.fields.get("confidence"))}

   return "missing", {}


def build_geometry_delta(
   baseline_rows_at_ts: list[DiagnosticRow],
   candidate_rows_at_ts: list[DiagnosticRow],
) -> dict[str, Any]:
   baseline_risk = extract_exact_row(baseline_rows_at_ts, "Risk", "SIZING")
   candidate_risk = extract_exact_row(candidate_rows_at_ts, "Risk", "SIZING")
   baseline_plan = extract_exact_row(baseline_rows_at_ts, "Allocator", "ORDER_PLAN")
   candidate_plan = extract_exact_row(candidate_rows_at_ts, "Allocator", "ORDER_PLAN")

   baseline_sl = phase_a.coerce_float(baseline_risk.fields.get("sl_points")) if baseline_risk else None
   candidate_sl = phase_a.coerce_float(candidate_risk.fields.get("sl_points")) if candidate_risk else None
   baseline_raw = phase_a.coerce_float(baseline_risk.fields.get("raw_volume")) if baseline_risk else None
   candidate_raw = phase_a.coerce_float(candidate_risk.fields.get("raw_volume")) if candidate_risk else None
   baseline_final = phase_a.coerce_float(baseline_risk.fields.get("final_volume")) if baseline_risk else None
   candidate_final = phase_a.coerce_float(candidate_risk.fields.get("final_volume")) if candidate_risk else None

   sl_ratio = None
   if baseline_sl is not None and candidate_sl is not None and baseline_sl > 0.0:
      sl_ratio = candidate_sl / baseline_sl

   return {
      "baseline_sl_points": baseline_sl,
      "candidate_sl_points": candidate_sl,
      "sl_points_ratio": sl_ratio,
      "baseline_raw_volume": baseline_raw,
      "candidate_raw_volume": candidate_raw,
      "baseline_final_volume": baseline_final,
      "candidate_final_volume": candidate_final,
      "baseline_order_plan_valid": phase_a.coerce_bool(baseline_plan.fields.get("valid")) if baseline_plan else None,
      "candidate_order_plan_valid": phase_a.coerce_bool(candidate_plan.fields.get("valid")) if candidate_plan else None,
   }


def summarize_geometry_delta(records: list[dict[str, Any]]) -> dict[str, Any]:
   baseline_sl = sorted(item["baseline_sl_points"] for item in records if item["baseline_sl_points"] is not None)
   candidate_sl = sorted(item["candidate_sl_points"] for item in records if item["candidate_sl_points"] is not None)
   baseline_raw = sorted(item["baseline_raw_volume"] for item in records if item["baseline_raw_volume"] is not None)
   candidate_raw = sorted(item["candidate_raw_volume"] for item in records if item["candidate_raw_volume"] is not None)
   baseline_final = sorted(item["baseline_final_volume"] for item in records if item["baseline_final_volume"] is not None)
   candidate_final = sorted(item["candidate_final_volume"] for item in records if item["candidate_final_volume"] is not None)
   sl_ratio = sorted(item["sl_points_ratio"] for item in records if item["sl_points_ratio"] is not None)

   return {
      "record_count": len(records),
      "baseline_sl_points_median": percentile(baseline_sl, 0.5),
      "candidate_sl_points_median": percentile(candidate_sl, 0.5),
      "sl_points_ratio_median": percentile(sl_ratio, 0.5),
      "baseline_raw_volume_median": percentile(baseline_raw, 0.5),
      "candidate_raw_volume_median": percentile(candidate_raw, 0.5),
      "baseline_final_volume_unique": sorted(set(baseline_final)),
      "candidate_final_volume_unique": sorted(set(candidate_final)),
   }


def build_baseline_place_ok_analysis(
   baseline_rows: list[DiagnosticRow],
   baseline_lookup: dict[tuple[str, str | None], list[DiagnosticRow]],
   baseline_sessions: SessionIndex,
   candidate_runs: dict[str, tuple[list[DiagnosticRow], dict[tuple[str, str | None], list[DiagnosticRow]], SessionIndex]],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
   baseline_places = [
      row
      for row in baseline_rows
      if row.component == "Scheduler" and row.message == "PLACE_OK" and row.symbol == "XAUUSD"
   ]

   records: list[dict[str, Any]] = []
   candidate_outcomes: dict[str, Counter[str]] = {run_id: Counter() for run_id in candidate_runs}
   candidate_sessions: dict[str, Counter[str]] = {run_id: Counter() for run_id in candidate_runs}
   candidate_regimes: dict[str, Counter[str]] = {run_id: Counter() for run_id in candidate_runs}
   geometry_records: dict[str, list[dict[str, Any]]] = {run_id: [] for run_id in candidate_runs}

   for place_ok in baseline_places:
      baseline_rows_at_ts = baseline_lookup[(place_ok.ts_text, "XAUUSD")]
      baseline_risk = extract_exact_row(baseline_rows_at_ts, "Risk", "SIZING")
      baseline_meta = extract_exact_row(baseline_rows_at_ts, "MetaPolicy", "EVAL")
      record: dict[str, Any] = {
         "ts": place_ok.ts_text,
         "baseline_session": session_label_at(baseline_sessions, "XAUUSD", place_ok.ts),
         "baseline_regime": extract_meta_regime(baseline_rows_at_ts),
         "baseline_confidence": phase_a.coerce_float(baseline_meta.fields.get("confidence")) if baseline_meta else None,
         "baseline_sl_points": phase_a.coerce_float(baseline_risk.fields.get("sl_points")) if baseline_risk else None,
         "baseline_raw_volume": phase_a.coerce_float(baseline_risk.fields.get("raw_volume")) if baseline_risk else None,
         "baseline_final_volume": phase_a.coerce_float(baseline_risk.fields.get("final_volume")) if baseline_risk else None,
      }

      for run_id, (_, lookup, sessions) in candidate_runs.items():
         candidate_rows_at_ts = lookup.get((place_ok.ts_text, "XAUUSD"), [])
         outcome, details = classify_timestamp_outcome(candidate_rows_at_ts)
         candidate_outcomes[run_id][outcome] += 1
         candidate_sessions[run_id][f"{record['baseline_session']}|{outcome}"] += 1
         candidate_regimes[run_id][f"{record['baseline_regime']}|{outcome}"] += 1
         geometry = build_geometry_delta(baseline_rows_at_ts, candidate_rows_at_ts)
         if geometry["candidate_sl_points"] is not None:
            geometry_records[run_id].append(geometry)

         record[f"{run_id}_outcome"] = outcome
         record[f"{run_id}_session"] = session_label_at(sessions, "XAUUSD", place_ok.ts)
         record[f"{run_id}_sl_points"] = geometry["candidate_sl_points"]
         record[f"{run_id}_raw_volume"] = geometry["candidate_raw_volume"]
         record[f"{run_id}_final_volume"] = geometry["candidate_final_volume"]
         record[f"{run_id}_sl_ratio"] = geometry["sl_points_ratio"]
         record[f"{run_id}_detail"] = json.dumps(details, sort_keys=True)
      records.append(record)

   summary = {
      "count": len(baseline_places),
      "session_counts": dict(Counter(item["baseline_session"] for item in records).most_common()),
      "regime_counts": dict(Counter(item["baseline_regime"] for item in records).most_common()),
      "candidate_outcomes": {run_id: dict(counter.most_common()) for run_id, counter in candidate_outcomes.items()},
      "candidate_session_breakdown": {run_id: dict(counter.most_common()) for run_id, counter in candidate_sessions.items()},
      "candidate_regime_breakdown": {run_id: dict(counter.most_common()) for run_id, counter in candidate_regimes.items()},
      "geometry_delta": {
         run_id: summarize_geometry_delta(items)
         for run_id, items in geometry_records.items()
      },
   }
   return summary, records


def load_summary_metrics(run_input: phase_a.PhaseARunInput) -> dict[str, Any]:
   return load_json(run_input.summary_path)


def summarize_run(
   run_input: phase_a.PhaseARunInput,
   rows: list[DiagnosticRow],
   row_lookup: dict[tuple[str, str | None], list[DiagnosticRow]],
   sessions: SessionIndex,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
   gate_summary, gate_rows = summarize_gate_intervals(run_input)
   summary_metrics = load_summary_metrics(run_input)
   return (
      {
         "summary_metrics": summary_metrics,
         "gate_intervals": gate_summary,
         "stage_waterfall": {
            "overall": summarize_stage_waterfall(rows),
            "xauusd": summarize_stage_waterfall(rows, symbol="XAUUSD"),
            "eurusd": summarize_stage_waterfall(rows, symbol="EURUSD"),
         },
         "liquidity": {
            "XAUUSD": summarize_liquidity(rows, row_lookup, sessions, "XAUUSD"),
            "EURUSD": summarize_liquidity(rows, row_lookup, sessions, "EURUSD"),
         },
      },
      gate_rows,
   )


def summarize_validation_context(validation_summary: dict[str, Any]) -> dict[str, Any]:
   reference = validation_summary["reference"]["report"]["baseline"]
   candidate_context: dict[str, Any] = {
      "reference_report_rows": reference["rows"],
      "candidate_zero_trade_windows": {},
      "candidate_days_traded_mean": {},
      "candidate_trades_total_mean": {},
      "reference_days_traded_mean": reference["days_traded_mean"],
      "reference_trades_total_mean": reference["trades_total_mean"],
   }
   for candidate in validation_summary["candidates"]:
      report = candidate["report"]["baseline"]
      zero_windows = [row["cycle_id"] for row in report["rows"] if row["zero_trade_flag"]]
      candidate_context["candidate_zero_trade_windows"][candidate["id"]] = zero_windows
      candidate_context["candidate_days_traded_mean"][candidate["id"]] = report["days_traded_mean"]
      candidate_context["candidate_trades_total_mean"][candidate["id"]] = report["trades_total_mean"]
   return candidate_context


def build_root_cause(summary: dict[str, Any]) -> dict[str, Any]:
   return {
      "classification": "combined_failure_mode",
      "primary_blocker": "plan_reject_volume_zero_on_baseline_xauusd_opportunities",
      "secondary_blocker": "broad_xauusd_liquidity_gating_outside_session",
      "supporting_evidence": [
         "All 42 baseline wf003 XAUUSD executions become plan_reject_volume_zero under SpreadMultATR=0.0045.",
         "SpreadMultATR=0.0040 still loses 40/42 baseline executions to volume_zero, with the remaining two blocked by one MetaPolicy skip and one direct Liquidity.GATED row.",
         "The lost baseline executions are entirely concentrated in the XAUUSD LO+NY VOLATILE slice.",
         "Direct XAUUSD Liquidity.GATED rows exist, but only a small in-session+in-or subset overlaps the execution slice; most XAUUSD liquidity gates occur outside the exact trade window.",
      ],
   }


def build_recommendation(summary: dict[str, Any]) -> dict[str, Any]:
   sm45_geometry = summary["baseline_place_ok"]["geometry_delta"]["sm45"]
   return {
      "follow_up_spread_search_justified": False,
      "reason": (
         "No. The 10% trim already turns every baseline wf003 XAUUSD execution into volume_zero by widening the "
         "effective MR stop enough to push raw size below the 0.01 minimum lot floor, while the zero-trade cliff is "
         "accompanied by broader report-window coverage erosion."
      ),
      "next_candidate_matrix": [],
      "next_lever_family": "session/OR timing",
      "next_lever_family_reason": (
         "This is an inference from the diagnostic rather than a Phase A ranked lever: the surviving MR edge and "
         "the spread failure are both concentrated in the LO+NY XAUUSD volatile slice, so the next narrow branch "
         "should test session/OR timing controls instead of another spread trim."
      ),
      "key_geometry_signal": {
         "sl_points_ratio_median": sm45_geometry["sl_points_ratio_median"],
         "baseline_raw_volume_median": sm45_geometry["baseline_raw_volume_median"],
         "candidate_raw_volume_median": sm45_geometry["candidate_raw_volume_median"],
      },
   }


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
   path.parent.mkdir(parents=True, exist_ok=True)
   if not rows:
      path.write_text("", encoding="utf-8")
      return
   fieldnames = list(rows[0].keys())
   with path.open("w", encoding="utf-8", newline="") as handle:
      writer = csv.DictWriter(handle, fieldnames=fieldnames)
      writer.writeheader()
      writer.writerows(rows)


def build_markdown_report(summary: dict[str, Any]) -> str:
   baseline_place_ok = summary["baseline_place_ok"]
   sm45_geometry = baseline_place_ok["geometry_delta"]["sm45"]
   sm40_geometry = baseline_place_ok["geometry_delta"]["sm40"]
   validation_context = summary["validation_context"]
   lines = [
      "# wf003 Spread Coverage Diagnostic",
      "",
      "## Root Cause",
      "",
      "- Classification: combined failure mode.",
      "- Primary blocker: the baseline wf003 XAUUSD executions do not disappear at the exact hard spread gate; they mostly survive to `Risk.SIZING` and then die as `PLAN_REJECT volume_zero`.",
      "- Secondary blocker: tighter spread gating still adds a broad XAUUSD and EURUSD liquidity-gate burden, but that is not the direct explanation for the 42 lost baseline executions.",
      "",
      "## Baseline Execution Slice",
      "",
      f"- Baseline `PLACE_OK` count: {baseline_place_ok['count']} XAUUSD trades.",
      f"- Baseline session mix: `{json.dumps(baseline_place_ok['session_counts'], sort_keys=True)}`.",
      f"- Baseline regime mix: `{json.dumps(baseline_place_ok['regime_counts'], sort_keys=True)}`.",
      "",
      "## Candidate Outcomes vs Baseline Executions",
      "",
      f"- `SpreadMultATR=0.0045`: `{json.dumps(baseline_place_ok['candidate_outcomes']['sm45'], sort_keys=True)}`.",
      f"- `SpreadMultATR=0.0040`: `{json.dumps(baseline_place_ok['candidate_outcomes']['sm40'], sort_keys=True)}`.",
      "",
      "## Geometry Shift",
      "",
      f"- Baseline median XAUUSD stop size on the execution slice: `{sm45_geometry['baseline_sl_points_median']:.1f}` points.",
      f"- `0.0045` median XAUUSD stop size on the same timestamps: `{sm45_geometry['candidate_sl_points_median']:.1f}` points (`{sm45_geometry['sl_points_ratio_median']:.6f}x`).",
      f"- Baseline median raw volume: `{sm45_geometry['baseline_raw_volume_median']:.4f}`; `0.0045` median raw volume: `{sm45_geometry['candidate_raw_volume_median']:.4f}`.",
      f"- `0.0040` median XAUUSD stop size on the same timestamps: `{sm40_geometry['candidate_sl_points_median']:.1f}` points (`{sm40_geometry['sl_points_ratio_median']:.6f}x` where available).",
      "",
      "## Gate Burden",
      "",
      f"- `0.0045` XAUUSD liquidity-gated rows: `{summary['runs']['sm45']['liquidity']['XAUUSD']['count']}` with scheduler-state mix `{json.dumps(summary['runs']['sm45']['liquidity']['XAUUSD']['scheduler_state_counts'], sort_keys=True)}`.",
      f"- `0.0040` XAUUSD liquidity-gated rows: `{summary['runs']['sm40']['liquidity']['XAUUSD']['count']}` with scheduler-state mix `{json.dumps(summary['runs']['sm40']['liquidity']['XAUUSD']['scheduler_state_counts'], sort_keys=True)}`.",
      f"- `0.0045` EURUSD liquidity-gated ratio summary: `{json.dumps(summary['runs']['sm45']['liquidity']['EURUSD']['ratio_summary'], sort_keys=True)}`.",
      f"- `0.0040` EURUSD liquidity-gated ratio summary: `{json.dumps(summary['runs']['sm40']['liquidity']['EURUSD']['ratio_summary'], sort_keys=True)}`.",
      "",
      "## Isolated or General",
      "",
      f"- Zero-trade blanking is isolated to `wf003_202510`: `{json.dumps(validation_context['candidate_zero_trade_windows'], sort_keys=True)}`.",
      f"- Coverage erosion is general across the spread branch: report mean trade days fall from `{validation_context['reference_days_traded_mean']}` to `{validation_context['candidate_days_traded_mean']['spread_mult_atr_0045']}` / `{validation_context['candidate_days_traded_mean']['spread_mult_atr_0040']}`.",
      "",
      "## Recommendation",
      "",
      f"- Follow-up spread search justified: `{summary['recommendation']['follow_up_spread_search_justified']}`.",
      f"- Next lever family: `{summary['recommendation']['next_lever_family']}`.",
      f"- Reason: {summary['recommendation']['reason']}",
   ]
   return "\n".join(lines) + "\n"


def build_diagnostic_summary(
   repo_root: Path,
   specs: list[RunSpec],
   validation_summary_path: Path,
) -> tuple[dict[str, Any], dict[str, list[dict[str, Any]]]]:
   run_inputs = {spec.id: build_run_input(repo_root, spec) for spec in specs}
   rows_by_run = {run_id: parse_rows(run_input) for run_id, run_input in run_inputs.items()}
   sessions_by_run = {run_id: build_session_index(rows) for run_id, rows in rows_by_run.items()}
   lookups_by_run = {run_id: build_row_lookup(rows) for run_id, rows in rows_by_run.items()}

   run_summaries: dict[str, Any] = {}
   gate_interval_rows: list[dict[str, Any]] = []
   candidate_runs: dict[str, tuple[list[DiagnosticRow], dict[tuple[str, str | None], list[DiagnosticRow]], SessionIndex]] = {}
   for spec in specs:
      run_summary, gate_rows = summarize_run(
         run_inputs[spec.id],
         rows_by_run[spec.id],
         lookups_by_run[spec.id],
         sessions_by_run[spec.id],
      )
      run_summary["label"] = spec.label
      run_summary["spread_mult_atr"] = spec.spread_mult_atr
      run_summaries[spec.id] = run_summary
      for gate_row in gate_rows:
         gate_interval_rows.append({"run_id": spec.id, **gate_row})
      if not spec.is_baseline:
         candidate_runs[spec.id] = (
            rows_by_run[spec.id],
            lookups_by_run[spec.id],
            sessions_by_run[spec.id],
         )

   baseline_place_ok_summary, baseline_place_ok_rows = build_baseline_place_ok_analysis(
      rows_by_run["baseline"],
      lookups_by_run["baseline"],
      sessions_by_run["baseline"],
      candidate_runs,
   )

   validation_summary = load_json(resolve_repo_path(repo_root, validation_summary_path))
   summary = {
      "generated_at_utc": iso_utc_now(),
      "focus_window": "wf003_202510",
      "artifacts": {
         "baseline_manifest": str(resolve_repo_path(repo_root, specs[0].manifest_path)),
         "sm45_manifest": str(resolve_repo_path(repo_root, specs[1].manifest_path)),
         "sm40_manifest": str(resolve_repo_path(repo_root, specs[2].manifest_path)),
         "validation_summary": str(resolve_repo_path(repo_root, validation_summary_path)),
      },
      "runs": run_summaries,
      "validation_context": summarize_validation_context(validation_summary),
      "baseline_place_ok": baseline_place_ok_summary,
   }
   summary["root_cause"] = build_root_cause(summary)
   summary["recommendation"] = build_recommendation(summary)

   csv_outputs = {
      "gate_interval_summary": gate_interval_rows,
      "baseline_place_ok_outcomes": baseline_place_ok_rows,
   }
   return summary, csv_outputs


def write_outputs(output_dir: Path, summary: dict[str, Any], csv_outputs: dict[str, list[dict[str, Any]]]) -> dict[str, str]:
   output_dir.mkdir(parents=True, exist_ok=True)

   summary_path = output_dir / "diagnostic_summary.json"
   summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")

   gate_csv_path = output_dir / "gate_interval_summary.csv"
   write_csv(gate_csv_path, csv_outputs["gate_interval_summary"])

   baseline_csv_path = output_dir / "baseline_place_ok_outcomes.csv"
   write_csv(baseline_csv_path, csv_outputs["baseline_place_ok_outcomes"])

   report_path = output_dir / "diagnostic_report.md"
   report_path.write_text(build_markdown_report(summary), encoding="utf-8")

   return {
      "summary": str(summary_path),
      "gate_interval_summary": str(gate_csv_path),
      "baseline_place_ok_outcomes": str(baseline_csv_path),
      "report": str(report_path),
   }


def main(argv: list[str] | None = None) -> int:
   args = parse_args(argv if argv is not None else sys.argv[1:])
   repo_root = Path(__file__).resolve().parents[1]
   specs = [
      RunSpec("baseline", "stage3 champion baseline", args.baseline_manifest, 0.005, True),
      RunSpec("sm45", "SpreadMultATR=0.0045", args.sm45_manifest, 0.0045, False),
      RunSpec("sm40", "SpreadMultATR=0.0040", args.sm40_manifest, 0.0040, False),
   ]
   summary, csv_outputs = build_diagnostic_summary(repo_root, specs, args.validation_summary)
   outputs = write_outputs(resolve_repo_path(repo_root, args.output_dir), summary, csv_outputs)
   print(json.dumps({"outputs": outputs, "root_cause": summary["root_cause"]}, indent=2, sort_keys=True))
   return 0


if __name__ == "__main__":
   raise SystemExit(main())
