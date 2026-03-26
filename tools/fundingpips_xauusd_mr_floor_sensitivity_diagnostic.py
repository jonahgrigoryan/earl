#!/usr/bin/env python3
"""Diagnose XAUUSD MR lot-floor sensitivity from existing artifacts."""

from __future__ import annotations

import argparse
import csv
import dataclasses
import json
import math
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

try:
   from tools import fundingpips_phase_a_research as phase_a
except ModuleNotFoundError:  # pragma: no cover - script execution fallback
   sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
   from tools import fundingpips_phase_a_research as phase_a


DEFAULT_OUTPUT_DIR = (
   Path(".tmp")
   / "fundingpips_xauusd_mr_floor_sensitivity_diagnostic"
   / "phasea_xauusd_mr_floor_sensitivity"
)

DEFAULT_PLAN_PATH = Path("docs") / "plans" / "PLAN_main.md"
DEFAULT_RESEARCH_SUMMARY_PATH = (
   Path(".tmp")
   / "fundingpips_phase_a_research"
   / "master_d0e5558_phase_a"
   / "research_attribution_summary.json"
)
DEFAULT_RESEARCH_CANDIDATES_PATH = (
   Path(".tmp")
   / "fundingpips_phase_a_research"
   / "master_d0e5558_phase_a"
   / "research_candidates.csv"
)
DEFAULT_SPREAD_DIAGNOSTIC_PATH = (
   Path(".tmp")
   / "fundingpips_wf003_spread_coverage_diagnostic"
   / "phasea_wf003_spread_coverage"
   / "diagnostic_summary.json"
)
DEFAULT_RL_DIAGNOSTIC_SUMMARY_PATH = (
   Path(".tmp")
   / "fundingpips_rl_emrt_sizing_diagnostic"
   / "phasea_rl_emrt_sizing"
   / "diagnostic_summary.json"
)
DEFAULT_RL_DIAGNOSTIC_REPORT_PATH = (
   Path(".tmp")
   / "fundingpips_rl_emrt_sizing_diagnostic"
   / "phasea_rl_emrt_sizing"
   / "diagnostic_report.md"
)
DEFAULT_RL_LINEAGE_CSV_PATH = (
   Path(".tmp")
   / "fundingpips_rl_emrt_sizing_diagnostic"
   / "phasea_rl_emrt_sizing"
   / "mr_lineage_sizing_comparison.csv"
)
DEFAULT_RL_NEAR_FLOOR_CSV_PATH = (
   Path(".tmp")
   / "fundingpips_rl_emrt_sizing_diagnostic"
   / "phasea_rl_emrt_sizing"
   / "near_floor_sizing.csv"
)

MIN_LOT = 0.01
LOT_STEP = 0.01
SAFE_ABOVE_FLOOR_VOLUME = 0.02
XAUUSD_POINT = 0.01


@dataclasses.dataclass(frozen=True)
class DatasetConfig:
   id: str
   label: str
   source_kind: str
   baseline_role: str | None = None
   manifest_path: Path | None = None
   phase_source: str = ""
   dataset_role: str = ""


def repo_root() -> Path:
   return Path(__file__).resolve().parents[1]


def resolve_repo_path(repo: Path, path: Path | str) -> Path:
   candidate = Path(path)
   return candidate if candidate.is_absolute() else (repo / candidate).resolve()


def iso_utc_now() -> str:
   return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> Any:
   return json.loads(path.read_text(encoding="utf-8"))


def load_csv_rows(path: Path) -> list[dict[str, Any]]:
   with path.open("r", encoding="utf-8", newline="") as handle:
      return list(csv.DictReader(handle))


def maybe_float(value: Any) -> float | None:
   if value in (None, "", "None"):
      return None
   if isinstance(value, (int, float)):
      return float(value)
   try:
      return float(str(value))
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


def distribution(values: Iterable[float | None]) -> dict[str, Any]:
   clean = [float(item) for item in values if item is not None and math.isfinite(float(item))]
   if not clean:
      return {
         "count": 0,
         "min": None,
         "p10": None,
         "median": None,
         "mean": None,
         "p90": None,
         "max": None,
      }
   ordered = sorted(clean)

   def pick(percentile: float) -> float:
      if len(ordered) == 1:
         return ordered[0]
      index = percentile * (len(ordered) - 1)
      lower = int(math.floor(index))
      upper = int(math.ceil(index))
      if lower == upper:
         return ordered[lower]
      ratio = index - lower
      return ordered[lower] * (1.0 - ratio) + ordered[upper] * ratio

   return {
      "count": len(ordered),
      "min": round(ordered[0], 6),
      "p10": round(pick(0.10), 6),
      "median": round(statistics.median(ordered), 6),
      "mean": round(statistics.fmean(ordered), 6),
      "p90": round(pick(0.90), 6),
      "max": round(ordered[-1], 6),
   }


def compute_stop_distance_points(entry_price: float | None, sl_price: float | None) -> float | None:
   if entry_price is None or sl_price is None:
      return None
   if not math.isfinite(entry_price) or not math.isfinite(sl_price):
      return None
   return abs(entry_price - sl_price) / XAUUSD_POINT


def classify_stop_distance_bucket(points: float | None) -> str:
   if points is None:
      return "unknown"
   if points < 3000.0:
      return "<3000_pts"
   if points < 4500.0:
      return "3000-4499_pts"
   if points < 5500.0:
      return "4500-5499_pts"
   return ">=5500_pts"


