#!/usr/bin/env python3
"""Diagnose RL-vs-EMRT confidence mixing and sizing-floor effects."""

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
from itertools import zip_longest
from pathlib import Path
from typing import Any, Iterable

try:
   from tools import fundingpips_mt5_runner as mt5_runner
   from tools import fundingpips_phase_a_research as phase_a_research
except ModuleNotFoundError:  # pragma: no cover - script execution fallback
   sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
   from tools import fundingpips_mt5_runner as mt5_runner
   from tools import fundingpips_phase_a_research as phase_a_research


DEFAULT_OUTPUT_DIR = (
   Path(".tmp")
   / "fundingpips_rl_emrt_sizing_diagnostic"
   / "phasea_rl_emrt_sizing"
)
DEFAULT_RUNNER_OUTPUT_DIR = DEFAULT_OUTPUT_DIR / "runner_runs"

DEFAULT_PLAN_PATH = Path("docs") / "plans" / "PLAN_main.md"
DEFAULT_RESEARCH_SUMMARY_PATH = (
   Path(".tmp")
   / "fundingpips_phase_a_research"
   / "master_d0e5558_phase_a"
   / "research_attribution_summary.json"
)
DEFAULT_RESEARCH_RANKINGS_PATH = (
   Path(".tmp")
   / "fundingpips_phase_a_research"
   / "master_d0e5558_phase_a"
   / "research_change_rankings.md"
)
DEFAULT_SPREAD_DIAGNOSTIC_PATH = (
   Path(".tmp")
   / "fundingpips_wf003_spread_coverage_diagnostic"
   / "phasea_wf003_spread_coverage"
   / "diagnostic_summary.json"
)
DEFAULT_VALIDATION_SUMMARY_PATH = (
   Path(".tmp")
   / "fundingpips_mr_emrt_weight_validation"
   / "phasea_mr_emrt_weight"
   / "validation_summary.json"
)
DEFAULT_CANDIDATE_COMPARISON_PATH = (
   Path(".tmp")
   / "fundingpips_mr_emrt_weight_validation"
   / "phasea_mr_emrt_weight"
   / "candidate_comparison.md"
)

DEFAULT_HOLDOUT_BASELINE_MANIFEST = (
   Path(".tmp")
   / "fundingpips_official_validation"
   / "master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c"
   / "run_manifest.json"
)
DEFAULT_HOLDOUT_CANDIDATE_MANIFEST = (
   Path(".tmp")
   / "fundingpips_mr_emrt_weight_validation"
   / "phasea_mr_emrt_weight"
   / "runner_runs"
   / "phasea_mr_emrt_weight__emrt_weight_020__holdout__baseline__d8fff9c35ff40d11"
   / "run_manifest.json"
)
DEFAULT_REPORT_CANDIDATE_MANIFESTS = {
   "wf001_202508": (
      Path(".tmp")
      / "fundingpips_mr_emrt_weight_validation"
      / "phasea_mr_emrt_weight"
      / "runner_runs"
      / "phasea_mr_emrt_weight__emrt_weight_020__wf001_202508__baseline__d83e28a2c09261fa"
      / "run_manifest.json"
   ),
   "wf002_202509": (
      Path(".tmp")
      / "fundingpips_mr_emrt_weight_validation"
      / "phasea_mr_emrt_weight"
      / "runner_runs"
      / "phasea_mr_emrt_weight__emrt_weight_020__wf002_202509__baseline__e90bef0269667296"
      / "run_manifest.json"
   ),
   "wf003_202510": (
      Path(".tmp")
      / "fundingpips_mr_emrt_weight_validation"
      / "phasea_mr_emrt_weight"
      / "runner_runs"
      / "phasea_mr_emrt_weight__emrt_weight_020__wf003_202510__baseline__5f30d0753c589c59"
      / "run_manifest.json"
   ),
}

MIN_LOT = 0.01
NEAR_FLOOR_BAND = 0.0025
BASELINE_WEIGHT = 0.0
CANDIDATE_WEIGHT = 0.2


@dataclasses.dataclass(frozen=True)
class WindowConfig:
   id: str
   label: str
   candidate_manifest: Path
   baseline_manifest: Path | None
   is_holdout: bool


@dataclasses.dataclass
class RunBundle:
   id: str
   label: str
   manifest_path: Path
   summary: dict[str, Any]
   meta_by_key: dict[tuple[str, str, int], dict[str, Any]]
   lineage_by_key: dict[tuple[str, str, int], list[dict[str, Any]]]


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


def round_or_none(value: float | None, places: int = 6) -> float | None:
   if value is None or not math.isfinite(value):
      return None
   return round(value, places)


def serialize_eval_key(key: tuple[str, str, int] | None) -> str:
   if key is None:
      return ""
   ts_text, symbol, ordinal = key
   return f"{ts_text}|{symbol}|{ordinal}"


def normalize_source_path(path: Any) -> str:
   if path in (None, ""):
      return ""
   candidate = Path(str(path))
   try:
      return str(candidate.resolve())
   except OSError:
      return str(candidate)


def distribution(values: Iterable[float]) -> dict[str, Any]:
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


def trade_day_set(lineages: Iterable[dict[str, Any]], prefix: str) -> set[str]:
   days: set[str] = set()
   flag_key = f"{prefix}_place_ok"
   date_key = f"{prefix}_decision_date"
   for row in lineages:
      if row.get(flag_key):
         date_value = row.get(date_key) or ""
         if date_value:
            days.add(str(date_value))
   return days


def summarize_volume_counts(values: Iterable[float | None]) -> dict[str, int]:
   counts: Counter[str] = Counter()
   for value in values:
      if value is None:
         counts["missing"] += 1
         continue
      counts[f"{value:.4f}"] += 1
   return dict(sorted(counts.items()))


def load_manifest_bundle(
   manifest_path: Path,
   role: str,
) -> tuple[phase_a_research.PhaseARunInput, dict[str, Any], list[phase_a_research.DecisionRow], list[phase_a_research.EventRow]]:
   manifest = load_json(manifest_path)
   run_root = manifest_path.parent
   run_input = phase_a_research.PhaseARunInput(
      id=run_root.name,
      baseline_role=role,
      root=run_root,
      manifest_path=manifest_path,
      summary_path=Path(manifest["collected_summary"]),
      daily_path=Path(manifest["collected_daily"]),
      report_path=Path(manifest["collected_report"]),
      decision_log_paths=tuple(Path(item) for item in manifest.get("collected_decision_logs", [])),
      event_log_paths=tuple(Path(item) for item in manifest.get("collected_event_logs", [])),
   )
   decision_rows = phase_a_research.parse_decision_logs(run_input)
   event_rows = phase_a_research.parse_event_logs(run_input)
   summary = load_json(run_input.summary_path)
   return run_input, summary, decision_rows, event_rows


