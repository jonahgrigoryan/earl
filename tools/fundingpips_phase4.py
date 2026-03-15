#!/usr/bin/env python3
"""FundingPips Phase 4 walk-forward and stress harness."""

from __future__ import annotations

import argparse
import collections
import csv
import dataclasses
import json
import sys
from datetime import date, timedelta
from pathlib import Path
from typing import Any

try:
   from tools import fundingpips_hpo as hpo
   from tools import fundingpips_mt5_runner as mt5_runner
except ModuleNotFoundError:  # pragma: no cover - script execution fallback
   sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
   from tools import fundingpips_hpo as hpo
   from tools import fundingpips_mt5_runner as mt5_runner


DEFAULT_PHASE4_ROOT = Path(".tmp") / "fundingpips_phase4"
DEFAULT_WINDOW_PHASES_PRIMARY = ("search", "report")
DEFAULT_WINDOW_PHASES_NEIGHBOR = ("report",)
SUPPORTED_WINDOW_PHASES = frozenset(("search", "report"))


@dataclasses.dataclass(frozen=True)
class SyntheticStressSpec:
   spread_return_penalty_pct_per_trade: float = 0.0
   slippage_return_penalty_pct_per_trade: float = 0.0
   delay_return_penalty_pct_per_trade: float = 0.0
   commission_money_per_trade: float = 0.0
   daily_dd_multiplier: float = 1.0
   overall_dd_multiplier: float = 1.0

   def is_identity(self) -> bool:
      return (
         self.spread_return_penalty_pct_per_trade == 0.0
         and self.slippage_return_penalty_pct_per_trade == 0.0
         and self.delay_return_penalty_pct_per_trade == 0.0
         and self.commission_money_per_trade == 0.0
         and self.daily_dd_multiplier == 1.0
         and self.overall_dd_multiplier == 1.0
      )


@dataclasses.dataclass(frozen=True)
class Phase4ScenarioSpec:
   id: str
   severity: str
   weight: float
   set_overrides: dict[str, Any]
   execution_mode: int | None
   source_scenario_id: str | None
   stress: SyntheticStressSpec


@dataclasses.dataclass(frozen=True)
class Phase4CandidateSpec:
   id: str
   group: str
   set_overrides: dict[str, Any]
   parent_candidate_id: str | None
   window_phases: tuple[str, ...]


@dataclasses.dataclass(frozen=True)
class WalkForwardConfig:
   search_window_months: int
   report_window_months: int
   roll_months: int


@dataclasses.dataclass(frozen=True)
class Phase4Spec:
   name: str
   rules_profile: str
   symbol: str
   period: str
   from_date: date
   to_date: date
   base_set: Path
   walk_forward: WalkForwardConfig
   primary_candidates: tuple[Phase4CandidateSpec, ...]
   neighbor_candidates: tuple[Phase4CandidateSpec, ...]
   scenarios: tuple[Phase4ScenarioSpec, ...]
   source_path: Path


@dataclasses.dataclass(frozen=True)
class WalkForwardCycle:
   id: str
   search_from_date: date
   search_to_date: date
   report_from_date: date
   report_to_date: date


@dataclasses.dataclass(frozen=True)
class Phase4Paths:
   phase4_dir: Path
   manifest_path: Path
   cycles_path: Path
   actual_runs_dir: Path
   scenario_records_path: Path
   window_summaries_path: Path
   phase4_summary_path: Path


def repo_root() -> Path:
   return mt5_runner.repo_root()


def parse_window_phases(raw_value: Any, *, default: tuple[str, ...]) -> tuple[str, ...]:
   if raw_value is None:
      return default
   if not isinstance(raw_value, list) or not raw_value:
      raise ValueError("window_phases must be a non-empty list when provided")

   normalized: list[str] = []
   seen: set[str] = set()
   for value in raw_value:
      phase = str(value).strip().lower()
      if phase not in SUPPORTED_WINDOW_PHASES:
         raise ValueError(f"Unsupported window phase: {value!r}")
      if phase in seen:
         continue
      normalized.append(phase)
      seen.add(phase)
   return tuple(normalized)


def parse_synthetic_stress(raw_value: Any, *, field_name: str) -> SyntheticStressSpec:
   if raw_value is None:
      return SyntheticStressSpec()
   if not isinstance(raw_value, dict):
      raise ValueError(f"{field_name} must be an object")

   stress = SyntheticStressSpec(
      spread_return_penalty_pct_per_trade=hpo.parse_float(
         raw_value.get("spread_return_penalty_pct_per_trade", 0.0),
         f"{field_name}.spread_return_penalty_pct_per_trade",
      ),
      slippage_return_penalty_pct_per_trade=hpo.parse_float(
         raw_value.get("slippage_return_penalty_pct_per_trade", 0.0),
         f"{field_name}.slippage_return_penalty_pct_per_trade",
      ),
      delay_return_penalty_pct_per_trade=hpo.parse_float(
         raw_value.get("delay_return_penalty_pct_per_trade", 0.0),
         f"{field_name}.delay_return_penalty_pct_per_trade",
      ),
      commission_money_per_trade=hpo.parse_float(
         raw_value.get("commission_money_per_trade", 0.0),
         f"{field_name}.commission_money_per_trade",
      ),
      daily_dd_multiplier=hpo.parse_float(
         raw_value.get("daily_dd_multiplier", 1.0),
         f"{field_name}.daily_dd_multiplier",
      ),
      overall_dd_multiplier=hpo.parse_float(
         raw_value.get("overall_dd_multiplier", 1.0),
         f"{field_name}.overall_dd_multiplier",
      ),
   )
   if stress.daily_dd_multiplier <= 0.0:
      raise ValueError(f"{field_name}.daily_dd_multiplier must be > 0")
   if stress.overall_dd_multiplier <= 0.0:
      raise ValueError(f"{field_name}.overall_dd_multiplier must be > 0")
   return stress