def classify_floor_margin_band(raw_volume: float | None) -> str:
   if raw_volume is None:
      return "unknown"
   if raw_volume < MIN_LOT:
      return "below_floor"
   ratio = raw_volume / MIN_LOT
   if ratio < 1.05:
      return "0-5pct_above_floor"
   if ratio < 1.25:
      return "5-25pct_above_floor"
   if ratio < 2.0:
      return "25-100pct_above_floor"
   return ">=100pct_above_floor"


def classify_candidate_bucket(
   raw_volume: float | None,
   final_volume: float | None,
   rejection_reason: str,
) -> str:
   if rejection_reason == "position_caps":
      return "position_caps"
   if rejection_reason == "volume_zero":
      return "rounded_to_0.00"
   if rejection_reason:
      return f"reject_{rejection_reason}"
   if final_volume is not None and final_volume <= 0.0:
      return "rounded_to_0.00"
   if final_volume is not None and final_volume >= SAFE_ABOVE_FLOOR_VOLUME - 1e-9:
      return "safe_above_floor"
   if final_volume is not None and abs(final_volume - MIN_LOT) < 1e-9:
      return "near_floor_0.01"
   if raw_volume is not None and raw_volume >= MIN_LOT:
      return "nonstandard_valid"
   return "other"


def quantization_kind(raw_volume: float | None, final_volume: float | None, rejection_reason: str) -> str:
   if raw_volume is None:
      return "unknown"
   if rejection_reason == "position_caps":
      return "blocked_by_position_caps"
   if rejection_reason == "volume_zero":
      return "quantized_to_zero"
   if final_volume is not None and final_volume <= 0.0:
      return "quantized_to_zero"
   if final_volume is not None and abs(final_volume - MIN_LOT) < 1e-9 and raw_volume > MIN_LOT:
      return "quantized_to_min_lot"
   if final_volume is not None and abs(final_volume - raw_volume) > 1e-9:
      return "quantized_other"
   return "no_quantization_change"


def overshoot_to_min_lot_pct(raw_volume: float | None) -> float | None:
   if raw_volume is None or raw_volume <= 0.0 or raw_volume >= MIN_LOT:
      return None
   return ((MIN_LOT / raw_volume) - 1.0) * 100.0


def normalize_candidate_row(
   dataset: DatasetConfig,
   source_row: dict[str, Any],
) -> dict[str, Any]:
   raw_volume = maybe_float(source_row.get("risk_raw_volume"))
   final_volume = maybe_float(source_row.get("volume"))
   rejection_reason = str(source_row.get("rejection_reason") or "")
   entry_price = maybe_float(source_row.get("requested_entry_price"))
   sl_price = maybe_float(source_row.get("sl"))
   stop_points = compute_stop_distance_points(entry_price, sl_price)
   current_quantization = quantization_kind(raw_volume, final_volume, rejection_reason)
   return {
      "dataset_id": dataset.id,
      "dataset_label": dataset.label,
      "phase_source": dataset.phase_source,
      "dataset_role": dataset.dataset_role,
      "decision_ts": str(source_row.get("decision_ts") or ""),
      "decision_date": str(source_row.get("decision_ts") or "")[:10],
      "decision_hour": str(source_row.get("decision_ts") or "")[11:13],
      "symbol": str(source_row.get("symbol") or ""),
      "strategy": str(source_row.get("strategy") or ""),
      "plan_valid": bool(maybe_bool(source_row.get("plan_valid"))),
      "place_ok": bool(maybe_bool(source_row.get("place_ok"))),
      "order_sent": bool(maybe_bool(source_row.get("order_sent"))),
      "rejection_reason": rejection_reason,
      "raw_volume": raw_volume,
      "final_volume": final_volume,
      "effective_risk_pct": maybe_float(source_row.get("effective_risk_pct")),
      "meta_confidence": maybe_float(source_row.get("meta_confidence")),
      "regime": str(source_row.get("meta_regime") or ""),
      "entry_price": entry_price,
      "sl_price": sl_price,
      "tp_price": maybe_float(source_row.get("tp")),
      "stop_distance_points": stop_points,
      "stop_distance_bucket": classify_stop_distance_bucket(stop_points),
      "floor_margin_band": classify_floor_margin_band(raw_volume),
      "bucket": classify_candidate_bucket(raw_volume, final_volume, rejection_reason),
      "quantization_kind": current_quantization,
      "quantized": current_quantization != "no_quantization_change",
      "overshoot_to_min_lot_pct": overshoot_to_min_lot_pct(raw_volume),
      "margin_to_floor": None if raw_volume is None else raw_volume - MIN_LOT,
   }


def build_run_input(manifest_path: Path, run_id: str, baseline_role: str) -> phase_a.PhaseARunInput:
   manifest = load_json(manifest_path)
   return phase_a.PhaseARunInput(
      id=run_id,
      baseline_role=baseline_role,
      root=manifest_path.parent,
      manifest_path=manifest_path,
      summary_path=Path(manifest["collected_summary"]),
      daily_path=Path(manifest["collected_daily"]),
      report_path=Path(manifest["collected_report"]),
      decision_log_paths=tuple(Path(item) for item in manifest.get("collected_decision_logs", [])),
      event_log_paths=tuple(Path(item) for item in manifest.get("collected_event_logs", [])),
   )


def load_report_manifest_candidates(
   manifest_path: Path,
   dataset: DatasetConfig,
) -> list[dict[str, Any]]:
   run_input = build_run_input(manifest_path, dataset.id, dataset.dataset_role or dataset.id)
   decision_rows = phase_a.parse_decision_logs(run_input)
   event_rows = phase_a.parse_event_logs(run_input)
   candidates = phase_a.build_candidates(decision_rows, event_rows)
   return [
      normalize_candidate_row(dataset, row)
      for row in candidates
      if row.get("symbol") == "XAUUSD" and row.get("strategy") == "MR"
   ]