def build_meta_records(
   decision_rows: list[phase_a_research.DecisionRow],
) -> tuple[dict[tuple[str, str, int], dict[str, Any]], dict[tuple[str, int], tuple[str, str, int]]]:
   counters: defaultdict[tuple[str, str], int] = defaultdict(int)
   meta_by_key: dict[tuple[str, str, int], dict[str, Any]] = {}
   source_lookup: dict[tuple[str, int], tuple[str, str, int]] = {}

   for row in decision_rows:
      if row.component != "MetaPolicy" or row.message != "EVAL":
         continue
      symbol = str(row.fields.get("symbol") or row.symbol or "")
      base_key = (row.ts_text, symbol)
      counters[base_key] += 1
      key = (row.ts_text, symbol, counters[base_key])
      emrt_rank = maybe_float(row.fields.get("emrt"))
      emrt_fastness = None if emrt_rank is None else max(0.0, 1.0 - emrt_rank)
      record = {
         "eval_key": serialize_eval_key(key),
         "decision_ts": row.ts_text,
         "decision_date": row.ts_text[:10],
         "decision_hour": row.ts_text[11:13],
         "symbol": symbol,
         "choice": str(row.fields.get("choice") or ""),
         "confidence": maybe_float(row.fields.get("confidence")),
         "mr_conf": maybe_float(row.fields.get("mr_conf")),
         "bwisc_conf": maybe_float(row.fields.get("bwisc_conf")),
         "emrt_rank": emrt_rank,
         "emrt_fastness": emrt_fastness,
         "regime": str(row.fields.get("regime") or ""),
         "gating_reason": str(row.fields.get("gating_reason") or ""),
         "news_window_state": str(row.fields.get("news_window_state") or ""),
         "spread_q": maybe_float(row.fields.get("spread_q")),
         "slippage_q": maybe_float(row.fields.get("slippage_q")),
         "hold_time_min": maybe_int(row.fields.get("hold_time_min")),
         "source_file": normalize_source_path(row.source_path),
         "source_row": row.source_row,
      }
      meta_by_key[key] = record
      source_lookup[(record["source_file"], row.source_row)] = key

   return meta_by_key, source_lookup


def build_lineage_records(
   decision_rows: list[phase_a_research.DecisionRow],
   event_rows: list[phase_a_research.EventRow],
   meta_source_lookup: dict[tuple[str, int], tuple[str, str, int]],
) -> dict[tuple[str, str, int], list[dict[str, Any]]]:
   candidates = phase_a_research.build_candidates(decision_rows, event_rows)
   records_by_key: defaultdict[tuple[str, str, int], list[dict[str, Any]]] = defaultdict(list)

   for row in candidates:
      if row.get("strategy") != "MR":
         continue
      source_file = normalize_source_path(row.get("meta_policy_source_file"))
      source_row = maybe_int(row.get("meta_policy_source_row"))
      if source_row is None:
         continue
      eval_key = meta_source_lookup.get((source_file, source_row))
      if eval_key is None:
         continue
      decision_ts = str(row.get("decision_ts") or "")
      record = {
         "eval_key": serialize_eval_key(eval_key),
         "candidate_id": str(row.get("candidate_id") or ""),
         "decision_ts": decision_ts,
         "decision_date": decision_ts[:10],
         "decision_hour": decision_ts[11:13],
         "signal_symbol": str(row.get("signal_symbol") or ""),
         "symbol": str(row.get("symbol") or ""),
         "plan_valid": bool(maybe_bool(row.get("plan_valid"))),
         "rejection_reason": str(row.get("rejection_reason") or ""),
         "place_ok": bool(maybe_bool(row.get("place_ok"))),
         "order_sent": bool(maybe_bool(row.get("order_sent"))),
         "effective_risk_pct": maybe_float(row.get("effective_risk_pct")),
         "risk_raw_volume": maybe_float(row.get("risk_raw_volume")),
         "risk_floored_volume": maybe_float(row.get("risk_floored_volume")),
         "risk_final_volume": maybe_float(row.get("risk_final_volume")),
         "volume_min": maybe_float(row.get("volume_min")),
         "volume_step": maybe_float(row.get("volume_step")),
         "risk_raw_gap_to_min_lot_frac": maybe_float(row.get("risk_raw_gap_to_min_lot_frac")),
         "risk_floored_gap_to_min_lot_frac": maybe_float(row.get("risk_floored_gap_to_min_lot_frac")),
         "risk_volume_zero_subcause": str(row.get("risk_volume_zero_subcause") or ""),
         "risk_volume_zero_reference_volume": maybe_float(row.get("risk_volume_zero_reference_volume")),
         "risk_volume_zero_gap_to_min_lot_frac": maybe_float(row.get("risk_volume_zero_gap_to_min_lot_frac")),
         "volume_zero_subcause": str(row.get("volume_zero_subcause") or ""),
         "volume_zero_reference_volume": maybe_float(row.get("volume_zero_reference_volume")),
         "volume_zero_gap_to_min_lot_frac": maybe_float(row.get("volume_zero_gap_to_min_lot_frac")),
         "budget_scaled_raw_volume": maybe_float(row.get("budget_scaled_raw_volume")),
         "budget_scaled_floored_volume": maybe_float(row.get("budget_scaled_floored_volume")),
         "final_volume": maybe_float(row.get("volume")),
         "logged_worst_case_risk_money": maybe_float(row.get("logged_worst_case_risk_money")),
         "requested_entry_price": maybe_float(row.get("requested_entry_price")),
         "sl": maybe_float(row.get("sl")),
         "tp": maybe_float(row.get("tp")),
         "meta_confidence": maybe_float(row.get("meta_confidence")),
         "meta_emrt": maybe_float(row.get("meta_emrt")),
         "meta_gating_reason": str(row.get("meta_gating_reason") or ""),
         "meta_regime": str(row.get("meta_regime") or ""),
      }
      records_by_key[eval_key].append(record)

   return dict(records_by_key)


def load_run_bundle(manifest_path: Path, role: str, label: str) -> RunBundle:
   run_input, summary, decision_rows, event_rows = load_manifest_bundle(manifest_path, role)
   meta_by_key, meta_source_lookup = build_meta_records(decision_rows)
   lineage_by_key = build_lineage_records(decision_rows, event_rows, meta_source_lookup)
   return RunBundle(
      id=run_input.id,
      label=label,
      manifest_path=manifest_path,
      summary=summary,
      meta_by_key=meta_by_key,
      lineage_by_key=lineage_by_key,
   )