def parse_phase4_scenarios(raw_scenarios: Any) -> tuple[Phase4ScenarioSpec, ...]:
   if not isinstance(raw_scenarios, list) or not raw_scenarios:
      raise ValueError("scenarios must be a non-empty list")

   scenarios: list[Phase4ScenarioSpec] = []
   seen_ids: set[str] = set()
   actual_scenario_ids: set[str] = set()

   for index, raw_scenario in enumerate(raw_scenarios):
      if not isinstance(raw_scenario, dict):
         raise ValueError(f"scenarios[{index}] must be an object")
      scenario_id = str(raw_scenario.get("id", "")).strip()
      if not scenario_id:
         raise ValueError(f"scenarios[{index}].id is required")
      if scenario_id in seen_ids:
         raise ValueError(f"Duplicate scenario id: {scenario_id}")
      severity = str(raw_scenario.get("severity", "baseline")).strip().lower()
      if severity not in ("baseline", "mild", "moderate", "custom"):
         raise ValueError(f"Unsupported scenarios[{index}].severity: {severity!r}")
      weight = hpo.parse_float(raw_scenario.get("weight"), f"scenarios[{index}].weight")
      if weight <= 0.0:
         raise ValueError(f"scenarios[{index}].weight must be > 0")
      set_overrides = raw_scenario.get("set_overrides") or {}
      if not isinstance(set_overrides, dict):
         raise ValueError(f"scenarios[{index}].set_overrides must be an object")
      raw_execution_mode = raw_scenario.get("execution_mode")
      execution_mode = None if raw_execution_mode is None else hpo.parse_int(
         raw_execution_mode,
         f"scenarios[{index}].execution_mode",
      )
      source_scenario_id = raw_scenario.get("source_scenario_id")
      if source_scenario_id is not None:
         source_scenario_id = str(source_scenario_id).strip() or None
      stress = parse_synthetic_stress(
         raw_scenario.get("synthetic_stress"),
         field_name=f"scenarios[{index}].synthetic_stress",
      )
      if source_scenario_id is not None and execution_mode is not None:
         raise ValueError(
            f"scenarios[{index}] cannot combine source_scenario_id with execution_mode overrides"
         )
      if source_scenario_id is not None and set_overrides:
         raise ValueError(
            f"scenarios[{index}] cannot combine source_scenario_id with set_overrides"
         )

      scenario = Phase4ScenarioSpec(
         id=scenario_id,
         severity=severity,
         weight=weight,
         set_overrides=dict(set_overrides),
         execution_mode=execution_mode,
         source_scenario_id=source_scenario_id,
         stress=stress,
      )
      scenarios.append(scenario)
      seen_ids.add(scenario_id)
      if source_scenario_id is None:
         actual_scenario_ids.add(scenario_id)

   if not actual_scenario_ids:
      raise ValueError("At least one concrete runner scenario without source_scenario_id is required")

   for scenario in scenarios:
      if scenario.source_scenario_id is None:
         continue
      if scenario.source_scenario_id not in actual_scenario_ids:
         raise ValueError(
            f"Scenario {scenario.id} references unknown concrete source_scenario_id "
            f"{scenario.source_scenario_id!r}"
         )
   return tuple(scenarios)


def parse_phase4_primary_candidates(raw_value: Any) -> tuple[Phase4CandidateSpec, ...]:
   if not isinstance(raw_value, list) or not raw_value:
      raise ValueError("primary_candidates must be a non-empty list")

   candidates: list[Phase4CandidateSpec] = []
   seen_ids: set[str] = set()
   for index, raw_candidate in enumerate(raw_value):
      if not isinstance(raw_candidate, dict):
         raise ValueError(f"primary_candidates[{index}] must be an object")
      candidate_id = str(raw_candidate.get("id", "")).strip()
      if not candidate_id:
         raise ValueError(f"primary_candidates[{index}].id is required")
      if candidate_id in seen_ids:
         raise ValueError(f"Duplicate primary candidate id: {candidate_id}")
      set_overrides = raw_candidate.get("set_overrides") or {}
      if not isinstance(set_overrides, dict) or not set_overrides:
         raise ValueError(f"primary_candidates[{index}].set_overrides must be a non-empty object")
      candidate = Phase4CandidateSpec(
         id=candidate_id,
         group="primary",
         set_overrides=dict(set_overrides),
         parent_candidate_id=None,
         window_phases=parse_window_phases(
            raw_candidate.get("window_phases"),
            default=DEFAULT_WINDOW_PHASES_PRIMARY,
         ),
      )
      candidates.append(candidate)
      seen_ids.add(candidate_id)
   return tuple(candidates)


def parse_phase4_neighbor_candidates(
   raw_value: Any,
   primary_candidates: tuple[Phase4CandidateSpec, ...],
) -> tuple[Phase4CandidateSpec, ...]:
   if raw_value is None:
      return ()
   if not isinstance(raw_value, list):
      raise ValueError("neighbor_candidates must be a list when provided")

   primary_index = {candidate.id: candidate for candidate in primary_candidates}
   candidates: list[Phase4CandidateSpec] = []
   seen_ids: set[str] = set(primary_index.keys())

   for index, raw_candidate in enumerate(raw_value):
      if not isinstance(raw_candidate, dict):
         raise ValueError(f"neighbor_candidates[{index}] must be an object")
      candidate_id = str(raw_candidate.get("id", "")).strip()
      if not candidate_id:
         raise ValueError(f"neighbor_candidates[{index}].id is required")
      if candidate_id in seen_ids:
         raise ValueError(f"Duplicate candidate id: {candidate_id}")
      base_candidate_id = str(raw_candidate.get("base_candidate_id", "")).strip() or None
      raw_overrides = raw_candidate.get("set_overrides") or {}
      if not isinstance(raw_overrides, dict):
         raise ValueError(f"neighbor_candidates[{index}].set_overrides must be an object")
      if base_candidate_id is None and not raw_overrides:
         raise ValueError(
            f"neighbor_candidates[{index}] requires either base_candidate_id or a full set_overrides object"
         )

      if base_candidate_id is None:
         merged_overrides = dict(raw_overrides)
      else:
         if base_candidate_id not in primary_index:
            raise ValueError(
               f"neighbor_candidates[{index}].base_candidate_id references unknown primary candidate "
               f"{base_candidate_id!r}"
            )
         merged_overrides = dict(primary_index[base_candidate_id].set_overrides)
         merged_overrides.update(raw_overrides)

      candidate = Phase4CandidateSpec(
         id=candidate_id,
         group="neighbor",
         set_overrides=merged_overrides,
         parent_candidate_id=base_candidate_id,
         window_phases=parse_window_phases(
            raw_candidate.get("window_phases"),
            default=DEFAULT_WINDOW_PHASES_NEIGHBOR,
         ),
      )
      candidates.append(candidate)
      seen_ids.add(candidate_id)
   return tuple(candidates)


def load_phase4_spec(path: Path) -> Phase4Spec:
   raw = hpo.load_json_file(path)
   name = str(raw.get("name", "")).strip()
   if not name:
      raise ValueError(f"Phase 4 spec name is required: {path}")
   rules_profile = str(raw.get("rules_profile", "")).strip()
   if not rules_profile:
      raise ValueError(f"rules_profile is required: {path}")
   symbol = str(raw.get("symbol", "")).strip()
   if not symbol:
      raise ValueError(f"symbol is required: {path}")
   period = str(raw.get("period", "")).strip()
   if not period:
      raise ValueError(f"period is required: {path}")
   base_set = Path(str(raw.get("base_set", "")).strip())
   if not str(base_set):
      raise ValueError(f"base_set is required: {path}")
   walk_forward_raw = raw.get("walk_forward")
   if not isinstance(walk_forward_raw, dict):
      raise ValueError("walk_forward must be an object")
   walk_forward = WalkForwardConfig(
      search_window_months=hpo.parse_int(
         walk_forward_raw.get("search_window_months"),
         "walk_forward.search_window_months",
      ),
      report_window_months=hpo.parse_int(
         walk_forward_raw.get("report_window_months"),
         "walk_forward.report_window_months",
      ),
      roll_months=hpo.parse_int(
         walk_forward_raw.get("roll_months"),
         "walk_forward.roll_months",
      ),
   )
   if walk_forward.search_window_months < 1:
      raise ValueError("walk_forward.search_window_months must be >= 1")
   if walk_forward.report_window_months < 1:
      raise ValueError("walk_forward.report_window_months must be >= 1")
   if walk_forward.roll_months < 1:
      raise ValueError("walk_forward.roll_months must be >= 1")

   primary_candidates = parse_phase4_primary_candidates(raw.get("primary_candidates"))
   neighbor_candidates = parse_phase4_neighbor_candidates(raw.get("neighbor_candidates"), primary_candidates)
   scenarios = parse_phase4_scenarios(raw.get("scenarios"))
   from_date = hpo.parse_iso_date(str(raw.get("from_date", "")))
   to_date = hpo.parse_iso_date(str(raw.get("to_date", "")))
   if to_date < from_date:
      raise ValueError(f"to_date must be >= from_date: {path}")

   return Phase4Spec(
      name=name,
      rules_profile=rules_profile,
      symbol=symbol,
      period=period,
      from_date=from_date,
      to_date=to_date,
      base_set=base_set,
      walk_forward=walk_forward,
      primary_candidates=primary_candidates,
      neighbor_candidates=neighbor_candidates,
      scenarios=scenarios,
      source_path=path.resolve(),
   )