def load_official_phase_a_candidates(
   research_candidates_path: Path,
   datasets: list[DatasetConfig],
) -> dict[str, list[dict[str, Any]]]:
   dataset_by_role = {item.baseline_role: item for item in datasets if item.baseline_role}
   results: defaultdict[str, list[dict[str, Any]]] = defaultdict(list)
   with research_candidates_path.open("r", encoding="utf-8", newline="") as handle:
      reader = csv.DictReader(handle)
      for row in reader:
         dataset = dataset_by_role.get(row.get("baseline_role"))
         if dataset is None:
            continue
         if row.get("symbol") != "XAUUSD" or row.get("strategy") != "MR":
            continue
         results[dataset.id].append(normalize_candidate_row(dataset, row))
   return dict(results)


def load_report_datasets(
   repo: Path,
   rl_diagnostic_summary: dict[str, Any],
) -> list[DatasetConfig]:
   return [
      DatasetConfig(
         id="wf001_202508",
         label="Report wf001_202508 baseline",
         source_kind="manifest",
         manifest_path=resolve_repo_path(repo, rl_diagnostic_summary["windows"]["wf001_202508"]["baseline"]["manifest_path"]),
         phase_source="Validation context",
         dataset_role="report_baseline",
      ),
      DatasetConfig(
         id="wf002_202509",
         label="Report wf002_202509 baseline",
         source_kind="manifest",
         manifest_path=resolve_repo_path(repo, rl_diagnostic_summary["windows"]["wf002_202509"]["baseline"]["manifest_path"]),
         phase_source="Validation context",
         dataset_role="report_baseline",
      ),
      DatasetConfig(
         id="wf003_202510",
         label="Report wf003_202510 baseline",
         source_kind="manifest",
         manifest_path=resolve_repo_path(repo, rl_diagnostic_summary["windows"]["wf003_202510"]["baseline"]["manifest_path"]),
         phase_source="Validation context",
         dataset_role="report_baseline",
      ),
   ]


def build_dataset_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
   bucket_counts = Counter(row["bucket"] for row in rows)
   quantization_counts = Counter(row["quantization_kind"] for row in rows)
   rejection_counts = Counter(row["rejection_reason"] for row in rows if row["rejection_reason"])
   regime_bucket_counts = Counter((row["regime"], row["bucket"]) for row in rows)
   stop_bucket_counts = Counter((row["stop_distance_bucket"], row["bucket"]) for row in rows)
   floor_band_counts = Counter(row["floor_margin_band"] for row in rows)

   executed_rows = [row for row in rows if row["place_ok"]]
   executed_bucket_counts = Counter(row["bucket"] for row in executed_rows)
   executed_floor_band_counts = Counter(row["floor_margin_band"] for row in executed_rows)

   zero_rows = [row for row in rows if row["bucket"] == "rounded_to_0.00"]
   valid_rows = [row for row in rows if row["plan_valid"]]

   return {
      "candidate_count": len(rows),
      "plan_valid_count": len(valid_rows),
      "place_ok_count": len(executed_rows),
      "bucket_counts": dict(bucket_counts),
      "bucket_shares": {
         key: round(value / len(rows), 6)
         for key, value in bucket_counts.items()
      } if rows else {},
      "executed_bucket_counts": dict(executed_bucket_counts),
      "executed_bucket_shares": {
         key: round(value / len(executed_rows), 6)
         for key, value in executed_bucket_counts.items()
      } if executed_rows else {},
      "quantization_counts": dict(quantization_counts),
      "rejection_reason_counts": dict(rejection_counts),
      "floor_margin_band_counts": dict(floor_band_counts),
      "executed_floor_margin_band_counts": dict(executed_floor_band_counts),
      "raw_volume": distribution(row["raw_volume"] for row in rows),
      "executed_raw_volume": distribution(row["raw_volume"] for row in executed_rows),
      "executed_stop_distance_points": distribution(row["stop_distance_points"] for row in executed_rows),
      "zero_stop_distance_points": distribution(row["stop_distance_points"] for row in zero_rows),
      "zero_overshoot_to_min_lot_pct": distribution(row["overshoot_to_min_lot_pct"] for row in zero_rows),
      "executed_min_lot_share": round(
         executed_bucket_counts.get("near_floor_0.01", 0) / len(executed_rows),
         6,
      ) if executed_rows else None,
      "zero_share_of_candidates": round(
         bucket_counts.get("rounded_to_0.00", 0) / len(rows),
         6,
      ) if rows else None,
      "regime_bucket_counts": {
         f"{regime}|{bucket}": count
         for (regime, bucket), count in sorted(regime_bucket_counts.items())
      },
      "stop_bucket_counts": {
         f"{stop_bucket}|{bucket}": count
         for (stop_bucket, bucket), count in sorted(stop_bucket_counts.items())
      },
   }