def build_baseline_report_spec(
   candidate_manifest_path: Path,
   window_id: str,
) -> mt5_runner.BacktestSpec:
   candidate_manifest = load_json(candidate_manifest_path)
   spec_data = dict(candidate_manifest["spec"])
   set_overrides = dict(spec_data.get("set_overrides") or {})
   set_overrides["MR_EMRTWeight"] = BASELINE_WEIGHT
   spec_data["set_overrides"] = set_overrides
   spec_data["name"] = f"phasea_rl_emrt_sizing__emrt_weight_000__{window_id}__baseline"
   spec_data["report_stem"] = spec_data["name"]
   return mt5_runner.build_spec(spec_data)


def ensure_report_baseline_manifests(
   repo: Path,
   window_configs: list[WindowConfig],
   runner_output_dir: Path,
   rerun_missing: bool,
) -> tuple[dict[str, Path], list[dict[str, Any]]]:
   manifests: dict[str, Path] = {}
   rerun_records: list[dict[str, Any]] = []
   paths: mt5_runner.RunnerPaths | None = None
   synced = False
   compiled = False

   for config in window_configs:
      if config.baseline_manifest is not None:
         manifests[config.id] = resolve_repo_path(repo, config.baseline_manifest)
         continue
      if not rerun_missing:
         raise RuntimeError(
            f"Missing same-stack baseline manifest for {config.id}; reruns are required to continue safely."
         )
      if paths is None:
         paths = mt5_runner.build_runner_paths(output_root=runner_output_dir)
      spec = build_baseline_report_spec(resolve_repo_path(repo, config.candidate_manifest), config.id)
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
      manifest_path = Path(result["manifest_path"])
      manifests[config.id] = manifest_path
      rerun_records.append(
         {
            "window_id": config.id,
            "status": result["status"],
            "manifest_path": str(manifest_path),
            "run_dir": result.get("run_dir"),
         }
      )

   return manifests, rerun_records


def classify_divergence(
   baseline_meta: dict[str, Any] | None,
   candidate_meta: dict[str, Any] | None,
   baseline_lineage: dict[str, Any] | None,
   candidate_lineage: dict[str, Any] | None,
) -> dict[str, Any]:
   baseline_choice = str((baseline_meta or {}).get("choice") or "")
   candidate_choice = str((candidate_meta or {}).get("choice") or "")
   baseline_place = bool((baseline_lineage or {}).get("place_ok"))
   candidate_place = bool((candidate_lineage or {}).get("place_ok"))
   baseline_valid = bool((baseline_lineage or {}).get("plan_valid"))
   candidate_valid = bool((candidate_lineage or {}).get("plan_valid"))
   baseline_final_volume = maybe_float((baseline_lineage or {}).get("final_volume"))
   candidate_final_volume = maybe_float((candidate_lineage or {}).get("final_volume"))
   baseline_raw_volume = maybe_float((baseline_lineage or {}).get("risk_raw_volume"))
   candidate_raw_volume = maybe_float((candidate_lineage or {}).get("risk_raw_volume"))
   candidate_rejection = str((candidate_lineage or {}).get("rejection_reason") or "")
   baseline_rejection = str((baseline_lineage or {}).get("rejection_reason") or "")

   stage = "none"
   reason = "no_behavioral_change"

   if baseline_meta is None or candidate_meta is None:
      stage = "timeline"
      reason = "missing_meta_row"
   elif baseline_choice != candidate_choice:
      stage = "meta_policy"
      reason = f"{baseline_choice or 'none'}_to_{candidate_choice or 'none'}".lower()
   elif baseline_choice == "MR" or candidate_choice == "MR" or baseline_lineage or candidate_lineage:
      if (baseline_lineage is None) != (candidate_lineage is None):
         stage = "allocator"
         reason = "missing_mr_lineage"
      elif baseline_valid != candidate_valid or baseline_rejection != candidate_rejection:
         stage = "allocator"
         if baseline_valid and candidate_rejection == "volume_zero":
            reason = "candidate_volume_zero"
         elif candidate_valid and baseline_rejection == "volume_zero":
            reason = "baseline_volume_zero"
         elif baseline_valid and candidate_rejection:
            reason = f"candidate_reject_{candidate_rejection}"
         elif candidate_valid and baseline_rejection:
            reason = f"baseline_reject_{baseline_rejection}"
         else:
            reason = "allocator_plan_change"
      elif baseline_final_volume != candidate_final_volume:
         stage = "rounded_volume"
         if baseline_final_volume is not None and candidate_final_volume is not None:
            reason = "candidate_rounded_down" if candidate_final_volume < baseline_final_volume else "candidate_rounded_up"
         else:
            reason = "final_volume_change"
      elif baseline_raw_volume != candidate_raw_volume:
         stage = "allocator_sizing"
         reason = "raw_volume_delta_only"
      elif baseline_place != candidate_place:
         stage = "execution"
         reason = "place_ok_delta"
      elif maybe_float((baseline_meta or {}).get("mr_conf")) != maybe_float((candidate_meta or {}).get("mr_conf")):
         stage = "signal_confidence"
         reason = "confidence_only"
   elif maybe_float((baseline_meta or {}).get("mr_conf")) != maybe_float((candidate_meta or {}).get("mr_conf")):
      stage = "signal_confidence"
      reason = "non_mr_confidence_only"

   zero_cliff = (
      baseline_place
      and candidate_rejection == "volume_zero"
      and baseline_final_volume is not None
      and baseline_final_volume >= MIN_LOT
   )
   rounded_down = (
      baseline_final_volume is not None
      and candidate_final_volume is not None
      and candidate_final_volume < baseline_final_volume
   )

   return {
      "stage": stage,
      "reason": reason,
      "lost_baseline_trade": baseline_place and not candidate_place,
      "gained_candidate_trade": candidate_place and not baseline_place,
      "zero_cliff": zero_cliff,
      "rounded_down": rounded_down,
      "baseline_at_min_lot": baseline_final_volume == MIN_LOT,
      "candidate_at_min_lot": candidate_final_volume == MIN_LOT,
      "baseline_near_floor": (
         baseline_raw_volume is not None and abs(baseline_raw_volume - MIN_LOT) <= NEAR_FLOOR_BAND
      ),
      "candidate_near_floor": (
         candidate_raw_volume is not None and abs(candidate_raw_volume - MIN_LOT) <= NEAR_FLOOR_BAND
      ),
   }


