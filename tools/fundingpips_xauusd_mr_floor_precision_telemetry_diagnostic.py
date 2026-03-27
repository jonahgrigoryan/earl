#!/usr/bin/env python3
"""Focused wf003 XAUUSD MR floor-precision telemetry diagnostic."""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
import sys
from collections import Counter
from datetime import datetime, timezone
from itertools import zip_longest
from pathlib import Path
from typing import Any, Iterable

try:
   from tools import fundingpips_mt5_runner as mt5_runner
   from tools import fundingpips_phase_a_research as phase_a
   from tools import fundingpips_rl_emrt_sizing_diagnostic as rl_diag
except ModuleNotFoundError:  # pragma: no cover - script execution fallback
   sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
   from tools import fundingpips_mt5_runner as mt5_runner
   from tools import fundingpips_phase_a_research as phase_a
   from tools import fundingpips_rl_emrt_sizing_diagnostic as rl_diag


DEFAULT_OUTPUT_DIR = (
   Path(".tmp")
   / "fundingpips_xauusd_mr_floor_precision_telemetry"
   / "phasea_xauusd_mr_floor_precision_telemetry"
)
# Keep the rerun cache root short enough that MT5 can load the generated
# `/config:` INI path on Windows during focused reruns.
DEFAULT_RUNNER_OUTPUT_DIR = Path(".tmp") / "fp_xau_prec_rr"

DEFAULT_PLAN_PATH = Path("docs") / "plans" / "PLAN_main.md"
DEFAULT_PRIOR_FLOOR_SUMMARY_PATH = (
   Path(".tmp")
   / "fundingpips_xauusd_mr_floor_sensitivity_diagnostic"
   / "phasea_xauusd_mr_floor_sensitivity"
   / "diagnostic_summary.json"
)
DEFAULT_PRIOR_RL_SUMMARY_PATH = (
   Path(".tmp")
   / "fundingpips_rl_emrt_sizing_diagnostic"
   / "phasea_rl_emrt_sizing"
   / "diagnostic_summary.json"
)
DEFAULT_PRIOR_SPREAD_SUMMARY_PATH = (
   Path(".tmp")
   / "fundingpips_wf003_spread_coverage_diagnostic"
   / "phasea_wf003_spread_coverage"
   / "diagnostic_summary.json"
)

DEFAULT_WF003_BASELINE_MANIFEST = (
   Path(".tmp")
   / "fundingpips_rl_emrt_sizing_diagnostic"
   / "phasea_rl_emrt_sizing"
   / "runner_runs"
   / "phasea_rl_emrt_sizing__emrt_weight_000__wf003_202510__baseline__c54eb9cf9feefece"
   / "run_manifest.json"
)
DEFAULT_WF003_CANDIDATE_MANIFEST = (
   Path(".tmp")
   / "fundingpips_mr_emrt_weight_validation"
   / "phasea_mr_emrt_weight"
   / "runner_runs"
   / "phasea_mr_emrt_weight__emrt_weight_020__wf003_202510__baseline__5f30d0753c589c59"
   / "run_manifest.json"
)
DEFAULT_WF002_BASELINE_MANIFEST = (
   Path(".tmp")
   / "fundingpips_rl_emrt_sizing_diagnostic"
   / "phasea_rl_emrt_sizing"
   / "runner_runs"
   / "phasea_rl_emrt_sizing__emrt_weight_000__wf002_202509__baseline__3b9ace62897dff0c"
   / "run_manifest.json"
)
DEFAULT_WF002_CANDIDATE_MANIFEST = (
   Path(".tmp")
   / "fundingpips_mr_emrt_weight_validation"
   / "phasea_mr_emrt_weight"
   / "runner_runs"
   / "phasea_mr_emrt_weight__emrt_weight_020__wf002_202509__baseline__e90bef0269667296"
   / "run_manifest.json"
)

EXPECTED_WF003_METRICS = {
   "baseline_emrt_000": {
      "days_traded": 22,
      "return_pct": 1.7191,
      "trades_total": 44,
   },
   "candidate_emrt_020": {
      "days_traded": 22,
      "return_pct": 1.7441,
      "trades_total": 44,
   },
}

XAUUSD_POINT = 0.01
GAP_THRESHOLDS_PCT = (1.0, 2.0, 5.0, 10.0)


def repo_root() -> Path:
   return Path(__file__).resolve().parents[1]


def resolve_repo_path(repo: Path, path: Path | str) -> Path:
   candidate = Path(path)
   return candidate if candidate.is_absolute() else (repo / candidate).resolve()


def iso_utc_now() -> str:
   return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> Any:
   return json.loads(path.read_text(encoding="utf-8"))


def maybe_float(value: Any) -> float | None:
   if value in (None, "", "None"):
      return None
   if isinstance(value, (int, float)):
      return float(value)
   try:
      return float(str(value))
   except ValueError:
      return None