def build_phase4_paths(phase4_name: str, repo: Path | None = None) -> Phase4Paths:
   root = repo or repo_root()
   phase4_dir = (root / DEFAULT_PHASE4_ROOT / phase4_name).resolve()
   return Phase4Paths(
      phase4_dir=phase4_dir,
      manifest_path=phase4_dir / "phase4_manifest.json",
      cycles_path=phase4_dir / "walk_forward_cycles.json",
      actual_runs_dir=phase4_dir / "actual_runs",
      scenario_records_path=phase4_dir / "scenario_records.jsonl",
      window_summaries_path=phase4_dir / "window_summaries.json",
      phase4_summary_path=phase4_dir / "phase4_summary.json",
   )


def month_floor(value: date) -> date:
   return date(value.year, value.month, 1)


def add_months(value: date, months: int) -> date:
   month_index = (value.year * 12) + (value.month - 1) + months
   year = month_index // 12
   month = (month_index % 12) + 1
   return date(year, month, 1)


def build_walk_forward_cycles(spec: Phase4Spec) -> tuple[WalkForwardCycle, ...]:
   report_month = add_months(month_floor(spec.from_date), spec.walk_forward.search_window_months)
   end_month = month_floor(spec.to_date)
   cycles: list[WalkForwardCycle] = []
   index = 1

   while report_month <= end_month:
      search_start = hpo.snap_start_to_weekday(
         max(spec.from_date, add_months(report_month, -spec.walk_forward.search_window_months))
      )
      search_end = hpo.snap_end_to_weekday(min(spec.to_date, report_month - timedelta(days=1)))
      report_start = hpo.snap_start_to_weekday(max(spec.from_date, report_month))
      report_end = hpo.snap_end_to_weekday(
         min(spec.to_date, add_months(report_month, spec.walk_forward.report_window_months) - timedelta(days=1))
      )

      if search_end >= search_start and report_end >= report_start:
         cycles.append(
            WalkForwardCycle(
               id=f"wf{index:03d}_{report_start.strftime('%Y%m')}",
               search_from_date=search_start,
               search_to_date=search_end,
               report_from_date=report_start,
               report_to_date=report_end,
            )
         )
         index += 1
      report_month = add_months(report_month, spec.walk_forward.roll_months)

   if not cycles:
      raise ValueError("Phase 4 spec did not produce any walk-forward cycles")
   return tuple(cycles)


def cycle_window_dates(cycle: WalkForwardCycle, window_phase: str) -> tuple[date, date]:
   if window_phase == "search":
      return cycle.search_from_date, cycle.search_to_date
   if window_phase == "report":
      return cycle.report_from_date, cycle.report_to_date
   raise ValueError(f"Unsupported window_phase: {window_phase!r}")


def cycle_window_trading_days(cycle: WalkForwardCycle, window_phase: str) -> int:
   start_date, end_date = cycle_window_dates(cycle, window_phase)
   return len(hpo.iter_trading_days(start_date, end_date))


def cycles_to_payload(cycles: tuple[WalkForwardCycle, ...]) -> list[dict[str, Any]]:
   return [
      {
         "id": cycle.id,
         "search_from_date": hpo.iso_date(cycle.search_from_date),
         "search_to_date": hpo.iso_date(cycle.search_to_date),
         "report_from_date": hpo.iso_date(cycle.report_from_date),
         "report_to_date": hpo.iso_date(cycle.report_to_date),
      }
      for cycle in cycles
   ]


def write_phase4_manifest(
   paths: Phase4Paths,
   spec: Phase4Spec,
   rules_profile: hpo.RulesProfile,
   cycles: tuple[WalkForwardCycle, ...],
) -> None:
   hpo.write_json_file(
      paths.manifest_path,
      {
         "generated_at_utc": hpo.utc_now_iso(),
         "phase4_name": spec.name,
         "phase4_spec_path": str(spec.source_path),
         "rules_profile_id": rules_profile.id,
         "rules_profile_path": str(hpo.rules_profile_path(rules_profile.id)),
         "phase4_dir": str(paths.phase4_dir),
         "cycles_path": str(paths.cycles_path),
         "actual_runs_dir": str(paths.actual_runs_dir),
         "scenario_records_path": str(paths.scenario_records_path),
         "window_summaries_path": str(paths.window_summaries_path),
         "phase4_summary_path": str(paths.phase4_summary_path),
         "cycle_count": len(cycles),
         "primary_candidate_ids": [candidate.id for candidate in spec.primary_candidates],
         "neighbor_candidate_ids": [candidate.id for candidate in spec.neighbor_candidates],
         "scenario_ids": [scenario.id for scenario in spec.scenarios],
      },
   )


def write_phase4_cycles(paths: Phase4Paths, cycles: tuple[WalkForwardCycle, ...]) -> None:
   hpo.write_json_file(
      paths.cycles_path,
      {
         "generated_at_utc": hpo.utc_now_iso(),
         "cycle_count": len(cycles),
         "cycles": cycles_to_payload(cycles),
      },
   )