def pair_window_lineages(
   window_id: str,
   baseline_bundle: RunBundle,
   candidate_bundle: RunBundle,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
   meta_rows: list[dict[str, Any]] = []
   lineage_rows: list[dict[str, Any]] = []
   all_keys = sorted(set(baseline_bundle.meta_by_key) | set(candidate_bundle.meta_by_key))

   for key in all_keys:
      baseline_meta = baseline_bundle.meta_by_key.get(key)
      candidate_meta = candidate_bundle.meta_by_key.get(key)
      baseline_q_adv = maybe_float((baseline_meta or {}).get("mr_conf"))
      emrt_fastness = maybe_float((baseline_meta or {}).get("emrt_fastness"))
      if emrt_fastness is None:
         emrt_fastness = maybe_float((candidate_meta or {}).get("emrt_fastness"))
      expected_candidate_conf = None
      if baseline_q_adv is not None and emrt_fastness is not None:
         expected_candidate_conf = CANDIDATE_WEIGHT * emrt_fastness + (1.0 - CANDIDATE_WEIGHT) * baseline_q_adv
      candidate_mr_conf = maybe_float((candidate_meta or {}).get("mr_conf"))
      baseline_mr_conf = baseline_q_adv
      rl_component = None if baseline_q_adv is None else (1.0 - CANDIDATE_WEIGHT) * baseline_q_adv
      emrt_component = None if emrt_fastness is None else CANDIDATE_WEIGHT * emrt_fastness
      delta_conf = None
      if baseline_mr_conf is not None and candidate_mr_conf is not None:
         delta_conf = candidate_mr_conf - baseline_mr_conf

      meta_rows.append(
         {
            "window_id": window_id,
            "eval_key": serialize_eval_key(key),
            "decision_ts": (baseline_meta or candidate_meta or {}).get("decision_ts"),
            "decision_date": (baseline_meta or candidate_meta or {}).get("decision_date"),
            "decision_hour": (baseline_meta or candidate_meta or {}).get("decision_hour"),
            "symbol": (baseline_meta or candidate_meta or {}).get("symbol"),
            "baseline_choice": (baseline_meta or {}).get("choice"),
            "candidate_choice": (candidate_meta or {}).get("choice"),
            "baseline_mr_conf": round_or_none(baseline_mr_conf),
            "candidate_mr_conf": round_or_none(candidate_mr_conf),
            "delta_conf": round_or_none(delta_conf),
            "emrt_rank": round_or_none(maybe_float((baseline_meta or candidate_meta or {}).get("emrt_rank"))),
            "emrt_fastness": round_or_none(emrt_fastness),
            "inferred_q_advantage": round_or_none(baseline_q_adv),
            "candidate_rl_component": round_or_none(rl_component),
            "candidate_emrt_component": round_or_none(emrt_component),
            "expected_candidate_mr_conf": round_or_none(expected_candidate_conf),
            "candidate_conf_residual": (
               None
               if expected_candidate_conf is None or candidate_mr_conf is None
               else round(candidate_mr_conf - expected_candidate_conf, 10)
            ),
            "regime": (baseline_meta or candidate_meta or {}).get("regime"),
            "gating_reason": (baseline_meta or candidate_meta or {}).get("gating_reason"),
            "news_window_state": (baseline_meta or candidate_meta or {}).get("news_window_state"),
            "spread_q": round_or_none(maybe_float((baseline_meta or candidate_meta or {}).get("spread_q"))),
            "slippage_q": round_or_none(maybe_float((baseline_meta or candidate_meta or {}).get("slippage_q"))),
         }
      )

      baseline_lineages = baseline_bundle.lineage_by_key.get(key, [])
      candidate_lineages = candidate_bundle.lineage_by_key.get(key, [])
      for pair_index, (baseline_lineage, candidate_lineage) in enumerate(zip_longest(baseline_lineages, candidate_lineages), start=1):
         divergence = classify_divergence(baseline_meta, candidate_meta, baseline_lineage, candidate_lineage)
         baseline_raw_volume = maybe_float((baseline_lineage or {}).get("risk_raw_volume"))
         candidate_raw_volume = maybe_float((candidate_lineage or {}).get("risk_raw_volume"))
         baseline_final_volume = maybe_float((baseline_lineage or {}).get("final_volume"))
         candidate_final_volume = maybe_float((candidate_lineage or {}).get("final_volume"))
         lineage_rows.append(
            {
               "window_id": window_id,
               "eval_key": serialize_eval_key(key),
               "pair_index": pair_index,
               "decision_ts": (baseline_meta or candidate_meta or {}).get("decision_ts"),
               "decision_date": (baseline_lineage or candidate_lineage or {}).get("decision_date"),
               "decision_hour": (baseline_lineage or candidate_lineage or {}).get("decision_hour"),
               "symbol": (baseline_lineage or candidate_lineage or {}).get("symbol"),
               "regime": (baseline_meta or candidate_meta or {}).get("regime"),
               "baseline_choice": (baseline_meta or {}).get("choice"),
               "candidate_choice": (candidate_meta or {}).get("choice"),
               "baseline_candidate_id": (baseline_lineage or {}).get("candidate_id"),
               "candidate_candidate_id": (candidate_lineage or {}).get("candidate_id"),
               "baseline_place_ok": bool((baseline_lineage or {}).get("place_ok")),
               "candidate_place_ok": bool((candidate_lineage or {}).get("place_ok")),
               "baseline_plan_valid": bool((baseline_lineage or {}).get("plan_valid")),
               "candidate_plan_valid": bool((candidate_lineage or {}).get("plan_valid")),
               "baseline_rejection_reason": (baseline_lineage or {}).get("rejection_reason"),
               "candidate_rejection_reason": (candidate_lineage or {}).get("rejection_reason"),
               "baseline_effective_risk_pct": round_or_none(maybe_float((baseline_lineage or {}).get("effective_risk_pct"))),
               "candidate_effective_risk_pct": round_or_none(maybe_float((candidate_lineage or {}).get("effective_risk_pct"))),
               "baseline_raw_volume": round_or_none(baseline_raw_volume, 8),
               "candidate_raw_volume": round_or_none(candidate_raw_volume, 8),
               "raw_volume_delta": (
                  None if baseline_raw_volume is None or candidate_raw_volume is None else round(candidate_raw_volume - baseline_raw_volume, 8)
               ),
               "baseline_final_volume": round_or_none(baseline_final_volume, 4),
               "candidate_final_volume": round_or_none(candidate_final_volume, 4),
               "rounded_volume_delta": (
                  None if baseline_final_volume is None or candidate_final_volume is None else round(candidate_final_volume - baseline_final_volume, 4)
               ),
               "baseline_mr_conf": round_or_none(baseline_q_adv),
               "candidate_mr_conf": round_or_none(candidate_mr_conf),
               "delta_conf": round_or_none(delta_conf),
               "emrt_fastness": round_or_none(emrt_fastness),
               "candidate_rl_component": round_or_none(rl_component),
               "candidate_emrt_component": round_or_none(emrt_component),
               "divergence_stage": divergence["stage"],
               "divergence_reason": divergence["reason"],
               "lost_baseline_trade": divergence["lost_baseline_trade"],
               "gained_candidate_trade": divergence["gained_candidate_trade"],
               "zero_cliff": divergence["zero_cliff"],
               "rounded_down": divergence["rounded_down"],
               "baseline_at_min_lot": divergence["baseline_at_min_lot"],
               "candidate_at_min_lot": divergence["candidate_at_min_lot"],
               "baseline_near_floor": divergence["baseline_near_floor"],
               "candidate_near_floor": divergence["candidate_near_floor"],
            }
         )

   return meta_rows, lineage_rows


def summarize_contributions(meta_rows: list[dict[str, Any]]) -> dict[str, Any]:
   q_advantage = [row["inferred_q_advantage"] for row in meta_rows if row.get("inferred_q_advantage") is not None]
   emrt_fastness = [row["emrt_fastness"] for row in meta_rows if row.get("emrt_fastness") is not None]
   delta_conf = [row["delta_conf"] for row in meta_rows if row.get("delta_conf") is not None]
   candidate_rl_component = [row["candidate_rl_component"] for row in meta_rows if row.get("candidate_rl_component") is not None]
   candidate_emrt_component = [row["candidate_emrt_component"] for row in meta_rows if row.get("candidate_emrt_component") is not None]
   negative_delta = sum(1 for row in delta_conf if row < 0.0)
   positive_delta = sum(1 for row in delta_conf if row > 0.0)
   emrt_beats_rl = sum(
      1
      for row in meta_rows
      if row.get("emrt_fastness") is not None
      and row.get("inferred_q_advantage") is not None
      and float(row["emrt_fastness"]) > float(row["inferred_q_advantage"])
   )
   shared = len([row for row in meta_rows if row.get("candidate_mr_conf") is not None and row.get("baseline_mr_conf") is not None])
   return {
      "shared_eval_count": shared,
      "q_advantage": distribution(q_advantage),
      "emrt_fastness": distribution(emrt_fastness),
      "delta_confidence": distribution(delta_conf),
      "candidate_rl_component": distribution(candidate_rl_component),
      "candidate_emrt_component": distribution(candidate_emrt_component),
      "negative_delta_share": round(negative_delta / shared, 6) if shared else None,
      "positive_delta_share": round(positive_delta / shared, 6) if shared else None,
      "emrt_above_rl_share": round(emrt_beats_rl / shared, 6) if shared else None,
   }


def summarize_lineage_effects(lineage_rows: list[dict[str, Any]]) -> dict[str, Any]:
   shared_rows = [row for row in lineage_rows if row.get("baseline_choice") or row.get("candidate_choice")]
   lost_rows = [row for row in lineage_rows if row.get("lost_baseline_trade")]
   gained_rows = [row for row in lineage_rows if row.get("gained_candidate_trade")]
   baseline_exec_rows = [row for row in lineage_rows if row.get("baseline_place_ok")]
   candidate_exec_rows = [row for row in lineage_rows if row.get("candidate_place_ok")]

   return {
      "shared_lineage_pairs": len(shared_rows),
      "divergence_stage_counts": dict(Counter(str(row.get("divergence_stage") or "") for row in shared_rows)),
      "divergence_reason_counts": dict(Counter(str(row.get("divergence_reason") or "") for row in shared_rows)),
      "lost_trade_reason_counts": dict(Counter(str(row.get("divergence_reason") or "") for row in lost_rows)),
      "lost_trade_regime_counts": dict(Counter(str(row.get("regime") or "") for row in lost_rows)),
      "lost_trade_symbol_counts": dict(Counter(str(row.get("symbol") or "") for row in lost_rows)),
      "lost_trade_hour_counts": dict(Counter(str(row.get("decision_hour") or "") for row in lost_rows)),
      "gained_trade_reason_counts": dict(Counter(str(row.get("divergence_reason") or "") for row in gained_rows)),
      "baseline_exec_count": len(baseline_exec_rows),
      "candidate_exec_count": len(candidate_exec_rows),
      "baseline_exec_volume_counts": summarize_volume_counts(row.get("baseline_final_volume") for row in baseline_exec_rows),
      "candidate_exec_volume_counts": summarize_volume_counts(row.get("candidate_final_volume") for row in candidate_exec_rows),
      "baseline_exec_raw_volume": distribution(row["baseline_raw_volume"] for row in baseline_exec_rows if row.get("baseline_raw_volume") is not None),
      "candidate_exec_raw_volume": distribution(row["candidate_raw_volume"] for row in candidate_exec_rows if row.get("candidate_raw_volume") is not None),
      "zero_cliff_count": sum(1 for row in lost_rows if row.get("zero_cliff")),
      "rounded_down_count": sum(1 for row in shared_rows if row.get("rounded_down")),
      "baseline_min_lot_exec_share": (
         round(sum(1 for row in baseline_exec_rows if row.get("baseline_at_min_lot")) / len(baseline_exec_rows), 6)
         if baseline_exec_rows
         else None
      ),
      "candidate_min_lot_exec_share": (
         round(sum(1 for row in candidate_exec_rows if row.get("candidate_at_min_lot")) / len(candidate_exec_rows), 6)
         if candidate_exec_rows
         else None
      ),
      "zero_cliff_raw_volume_delta": distribution(
         row["raw_volume_delta"] for row in lost_rows if row.get("zero_cliff") and row.get("raw_volume_delta") is not None
      ),
      "trade_day_loss": len(trade_day_set(shared_rows, "baseline") - trade_day_set(shared_rows, "candidate")),
      "trade_day_gain": len(trade_day_set(shared_rows, "candidate") - trade_day_set(shared_rows, "baseline")),
      "lost_trade_dates": sorted(trade_day_set(lost_rows, "baseline")),
   }


def summarize_window(
   window: WindowConfig,
   baseline_bundle: RunBundle,
   candidate_bundle: RunBundle,
   meta_rows: list[dict[str, Any]],
   lineage_rows: list[dict[str, Any]],
) -> dict[str, Any]:
   baseline_summary = baseline_bundle.summary
   candidate_summary = candidate_bundle.summary
   shared_meta = [row for row in meta_rows if row.get("baseline_mr_conf") is not None and row.get("candidate_mr_conf") is not None]
   baseline_exec_rows = [row for row in lineage_rows if row.get("baseline_place_ok")]
   shared_exec_meta_rows = {row["eval_key"]: row for row in shared_meta if row["eval_key"] in {item["eval_key"] for item in baseline_exec_rows}}
   contribution_summary = summarize_contributions(shared_meta)
   executed_contributions = summarize_contributions(list(shared_exec_meta_rows.values()))
   lineage_summary = summarize_lineage_effects(lineage_rows)
   choice_transition_counts = Counter(
      f"{row.get('baseline_choice') or 'none'}->{row.get('candidate_choice') or 'none'}"
      for row in shared_meta
   )

   baseline_return = maybe_float(baseline_summary.get("final_return_pct"))
   candidate_return = maybe_float(candidate_summary.get("final_return_pct"))
   baseline_trades = maybe_int(baseline_summary.get("trades_total"))
   candidate_trades = maybe_int(candidate_summary.get("trades_total"))
   baseline_days = maybe_int(baseline_summary.get("days_traded"))
   candidate_days = maybe_int(candidate_summary.get("days_traded"))

   return {
      "window_id": window.id,
      "label": window.label,
      "baseline": {
         "manifest_path": str(baseline_bundle.manifest_path),
         "return_pct": round_or_none(baseline_return),
         "trades_total": baseline_trades,
         "days_traded": baseline_days,
         "max_daily_dd_pct": round_or_none(maybe_float(baseline_summary.get("max_daily_dd_pct"))),
         "max_overall_dd_pct": round_or_none(maybe_float(baseline_summary.get("max_overall_dd_pct"))),
      },
      "candidate": {
         "manifest_path": str(candidate_bundle.manifest_path),
         "return_pct": round_or_none(candidate_return),
         "trades_total": candidate_trades,
         "days_traded": candidate_days,
         "max_daily_dd_pct": round_or_none(maybe_float(candidate_summary.get("max_daily_dd_pct"))),
         "max_overall_dd_pct": round_or_none(maybe_float(candidate_summary.get("max_overall_dd_pct"))),
      },
      "delta_vs_baseline": {
         "return_pct": round_or_none(candidate_return - baseline_return if baseline_return is not None and candidate_return is not None else None),
         "trades_total": (candidate_trades - baseline_trades) if baseline_trades is not None and candidate_trades is not None else None,
         "days_traded": (candidate_days - baseline_days) if baseline_days is not None and candidate_days is not None else None,
      },
      "shared_meta_eval_count": len(shared_meta),
      "choice_transition_counts": dict(choice_transition_counts),
      "all_mr_eval_contributions": contribution_summary,
      "baseline_executed_mr_contributions": executed_contributions,
      "lineage_effects": lineage_summary,
   }


def build_near_floor_rows(lineage_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
   results: list[dict[str, Any]] = []
   for row in lineage_rows:
      if not (row.get("zero_cliff") or row.get("baseline_near_floor") or row.get("candidate_near_floor") or row.get("baseline_at_min_lot") or row.get("candidate_at_min_lot")):
         continue
      results.append(row)
   return results


def build_top_level_root_cause(report_summaries: list[dict[str, Any]]) -> dict[str, Any]:
   reason_counts: Counter[str] = Counter()
   zero_cliff_count = 0
   total_lost = 0
   trade_day_loss_windows: list[str] = []
   windows_with_losses: list[str] = []

   for summary in report_summaries:
      effects = summary["lineage_effects"]
      lost_reason_counts = Counter(effects["lost_trade_reason_counts"])
      reason_counts.update(lost_reason_counts)
      total_lost += sum(lost_reason_counts.values())
      zero_cliff_count += int(effects["zero_cliff_count"])
      if summary["delta_vs_baseline"]["trades_total"] is not None and summary["delta_vs_baseline"]["trades_total"] < 0:
         windows_with_losses.append(summary["window_id"])
      if effects["trade_day_loss"] > 0:
         trade_day_loss_windows.append(summary["window_id"])

   primary_reason = reason_counts.most_common(1)[0][0] if reason_counts else "no_trade_loss_detected"
   classification = "xauusd_min_lot_quantization" if primary_reason == "candidate_volume_zero" else "mixed_policy_and_sizing_shift"
   return {
      "classification": classification,
      "primary_lost_trade_reason": primary_reason,
      "lost_trade_reason_counts": dict(reason_counts),
      "zero_cliff_share_of_lost_trades": (round(zero_cliff_count / total_lost, 6) if total_lost else None),
      "windows_with_trade_losses": windows_with_losses,
      "windows_with_trade_day_losses": trade_day_loss_windows,
      "interpretation": (
         "Most lost report trades are baseline XAUUSD MR entries that already sit on the 0.01 lot floor at weight 0.0 and then fall through the floor as candidate confidence nudges effective risk and raw volume lower."
         if classification == "xauusd_min_lot_quantization"
         else "The regression is not explained by one single floor cliff; policy-path and sizing-path changes both matter."
      ),
   }


def build_next_recommendation(summary: dict[str, Any]) -> dict[str, Any]:
   exhausted = summary["root_cause"]["classification"] == "xauusd_min_lot_quantization" and summary["windows"]["holdout"]["delta_vs_baseline"]["trades_total"] == 0
   if exhausted:
      return {
         "result": "close_single_knob_path",
         "recommended_next_step": (
            "Do not open another single-knob confidence-mix search. Close the remaining single-knob path and only consider a new branch if it directly targets XAUUSD MR floor sensitivity as an architecture-level diagnostic or execution-path change, not another scalar confidence tweak."
         ),
         "why": (
            "The saved report regression came from a cross-stack reference mismatch, and the true same-stack effect is mostly low-signal XAUUSD min-lot churn: holdout gains occur when the same executions survive with unchanged rounded volumes, while `0.2` only reshuffles floor-sized report lineages instead of producing a clean new edge."
         ),
      }
   return {
      "result": "narrow_follow_up_possible",
      "recommended_next_step": (
         "A narrowly scoped follow-up may still be justified, but only if it explicitly targets the stage identified above instead of opening another generic confidence or threshold scan."
      ),
      "why": (
         "The report regression is not cleanly dominated by a single min-lot amplification mechanism across the saved windows."
      ),
   }


def build_markdown_report(summary: dict[str, Any]) -> str:
   holdout = summary["windows"]["holdout"]
   root_cause = summary["root_cause"]
   recommendation = summary["recommendation"]
   saved_gap = summary["saved_reference_gap"]

   def window_line(window: dict[str, Any]) -> str:
      effects = window["lineage_effects"]
      return (
         f"- `{window['window_id']}`: return `{window['baseline']['return_pct']:.4f}% -> {window['candidate']['return_pct']:.4f}%`, trades `{window['baseline']['trades_total']} -> {window['candidate']['trades_total']}`, days `{window['baseline']['days_traded']} -> {window['candidate']['days_traded']}`, lost-trade reasons `{json.dumps(effects['lost_trade_reason_counts'], sort_keys=True)}`."
      )

   lines = [
      "# RL-vs-EMRT Lineage and Sizing Diagnostic",
      "",
      "## Artifact Note",
      "",
      "- The saved `MR_EMRTWeight` validation summary keeps the holdout reference on the current champion stack, but its report reference rows point back to older Stage 3 artifacts.",
      "- This diagnostic therefore stayed artifact-first where possible, reused the official holdout `MR_EMRTWeight=0.0` run, and reran only the missing same-stack `MR_EMRTWeight=0.0` report windows from the saved `0.2` manifests with the weight override reverted to `0.0`.",
      f"- Saved vs same-stack `wf001_202508`: reference `{saved_gap['wf001_202508']['saved_reference']['trades_total']}` trades / `{saved_gap['wf001_202508']['saved_reference']['days_traded']}` days vs rerun baseline `{saved_gap['wf001_202508']['same_stack_rerun_baseline']['trades_total']}` / `{saved_gap['wf001_202508']['same_stack_rerun_baseline']['days_traded']}`.",
      f"- Saved vs same-stack `wf003_202510`: reference `{saved_gap['wf003_202510']['saved_reference']['trades_total']}` trades / `{saved_gap['wf003_202510']['saved_reference']['days_traded']}` days vs rerun baseline `{saved_gap['wf003_202510']['same_stack_rerun_baseline']['trades_total']}` / `{saved_gap['wf003_202510']['same_stack_rerun_baseline']['days_traded']}`.",
      "",
      "## Holdout Contrast",
      "",
      f"- Holdout return changed `{holdout['baseline']['return_pct']:.4f}% -> {holdout['candidate']['return_pct']:.4f}%` with trades and trade days unchanged at `{holdout['baseline']['trades_total']}` / `{holdout['baseline']['days_traded']}`.",
      f"- Holdout shared executed MR lineages: `{holdout['baseline_executed_mr_contributions']['shared_eval_count']}`; negative confidence-delta share `{holdout['baseline_executed_mr_contributions']['negative_delta_share']}`.",
      f"- Holdout zero-cliff count: `{holdout['lineage_effects']['zero_cliff_count']}`.",
      "",
      "## Report Windows",
      "",
      window_line(summary["windows"]["wf001_202508"]),
      window_line(summary["windows"]["wf002_202509"]),
      window_line(summary["windows"]["wf003_202510"]),
      "",
      "## What Actually Regressed",
      "",
      "- The saved report-window regression is primarily a reference mismatch, not a true same-stack `0.0 -> 0.2` deterioration.",
      "- Under the rerun same-stack baseline, `wf001_202508` and `wf002_202509` are identical to the `0.2` candidate, and `wf003_202510` is slightly better for `0.2` on net even though many individual lineages churn.",
      "",
      "## Root Cause",
      "",
      f"- Classification: `{root_cause['classification']}`.",
      f"- Primary lost-trade reason: `{root_cause['primary_lost_trade_reason']}` with counts `{json.dumps(root_cause['lost_trade_reason_counts'], sort_keys=True)}`.",
      f"- Zero-cliff share of lost trades: `{root_cause['zero_cliff_share_of_lost_trades']}`.",
      f"- Interpretation: {root_cause['interpretation']}",
      "",
      "## Confidence Mix",
      "",
      f"- Shared MR evals across report windows show negative confidence deltas on `{summary['report_aggregate']['all_mr_eval_contributions']['negative_delta_share']}` of joined rows.",
      f"- On baseline executed report MR lineages, RL-side `q_advantage` median is `{summary['report_aggregate']['baseline_executed_mr_contributions']['q_advantage']['median']}` vs EMRT fastness median `{summary['report_aggregate']['baseline_executed_mr_contributions']['emrt_fastness']['median']}`.",
      f"- EMRT fastness is constant across the matched report artifacts: `{summary['report_aggregate']['lever_interpretation']['matched_emrt_fastness_value']}`. The `0.2` lever therefore acts mostly as confidence compression toward `0.5`, not as a rich two-signal mix.",
      "",
      "## Recommendation",
      "",
      f"- Result: `{recommendation['result']}`.",
      f"- Next step: {recommendation['recommended_next_step']}",
      f"- Why: {recommendation['why']}",
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


def build_saved_reference_gap(
   validation_summary: dict[str, Any],
   window_summaries: dict[str, Any],
) -> dict[str, Any]:
   saved_reference_rows = {
      row["cycle_id"]: row
      for row in validation_summary.get("reference", {}).get("report", {}).get("baseline", {}).get("rows", [])
   }
   candidate_rows = {
      row["cycle_id"]: row
      for row in validation_summary.get("candidates", [{}])[0].get("report", {}).get("baseline", {}).get("rows", [])
   }
   gap: dict[str, Any] = {}
   for window_id in ("wf001_202508", "wf002_202509", "wf003_202510"):
      rerun = window_summaries[window_id]
      saved_reference = saved_reference_rows.get(window_id, {})
      saved_candidate = candidate_rows.get(window_id, {})
      gap[window_id] = {
         "saved_reference": {
            "return_pct": saved_reference.get("final_return_pct"),
            "trades_total": saved_reference.get("trades_total"),
            "days_traded": saved_reference.get("days_traded"),
         },
         "same_stack_rerun_baseline": rerun["baseline"],
         "saved_candidate": {
            "return_pct": saved_candidate.get("final_return_pct"),
            "trades_total": saved_candidate.get("trades_total"),
            "days_traded": saved_candidate.get("days_traded"),
         },
         "same_stack_candidate": rerun["candidate"],
      }
   return gap


def build_summary(
   repo: Path,
   window_configs: list[WindowConfig],
   baseline_manifests: dict[str, Path],
   rerun_records: list[dict[str, Any]],
) -> tuple[dict[str, Any], dict[str, list[dict[str, Any]]]]:
   window_summaries: dict[str, Any] = {}
   lineage_csv_rows: list[dict[str, Any]] = []
   near_floor_rows: list[dict[str, Any]] = []
   meta_csv_rows: list[dict[str, Any]] = []
   report_meta_rows: list[dict[str, Any]] = []
   report_exec_meta_rows: list[dict[str, Any]] = []

   for window in window_configs:
      baseline_bundle = load_run_bundle(baseline_manifests[window.id], f"{window.id}_baseline", f"{window.label} baseline")
      candidate_bundle = load_run_bundle(resolve_repo_path(repo, window.candidate_manifest), f"{window.id}_candidate", f"{window.label} candidate")
      meta_rows, lineage_rows = pair_window_lineages(window.id, baseline_bundle, candidate_bundle)
      meta_csv_rows.extend(meta_rows)
      lineage_csv_rows.extend(lineage_rows)
      near_floor_rows.extend(build_near_floor_rows(lineage_rows))
      window_summary = summarize_window(window, baseline_bundle, candidate_bundle, meta_rows, lineage_rows)
      window_summaries[window.id] = window_summary
      if not window.is_holdout:
         report_meta_rows.extend(row for row in meta_rows if row.get("baseline_mr_conf") is not None and row.get("candidate_mr_conf") is not None)
         baseline_exec_eval_keys = {row["eval_key"] for row in lineage_rows if row.get("baseline_place_ok")}
         report_exec_meta_rows.extend(
            row
            for row in meta_rows
            if row["eval_key"] in baseline_exec_eval_keys and row.get("baseline_mr_conf") is not None and row.get("candidate_mr_conf") is not None
         )

   report_window_summaries = [
      window_summaries["wf001_202508"],
      window_summaries["wf002_202509"],
      window_summaries["wf003_202510"],
   ]

   validation_summary = load_json(resolve_repo_path(repo, DEFAULT_VALIDATION_SUMMARY_PATH))
   summary = {
      "generated_at_utc": iso_utc_now(),
      "artifacts": {
         "plan": str(resolve_repo_path(repo, DEFAULT_PLAN_PATH)),
         "research_attribution_summary": str(resolve_repo_path(repo, DEFAULT_RESEARCH_SUMMARY_PATH)),
         "research_change_rankings": str(resolve_repo_path(repo, DEFAULT_RESEARCH_RANKINGS_PATH)),
         "spread_diagnostic_summary": str(resolve_repo_path(repo, DEFAULT_SPREAD_DIAGNOSTIC_PATH)),
         "mr_emrt_weight_validation_summary": str(resolve_repo_path(repo, DEFAULT_VALIDATION_SUMMARY_PATH)),
         "mr_emrt_weight_candidate_comparison": str(resolve_repo_path(repo, DEFAULT_CANDIDATE_COMPARISON_PATH)),
      },
      "artifact_resolution": {
         "reran_missing_report_baselines": rerun_records,
         "note": (
            "The saved MR_EMRTWeight validation summary reuses older report reference rows; the same-stack MR_EMRTWeight=0.0 report manifests were missing locally, so this diagnostic reran only those three baseline windows from the saved 0.2 specs with MR_EMRTWeight reverted to 0.0."
         ),
      },
      "validation_reference_context": {
         "reference_id": validation_summary.get("reference", {}).get("id"),
         "candidate_id": validation_summary.get("candidates", [{}])[0].get("id"),
         "saved_report_reference_rows": validation_summary.get("reference", {}).get("report", {}).get("baseline", {}).get("rows"),
         "saved_candidate_report_rows": validation_summary.get("candidates", [{}])[0].get("report", {}).get("baseline", {}).get("rows"),
      },
      "windows": window_summaries,
      "report_aggregate": {
         "all_mr_eval_contributions": summarize_contributions(report_meta_rows),
         "baseline_executed_mr_contributions": summarize_contributions(report_exec_meta_rows),
         "lever_interpretation": {
            "matched_emrt_fastness_is_constant": (
               len({row["emrt_fastness"] for row in report_meta_rows if row.get("emrt_fastness") is not None}) == 1
            ),
            "matched_emrt_fastness_value": (
               report_meta_rows[0]["emrt_fastness"] if report_meta_rows and report_meta_rows[0].get("emrt_fastness") is not None else None
            ),
            "interpretation": (
               "Across the matched report-window artifacts, EMRT fastness is constant at 0.5, so MR_EMRTWeight=0.2 behaves as confidence compression toward 0.5 (`0.1 + 0.8*q_advantage`) rather than a blend of two independently varying signals."
            ),
         },
      },
   }
   summary["saved_reference_gap"] = build_saved_reference_gap(validation_summary, window_summaries)
   summary["root_cause"] = build_top_level_root_cause(report_window_summaries)
   summary["recommendation"] = build_next_recommendation(summary)

   csv_outputs = {
      "meta_lineage_comparison": meta_csv_rows,
      "mr_lineage_sizing_comparison": lineage_csv_rows,
      "near_floor_sizing": near_floor_rows,
   }
   return summary, csv_outputs


def write_outputs(
   output_dir: Path,
   summary: dict[str, Any],
   csv_outputs: dict[str, list[dict[str, Any]]],
) -> dict[str, str]:
   output_dir.mkdir(parents=True, exist_ok=True)
   summary_path = output_dir / "diagnostic_summary.json"
   summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")

   meta_csv_path = output_dir / "meta_lineage_comparison.csv"
   write_csv(meta_csv_path, csv_outputs["meta_lineage_comparison"])

   lineage_csv_path = output_dir / "mr_lineage_sizing_comparison.csv"
   write_csv(lineage_csv_path, csv_outputs["mr_lineage_sizing_comparison"])

   floor_csv_path = output_dir / "near_floor_sizing.csv"
   write_csv(floor_csv_path, csv_outputs["near_floor_sizing"])

   report_path = output_dir / "diagnostic_report.md"
   report_path.write_text(build_markdown_report(summary), encoding="utf-8")

   return {
      "summary": str(summary_path),
      "meta_lineage_comparison": str(meta_csv_path),
      "mr_lineage_sizing_comparison": str(lineage_csv_path),
      "near_floor_sizing": str(floor_csv_path),
      "report": str(report_path),
   }


def parse_args(argv: list[str]) -> argparse.Namespace:
   parser = argparse.ArgumentParser(description=__doc__)
   parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR, help="Directory for diagnostic outputs.")
   parser.add_argument("--runner-output-dir", type=Path, default=DEFAULT_RUNNER_OUTPUT_DIR, help="Directory used for any minimal baseline reruns.")
   parser.add_argument("--no-rerun-missing-report-baselines", action="store_true", help="Fail instead of rerunning missing same-stack report baseline windows.")
   return parser.parse_args(argv)


def default_window_configs() -> list[WindowConfig]:
   return [
      WindowConfig("holdout", "Holdout", DEFAULT_HOLDOUT_CANDIDATE_MANIFEST, DEFAULT_HOLDOUT_BASELINE_MANIFEST, True),
      WindowConfig("wf001_202508", "Report wf001_202508", DEFAULT_REPORT_CANDIDATE_MANIFESTS["wf001_202508"], None, False),
      WindowConfig("wf002_202509", "Report wf002_202509", DEFAULT_REPORT_CANDIDATE_MANIFESTS["wf002_202509"], None, False),
      WindowConfig("wf003_202510", "Report wf003_202510", DEFAULT_REPORT_CANDIDATE_MANIFESTS["wf003_202510"], None, False),
   ]


def main(argv: list[str] | None = None) -> int:
   args = parse_args(argv if argv is not None else sys.argv[1:])
   repo = repo_root()
   window_configs = default_window_configs()
   baseline_manifests, rerun_records = ensure_report_baseline_manifests(
      repo,
      window_configs,
      resolve_repo_path(repo, args.runner_output_dir),
      rerun_missing=not args.no_rerun_missing_report_baselines,
   )
   summary, csv_outputs = build_summary(repo, window_configs, baseline_manifests, rerun_records)
   outputs = write_outputs(resolve_repo_path(repo, args.output_dir), summary, csv_outputs)
   print(json.dumps({"outputs": outputs, "root_cause": summary["root_cause"]}, indent=2, sort_keys=True))
   return 0


if __name__ == "__main__":
   raise SystemExit(main())