def maybe_int(value: Any) -> int | None:
   if value in (None, "", "None"):
      return None
   if isinstance(value, bool):
      return int(value)
   if isinstance(value, int):
      return value
   try:
      return int(str(value))
   except ValueError:
      return None


def maybe_bool(value: Any) -> bool | None:
   if value in (None, "", "None"):
      return None
   if isinstance(value, bool):
      return value
   text = str(value).strip().lower()
   if text in {"true", "1", "yes"}:
      return True
   if text in {"false", "0", "no"}:
      return False
   return None


def round_or_none(value: float | None, places: int = 6) -> float | None:
   if value is None or not math.isfinite(value):
      return None
   return round(value, places)


def safe_relative(path: Path) -> str:
   try:
      return str(path.resolve().relative_to(repo_root()))
   except ValueError:
      return str(path.resolve())


def load_manifest_candidates(manifest_path: Path) -> list[dict[str, Any]]:
   manifest = load_json(manifest_path)
   run_root = manifest_path.parent
   run_input = phase_a.PhaseARunInput(
      id=run_root.name,
      baseline_role="precision_telemetry",
      root=run_root,
      manifest_path=manifest_path,
      summary_path=Path(manifest["collected_summary"]),
      daily_path=Path(manifest["collected_daily"]),
      report_path=Path(manifest["collected_report"]),
      decision_log_paths=tuple(Path(item) for item in manifest.get("collected_decision_logs", [])),
      event_log_paths=tuple(Path(item) for item in manifest.get("collected_event_logs", [])),
   )
   decision_rows = phase_a.parse_decision_logs(run_input)
   event_rows = phase_a.parse_event_logs(run_input)
   return phase_a.build_candidates(decision_rows, event_rows)


def build_spec_from_manifest(manifest_path: Path) -> mt5_runner.BacktestSpec:
   manifest = load_json(manifest_path)
   return mt5_runner.build_spec(dict(manifest["spec"]))


def rerun_specs(
   repo: Path,
   runner_output_dir: Path,
   manifests: list[tuple[str, Path]],
) -> dict[str, dict[str, Any]]:
   results: dict[str, dict[str, Any]] = {}
   paths = mt5_runner.build_runner_paths(output_root=runner_output_dir)
   synced = False
   compiled = False

   for run_id, manifest_path in manifests:
      spec = build_spec_from_manifest(manifest_path)
      result = mt5_runner.run_single_backtest(
         spec,
         paths,
         dry_run=False,
         sync_before_run=not synced,
         compile_before_run=not compiled,
         force=False,
         stop_existing=True,
      )
      synced = True
      compiled = True
      results[run_id] = result
   return results


def volume_gap_pct(reference_volume: float | None, volume_min: float | None) -> float | None:
   if reference_volume is None or volume_min is None or volume_min <= 0.0:
      return None
   gap = ((volume_min - reference_volume) / volume_min) * 100.0
   return max(gap, 0.0)


def compute_stop_distance_points(entry_price: float | None, sl_price: float | None) -> float | None:
   if entry_price is None or sl_price is None:
      return None
   if not math.isfinite(entry_price) or not math.isfinite(sl_price):
      return None
   return abs(entry_price - sl_price) / XAUUSD_POINT