def build_metric_record(
   *,
   rules_profile: hpo.RulesProfile,
   final_return_pct: float,
   max_daily_dd_pct: float,
   max_overall_dd_pct: float,
   pass_days_traded: int,
   trades_total: int,
   days_traded: int,
   min_trade_days_required: int,
   observed_server_days: int,
   window_trading_days: int,
) -> dict[str, Any]:
   required_trade_days = max(min_trade_days_required, rules_profile.min_trade_days)
   breach_flag = (
      max_daily_dd_pct >= rules_profile.daily_loss_cap_pct
      or max_overall_dd_pct >= rules_profile.overall_loss_cap_pct
   )
   target_hit = final_return_pct >= rules_profile.target_profit_pct
   min_trade_days_met = days_traded >= required_trade_days
   pass_flag = target_hit and min_trade_days_met and not breach_flag
   progress_ratio = hpo.clamp(final_return_pct / rules_profile.target_profit_pct, -1.0, 1.0)
   daily_slack_ratio = hpo.clamp(
      (rules_profile.daily_loss_cap_pct - max_daily_dd_pct) / rules_profile.daily_loss_cap_pct,
      0.0,
      1.0,
   )
   overall_slack_ratio = hpo.clamp(
      (rules_profile.overall_loss_cap_pct - max_overall_dd_pct) / rules_profile.overall_loss_cap_pct,
      0.0,
      1.0,
   )
   if not pass_flag:
      speed_ratio = 0.0
   else:
      denominator = window_trading_days - required_trade_days
      if denominator <= 0:
         speed_ratio = 1.0
      else:
         speed_ratio = hpo.clamp(
            1.0 - ((pass_days_traded - required_trade_days) / denominator),
            0.0,
            1.0,
         )
   zero_trade_flag = (trades_total == 0)
   reset_exposure_ratio = hpo.clamp(max_daily_dd_pct / rules_profile.daily_loss_cap_pct, 0.0, 1.0)
   return {
      "valid": True,
      "pass_flag": pass_flag,
      "breach_flag": breach_flag,
      "progress_ratio": progress_ratio,
      "daily_slack_ratio": daily_slack_ratio,
      "overall_slack_ratio": overall_slack_ratio,
      "speed_ratio": speed_ratio,
      "zero_trade_flag": zero_trade_flag,
      "reset_exposure_ratio": reset_exposure_ratio,
      "summary_metrics": {
         "final_return_pct": final_return_pct,
         "max_daily_dd_pct": max_daily_dd_pct,
         "max_overall_dd_pct": max_overall_dd_pct,
         "pass_days_traded": pass_days_traded,
         "trades_total": trades_total,
         "days_traded": days_traded,
         "min_trade_days_required": required_trade_days,
         "observed_server_days": observed_server_days,
      },
   }


def normalize_counter(counter: collections.Counter[str]) -> dict[str, Any]:
   total = int(sum(counter.values()))
   counts = {key: int(counter[key]) for key in sorted(counter)}
   shares = {
      key: round(counts[key] / total, 6)
      for key in counts
   } if total > 0 else {}
   return {
      "total": total,
      "counts": counts,
      "shares": shares,
   }


def parse_fields_json(raw_value: str) -> dict[str, Any]:
   if not raw_value:
      return {}
   try:
      parsed = json.loads(raw_value)
   except ValueError:
      return {}
   return parsed if isinstance(parsed, dict) else {}


def iter_log_rows(path: Path) -> list[dict[str, str]]:
   rows: list[dict[str, str]] = []
   with path.open("r", encoding="utf-8", newline="") as handle:
      for index, raw_line in enumerate(handle):
         line = raw_line.rstrip("\r\n")
         if not line:
            continue
         if index == 0 and line.startswith("date,time,event,component,level,message,fields_json"):
            continue
         parts = line.split(",", 6)
         if len(parts) < 7:
            continue
         rows.append(
            {
               "date": parts[0],
               "time": parts[1],
               "event": parts[2],
               "component": parts[3],
               "level": parts[4],
               "message": parts[5],
               "fields_json": parts[6],
            }
         )
   return rows


def summarize_regime_logs(decision_logs: list[str]) -> dict[str, Any]:
   overall_regimes: collections.Counter[str] = collections.Counter()
   by_symbol: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
   by_day: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)

   for raw_path in decision_logs:
      path = Path(raw_path)
      if not path.exists():
         continue
      for row in iter_log_rows(path):
         if row.get("component") != "MetaPolicy" or row.get("message") != "EVAL":
            continue
         fields = parse_fields_json(row.get("fields_json", ""))
         regime = str(fields.get("regime", "UNKNOWN")).strip().upper() or "UNKNOWN"
         symbol = str(fields.get("symbol", "UNKNOWN")).strip().upper() or "UNKNOWN"
         server_day = str(row.get("date", "")).strip()
         overall_regimes[regime] += 1
         by_symbol[symbol][regime] += 1
         if server_day:
            by_day[server_day][regime] += 1

   preferred_symbol = "XAUUSD" if "XAUUSD" in by_symbol else ""
   if not preferred_symbol and by_symbol:
      preferred_symbol = max(
         sorted(by_symbol.keys()),
         key=lambda item: int(sum(by_symbol[item].values())),
      )
   dominant_counter = by_symbol.get(preferred_symbol) if preferred_symbol else overall_regimes
   dominant_regime = ""
   if dominant_counter:
      dominant_regime = max(
         sorted(dominant_counter.keys()),
         key=lambda item: int(dominant_counter[item]),
      )

   daily_dominant = {
      server_day: max(
         sorted(counter.keys()),
         key=lambda item: int(counter[item]),
      )
      for server_day, counter in sorted(by_day.items())
      if counter
   }
   return {
      "preferred_symbol": preferred_symbol,
      "dominant_regime": dominant_regime,
      "overall": normalize_counter(overall_regimes),
      "by_symbol": {
         symbol: normalize_counter(counter)
         for symbol, counter in sorted(by_symbol.items())
      },
      "daily_dominant_regime": daily_dominant,
   }


def summarize_daily_regimes(
   daily_rows: list[dict[str, str]],
   daily_dominant_regime: dict[str, str],
) -> dict[str, Any]:
   aggregates: dict[str, dict[str, Any]] = {}
   for row in daily_rows:
      server_day = str(row.get("server_date", "")).strip()
      regime = daily_dominant_regime.get(server_day, "UNKNOWN")
      baseline_used = hpo.parse_float(row.get("baseline_used", 0.0), f"{server_day}.baseline_used")
      end_equity = hpo.parse_float(row.get("end_equity", baseline_used), f"{server_day}.end_equity")
      max_daily_dd_pct = hpo.parse_float(row.get("max_daily_dd_pct", 0.0), f"{server_day}.max_daily_dd_pct")
      daily_breach = hpo.parse_bool(row.get("daily_breach", "false"), f"{server_day}.daily_breach")

      bucket = aggregates.setdefault(
         regime,
         {
            "day_count": 0,
            "pnl_money_sum": 0.0,
            "max_daily_dd_pct_max": 0.0,
            "daily_breach_count": 0,
         },
      )
      bucket["day_count"] += 1
      bucket["pnl_money_sum"] += (end_equity - baseline_used)
      bucket["max_daily_dd_pct_max"] = max(bucket["max_daily_dd_pct_max"], max_daily_dd_pct)
      bucket["daily_breach_count"] += 1 if daily_breach else 0

   return {
      regime: {
         "day_count": int(values["day_count"]),
         "pnl_money_sum": round(float(values["pnl_money_sum"]), 2),
         "max_daily_dd_pct_max": round(float(values["max_daily_dd_pct_max"]), 6),
         "daily_breach_count": int(values["daily_breach_count"]),
      }
      for regime, values in sorted(aggregates.items())
   }