def build_window_bucket_rows(
   datasets: list[DatasetConfig],
   summaries: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
   output: list[dict[str, Any]] = []
   for dataset in datasets:
      summary = summaries[dataset.id]
      output.append(
         {
            "dataset_id": dataset.id,
            "dataset_label": dataset.label,
            "phase_source": dataset.phase_source,
            "dataset_role": dataset.dataset_role,
            "candidate_count": summary["candidate_count"],
            "plan_valid_count": summary["plan_valid_count"],
            "place_ok_count": summary["place_ok_count"],
            "safe_above_floor_count": summary["bucket_counts"].get("safe_above_floor", 0),
            "near_floor_0_01_count": summary["bucket_counts"].get("near_floor_0.01", 0),
            "rounded_to_0_00_count": summary["bucket_counts"].get("rounded_to_0.00", 0),
            "position_caps_count": summary["bucket_counts"].get("position_caps", 0),
            "executed_min_lot_share": summary["executed_min_lot_share"],
            "zero_share_of_candidates": summary["zero_share_of_candidates"],
            "executed_raw_min": summary["executed_raw_volume"]["min"],
            "executed_raw_median": summary["executed_raw_volume"]["median"],
            "executed_raw_max": summary["executed_raw_volume"]["max"],
            "executed_stop_points_median": summary["executed_stop_distance_points"]["median"],
         }
      )
   return output


def build_regime_bucket_rows(rows_by_dataset: dict[str, list[dict[str, Any]]]) -> list[dict[str, Any]]:
   output: list[dict[str, Any]] = []
   for dataset_id, rows in rows_by_dataset.items():
      counter = Counter((row["regime"] or "UNKNOWN", row["bucket"]) for row in rows)
      for (regime, bucket), count in sorted(counter.items()):
         output.append(
            {
               "dataset_id": dataset_id,
               "regime": regime,
               "bucket": bucket,
               "count": count,
            }
         )
   return output


def build_wf003_zero_tolerance_rows(wf003_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
   zero_rows = [row for row in wf003_rows if row["bucket"] == "rounded_to_0.00" and row["raw_volume"] is not None]
   if not zero_rows:
      return []

   bands = [
      ("<=1pct_overshoot", 1.0),
      ("<=2pct_overshoot", 2.0),
      ("<=5pct_overshoot", 5.0),
      ("<=10pct_overshoot", 10.0),
      ("<=20pct_overshoot", 20.0),
      ("<=30pct_overshoot", 30.0),
   ]
   output: list[dict[str, Any]] = []
   for label, threshold in bands:
      matched = [
         row
         for row in zero_rows
         if row["overshoot_to_min_lot_pct"] is not None and row["overshoot_to_min_lot_pct"] <= threshold
      ]
      output.append(
         {
            "threshold_label": label,
            "max_overshoot_to_min_lot_pct": threshold,
            "count": len(matched),
            "share_of_wf003_zero_rows": round(len(matched) / len(zero_rows), 6),
            "raw_volume_min": round_or_none(min((row["raw_volume"] for row in matched), default=None), 4),
            "raw_volume_median": round_or_none(statistics.median(row["raw_volume"] for row in matched), 4) if matched else None,
            "raw_volume_max": round_or_none(max((row["raw_volume"] for row in matched), default=None), 4),
         }
      )
   return output


def build_replacement_rows(rl_lineage_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
   output: list[dict[str, Any]] = []
   for row in rl_lineage_rows:
      if row.get("window_id") != "wf003_202510":
         continue
      if not (
         maybe_bool(row.get("lost_baseline_trade"))
         or maybe_bool(row.get("gained_candidate_trade"))
         or maybe_bool(row.get("rounded_down"))
         or maybe_bool(row.get("zero_cliff"))
      ):
         continue
      output.append(
         {
            "decision_ts": row.get("decision_ts"),
            "decision_hour": row.get("decision_hour"),
            "symbol": row.get("symbol"),
            "regime": row.get("regime"),
            "divergence_stage": row.get("divergence_stage"),
            "divergence_reason": row.get("divergence_reason"),
            "lost_baseline_trade": row.get("lost_baseline_trade"),
            "gained_candidate_trade": row.get("gained_candidate_trade"),
            "zero_cliff": row.get("zero_cliff"),
            "rounded_down": row.get("rounded_down"),
            "baseline_raw_volume": row.get("baseline_raw_volume"),
            "candidate_raw_volume": row.get("candidate_raw_volume"),
            "raw_volume_delta": row.get("raw_volume_delta"),
            "baseline_final_volume": row.get("baseline_final_volume"),
            "candidate_final_volume": row.get("candidate_final_volume"),
            "baseline_rejection_reason": row.get("baseline_rejection_reason"),
            "candidate_rejection_reason": row.get("candidate_rejection_reason"),
         }
      )
   return output


def build_runtime_path() -> list[dict[str, Any]]:
   return [
      {
         "stage": "scheduler_handoff",
         "file": "MQL5/Include/RPEA/scheduler.mqh",
         "line": 343,
         "detail": "Scheduler hands MR `slPoints`, `tpPoints`, and `conf` into `Allocator_BuildOrderPlan()` before any placement call.",
      },
      {
         "stage": "contract_metadata",
         "file": "MQL5/Include/RPEA/allocator.mqh",
         "line": 41,
         "detail": "Allocator loads `SYMBOL_POINT`, `SYMBOL_TRADE_TICK_SIZE`, `SYMBOL_TRADE_TICK_VALUE`, and digits via `Allocator_GetContractDetails()`.",
      },
      {
         "stage": "risk_inputs",
         "file": "MQL5/Include/RPEA/risk.mqh",
         "line": 59,
         "detail": "Risk sizing converts confidence-scaled risk money into raw lots using `OrderCalcProfit()` and symbol `SYMBOL_VOLUME_MIN/MAX/STEP` metadata.",
      },
      {
         "stage": "step_floor",
         "file": "MQL5/Include/RPEA/risk.mqh",
         "line": 9,
         "detail": "`Risk_FloorToStep()` uses `MathFloor(value / step)`; this is the primary quantization entry point.",
      },
      {
         "stage": "min_lot_zero",
         "file": "MQL5/Include/RPEA/risk.mqh",
         "line": 139,
         "detail": "If floored volume falls below `SYMBOL_VOLUME_MIN`, risk sizing sets volume to `0.0`; the margin loop can also step volume down to `0.0` later.",
      },
      {
         "stage": "allocator_reject",
         "file": "MQL5/Include/RPEA/allocator.mqh",
         "line": 498,
         "detail": "Allocator converts any non-positive sized volume into `rejection = volume_zero` before `PlaceOrder()` is reached.",
      },
      {
         "stage": "budget_secondary_floor",
         "file": "MQL5/Include/RPEA/allocator.mqh",
         "line": 543,
         "detail": "Budget headroom scaling floors the downscaled volume to `SYMBOL_VOLUME_STEP` and zeroes it again if the result drops below `SYMBOL_VOLUME_MIN`.",
      },
      {
         "stage": "placement_normalization_secondary",
         "file": "MQL5/Include/RPEA/order_engine.mqh",
         "line": 5532,
         "detail": "`OE_NormalizeVolume()` re-normalizes to broker step using nearest-step `MathRound`; this is secondary here because `volume_zero` rows never reach placement.",
      },
   ]


def build_prior_truth_summary(
   research_summary: dict[str, Any],
   spread_summary: dict[str, Any],
   rl_summary: dict[str, Any],
) -> dict[str, Any]:
   return {
      "phase_a_ranked_levers": [item["title"] for item in research_summary.get("recommended_changes", [])],
      "spread_root_cause": spread_summary.get("root_cause", {}),
      "spread_recommendation": spread_summary.get("recommendation", {}),
      "rl_root_cause": rl_summary.get("root_cause", {}),
      "rl_recommendation": rl_summary.get("recommendation", {}),
   }


def build_aggregate_summary(dataset_summaries: dict[str, dict[str, Any]]) -> dict[str, Any]:
   holdout = dataset_summaries["holdout"]
   contiguous = dataset_summaries["contiguous_public_rule3"]
   wf001 = dataset_summaries["wf001_202508"]
   wf002 = dataset_summaries["wf002_202509"]
   wf003 = dataset_summaries["wf003_202510"]
   return {
      "general_floor_dependence": {
         "holdout_executed_min_lot_share": holdout["executed_min_lot_share"],
         "contiguous_executed_min_lot_share": contiguous["executed_min_lot_share"],
         "wf001_executed_min_lot_share": wf001["executed_min_lot_share"],
         "wf002_executed_min_lot_share": wf002["executed_min_lot_share"],
         "wf003_executed_min_lot_share": wf003["executed_min_lot_share"],
      },
      "hard_zero_cliff": {
         "holdout_zero_share_of_candidates": holdout["zero_share_of_candidates"],
         "contiguous_zero_share_of_candidates": contiguous["zero_share_of_candidates"],
         "wf001_zero_share_of_candidates": wf001["zero_share_of_candidates"],
         "wf002_zero_share_of_candidates": wf002["zero_share_of_candidates"],
         "wf003_zero_share_of_candidates": wf003["zero_share_of_candidates"],
      },
      "concentration_call": (
         "General XAUUSD MR execution is often quantized to 0.01, but the true `volume_zero` cliff is concentrated in the `wf003_202510` volatile ~6101-point stop slice rather than across the full XAUUSD MR book."
      ),
   }


def build_session_evidence(spread_summary: dict[str, Any]) -> dict[str, Any]:
   baseline_place_ok = spread_summary.get("baseline_place_ok", {})
   return {
      "report_window_slice": "wf003_202510",
      "baseline_place_ok_session_counts": baseline_place_ok.get("session_counts", {}),
      "baseline_place_ok_regime_counts": baseline_place_ok.get("regime_counts", {}),
      "candidate_outcomes": baseline_place_ok.get("candidate_outcomes", {}),
      "interpretation": (
         "Session concentration is proven in the merged spread diagnostic: the hard `volume_zero` cliff lives inside the XAUUSD `LO+NY` volatile execution slice for `wf003_202510`."
      ),
   }


def build_replacement_summary(rl_summary: dict[str, Any]) -> dict[str, Any]:
   wf003 = rl_summary["windows"]["wf003_202510"]["lineage_effects"]
   return {
      "window_id": "wf003_202510",
      "lost_trade_reason_counts": wf003["lost_trade_reason_counts"],
      "gained_trade_reason_counts": wf003["gained_trade_reason_counts"],
      "divergence_reason_counts": wf003["divergence_reason_counts"],
      "lost_trade_hour_counts": wf003["lost_trade_hour_counts"],
      "rounded_down_count": wf003["rounded_down_count"],
      "zero_cliff_count": wf003["zero_cliff_count"],
      "interpretation": (
         "Replacement behavior is cap-coupled: tiny raw-volume drops kick baseline floor-sized executions out as `candidate_volume_zero`, and the freed position-cap slots are then reused by replacement lineages later in the same report window."
      ),
   }


def build_recommendation(
   dataset_summaries: dict[str, dict[str, Any]],
   wf003_zero_tolerance_rows: list[dict[str, Any]],
) -> dict[str, Any]:
   holdout = dataset_summaries["holdout"]
   wf003 = dataset_summaries["wf003_202510"]
   within_5pct = next(
      (row for row in wf003_zero_tolerance_rows if row["threshold_label"] == "<=5pct_overshoot"),
      None,
   )
   within_10pct = next(
      (row for row in wf003_zero_tolerance_rows if row["threshold_label"] == "<=10pct_overshoot"),
      None,
   )

   return {
      "behavior_change_branch_justified": False,
      "follow_up_branch_justified": True,
      "exact_next_branch": "codex/xauusd-mr-floor-precision-telemetry",
      "intervention_class": "safer_floor_aware_sizing_diagnostics_and_rejection_classification",
      "why_not_behavior_change_yet": (
         "A generic round-up or min-lot rescue rule is not narrow enough on current evidence. `wf003_202510` zero rows span roughly 0.0071-0.0100 raw lots, so the broad below-floor population would require about 2% to 41% risk overshoot to force 0.01 lots."
      ),
      "why_follow_up_branch_is_still_worth_it": (
         "The cliff is real and narrow in the executable slice, but the current logs only preserve `raw_volume` to 4 decimals and collapse distinct failure modes into `volume_zero`. A tiny telemetry/classification branch can expose the exact sub-step gap to 0.01 and tell us whether any later rounding/intervention can be scoped safely."
      ),
      "minimum_scope": [
         "Log pre-step `raw_volume` and post-step `floored_volume` to at least 8 decimals in `Risk.SIZING`.",
         "Log `SYMBOL_VOLUME_MIN`, `SYMBOL_VOLUME_STEP`, and the fractional gap to the min lot.",
         "Split `volume_zero` into `below_min_after_step`, `below_min_after_margin`, and `below_min_after_budget`.",
         "Preserve the existing runtime behavior; do not change sizing or rounding in the same branch.",
      ],
      "tolerance_guardrails": {
         "<=5pct_overshoot_share_of_wf003_zero_rows": None if within_5pct is None else within_5pct["share_of_wf003_zero_rows"],
         "<=10pct_overshoot_share_of_wf003_zero_rows": None if within_10pct is None else within_10pct["share_of_wf003_zero_rows"],
      },
      "key_call": (
         "Do not open a rounding/size-behavior branch yet. Open one narrow precision-telemetry branch instead, then decide whether a min-lot rescue rule is truly narrow or just a hidden risk expansion."
      ),
      "architecture_locally_exhausted": False,
      "if_rejected_then_close_path": (
         "If higher-precision telemetry shows the candidate zero rows are not tightly clustered just below 0.01, close the path instead of testing a broad rescue rule."
      ),
      "supporting_context": {
         "holdout_executed_min_lot_share": holdout["executed_min_lot_share"],
         "wf003_executed_min_lot_share": wf003["executed_min_lot_share"],
         "wf003_zero_share_of_candidates": wf003["zero_share_of_candidates"],
      },
   }


def build_summary(
   repo: Path,
   plan_path: Path,
   research_summary_path: Path,
   research_candidates_path: Path,
   spread_diagnostic_path: Path,
   rl_diagnostic_summary_path: Path,
   rl_diagnostic_report_path: Path,
   rl_lineage_csv_path: Path,
   rl_near_floor_csv_path: Path,
) -> tuple[dict[str, Any], dict[str, list[dict[str, Any]]]]:
   plan_resolved = resolve_repo_path(repo, plan_path)
   research_summary_resolved = resolve_repo_path(repo, research_summary_path)
   research_candidates_resolved = resolve_repo_path(repo, research_candidates_path)
   spread_diagnostic_resolved = resolve_repo_path(repo, spread_diagnostic_path)
   rl_diagnostic_summary_resolved = resolve_repo_path(repo, rl_diagnostic_summary_path)
   rl_diagnostic_report_resolved = resolve_repo_path(repo, rl_diagnostic_report_path)
   rl_lineage_csv_resolved = resolve_repo_path(repo, rl_lineage_csv_path)
   rl_near_floor_csv_resolved = resolve_repo_path(repo, rl_near_floor_csv_path)

   research_summary = load_json(research_summary_resolved)
   spread_summary = load_json(spread_diagnostic_resolved)
   rl_summary = load_json(rl_diagnostic_summary_resolved)
   rl_lineage_rows = load_csv_rows(rl_lineage_csv_resolved)
   rl_near_floor_rows = load_csv_rows(rl_near_floor_csv_resolved)

   official_datasets = [
      DatasetConfig(
         id="holdout",
         label="Official holdout",
         source_kind="research_candidates",
         baseline_role="holdout_primary_truth",
         phase_source="Phase A primary truth",
         dataset_role="holdout_primary_truth",
      ),
      DatasetConfig(
         id="contiguous_public_rule3",
         label="Official contiguous public-rule3",
         source_kind="research_candidates",
         baseline_role="contiguous_public_rule3_secondary_corroboration",
         phase_source="Phase A corroboration",
         dataset_role="contiguous_public_rule3_secondary_corroboration",
      ),
   ]
   report_datasets = load_report_datasets(repo, rl_summary)
   datasets = official_datasets + report_datasets

   rows_by_dataset = load_official_phase_a_candidates(research_candidates_resolved, official_datasets)
   for dataset in report_datasets:
      rows_by_dataset[dataset.id] = load_report_manifest_candidates(dataset.manifest_path, dataset)

   dataset_summaries = {
      dataset.id: build_dataset_summary(rows_by_dataset[dataset.id])
      for dataset in datasets
   }

   wf003_zero_tolerance_rows = build_wf003_zero_tolerance_rows(rows_by_dataset["wf003_202510"])
   replacement_rows = build_replacement_rows(rl_lineage_rows)
   summary = {
      "generated_at_utc": iso_utc_now(),
      "artifacts": {
         "plan": str(plan_resolved),
         "research_attribution_summary": str(research_summary_resolved),
         "research_candidates": str(research_candidates_resolved),
         "spread_diagnostic_summary": str(spread_diagnostic_resolved),
         "rl_diagnostic_summary": str(rl_diagnostic_summary_resolved),
         "rl_diagnostic_report": str(rl_diagnostic_report_resolved),
         "rl_lineage_sizing_comparison": str(rl_lineage_csv_resolved),
         "rl_near_floor_sizing": str(rl_near_floor_csv_resolved),
      },
      "source_truth": {
         "plan_path": str(plan_resolved),
         "diagnostic_first_branch": True,
         "no_broad_new_lever_search": True,
      },
      "prior_truth": build_prior_truth_summary(research_summary, spread_summary, rl_summary),
      "runtime_path": build_runtime_path(),
      "datasets": dataset_summaries,
      "aggregate": build_aggregate_summary(dataset_summaries),
      "session_evidence": build_session_evidence(spread_summary),
      "replacement_lineage_evidence": build_replacement_summary(rl_summary),
      "wf003_zero_tolerance": {
         "rows": wf003_zero_tolerance_rows,
         "note": (
            "These tolerance shares are approximate upper bounds because the current `Risk.SIZING` log rounds `raw_volume` to 4 decimals."
         ),
      },
      "recommendation": build_recommendation(dataset_summaries, wf003_zero_tolerance_rows),
   }

   csv_outputs = {
      "window_bucket_summary": build_window_bucket_rows(datasets, dataset_summaries),
      "regime_bucket_summary": build_regime_bucket_rows(rows_by_dataset),
      "replacement_lineage_summary": replacement_rows,
      "wf003_zero_tolerance_summary": wf003_zero_tolerance_rows,
      "wf003_near_floor_reference": [
         row for row in rl_near_floor_rows if row.get("window_id") == "wf003_202510"
      ],
   }
   return summary, csv_outputs


def build_markdown_report(summary: dict[str, Any]) -> str:
   datasets = summary["datasets"]
   holdout = datasets["holdout"]
   contiguous = datasets["contiguous_public_rule3"]
   wf002 = datasets["wf002_202509"]
   wf003 = datasets["wf003_202510"]
   replacement = summary["replacement_lineage_evidence"]
   recommendation = summary["recommendation"]
   wf003_tolerance = {item["threshold_label"]: item for item in summary["wf003_zero_tolerance"]["rows"]}

   lines = [
      "# XAUUSD MR Floor-Sensitivity Diagnostic",
      "",
      "## Runtime Path",
      "",
      "- `scheduler.mqh` hands MR confidence and stop geometry into `Allocator_BuildOrderPlan()` before placement.",
      "- `allocator.mqh` pulls contract pricing metadata, then calls `Risk_SizingByATRDistanceForSymbol()`.",
      "- `risk.mqh` is where floor sensitivity first enters: it reads `SYMBOL_VOLUME_MIN/MAX/STEP`, converts risk money into raw lots, floors by step with `MathFloor`, and zeroes any result below `SYMBOL_VOLUME_MIN`.",
      "- `allocator.mqh` then converts that non-positive size into `rejection_reason=volume_zero` before `PlaceOrder()` is reached.",
      "- `order_engine.mqh` still re-normalizes volume later, but that is secondary here because floor-rejected rows never reach placement.",
      "",
      "## Bucket Summary",
      "",
      f"- Holdout executed XAUUSD MR min-lot share: `{holdout['executed_min_lot_share']}` (`{holdout['executed_bucket_counts'].get('near_floor_0.01', 0)}/{holdout['place_ok_count']}`), with zero-share `{holdout['zero_share_of_candidates']}` across all XAUUSD MR candidates.",
      f"- Contiguous corroboration executed min-lot share: `{contiguous['executed_min_lot_share']}` (`{contiguous['executed_bucket_counts'].get('near_floor_0.01', 0)}/{contiguous['place_ok_count']}`), with only `{contiguous['bucket_counts'].get('rounded_to_0.00', 0)}` `volume_zero` candidate.",
      f"- `wf002_202509` executed min-lot share: `{wf002['executed_min_lot_share']}` (`{wf002['executed_bucket_counts'].get('near_floor_0.01', 0)}/{wf002['place_ok_count']}`), but zero-share still `{wf002['zero_share_of_candidates']}`.",
      f"- `wf003_202510` executed min-lot share: `{wf003['executed_min_lot_share']}` (`{wf003['executed_bucket_counts'].get('near_floor_0.01', 0)}/{wf003['place_ok_count']}`), while zero-share jumps to `{wf003['zero_share_of_candidates']}` with `{wf003['bucket_counts'].get('rounded_to_0.00', 0)}` `volume_zero` candidates.",
      "",
      "## Concentration",
      "",
      f"- The hard zero cliff is concentrated in `wf003_202510`: executed stop distance median `{wf003['executed_stop_distance_points']['median']}` points, zero-stop median `{wf003['zero_stop_distance_points']['median']}` points, regime bucket `{json.dumps({k: v for k, v in wf003['regime_bucket_counts'].items() if 'rounded_to_0.00' in k}, sort_keys=True)}`.",
      f"- Holdout stays floor-dependent but not zero-cliffed: executed raw-volume median `{holdout['executed_raw_volume']['median']}` and executed stop median `{holdout['executed_stop_distance_points']['median']}` points.",
      f"- Session evidence from the merged spread diagnostic stays narrow: `{json.dumps(summary['session_evidence']['baseline_place_ok_session_counts'], sort_keys=True)}` with regime `{json.dumps(summary['session_evidence']['baseline_place_ok_regime_counts'], sort_keys=True)}` for the `wf003` execution slice.",
      "",
      "## Replacement Path",
      "",
      f"- The merged RL diagnostic already shows cap-coupled churn in `wf003_202510`: lost-trade reasons `{json.dumps(replacement['lost_trade_reason_counts'], sort_keys=True)}` and gained-trade reasons `{json.dumps(replacement['gained_trade_reason_counts'], sort_keys=True)}`.",
      f"- That means tiny raw-volume drops do not just delete trades; they free position-cap slots that later replacement lineages can consume.",
      "",
      "## Why Not A Rounding Branch Yet",
      "",
      f"- Approximate share of `wf003` zero rows recoverable with at most 5% min-lot overshoot: `{wf003_tolerance.get('<=5pct_overshoot', {}).get('share_of_wf003_zero_rows')}`.",
      f"- Approximate share recoverable only if you allow up to 10% overshoot: `{wf003_tolerance.get('<=10pct_overshoot', {}).get('share_of_wf003_zero_rows')}`.",
      "- The below-floor population is too broad to justify a generic round-up rule from current evidence, and current `raw_volume` logs are only 4-decimal precise.",
      "",
      "## Recommendation",
      "",
      f"- Follow-up branch justified: `{recommendation['follow_up_branch_justified']}`.",
      f"- Exact next branch: `{recommendation['exact_next_branch']}`.",
      f"- Intervention class: `{recommendation['intervention_class']}`.",
      f"- Key call: {recommendation['key_call']}",
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


def write_outputs(
   output_dir: Path,
   summary: dict[str, Any],
   csv_outputs: dict[str, list[dict[str, Any]]],
) -> dict[str, str]:
   output_dir.mkdir(parents=True, exist_ok=True)

   summary_path = output_dir / "diagnostic_summary.json"
   summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")

   report_path = output_dir / "diagnostic_report.md"
   report_path.write_text(build_markdown_report(summary), encoding="utf-8")

   window_bucket_path = output_dir / "window_bucket_summary.csv"
   write_csv(window_bucket_path, csv_outputs["window_bucket_summary"])

   regime_bucket_path = output_dir / "regime_bucket_summary.csv"
   write_csv(regime_bucket_path, csv_outputs["regime_bucket_summary"])

   replacement_path = output_dir / "replacement_lineage_summary.csv"
   write_csv(replacement_path, csv_outputs["replacement_lineage_summary"])

   tolerance_path = output_dir / "wf003_zero_tolerance_summary.csv"
   write_csv(tolerance_path, csv_outputs["wf003_zero_tolerance_summary"])

   near_floor_reference_path = output_dir / "wf003_near_floor_reference.csv"
   write_csv(near_floor_reference_path, csv_outputs["wf003_near_floor_reference"])

   return {
      "summary": str(summary_path),
      "report": str(report_path),
      "window_bucket_summary": str(window_bucket_path),
      "regime_bucket_summary": str(regime_bucket_path),
      "replacement_lineage_summary": str(replacement_path),
      "wf003_zero_tolerance_summary": str(tolerance_path),
      "wf003_near_floor_reference": str(near_floor_reference_path),
   }


def parse_args(argv: list[str]) -> argparse.Namespace:
   parser = argparse.ArgumentParser(description=__doc__)
   parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
   parser.add_argument("--plan-path", type=Path, default=DEFAULT_PLAN_PATH)
   parser.add_argument("--research-summary-path", type=Path, default=DEFAULT_RESEARCH_SUMMARY_PATH)
   parser.add_argument("--research-candidates-path", type=Path, default=DEFAULT_RESEARCH_CANDIDATES_PATH)
   parser.add_argument("--spread-diagnostic-path", type=Path, default=DEFAULT_SPREAD_DIAGNOSTIC_PATH)
   parser.add_argument("--rl-diagnostic-summary-path", type=Path, default=DEFAULT_RL_DIAGNOSTIC_SUMMARY_PATH)
   parser.add_argument("--rl-diagnostic-report-path", type=Path, default=DEFAULT_RL_DIAGNOSTIC_REPORT_PATH)
   parser.add_argument("--rl-lineage-csv-path", type=Path, default=DEFAULT_RL_LINEAGE_CSV_PATH)
   parser.add_argument("--rl-near-floor-csv-path", type=Path, default=DEFAULT_RL_NEAR_FLOOR_CSV_PATH)
   return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
   args = parse_args(argv if argv is not None else sys.argv[1:])
   repo = repo_root()
   summary, csv_outputs = build_summary(
      repo=repo,
      plan_path=args.plan_path,
      research_summary_path=args.research_summary_path,
      research_candidates_path=args.research_candidates_path,
      spread_diagnostic_path=args.spread_diagnostic_path,
      rl_diagnostic_summary_path=args.rl_diagnostic_summary_path,
      rl_diagnostic_report_path=args.rl_diagnostic_report_path,
      rl_lineage_csv_path=args.rl_lineage_csv_path,
      rl_near_floor_csv_path=args.rl_near_floor_csv_path,
   )
   outputs = write_outputs(resolve_repo_path(repo, args.output_dir), summary, csv_outputs)
   print(json.dumps({"outputs": outputs, "recommendation": summary["recommendation"]}, indent=2, sort_keys=True))
   return 0


if __name__ == "__main__":
   raise SystemExit(main())