def normalize_precision_row(run_id: str, run_label: str, source_row: dict[str, Any]) -> dict[str, Any]:
   volume_min = maybe_float(source_row.get("volume_min")) or 0.0
   volume_step = maybe_float(source_row.get("volume_step")) or 0.0
   raw_volume = maybe_float(source_row.get("risk_raw_volume"))
   floored_volume = maybe_float(source_row.get("risk_floored_volume"))
   final_volume = maybe_float(source_row.get("volume"))
   zero_subcause = str(
      source_row.get("volume_zero_subcause")
      or source_row.get("risk_volume_zero_subcause")
      or ""
   )
   zero_reference_volume = maybe_float(source_row.get("volume_zero_reference_volume"))
   if zero_reference_volume is None:
      zero_reference_volume = maybe_float(source_row.get("risk_volume_zero_reference_volume"))
   zero_gap_pct = volume_gap_pct(
      zero_reference_volume,
      volume_min if volume_min > 0.0 else None,
   )
   if zero_gap_pct is None:
      risk_gap_frac = maybe_float(source_row.get("risk_volume_zero_gap_to_min_lot_frac"))
      if risk_gap_frac is not None:
         zero_gap_pct = risk_gap_frac * 100.0

   return {
      "run_id": run_id,
      "run_label": run_label,
      "candidate_id": str(source_row.get("candidate_id") or ""),
      "decision_ts": str(source_row.get("decision_ts") or ""),
      "decision_date": str(source_row.get("decision_ts") or "")[:10],
      "decision_hour": str(source_row.get("decision_ts") or "")[11:13],
      "symbol": str(source_row.get("symbol") or ""),
      "strategy": str(source_row.get("strategy") or ""),
      "plan_valid": bool(maybe_bool(source_row.get("plan_valid"))),
      "place_ok": bool(maybe_bool(source_row.get("place_ok"))),
      "rejection_reason": str(source_row.get("rejection_reason") or ""),
      "volume_zero_subcause": zero_subcause,
      "floor_zero": bool(zero_subcause) or str(source_row.get("rejection_reason") or "") == "volume_zero",
      "raw_volume": raw_volume,
      "floored_volume": floored_volume,
      "final_volume": final_volume,
      "volume_min": round_or_none(volume_min, 8),
      "volume_step": round_or_none(volume_step, 8),
      "raw_gap_pct": round_or_none(
         (maybe_float(source_row.get("risk_raw_gap_to_min_lot_frac")) or 0.0) * 100.0,
         8,
      ),
      "floored_gap_pct": round_or_none(
         (maybe_float(source_row.get("risk_floored_gap_to_min_lot_frac")) or 0.0) * 100.0,
         8,
      ),
      "volume_zero_reference_volume": round_or_none(zero_reference_volume, 8),
      "volume_zero_gap_pct": round_or_none(zero_gap_pct, 8),
      "budget_scaled_raw_volume": round_or_none(maybe_float(source_row.get("budget_scaled_raw_volume")), 8),
      "budget_scaled_floored_volume": round_or_none(maybe_float(source_row.get("budget_scaled_floored_volume")), 8),
      "effective_risk_pct": round_or_none(maybe_float(source_row.get("effective_risk_pct")), 8),
      "meta_confidence": round_or_none(maybe_float(source_row.get("meta_confidence")), 8),
      "requested_entry_price": round_or_none(maybe_float(source_row.get("requested_entry_price")), 5),
      "sl": round_or_none(maybe_float(source_row.get("sl")), 5),
      "tp": round_or_none(maybe_float(source_row.get("tp")), 5),
      "stop_distance_points": round_or_none(
         compute_stop_distance_points(
            maybe_float(source_row.get("requested_entry_price")),
            maybe_float(source_row.get("sl")),
         ),
         2,
      ),
   }