def normalize_actual_run_record(
   *,
   spec: Phase4Spec,
   rules_profile: hpo.RulesProfile,
   cycle: WalkForwardCycle,
   window_phase: str,
   candidate: Phase4CandidateSpec,
   scenario: Phase4ScenarioSpec,
   result: dict[str, Any],
) -> dict[str, Any]:
   manifest_path = Path(result["manifest_path"])
   summary_path = Path(result["summary_path"])
   daily_path = Path(result["daily_path"])
   report_path_value = result.get("report_path")
   report_path = Path(report_path_value) if report_path_value else None

   if not manifest_path.exists():
      raise FileNotFoundError(f"Runner manifest missing: {manifest_path}")
   if not summary_path.exists():
      raise FileNotFoundError(f"Summary artifact missing: {summary_path}")
   if not daily_path.exists():
      raise FileNotFoundError(f"Daily artifact missing: {daily_path}")

   manifest = hpo.load_json_file(manifest_path)
   summary = hpo.load_json_file(summary_path)
   hpo.validate_summary(summary, summary_path)
   daily_rows = hpo.load_csv_rows(daily_path)
   report_metrics = hpo.parse_mt5_report_metrics(report_path)
   decision_logs = list(result.get("decision_logs") or [])
   event_logs = list(result.get("event_logs") or [])

   start_date, end_date = cycle_window_dates(cycle, window_phase)
   window_trading_days = cycle_window_trading_days(cycle, window_phase)
   pass_days_traded = hpo.parse_int(summary.get("pass_days_traded", 0), "pass_days_traded")
   trades_total = hpo.parse_int(summary.get("trades_total", 0), "trades_total")
   days_traded = hpo.parse_int(summary.get("days_traded", 0), "days_traded")
   min_trade_days_required = hpo.parse_int(
      summary.get("min_trade_days_required", rules_profile.min_trade_days),
      "min_trade_days_required",
   )
   observed_server_days = hpo.parse_int(
      summary.get("observed_server_days", len(daily_rows)),
      "observed_server_days",
   )
   final_return_pct = hpo.parse_float(summary["final_return_pct"], "final_return_pct")
   max_daily_dd_pct = hpo.parse_float(summary["max_daily_dd_pct"], "max_daily_dd_pct")
   max_overall_dd_pct = hpo.parse_float(summary["max_overall_dd_pct"], "max_overall_dd_pct")

   regime_summary = summarize_regime_logs(decision_logs)
   daily_regime_summary = summarize_daily_regimes(daily_rows, regime_summary["daily_dominant_regime"])

   manifest_spec = manifest.get("spec") if isinstance(manifest.get("spec"), dict) else {}
   initial_baseline_value = summary.get("initial_baseline", manifest_spec.get("deposit", 10000))
   initial_baseline = hpo.parse_float(initial_baseline_value, "initial_baseline")

   record = {
      "cycle_id": cycle.id,
      "window_phase": window_phase,
      "candidate_id": candidate.id,
      "candidate_group": candidate.group,
      "parent_candidate_id": candidate.parent_candidate_id,
      "scenario_id": scenario.id,
      "source_scenario_id": None,
      "scenario_weight": scenario.weight,
      "scenario_severity": scenario.severity,
      "status": result.get("status"),
      "from_date": hpo.iso_date(start_date),
      "to_date": hpo.iso_date(end_date),
      "window_trading_days": window_trading_days,
      "manifest_path": str(manifest_path),
      "summary_path": str(summary_path),
      "daily_path": str(daily_path),
      "report_path": str(report_path) if report_path else None,
      "run_dir": result.get("run_dir"),
      "cache_key": result.get("cache_key"),
      "decision_logs": decision_logs,
      "event_logs": event_logs,
      "run_manifest_spec": manifest_spec,
      "report_metrics": report_metrics,
      "regime_summary": regime_summary,
      "daily_regime_summary": daily_regime_summary,
      "initial_baseline": initial_baseline,
      "stress_applied": False,
      "stress_components": {},
   }
   record.update(
      build_metric_record(
         rules_profile=rules_profile,
         final_return_pct=final_return_pct,
         max_daily_dd_pct=max_daily_dd_pct,
         max_overall_dd_pct=max_overall_dd_pct,
         pass_days_traded=pass_days_traded,
         trades_total=trades_total,
         days_traded=days_traded,
         min_trade_days_required=min_trade_days_required,
         observed_server_days=observed_server_days,
         window_trading_days=window_trading_days,
      )
   )
   return record


def actual_run_record_path(
   paths: Phase4Paths,
   cycle_id: str,
   window_phase: str,
   candidate_id: str,
   scenario_id: str,
) -> Path:
   return paths.actual_runs_dir / cycle_id / window_phase / candidate_id / f"{scenario_id}.json"


def apply_synthetic_stress(
   source_record: dict[str, Any],
   scenario: Phase4ScenarioSpec,
   rules_profile: hpo.RulesProfile,
) -> dict[str, Any]:
   stressed = json.loads(json.dumps(source_record))
   base_metrics = source_record["summary_metrics"]
   trades_total = int(base_metrics["trades_total"])
   initial_baseline = float(source_record.get("initial_baseline", 10000.0))

   spread_penalty_pct = scenario.stress.spread_return_penalty_pct_per_trade * trades_total
   slippage_penalty_pct = scenario.stress.slippage_return_penalty_pct_per_trade * trades_total
   delay_penalty_pct = scenario.stress.delay_return_penalty_pct_per_trade * trades_total
   commission_penalty_pct = 0.0
   if initial_baseline > 0.0:
      commission_penalty_pct = (
         scenario.stress.commission_money_per_trade * trades_total / initial_baseline
      ) * 100.0

   stressed_return_pct = (
      float(base_metrics["final_return_pct"])
      - spread_penalty_pct
      - slippage_penalty_pct
      - delay_penalty_pct
      - commission_penalty_pct
   )
   stressed_max_daily_dd_pct = (
      float(base_metrics["max_daily_dd_pct"]) * scenario.stress.daily_dd_multiplier
   )
   stressed_max_overall_dd_pct = (
      float(base_metrics["max_overall_dd_pct"]) * scenario.stress.overall_dd_multiplier
   )

   stressed.update(
      {
         "scenario_id": scenario.id,
         "source_scenario_id": scenario.source_scenario_id,
         "scenario_weight": scenario.weight,
         "scenario_severity": scenario.severity,
         "stress_applied": True,
         "stress_components": {
            "spread_return_penalty_pct": round(spread_penalty_pct, 6),
            "slippage_return_penalty_pct": round(slippage_penalty_pct, 6),
            "delay_return_penalty_pct": round(delay_penalty_pct, 6),
            "commission_return_penalty_pct": round(commission_penalty_pct, 6),
            "daily_dd_multiplier": scenario.stress.daily_dd_multiplier,
            "overall_dd_multiplier": scenario.stress.overall_dd_multiplier,
         },
      }
   )
   stressed.update(
      build_metric_record(
         rules_profile=rules_profile,
         final_return_pct=stressed_return_pct,
         max_daily_dd_pct=stressed_max_daily_dd_pct,
         max_overall_dd_pct=stressed_max_overall_dd_pct,
         pass_days_traded=int(base_metrics["pass_days_traded"]),
         trades_total=trades_total,
         days_traded=int(base_metrics["days_traded"]),
         min_trade_days_required=int(base_metrics["min_trade_days_required"]),
         observed_server_days=int(base_metrics["observed_server_days"]),
         window_trading_days=int(source_record["window_trading_days"]),
      )
   )
   stressed["summary_metrics"]["final_return_pct_unstressed"] = float(base_metrics["final_return_pct"])
   stressed["summary_metrics"]["max_daily_dd_pct_unstressed"] = float(base_metrics["max_daily_dd_pct"])
   stressed["summary_metrics"]["max_overall_dd_pct_unstressed"] = float(base_metrics["max_overall_dd_pct"])
   return stressed