def build_precision_rows(run_id: str, run_label: str, candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
   return [
      normalize_precision_row(run_id, run_label, row)
      for row in candidates
      if row.get("symbol") == "XAUUSD" and row.get("strategy") == "MR"
   ]


def distribution(values: Iterable[float | None]) -> dict[str, Any]:
   clean = [float(item) for item in values if item is not None and math.isfinite(float(item))]
   if not clean:
      return {
         "count": 0,
         "min": None,
         "median": None,
         "mean": None,
         "max": None,
      }
   return {
      "count": len(clean),
      "min": round(min(clean), 8),
      "median": round(statistics.median(clean), 8),
      "mean": round(statistics.fmean(clean), 8),
      "max": round(max(clean), 8),
   }


def build_zero_cause_breakdown_rows(rows: list[dict[str, Any]], slice_label: str) -> list[dict[str, Any]]:
   zero_rows = [row for row in rows if row.get("floor_zero")]
   counts = Counter(str(row.get("volume_zero_subcause") or "unspecified") for row in zero_rows)
   total = len(zero_rows)
   return [
      {
         "slice_label": slice_label,
         "volume_zero_subcause": cause,
         "count": count,
         "share_of_slice": round(count / total, 6) if total else None,
      }
      for cause, count in sorted(counts.items())
   ]


def build_gap_distribution_rows(rows: list[dict[str, Any]], slice_label: str) -> list[dict[str, Any]]:
   zero_rows = [row for row in rows if row.get("floor_zero") and row.get("volume_zero_gap_pct") is not None]
   output: list[dict[str, Any]] = []
   total = len(zero_rows)
   for threshold in GAP_THRESHOLDS_PCT:
      matched = [row for row in zero_rows if float(row["volume_zero_gap_pct"]) <= threshold]
      output.append(
         {
            "slice_label": slice_label,
            "threshold_label": f"<= {threshold:.0f}pct below min lot",
            "max_gap_pct": threshold,
            "count": len(matched),
            "share_of_slice": round(len(matched) / total, 6) if total else None,
            "reference_volume_min": round_or_none(min((row["volume_zero_reference_volume"] for row in matched), default=None), 8),
            "reference_volume_median": (
               round(statistics.median(row["volume_zero_reference_volume"] for row in matched), 8)
               if matched
               else None
            ),
            "reference_volume_max": round_or_none(max((row["volume_zero_reference_volume"] for row in matched), default=None), 8),
         }
      )
   return output


def build_zero_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
   zero_rows = [row for row in rows if row.get("floor_zero")]
   cause_counts = Counter(str(row.get("volume_zero_subcause") or "unspecified") for row in zero_rows)
   return {
      "count": len(zero_rows),
      "zero_cause_counts": dict(cause_counts),
      "reference_volume": distribution(row.get("volume_zero_reference_volume") for row in zero_rows),
      "gap_pct": distribution(row.get("volume_zero_gap_pct") for row in zero_rows),
      "raw_volume": distribution(row.get("raw_volume") for row in zero_rows),
      "floored_volume": distribution(row.get("floored_volume") for row in zero_rows),
   }


def build_metric_guard(label: str, current_summary: dict[str, Any], expected: dict[str, Any]) -> dict[str, Any]:
   current = {
      "return_pct": round_or_none(maybe_float(current_summary.get("final_return_pct")), 4),
      "trades_total": maybe_int(current_summary.get("trades_total")),
      "days_traded": maybe_int(current_summary.get("days_traded")),
   }
   passed = (
      current["return_pct"] == expected["return_pct"]
      and current["trades_total"] == expected["trades_total"]
      and current["days_traded"] == expected["days_traded"]
   )
   return {
      "label": label,
      "expected": expected,
      "current": current,
      "passed": passed,
      "delta_return_pct": (
         None
         if current["return_pct"] is None
         else round(current["return_pct"] - expected["return_pct"], 4)
      ),
      "delta_trades_total": (
         None
         if current["trades_total"] is None
         else current["trades_total"] - expected["trades_total"]
      ),
      "delta_days_traded": (
         None
         if current["days_traded"] is None
         else current["days_traded"] - expected["days_traded"]
      ),
   }


def pair_precision_lineages(
   window_id: str,
   baseline_bundle: rl_diag.RunBundle,
   candidate_bundle: rl_diag.RunBundle,
) -> list[dict[str, Any]]:
   output: list[dict[str, Any]] = []
   all_keys = sorted(set(baseline_bundle.meta_by_key) | set(candidate_bundle.meta_by_key))

   for key in all_keys:
      baseline_meta = baseline_bundle.meta_by_key.get(key)
      candidate_meta = candidate_bundle.meta_by_key.get(key)
      baseline_lineages = baseline_bundle.lineage_by_key.get(key, [])
      candidate_lineages = candidate_bundle.lineage_by_key.get(key, [])
      for pair_index, (baseline_lineage, candidate_lineage) in enumerate(
         zip_longest(baseline_lineages, candidate_lineages),
         start=1,
      ):
         divergence = rl_diag.classify_divergence(
            baseline_meta,
            candidate_meta,
            baseline_lineage,
            candidate_lineage,
         )
         candidate_subcause = str(
            (candidate_lineage or {}).get("volume_zero_subcause")
            or (candidate_lineage or {}).get("risk_volume_zero_subcause")
            or ""
         )
         candidate_gap_frac = (
            maybe_float((candidate_lineage or {}).get("volume_zero_gap_to_min_lot_frac"))
            or maybe_float((candidate_lineage or {}).get("risk_volume_zero_gap_to_min_lot_frac"))
         )
         output.append(
            {
               "window_id": window_id,
               "pair_index": pair_index,
               "eval_key": rl_diag.serialize_eval_key(key),
               "decision_ts": (baseline_meta or candidate_meta or {}).get("decision_ts"),
               "decision_hour": (baseline_meta or candidate_meta or {}).get("decision_hour"),
               "symbol": (baseline_lineage or candidate_lineage or {}).get("symbol"),
               "regime": (baseline_meta or candidate_meta or {}).get("regime"),
               "baseline_candidate_id": (baseline_lineage or {}).get("candidate_id"),
               "candidate_candidate_id": (candidate_lineage or {}).get("candidate_id"),
               "baseline_place_ok": bool((baseline_lineage or {}).get("place_ok")),
               "candidate_place_ok": bool((candidate_lineage or {}).get("place_ok")),
               "baseline_rejection_reason": str((baseline_lineage or {}).get("rejection_reason") or ""),
               "candidate_rejection_reason": str((candidate_lineage or {}).get("rejection_reason") or ""),
               "candidate_volume_zero_subcause": candidate_subcause,
               "candidate_volume_zero_reference_volume": round_or_none(
                  maybe_float((candidate_lineage or {}).get("volume_zero_reference_volume"))
                  or maybe_float((candidate_lineage or {}).get("risk_volume_zero_reference_volume")),
                  8,
               ),
               "candidate_volume_zero_gap_pct": (
                  round(candidate_gap_frac * 100.0, 8)
                  if candidate_gap_frac is not None
                  else None
               ),
               "candidate_budget_scaled_raw_volume": round_or_none(
                  maybe_float((candidate_lineage or {}).get("budget_scaled_raw_volume")),
                  8,
               ),
               "candidate_budget_scaled_floored_volume": round_or_none(
                  maybe_float((candidate_lineage or {}).get("budget_scaled_floored_volume")),
                  8,
               ),
               "candidate_raw_volume": round_or_none(maybe_float((candidate_lineage or {}).get("risk_raw_volume")), 8),
               "candidate_floored_volume": round_or_none(maybe_float((candidate_lineage or {}).get("risk_floored_volume")), 8),
               "candidate_final_volume": round_or_none(maybe_float((candidate_lineage or {}).get("final_volume")), 8),
               "baseline_raw_volume": round_or_none(maybe_float((baseline_lineage or {}).get("risk_raw_volume")), 8),
               "baseline_final_volume": round_or_none(maybe_float((baseline_lineage or {}).get("final_volume")), 8),
               "lost_baseline_trade": divergence["lost_baseline_trade"],
               "gained_candidate_trade": divergence["gained_candidate_trade"],
               "divergence_reason": divergence["reason"],
            }
         )
   return output


def build_failure_slice_rows(paired_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
   return [
      row
      for row in paired_rows
      if row.get("lost_baseline_trade") and row.get("candidate_volume_zero_subcause")
   ]


def summarize_failure_slice(rows: list[dict[str, Any]]) -> dict[str, Any]:
   cause_counts = Counter(str(row.get("candidate_volume_zero_subcause") or "unspecified") for row in rows)
   gap_distribution = build_gap_distribution_rows(
      [
         {
            "floor_zero": True,
            "volume_zero_subcause": row.get("candidate_volume_zero_subcause"),
            "volume_zero_gap_pct": row.get("candidate_volume_zero_gap_pct"),
            "volume_zero_reference_volume": row.get("candidate_volume_zero_reference_volume"),
         }
         for row in rows
      ],
      "wf003 failure slice",
   )
   return {
      "count": len(rows),
      "zero_cause_counts": dict(cause_counts),
      "reference_volume": distribution(row.get("candidate_volume_zero_reference_volume") for row in rows),
      "gap_pct": distribution(row.get("candidate_volume_zero_gap_pct") for row in rows),
      "tolerance_bands": gap_distribution,
   }


def build_intervention_call(
   failure_slice: dict[str, Any],
   replacement_summary: dict[str, Any],
) -> dict[str, Any]:
   del replacement_summary
   bands_by_label = {row["threshold_label"]: row for row in failure_slice["tolerance_bands"]}
   share_within_2pct = maybe_float(bands_by_label.get("<= 2pct below min lot", {}).get("share_of_slice"))
   share_within_5pct = maybe_float(bands_by_label.get("<= 5pct below min lot", {}).get("share_of_slice"))
   later_branch_justified = bool(
      failure_slice["count"] > 0
      and (
         (share_within_2pct is not None and share_within_2pct >= 0.80)
         or (share_within_5pct is not None and share_within_5pct >= 0.90)
      )
   )
   if later_branch_justified:
      return {
         "later_intervention_branch_justified": True,
         "exact_next_branch": "codex/xauusd-mr-floor-narrow-rescue-validation",
         "close_path": False,
         "why": (
            "The failure slice is tightly concentrated just under the 0.01 minimum lot, so a later branch can stay narrow and target only the specific near-floor loss mode rather than broad sizing changes."
         ),
      }
   return {
      "later_intervention_branch_justified": False,
      "exact_next_branch": "",
      "close_path": True,
         "why": (
            "The failure slice is still too broad below the 0.01 minimum lot to justify a narrowly bounded rescue rule, especially with replacement lineages continuing to reuse freed position-cap slots."
         ),
      }


def build_markdown_report(summary: dict[str, Any]) -> str:
   reruns = summary["reruns"]
   baseline_zero = summary["wf003"]["baseline_zero_rows"]
   candidate_zero = summary["wf003"]["candidate_zero_rows"]
   failure_slice = summary["wf003"]["failure_slice"]
   replacement = summary["wf003"]["replacement_churn"]
   conclusion = summary["conclusion"]
   bands = {row["threshold_label"]: row for row in failure_slice["tolerance_bands"]}

   lines = [
      "# XAUUSD MR Floor-Precision Telemetry Diagnostic",
      "",
      "## Behavior Guard",
      "",
      f"- `wf003_202510` baseline `MR_EMRTWeight=0.0`: `{reruns['baseline_emrt_000']['guard']['current']['return_pct']:.4f}%`, `{reruns['baseline_emrt_000']['guard']['current']['trades_total']}` trades, `{reruns['baseline_emrt_000']['guard']['current']['days_traded']}` days; unchanged guard `{reruns['baseline_emrt_000']['guard']['passed']}`.",
      f"- `wf003_202510` candidate `MR_EMRTWeight=0.2`: `{reruns['candidate_emrt_020']['guard']['current']['return_pct']:.4f}%`, `{reruns['candidate_emrt_020']['guard']['current']['trades_total']}` trades, `{reruns['candidate_emrt_020']['guard']['current']['days_traded']}` days; unchanged guard `{reruns['candidate_emrt_020']['guard']['passed']}`.",
      "",
      "## Zero Causes",
      "",
      f"- Baseline wf003 zero rows: `{baseline_zero['count']}` with causes `{json.dumps(baseline_zero['zero_cause_counts'], sort_keys=True)}`.",
      f"- Candidate wf003 zero rows: `{candidate_zero['count']}` with causes `{json.dumps(candidate_zero['zero_cause_counts'], sort_keys=True)}`.",
      f"- Failure slice rows lost from baseline executions to candidate floor-zero: `{failure_slice['count']}` with causes `{json.dumps(failure_slice['zero_cause_counts'], sort_keys=True)}`.",
      "",
      "## Gap Bands",
      "",
      f"- Failure slice share within `<=1%` below min lot: `{bands.get('<= 1pct below min lot', {}).get('share_of_slice')}`.",
      f"- Failure slice share within `<=2%` below min lot: `{bands.get('<= 2pct below min lot', {}).get('share_of_slice')}`.",
      f"- Failure slice share within `<=5%` below min lot: `{bands.get('<= 5pct below min lot', {}).get('share_of_slice')}`.",
      f"- Failure slice share within `<=10%` below min lot: `{bands.get('<= 10pct below min lot', {}).get('share_of_slice')}`.",
      f"- Failure slice reference-volume range: `{failure_slice['reference_volume']['min']} -> {failure_slice['reference_volume']['max']}` lots.",
      "",
      "## Replacement Churn",
      "",
      f"- Current wf003 lost-trade reasons: `{json.dumps(replacement['current_lost_trade_reason_counts'], sort_keys=True)}`.",
      f"- Current wf003 gained-trade reasons: `{json.dumps(replacement['current_gained_trade_reason_counts'], sort_keys=True)}`.",
      f"- Prior wf003 lost-trade reasons: `{json.dumps(replacement['prior_lost_trade_reason_counts'], sort_keys=True)}`.",
      f"- Prior wf003 gained-trade reasons: `{json.dumps(replacement['prior_gained_trade_reason_counts'], sort_keys=True)}`.",
      "",
      "## Call",
      "",
      f"- Later intervention branch justified: `{conclusion['later_intervention_branch_justified']}`.",
      (
         f"- Exact next branch: `{conclusion['exact_next_branch']}`."
         if conclusion["later_intervention_branch_justified"]
         else "- Exact next branch: none."
      ),
      f"- Why: {conclusion['why']}",
      "",
   ]
   return "\n".join(lines)


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


def build_summary(
   *,
   repo: Path,
   plan_path: Path,
   prior_floor_summary_path: Path,
   prior_rl_summary_path: Path,
   prior_spread_summary_path: Path,
   runner_output_dir: Path,
   wf003_baseline_manifest: Path,
   wf003_candidate_manifest: Path,
   include_wf002_controls: bool,
   wf002_baseline_manifest: Path,
   wf002_candidate_manifest: Path,
) -> tuple[dict[str, Any], dict[str, list[dict[str, Any]]]]:
   manifests_to_run = [
      ("baseline_emrt_000", resolve_repo_path(repo, wf003_baseline_manifest)),
      ("candidate_emrt_020", resolve_repo_path(repo, wf003_candidate_manifest)),
   ]
   if include_wf002_controls:
      manifests_to_run.extend(
         [
            ("wf002_baseline_emrt_000", resolve_repo_path(repo, wf002_baseline_manifest)),
            ("wf002_candidate_emrt_020", resolve_repo_path(repo, wf002_candidate_manifest)),
         ]
      )

   rerun_results = rerun_specs(repo, runner_output_dir, manifests_to_run)
   rerun_manifests = {run_id: Path(result["manifest_path"]) for run_id, result in rerun_results.items()}
   rerun_summaries = {
      run_id: load_json(Path(load_json(manifest_path)["collected_summary"]))
      for run_id, manifest_path in rerun_manifests.items()
   }

   guards = {
      run_id: build_metric_guard(run_id, rerun_summaries[run_id], EXPECTED_WF003_METRICS[run_id])
      for run_id in ("baseline_emrt_000", "candidate_emrt_020")
   }
   failed_guards = [run_id for run_id, guard in guards.items() if not guard["passed"]]
   if failed_guards:
      raise RuntimeError(
         "Telemetry-only guard failed; rerun summary metrics changed: "
         + ", ".join(failed_guards)
      )

   baseline_rows = build_precision_rows(
      "baseline_emrt_000",
      "wf003 baseline MR_EMRTWeight=0.0",
      load_manifest_candidates(rerun_manifests["baseline_emrt_000"]),
   )
   candidate_rows = build_precision_rows(
      "candidate_emrt_020",
      "wf003 candidate MR_EMRTWeight=0.2",
      load_manifest_candidates(rerun_manifests["candidate_emrt_020"]),
   )

   baseline_bundle = rl_diag.load_run_bundle(rerun_manifests["baseline_emrt_000"], "precision_baseline", "wf003 baseline")
   candidate_bundle = rl_diag.load_run_bundle(rerun_manifests["candidate_emrt_020"], "precision_candidate", "wf003 candidate")
   paired_rows = pair_precision_lineages("wf003_202510", baseline_bundle, candidate_bundle)
   failure_slice_rows = build_failure_slice_rows(paired_rows)

   prior_floor_summary = load_json(resolve_repo_path(repo, prior_floor_summary_path))
   prior_rl_summary = load_json(resolve_repo_path(repo, prior_rl_summary_path))
   prior_spread_summary = load_json(resolve_repo_path(repo, prior_spread_summary_path))

   window_config = rl_diag.WindowConfig(
      id="wf003_202510",
      label="Report wf003_202510",
      candidate_manifest=rerun_manifests["candidate_emrt_020"],
      baseline_manifest=rerun_manifests["baseline_emrt_000"],
      is_holdout=False,
   )
   rl_meta_rows, rl_lineage_rows = rl_diag.pair_window_lineages(
      "wf003_202510",
      baseline_bundle,
      candidate_bundle,
   )
   current_window_summary = rl_diag.summarize_window(
      window_config,
      baseline_bundle,
      candidate_bundle,
      rl_meta_rows,
      rl_lineage_rows,
   )
   prior_window_summary = prior_rl_summary["windows"]["wf003_202510"]["lineage_effects"]

   baseline_zero_summary = build_zero_summary(baseline_rows)
   candidate_zero_summary = build_zero_summary(candidate_rows)
   failure_slice_summary = summarize_failure_slice(failure_slice_rows)
   conclusion = build_intervention_call(failure_slice_summary, current_window_summary["lineage_effects"])

   summary = {
      "generated_at_utc": iso_utc_now(),
      "artifacts": {
         "plan": str(resolve_repo_path(repo, plan_path)),
         "prior_floor_summary": str(resolve_repo_path(repo, prior_floor_summary_path)),
         "prior_rl_summary": str(resolve_repo_path(repo, prior_rl_summary_path)),
         "prior_spread_summary": str(resolve_repo_path(repo, prior_spread_summary_path)),
      },
      "reruns": {
         run_id: {
            "status": rerun_results[run_id]["status"],
            "manifest_path": str(rerun_manifests[run_id]),
            "summary_path": str(load_json(rerun_manifests[run_id])["collected_summary"]),
            "guard": guards[run_id] if run_id in guards else None,
         }
         for run_id in rerun_manifests
      },
      "wf003": {
         "baseline_zero_rows": baseline_zero_summary,
         "candidate_zero_rows": candidate_zero_summary,
         "failure_slice": failure_slice_summary,
         "replacement_churn": {
            "current_lost_trade_reason_counts": current_window_summary["lineage_effects"]["lost_trade_reason_counts"],
            "current_gained_trade_reason_counts": current_window_summary["lineage_effects"]["gained_trade_reason_counts"],
            "current_zero_cliff_count": current_window_summary["lineage_effects"]["zero_cliff_count"],
            "current_rounded_down_count": current_window_summary["lineage_effects"]["rounded_down_count"],
            "prior_lost_trade_reason_counts": prior_window_summary["lost_trade_reason_counts"],
            "prior_gained_trade_reason_counts": prior_window_summary["gained_trade_reason_counts"],
            "prior_zero_cliff_count": prior_window_summary["zero_cliff_count"],
            "prior_rounded_down_count": prior_window_summary["rounded_down_count"],
            "replacement_conclusion_unchanged": (
               current_window_summary["lineage_effects"]["lost_trade_reason_counts"] == prior_window_summary["lost_trade_reason_counts"]
               and current_window_summary["lineage_effects"]["gained_trade_reason_counts"] == prior_window_summary["gained_trade_reason_counts"]
               and current_window_summary["lineage_effects"]["zero_cliff_count"] == prior_window_summary["zero_cliff_count"]
            ),
         },
      },
      "source_truth": {
         "prior_floor_recommendation": prior_floor_summary["recommendation"]["key_call"],
         "prior_spread_root_cause": prior_spread_summary["root_cause"]["primary_blocker"],
      },
      "conclusion": conclusion,
   }

   csv_outputs = {
      "precision_volume_rows": baseline_rows + candidate_rows,
      "zero_cause_breakdown": (
         build_zero_cause_breakdown_rows(baseline_rows, "wf003 baseline all zero rows")
         + build_zero_cause_breakdown_rows(candidate_rows, "wf003 candidate all zero rows")
         + build_zero_cause_breakdown_rows(
            [
               {
                  "floor_zero": True,
                  "volume_zero_subcause": row.get("candidate_volume_zero_subcause"),
               }
               for row in failure_slice_rows
            ],
            "wf003 failure slice",
         )
      ),
      "min_lot_gap_distribution": (
         build_gap_distribution_rows(baseline_rows, "wf003 baseline all zero rows")
         + build_gap_distribution_rows(candidate_rows, "wf003 candidate all zero rows")
         + failure_slice_summary["tolerance_bands"]
      ),
      "wf003_failure_slice_tolerance_bands": failure_slice_summary["tolerance_bands"],
      "wf003_failure_slice_rows": failure_slice_rows,
   }
   return summary, csv_outputs


def write_outputs(
   output_dir: Path,
   summary: dict[str, Any],
   csv_outputs: dict[str, list[dict[str, Any]]],
) -> dict[str, str]:
   output_dir.mkdir(parents=True, exist_ok=True)

   summary_path = output_dir / "precision_telemetry_summary.json"
   summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")

   report_path = output_dir / "precision_telemetry_report.md"
   report_path.write_text(build_markdown_report(summary), encoding="utf-8")

   precision_rows_path = output_dir / "precision_volume_rows.csv"
   write_csv(precision_rows_path, csv_outputs["precision_volume_rows"])

   zero_cause_path = output_dir / "zero_cause_breakdown.csv"
   write_csv(zero_cause_path, csv_outputs["zero_cause_breakdown"])

   gap_distribution_path = output_dir / "min_lot_gap_distribution.csv"
   write_csv(gap_distribution_path, csv_outputs["min_lot_gap_distribution"])

   tolerance_path = output_dir / "wf003_failure_slice_tolerance_bands.csv"
   write_csv(tolerance_path, csv_outputs["wf003_failure_slice_tolerance_bands"])

   failure_slice_path = output_dir / "wf003_failure_slice_rows.csv"
   write_csv(failure_slice_path, csv_outputs["wf003_failure_slice_rows"])

   return {
      "summary": str(summary_path),
      "report": str(report_path),
      "precision_volume_rows": str(precision_rows_path),
      "zero_cause_breakdown": str(zero_cause_path),
      "min_lot_gap_distribution": str(gap_distribution_path),
      "wf003_failure_slice_tolerance_bands": str(tolerance_path),
      "wf003_failure_slice_rows": str(failure_slice_path),
   }


def parse_args(argv: list[str]) -> argparse.Namespace:
   parser = argparse.ArgumentParser(description=__doc__)
   parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
   parser.add_argument("--runner-output-dir", type=Path, default=DEFAULT_RUNNER_OUTPUT_DIR)
   parser.add_argument("--plan-path", type=Path, default=DEFAULT_PLAN_PATH)
   parser.add_argument("--prior-floor-summary-path", type=Path, default=DEFAULT_PRIOR_FLOOR_SUMMARY_PATH)
   parser.add_argument("--prior-rl-summary-path", type=Path, default=DEFAULT_PRIOR_RL_SUMMARY_PATH)
   parser.add_argument("--prior-spread-summary-path", type=Path, default=DEFAULT_PRIOR_SPREAD_SUMMARY_PATH)
   parser.add_argument("--wf003-baseline-manifest", type=Path, default=DEFAULT_WF003_BASELINE_MANIFEST)
   parser.add_argument("--wf003-candidate-manifest", type=Path, default=DEFAULT_WF003_CANDIDATE_MANIFEST)
   parser.add_argument("--include-wf002-controls", action="store_true")
   parser.add_argument("--wf002-baseline-manifest", type=Path, default=DEFAULT_WF002_BASELINE_MANIFEST)
   parser.add_argument("--wf002-candidate-manifest", type=Path, default=DEFAULT_WF002_CANDIDATE_MANIFEST)
   return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
   args = parse_args(argv if argv is not None else sys.argv[1:])
   repo = repo_root()
   summary, csv_outputs = build_summary(
      repo=repo,
      plan_path=args.plan_path,
      prior_floor_summary_path=args.prior_floor_summary_path,
      prior_rl_summary_path=args.prior_rl_summary_path,
      prior_spread_summary_path=args.prior_spread_summary_path,
      runner_output_dir=resolve_repo_path(repo, args.runner_output_dir),
      wf003_baseline_manifest=args.wf003_baseline_manifest,
      wf003_candidate_manifest=args.wf003_candidate_manifest,
      include_wf002_controls=args.include_wf002_controls,
      wf002_baseline_manifest=args.wf002_baseline_manifest,
      wf002_candidate_manifest=args.wf002_candidate_manifest,
   )
   outputs = write_outputs(resolve_repo_path(repo, args.output_dir), summary, csv_outputs)
   print(json.dumps(outputs, indent=2, sort_keys=True))
   return 0


if __name__ == "__main__":  # pragma: no cover
   raise SystemExit(main())