def load_actual_run_records(paths: Phase4Paths) -> list[dict[str, Any]]:
   if not paths.actual_runs_dir.exists():
      return []
   records: list[dict[str, Any]] = []
   for path in sorted(paths.actual_runs_dir.rglob("*.json")):
      loaded = hpo.load_json_file(path)
      loaded["record_path"] = str(path)
      regime_summary = summarize_regime_logs(list(loaded.get("decision_logs") or []))
      daily_path_value = loaded.get("daily_path")
      daily_rows: list[dict[str, str]] = []
      if daily_path_value:
         daily_path = Path(str(daily_path_value))
         if daily_path.exists():
            daily_rows = hpo.load_csv_rows(daily_path)
      loaded["regime_summary"] = regime_summary
      loaded["daily_regime_summary"] = summarize_daily_regimes(
         daily_rows,
         regime_summary["daily_dominant_regime"],
      )
      persisted = dict(loaded)
      persisted.pop("record_path", None)
      hpo.write_json_file(path, persisted)
      records.append(loaded)
   return records


def build_scenario_records(
   actual_records: list[dict[str, Any]],
   spec: Phase4Spec,
   rules_profile: hpo.RulesProfile,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
   grouped: dict[tuple[str, str, str], dict[str, dict[str, Any]]] = collections.defaultdict(dict)
   missing: list[dict[str, Any]] = []

   for record in actual_records:
      grouped[(record["cycle_id"], record["window_phase"], record["candidate_id"])][record["scenario_id"]] = record

   scenario_records: list[dict[str, Any]] = []
   for key in sorted(grouped.keys()):
      actual_by_scenario = grouped[key]
      for scenario in spec.scenarios:
         if scenario.source_scenario_id is None:
            actual_record = actual_by_scenario.get(scenario.id)
            if actual_record is None:
               missing.append(
                  {
                     "cycle_id": key[0],
                     "window_phase": key[1],
                     "candidate_id": key[2],
                     "scenario_id": scenario.id,
                  }
               )
               continue
            scenario_records.append(actual_record)
            continue

         source_record = actual_by_scenario.get(scenario.source_scenario_id)
         if source_record is None:
            missing.append(
               {
                  "cycle_id": key[0],
                  "window_phase": key[1],
                  "candidate_id": key[2],
                  "scenario_id": scenario.id,
                  "source_scenario_id": scenario.source_scenario_id,
               }
            )
            continue
         scenario_records.append(apply_synthetic_stress(source_record, scenario, rules_profile))
   scenario_records.sort(
      key=lambda item: (
         item["cycle_id"],
         item["window_phase"],
         item["candidate_group"],
         item["candidate_id"],
         item["scenario_id"],
      )
   )
   return scenario_records, missing


def summarize_window_records(
   records: list[dict[str, Any]],
   spec: Phase4Spec,
   missing_records: list[dict[str, Any]],
) -> list[dict[str, Any]]:
   grouped: dict[tuple[str, str, str], list[dict[str, Any]]] = collections.defaultdict(list)
   missing_index: dict[tuple[str, str, str], list[str]] = collections.defaultdict(list)
   for record in records:
      grouped[(record["cycle_id"], record["window_phase"], record["candidate_id"])].append(record)
   for missing in missing_records:
      missing_index[(missing["cycle_id"], missing["window_phase"], missing["candidate_id"])].append(missing["scenario_id"])

   summaries: list[dict[str, Any]] = []
   for key in sorted(set(grouped.keys()) | set(missing_index.keys())):
      present = sorted(grouped.get(key, []), key=lambda item: item["scenario_id"])
      missing_ids = sorted(set(missing_index.get(key, [])))
      aggregate, objective = hpo.aggregate_trial_runs(
         present,
         scenario_count=len(spec.scenarios),
         window_count=1,
      )
      sample = present[0] if present else {}
      summaries.append(
         {
            "cycle_id": key[0],
            "window_phase": key[1],
            "candidate_id": key[2],
            "candidate_group": sample.get("candidate_group"),
            "parent_candidate_id": sample.get("parent_candidate_id"),
            "complete": (len(missing_ids) == 0) and bool(aggregate.get("valid", False)),
            "missing_scenario_ids": missing_ids,
            "objective": objective,
            "aggregate_metrics": aggregate,
            "scenario_ids_present": [record["scenario_id"] for record in present],
            "dominant_regime": sample.get("regime_summary", {}).get("dominant_regime"),
            "preferred_symbol": sample.get("regime_summary", {}).get("preferred_symbol"),
         }
      )
   return summaries


def build_phase4_summary(
   spec: Phase4Spec,
   cycles: tuple[WalkForwardCycle, ...],
   scenario_records: list[dict[str, Any]],
   window_summaries: list[dict[str, Any]],
) -> dict[str, Any]:
   summary_index = {
      (item["cycle_id"], item["window_phase"], item["candidate_id"]): item
      for item in window_summaries
   }
   scenario_groups: dict[tuple[str, str], list[dict[str, Any]]] = collections.defaultdict(list)
   for record in scenario_records:
      if record["candidate_group"] == "primary":
         scenario_groups[(record["window_phase"], record["scenario_severity"])].append(record)

   cycle_rows: list[dict[str, Any]] = []
   search_winners: list[str] = []
   neighbor_checks: list[dict[str, Any]] = []
   for cycle in cycles:
      search_rows = [
         item
         for item in window_summaries
         if item["cycle_id"] == cycle.id
         and item["window_phase"] == "search"
         and item["candidate_group"] == "primary"
         and item["complete"]
      ]
      report_rows = [
         item
         for item in window_summaries
         if item["cycle_id"] == cycle.id
         and item["window_phase"] == "report"
         and item["candidate_group"] == "primary"
         and item["complete"]
      ]
      search_ranked = sorted(search_rows, key=lambda item: float(item["objective"]), reverse=True)
      report_ranked = sorted(report_rows, key=lambda item: float(item["objective"]), reverse=True)
      selected_search = search_ranked[0]["candidate_id"] if search_ranked else ""
      if selected_search:
         search_winners.append(selected_search)
      search_margin = None
      if len(search_ranked) >= 2:
         search_margin = round(float(search_ranked[0]["objective"]) - float(search_ranked[1]["objective"]), 6)
      report_margin = None
      if len(report_ranked) >= 2:
         report_margin = round(float(report_ranked[0]["objective"]) - float(report_ranked[1]["objective"]), 6)

      cycle_neighbor_checks: list[dict[str, Any]] = []
      for neighbor in spec.neighbor_candidates:
         neighbor_summary = summary_index.get((cycle.id, "report", neighbor.id))
         if neighbor_summary is None or not neighbor_summary["complete"]:
            continue
         if neighbor.parent_candidate_id is None:
            continue
         parent_summary = summary_index.get((cycle.id, "report", neighbor.parent_candidate_id))
         if parent_summary is None or not parent_summary["complete"]:
            continue
         parent_aggregate = parent_summary["aggregate_metrics"]
         neighbor_aggregate = neighbor_summary["aggregate_metrics"]
         collapse = (
            float(parent_aggregate.get("breach_rate", 0.0)) == 0.0
            and float(parent_aggregate.get("zero_trade_rate", 0.0)) == 0.0
            and (
               float(neighbor_aggregate.get("breach_rate", 0.0)) > 0.0
               or float(neighbor_aggregate.get("zero_trade_rate", 0.0)) > 0.0
            )
         )
         check = {
            "cycle_id": cycle.id,
            "candidate_id": neighbor.id,
            "parent_candidate_id": neighbor.parent_candidate_id,
            "collapse": collapse,
            "objective_delta": round(
               float(neighbor_summary["objective"]) - float(parent_summary["objective"]),
               6,
            ),
         }
         cycle_neighbor_checks.append(check)
         neighbor_checks.append(check)

      cycle_rows.append(
         {
            "cycle_id": cycle.id,
            "search_ranking": [
               {
                  "candidate_id": item["candidate_id"],
                  "objective": item["objective"],
               }
               for item in search_ranked
            ],
            "search_selected_candidate": selected_search,
            "search_margin_to_runner_up": search_margin,
            "report_ranking": [
               {
                  "candidate_id": item["candidate_id"],
                  "objective": item["objective"],
               }
               for item in report_ranked
            ],
            "report_margin_to_runner_up": report_margin,
            "neighbor_checks": cycle_neighbor_checks,
         }
      )

   stress_gate = {}
   for severity in ("mild", "moderate"):
      records = [
         record
         for record in scenario_groups.get(("report", severity), [])
         if record.get("valid", False)
      ]
      stress_gate[severity] = {
         "record_count": len(records),
         "breach_count": sum(1 for record in records if record["breach_flag"]),
         "zero_trade_count": sum(1 for record in records if record["zero_trade_flag"]),
         "positive_return_count": sum(
            1
            for record in records
            if float(record["summary_metrics"]["final_return_pct"]) > 0.0
         ),
      }

   gate_signals = {
      "mild_report_noncollapse": (
         stress_gate["mild"]["record_count"] > 0
         and stress_gate["mild"]["breach_count"] == 0
         and stress_gate["mild"]["zero_trade_count"] == 0
      ),
      "moderate_report_noncollapse": (
         stress_gate["moderate"]["record_count"] > 0
         and stress_gate["moderate"]["breach_count"] == 0
         and stress_gate["moderate"]["zero_trade_count"] == 0
      ),
      "neighbor_collapse_count": sum(1 for check in neighbor_checks if check["collapse"]),
      "search_winner_consistent": (len(set(search_winners)) == 1) if search_winners else False,
      "positive_search_margin_cycles": sum(
         1
         for cycle_row in cycle_rows
         if cycle_row["search_margin_to_runner_up"] is not None
         and float(cycle_row["search_margin_to_runner_up"]) > 0.0
      ),
   }
   return {
      "generated_at_utc": hpo.utc_now_iso(),
      "phase4_name": spec.name,
      "cycle_count": len(cycles),
      "primary_candidate_ids": [candidate.id for candidate in spec.primary_candidates],
      "neighbor_candidate_ids": [candidate.id for candidate in spec.neighbor_candidates],
      "scenario_ids": [scenario.id for scenario in spec.scenarios],
      "cycle_summaries": cycle_rows,
      "stress_gate": stress_gate,
      "gate_signals": gate_signals,
   }


def export_phase4(phase4_dir: Path) -> dict[str, Any]:
   manifest_path = phase4_dir / "phase4_manifest.json"
   if not manifest_path.exists():
      raise FileNotFoundError(f"Phase 4 manifest not found: {manifest_path}")
   manifest = hpo.load_json_file(manifest_path)
   spec_path = Path(str(manifest.get("phase4_spec_path", "")).strip())
   if not spec_path:
      raise ValueError(f"phase4_spec_path missing from manifest: {manifest_path}")
   spec = load_phase4_spec(spec_path)
   rules_profile = hpo.load_rules_profile(hpo.rules_profile_path(spec.rules_profile))
   paths = build_phase4_paths(spec.name, repo=phase4_dir.parents[2])
   cycles = build_walk_forward_cycles(spec)
   actual_records = load_actual_run_records(paths)
   scenario_records, missing_records = build_scenario_records(actual_records, spec, rules_profile)
   window_summaries = summarize_window_records(scenario_records, spec, missing_records)
   phase4_summary = build_phase4_summary(spec, cycles, scenario_records, window_summaries)
   phase4_summary["missing_records"] = missing_records
   phase4_summary["actual_run_record_count"] = len(actual_records)
   phase4_summary["scenario_record_count"] = len(scenario_records)

   hpo.ensure_directory(paths.phase4_dir)
   with paths.scenario_records_path.open("w", encoding="utf-8") as handle:
      for record in scenario_records:
         handle.write(json.dumps(record, sort_keys=True) + "\n")
   hpo.write_json_file(paths.window_summaries_path, window_summaries)
   hpo.write_json_file(paths.phase4_summary_path, phase4_summary)

   return {
      "phase4_name": spec.name,
      "phase4_dir": str(paths.phase4_dir),
      "scenario_records_path": str(paths.scenario_records_path),
      "window_summaries_path": str(paths.window_summaries_path),
      "phase4_summary_path": str(paths.phase4_summary_path),
      "actual_run_record_count": len(actual_records),
      "scenario_record_count": len(scenario_records),
      "missing_record_count": len(missing_records),
      "gate_signals": phase4_summary["gate_signals"],
   }


def prepare_phase4(phase4_spec_path: Path) -> dict[str, Any]:
   spec = load_phase4_spec(phase4_spec_path)
   rules_profile = hpo.load_rules_profile(hpo.rules_profile_path(spec.rules_profile))
   cycles = build_walk_forward_cycles(spec)
   paths = build_phase4_paths(spec.name)
   hpo.ensure_directory(paths.phase4_dir)
   write_phase4_manifest(paths, spec, rules_profile, cycles)
   write_phase4_cycles(paths, cycles)
   return {
      "phase4_name": spec.name,
      "phase4_dir": str(paths.phase4_dir),
      "manifest_path": str(paths.manifest_path),
      "cycles_path": str(paths.cycles_path),
      "cycle_count": len(cycles),
      "cycles": cycles_to_payload(cycles),
   }


def candidate_scope_filter(
   spec: Phase4Spec,
   candidate_scope: str,
) -> tuple[Phase4CandidateSpec, ...]:
   if candidate_scope == "primary":
      return spec.primary_candidates
   if candidate_scope == "all":
      return spec.primary_candidates + spec.neighbor_candidates
   raise ValueError(f"Unsupported candidate_scope: {candidate_scope!r}")


def run_phase4(
   phase4_spec_path: Path,
   *,
   cycle_ids: tuple[str, ...] = (),
   candidate_scope: str = "all",
   window_phase: str = "both",
   mt5_install_path: str | None = None,
   terminal_data_path: str | None = None,
   output_root: str | Path = mt5_runner.DEFAULT_OUTPUT_ROOT,
   stop_existing: bool = False,
   force: bool = False,
   runner_paths: mt5_runner.RunnerPaths | None = None,
   runner_module: Any = mt5_runner,
) -> dict[str, Any]:
   spec = load_phase4_spec(phase4_spec_path)
   rules_profile = hpo.load_rules_profile(hpo.rules_profile_path(spec.rules_profile))
   cycles = build_walk_forward_cycles(spec)
   selected_cycle_ids = set(cycle_ids)
   selected_cycles = [
      cycle
      for cycle in cycles
      if not selected_cycle_ids or cycle.id in selected_cycle_ids
   ]
   if selected_cycle_ids and len(selected_cycles) != len(selected_cycle_ids):
      known_cycle_ids = {cycle.id for cycle in cycles}
      missing_cycle_ids = sorted(selected_cycle_ids - known_cycle_ids)
      raise ValueError(f"Unknown cycle id(s): {missing_cycle_ids}")

   paths = build_phase4_paths(spec.name)
   hpo.ensure_directory(paths.phase4_dir)
   write_phase4_manifest(paths, spec, rules_profile, cycles)
   write_phase4_cycles(paths, cycles)

   if runner_paths is None:
      runner_paths = runner_module.build_runner_paths(
         mt5_install_path=mt5_install_path,
         terminal_data_path=terminal_data_path,
         output_root=output_root,
      )

   candidate_rows = candidate_scope_filter(spec, candidate_scope)
   actual_scenarios = tuple(
      scenario for scenario in spec.scenarios
      if scenario.source_scenario_id is None
   )
   pending_sync = True
   pending_compile = True
   executed_runs = 0

   for cycle in selected_cycles:
      for candidate in candidate_rows:
         phases = candidate.window_phases
         if window_phase == "search":
            phases = tuple(phase for phase in phases if phase == "search")
         elif window_phase == "report":
            phases = tuple(phase for phase in phases if phase == "report")
         elif window_phase != "both":
            raise ValueError(f"Unsupported window_phase: {window_phase!r}")
         if not phases:
            continue

         for phase_name in phases:
            start_date, end_date = cycle_window_dates(cycle, phase_name)
            for scenario in actual_scenarios:
               run_data = {
                  "name": f"{spec.name}__{cycle.id}__{phase_name}__{candidate.id}__{scenario.id}",
                  "symbol": spec.symbol,
                  "period": spec.period,
                  "from_date": hpo.to_mt5_date(start_date),
                  "to_date": hpo.to_mt5_date(end_date),
                  "base_set": str(spec.base_set),
                  "scenario": scenario.id,
                  "rules_profile": spec.rules_profile,
                  "set_overrides": dict(candidate.set_overrides) | dict(scenario.set_overrides),
               }
               if scenario.execution_mode is not None:
                  run_data["execution_mode"] = scenario.execution_mode
               run_spec = runner_module.build_spec(run_data)
               result = runner_module.run_single_backtest(
                  run_spec,
                  runner_paths,
                  dry_run=False,
                  sync_before_run=pending_sync,
                  compile_before_run=pending_compile,
                  force=force,
                  stop_existing=stop_existing,
               )
               if pending_sync and result.get("status") != "cache_hit":
                  pending_sync = False
                  pending_compile = False
               record = normalize_actual_run_record(
                  spec=spec,
                  rules_profile=rules_profile,
                  cycle=cycle,
                  window_phase=phase_name,
                  candidate=candidate,
                  scenario=scenario,
                  result=result,
               )
               record_path = actual_run_record_path(paths, cycle.id, phase_name, candidate.id, scenario.id)
               hpo.write_json_file(record_path, record)
               executed_runs += 1

   exported = export_phase4(paths.phase4_dir)
   return {
      "phase4_name": spec.name,
      "phase4_dir": str(paths.phase4_dir),
      "cycle_ids": [cycle.id for cycle in selected_cycles],
      "candidate_scope": candidate_scope,
      "window_phase": window_phase,
      "executed_runs": executed_runs,
      "exports": exported,
   }


def build_parser() -> argparse.ArgumentParser:
   parser = argparse.ArgumentParser(description="FundingPips Phase 4 walk-forward/stress tooling")
   subparsers = parser.add_subparsers(dest="command", required=True)

   prepare_parser = subparsers.add_parser("prepare-phase4", help="Generate Phase 4 walk-forward cycles")
   prepare_parser.add_argument("--phase4-spec", required=True)

   run_parser = subparsers.add_parser("run-phase4", help="Run Phase 4 walk-forward/stress evaluations")
   run_parser.add_argument("--phase4-spec", required=True)
   run_parser.add_argument("--cycle-id", action="append", default=[])
   run_parser.add_argument("--candidate-scope", choices=("primary", "all"), default="all")
   run_parser.add_argument("--window-phase", choices=("search", "report", "both"), default="both")
   run_parser.add_argument("--mt5-install-path", default=None)
   run_parser.add_argument("--terminal-data-path", default=None)
   run_parser.add_argument("--output-root", default=str(mt5_runner.DEFAULT_OUTPUT_ROOT))
   run_parser.add_argument("--stop-existing", action="store_true")
   run_parser.add_argument("--force", action="store_true")

   export_parser = subparsers.add_parser("export-phase4", help="Regenerate Phase 4 summary artifacts")
   export_parser.add_argument("--phase4-dir", required=True)

   return parser


def main(argv: list[str] | None = None) -> int:
   parser = build_parser()
   args = parser.parse_args(argv)

   if args.command == "prepare-phase4":
      result = prepare_phase4(
         mt5_runner.resolve_repo_path(repo_root(), Path(args.phase4_spec))
      )
      print(json.dumps(result, indent=2, sort_keys=True))
      return 0

   if args.command == "run-phase4":
      result = run_phase4(
         mt5_runner.resolve_repo_path(repo_root(), Path(args.phase4_spec)),
         cycle_ids=tuple(args.cycle_id),
         candidate_scope=args.candidate_scope,
         window_phase=args.window_phase,
         mt5_install_path=args.mt5_install_path,
         terminal_data_path=args.terminal_data_path,
         output_root=args.output_root,
         stop_existing=args.stop_existing,
         force=args.force,
      )
      print(json.dumps(result, indent=2, sort_keys=True))
      return 0

   if args.command == "export-phase4":
      phase4_dir = mt5_runner.resolve_repo_path(repo_root(), Path(args.phase4_dir))
      result = export_phase4(phase4_dir)
      print(json.dumps(result, indent=2, sort_keys=True))
      return 0

   parser.error(f"Unsupported command: {args.command}")
   return 2


if __name__ == "__main__":
   try:
      raise SystemExit(main())
   except Exception as exc:  # pragma: no cover - CLI safety net
      print(f"ERROR: {exc}", file=sys.stderr)
      raise SystemExit(1)
