#!/usr/bin/env python3
"""FundingPips Phase 2 windowed HPO orchestration."""

from __future__ import annotations

import argparse
import csv
import dataclasses
import html
import json
import sqlite3
import sys
from contextlib import closing
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

try:
   from tools import fundingpips_mt5_runner as mt5_runner
except ModuleNotFoundError:  # pragma: no cover - script execution fallback
   sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
   from tools import fundingpips_mt5_runner as mt5_runner


DEFAULT_STUDY_ROOT = Path(".tmp") / "fundingpips_hpo_studies"
DEFAULT_RULES_PROFILE_DIR = Path("tools") / "fundingpips_rules_profiles"
INVALID_OBJECTIVE = -1e9


class Phase2TrialFailure(RuntimeError):
   """Signal a recoverable trial failure that should not count as COMPLETE."""


REQUIRED_SUMMARY_FIELDS = (
   "pass",
   "pass_days_traded",
   "final_return_pct",
   "max_daily_dd_pct",
   "max_overall_dd_pct",
   "any_daily_breach",
   "overall_breach",
   "trades_total",
)

CANDIDATE_B_OVERRIDES: dict[str, Any] = {
   "UseLondonOnly": 0,
   "StartHourLO": 1,
   "StartHourNY": 1,
   "ORMinutes": 30,
   "CutoffHour": 23,
   "NewsBufferS": 0,
   "SpreadMultATR": 1.0,
   "MaxSpreadPoints": 0,
   "BWISC_ConfCut": 0.00,
   "MR_ConfCut": 0.00,
   "MR_EMRTWeight": 0.0,
   "EMRT_FastThresholdPct": 100,
   "EnableMR": 1,
   "EnableMRBypassOnRLUnloaded": 1,
   "MR_LongOnly": 1,
   "EnableAnomalyDetector": 0,
   "AnomalyShadowMode": 0,
   "UseBanditMetaPolicy": 0,
   "BanditShadowMode": 0,
}


@dataclasses.dataclass(frozen=True)
class RulesProfile:
   id: str
   target_profit_pct: float
   daily_loss_cap_pct: float
   overall_loss_cap_pct: float
   min_trade_days: int


@dataclasses.dataclass(frozen=True)
class SearchDimension:
   name: str
   kind: str
   low: float | None = None
   high: float | None = None
   step: float | None = None
   choices: tuple[Any, ...] = ()


@dataclasses.dataclass(frozen=True)
class ScenarioSpec:
   id: str
   weight: float
   set_overrides: dict[str, Any]


@dataclasses.dataclass(frozen=True)
class StudySpec:
   name: str
   rules_profile: str
   symbol: str
   period: str
   from_date: date
   to_date: date
   window_length_trading_days: int
   window_step_trading_days: int
   base_set: Path
   seed: int
   n_trials: int
   search_space: tuple[SearchDimension, ...]
   scenarios: tuple[ScenarioSpec, ...]
   source_path: Path


@dataclasses.dataclass(frozen=True)
class StudyWindow:
   id: str
   from_date: date
   to_date: date


@dataclasses.dataclass(frozen=True)
class StudyPaths:
   study_dir: Path
   sqlite_path: Path
   manifest_path: Path
   windows_path: Path
   trial_results_csv_path: Path
   trial_results_jsonl_path: Path
   run_records_jsonl_path: Path
   best_trial_summary_path: Path


def repo_root() -> Path:
   return mt5_runner.repo_root()


def utc_now_iso() -> str:
   return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def stable_json(data: Any) -> str:
   return json.dumps(data, sort_keys=True, separators=(",", ":"))


def ensure_directory(path: Path) -> None:
   path.mkdir(parents=True, exist_ok=True)


def clamp(value: float, low: float, high: float) -> float:
   return max(low, min(high, value))


def parse_iso_date(value: str) -> date:
   return date.fromisoformat(value)


def iso_date(value: date) -> str:
   return value.isoformat()


def compact_date(value: date) -> str:
   return value.strftime("%Y%m%d")


def to_mt5_date(value: date) -> str:
   return value.strftime("%Y.%m.%d")


def read_text_with_encodings(path: Path, encodings: tuple[str, ...] | None = None) -> str:
   tried = encodings or ("ascii", "utf-8", "utf-8-sig", "utf-16", "utf-16-le", "utf-16-be", "cp1252")
   for encoding in tried:
      try:
         return path.read_text(encoding=encoding)
      except UnicodeDecodeError:
         continue
   return path.read_text(encoding="utf-8", errors="ignore")


def load_json_file(path: Path) -> dict[str, Any]:
   data = json.loads(read_text_with_encodings(path))
   if not isinstance(data, dict):
      raise ValueError(f"JSON object expected: {path}")
   return data


def load_csv_rows(path: Path) -> list[dict[str, str]]:
   with path.open("r", encoding="utf-8", newline="") as handle:
      reader = csv.DictReader(handle)
      if reader.fieldnames is None:
         raise ValueError(f"CSV header missing: {path}")
      return [dict(row) for row in reader]


def parse_bool(value: Any, field_name: str) -> bool:
   if isinstance(value, bool):
      return value
   if isinstance(value, str):
      normalized = value.strip().lower()
      if normalized in ("true", "1"):
         return True
      if normalized in ("false", "0"):
         return False
   raise ValueError(f"Boolean expected for {field_name}: {value!r}")


def parse_float(value: Any, field_name: str) -> float:
   if isinstance(value, (int, float)):
      return float(value)
   if isinstance(value, str) and value.strip():
      return float(value.strip())
   raise ValueError(f"Numeric value expected for {field_name}: {value!r}")


def parse_int(value: Any, field_name: str) -> int:
   if isinstance(value, bool):
      raise ValueError(f"Integer value expected for {field_name}: {value!r}")
   if isinstance(value, int):
      return value
   if isinstance(value, float) and value.is_integer():
      return int(value)
   if isinstance(value, str) and value.strip():
      return int(value.strip())
   raise ValueError(f"Integer value expected for {field_name}: {value!r}")


def snap_start_to_weekday(value: date) -> date:
   while value.weekday() >= 5:
      value += timedelta(days=1)
   return value


def snap_end_to_weekday(value: date) -> date:
   while value.weekday() >= 5:
      value -= timedelta(days=1)
   return value


def iter_trading_days(start_date: date, end_date: date) -> list[date]:
   days: list[date] = []
   current = start_date
   while current <= end_date:
      if current.weekday() < 5:
         days.append(current)
      current += timedelta(days=1)
   return days


def render_set_with_overrides(base_set_text: str, overrides: dict[str, Any]) -> str:
   normalized_overrides = {
      key: mt5_runner.normalize_override_value(value)
      for key, value in overrides.items()
   }
   seen: set[str] = set()
   output_lines: list[str] = []

   for line in base_set_text.splitlines():
      stripped = line.strip()
      if not stripped or stripped.startswith(";") or "=" not in line:
         output_lines.append(line)
         continue

      key, value = line.split("=", 1)
      key = key.strip()
      scalar_value = value.split("||", 1)[0].strip()
      if key in normalized_overrides:
         scalar_value = normalized_overrides[key]
         seen.add(key)
      output_lines.append(f"{key}={scalar_value}")

   for key in sorted(normalized_overrides.keys() - seen):
      output_lines.append(f"{key}={normalized_overrides[key]}")

   return "\n".join(output_lines) + "\n"


def parse_search_space(raw_search_space: Any) -> tuple[SearchDimension, ...]:
   if not isinstance(raw_search_space, dict) or not raw_search_space:
      raise ValueError("search_space must be a non-empty object")

   dimensions: list[SearchDimension] = []
   for name, raw_dimension in raw_search_space.items():
      if not isinstance(raw_dimension, dict):
         raise ValueError(f"search_space[{name}] must be an object")
      kind = str(raw_dimension.get("type", "")).strip().lower()
      if kind == "float":
         low = parse_float(raw_dimension.get("low"), f"{name}.low")
         high = parse_float(raw_dimension.get("high"), f"{name}.high")
         step = parse_float(raw_dimension.get("step"), f"{name}.step")
         if high < low:
            raise ValueError(f"search_space[{name}] high must be >= low")
         if step <= 0:
            raise ValueError(f"search_space[{name}] step must be > 0")
         dimensions.append(SearchDimension(name=name, kind="float", low=low, high=high, step=step))
         continue
      if kind == "categorical":
         choices = raw_dimension.get("choices")
         if not isinstance(choices, list) or not choices:
            raise ValueError(f"search_space[{name}] choices must be a non-empty list")
         dimensions.append(SearchDimension(name=name, kind="categorical", choices=tuple(choices)))
         continue
      raise ValueError(f"Unsupported search_space[{name}] type: {kind!r}")
   return tuple(dimensions)


def parse_scenarios(raw_scenarios: Any) -> tuple[ScenarioSpec, ...]:
   if not isinstance(raw_scenarios, list) or not raw_scenarios:
      raise ValueError("scenarios must be a non-empty list")

   scenarios: list[ScenarioSpec] = []
   for index, raw_scenario in enumerate(raw_scenarios):
      if not isinstance(raw_scenario, dict):
         raise ValueError(f"scenarios[{index}] must be an object")
      scenario_id = str(raw_scenario.get("id", "")).strip()
      if not scenario_id:
         raise ValueError(f"scenarios[{index}].id is required")
      weight = parse_float(raw_scenario.get("weight"), f"scenarios[{index}].weight")
      if weight <= 0:
         raise ValueError(f"scenarios[{index}].weight must be > 0")
      set_overrides = raw_scenario.get("set_overrides") or {}
      if not isinstance(set_overrides, dict):
         raise ValueError(f"scenarios[{index}].set_overrides must be an object")
      scenarios.append(ScenarioSpec(id=scenario_id, weight=weight, set_overrides=dict(set_overrides)))
   return tuple(scenarios)


def load_rules_profile(path: Path) -> RulesProfile:
   raw = load_json_file(path)
   profile_id = str(raw.get("id", "")).strip()
   if not profile_id:
      raise ValueError(f"rules profile id is required: {path}")
   profile = RulesProfile(
      id=profile_id,
      target_profit_pct=parse_float(raw.get("target_profit_pct"), "target_profit_pct"),
      daily_loss_cap_pct=parse_float(raw.get("daily_loss_cap_pct"), "daily_loss_cap_pct"),
      overall_loss_cap_pct=parse_float(raw.get("overall_loss_cap_pct"), "overall_loss_cap_pct"),
      min_trade_days=parse_int(raw.get("min_trade_days"), "min_trade_days"),
   )
   if profile.min_trade_days < 1:
      raise ValueError(f"min_trade_days must be >= 1: {path}")
   return profile


def rules_profile_path(profile_id: str, repo: Path | None = None) -> Path:
   root = repo or repo_root()
   return (root / DEFAULT_RULES_PROFILE_DIR / f"{profile_id}.json").resolve()


def load_study_spec(path: Path) -> StudySpec:
   raw = load_json_file(path)
   name = str(raw.get("name", "")).strip()
   if not name:
      raise ValueError(f"study name is required: {path}")
   spec = StudySpec(
      name=name,
      rules_profile=str(raw.get("rules_profile", "")).strip(),
      symbol=str(raw.get("symbol", "")).strip(),
      period=str(raw.get("period", "")).strip(),
      from_date=parse_iso_date(str(raw.get("from_date", ""))),
      to_date=parse_iso_date(str(raw.get("to_date", ""))),
      window_length_trading_days=parse_int(raw.get("window_length_trading_days"), "window_length_trading_days"),
      window_step_trading_days=parse_int(raw.get("window_step_trading_days"), "window_step_trading_days"),
      base_set=Path(str(raw.get("base_set", ""))),
      seed=parse_int(raw.get("seed"), "seed"),
      n_trials=parse_int(raw.get("n_trials"), "n_trials"),
      search_space=parse_search_space(raw.get("search_space")),
      scenarios=parse_scenarios(raw.get("scenarios")),
      source_path=path.resolve(),
   )
   if not spec.rules_profile:
      raise ValueError(f"rules_profile is required: {path}")
   if not spec.symbol:
      raise ValueError(f"symbol is required: {path}")
   if not spec.period:
      raise ValueError(f"period is required: {path}")
   if not str(spec.base_set):
      raise ValueError(f"base_set is required: {path}")
   if spec.window_length_trading_days < 1:
      raise ValueError(f"window_length_trading_days must be >= 1: {path}")
   if spec.window_step_trading_days < 1:
      raise ValueError(f"window_step_trading_days must be >= 1: {path}")
   if spec.n_trials < 1:
      raise ValueError(f"n_trials must be >= 1: {path}")
   if spec.to_date < spec.from_date:
      raise ValueError(f"to_date must be >= from_date: {path}")
   return spec


def build_study_paths(study_name: str, repo: Path | None = None) -> StudyPaths:
   root = repo or repo_root()
   study_dir = (root / DEFAULT_STUDY_ROOT / study_name).resolve()
   return StudyPaths(
      study_dir=study_dir,
      sqlite_path=study_dir / "study.sqlite3",
      manifest_path=study_dir / "study_manifest.json",
      windows_path=study_dir / "windows.json",
      trial_results_csv_path=study_dir / "trial_results.csv",
      trial_results_jsonl_path=study_dir / "trial_results.jsonl",
      run_records_jsonl_path=study_dir / "run_records.jsonl",
      best_trial_summary_path=study_dir / "best_trial_summary.json",
   )


def build_windows(spec: StudySpec) -> tuple[StudyWindow, ...]:
   snapped_start = snap_start_to_weekday(spec.from_date)
   snapped_end = snap_end_to_weekday(spec.to_date)
   if snapped_end < snapped_start:
      raise ValueError("Study date range contains no weekdays after weekend snap")

   trading_days = iter_trading_days(snapped_start, snapped_end)
   if len(trading_days) < spec.window_length_trading_days:
      raise ValueError("Not enough trading days for requested window length")

   windows: list[StudyWindow] = []
   last_index = len(trading_days) - spec.window_length_trading_days
   for offset in range(0, last_index + 1, spec.window_step_trading_days):
      start_day = trading_days[offset]
      end_day = trading_days[offset + spec.window_length_trading_days - 1]
      windows.append(
         StudyWindow(
            id=f"w{len(windows) + 1:03d}_{compact_date(start_day)}_{compact_date(end_day)}",
            from_date=start_day,
            to_date=end_day,
         )
      )
   return tuple(windows)


def windows_to_payload(windows: tuple[StudyWindow, ...]) -> list[dict[str, Any]]:
   return [
      {"id": window.id, "from_date": iso_date(window.from_date), "to_date": iso_date(window.to_date)}
      for window in windows
   ]


def write_json_file(path: Path, payload: Any) -> None:
   ensure_directory(path.parent)
   path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def require_optuna() -> Any:
   try:
      import optuna  # type: ignore
   except ImportError as exc:
      raise RuntimeError(
         "Optuna is required for Phase 2. Install requirements-hpo.txt before running studies."
      ) from exc
   return optuna


def build_storage_url(path: Path) -> str:
   return f"sqlite:///{path.resolve().as_posix()}"


def ensure_custom_tables(sqlite_path: Path) -> None:
   ensure_directory(sqlite_path.parent)
   with closing(sqlite3.connect(sqlite_path, timeout=60)) as conn:
      conn.execute(
         """
         CREATE TABLE IF NOT EXISTS phase2_trial_results (
            study_name TEXT NOT NULL,
            trial_number INTEGER NOT NULL,
            state TEXT NOT NULL,
            objective REAL NOT NULL,
            params_json TEXT NOT NULL,
            aggregate_metrics_json TEXT NOT NULL,
            created_at_utc TEXT NOT NULL,
            updated_at_utc TEXT NOT NULL,
            PRIMARY KEY (study_name, trial_number)
         )
         """
      )
      conn.execute(
         """
         CREATE TABLE IF NOT EXISTS phase2_run_records (
            study_name TEXT NOT NULL,
            trial_number INTEGER NOT NULL,
            window_id TEXT NOT NULL,
            scenario_id TEXT NOT NULL,
            cache_key TEXT,
            run_dir TEXT,
            summary_path TEXT,
            daily_path TEXT,
            report_path TEXT,
            run_metrics_json TEXT NOT NULL,
            created_at_utc TEXT NOT NULL,
            PRIMARY KEY (study_name, trial_number, window_id, scenario_id)
         )
         """
      )
      conn.commit()


def clear_trial_run_records(sqlite_path: Path, study_name: str, trial_number: int) -> None:
   with closing(sqlite3.connect(sqlite_path, timeout=60)) as conn:
      conn.execute(
         "DELETE FROM phase2_run_records WHERE study_name = ? AND trial_number = ?",
         (study_name, trial_number),
      )
      conn.commit()


def upsert_trial_result(
   sqlite_path: Path,
   study_name: str,
   trial_number: int,
   state: str,
   objective: float,
   params: dict[str, Any],
   aggregate_metrics: dict[str, Any],
   created_at_utc: str,
) -> None:
   updated_at_utc = utc_now_iso()
   with closing(sqlite3.connect(sqlite_path, timeout=60)) as conn:
      conn.execute(
         """
         INSERT INTO phase2_trial_results (
            study_name,
            trial_number,
            state,
            objective,
            params_json,
            aggregate_metrics_json,
            created_at_utc,
            updated_at_utc
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(study_name, trial_number) DO UPDATE SET
            state = excluded.state,
            objective = excluded.objective,
            params_json = excluded.params_json,
            aggregate_metrics_json = excluded.aggregate_metrics_json,
            updated_at_utc = excluded.updated_at_utc
         """,
         (
            study_name,
            trial_number,
            state,
            float(objective),
            stable_json(params),
            stable_json(aggregate_metrics),
            created_at_utc,
            updated_at_utc,
         ),
      )
      conn.commit()


def upsert_run_record(sqlite_path: Path, run_record: dict[str, Any], created_at_utc: str) -> None:
   with closing(sqlite3.connect(sqlite_path, timeout=60)) as conn:
      conn.execute(
         """
         INSERT INTO phase2_run_records (
            study_name,
            trial_number,
            window_id,
            scenario_id,
            cache_key,
            run_dir,
            summary_path,
            daily_path,
            report_path,
            run_metrics_json,
            created_at_utc
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(study_name, trial_number, window_id, scenario_id) DO UPDATE SET
            cache_key = excluded.cache_key,
            run_dir = excluded.run_dir,
            summary_path = excluded.summary_path,
            daily_path = excluded.daily_path,
            report_path = excluded.report_path,
            run_metrics_json = excluded.run_metrics_json
         """,
         (
            run_record["study_name"],
            run_record["trial_number"],
            run_record["window_id"],
            run_record["scenario_id"],
            run_record.get("cache_key"),
            run_record.get("run_dir"),
            run_record.get("summary_path"),
            run_record.get("daily_path"),
            run_record.get("report_path"),
            stable_json(run_record),
            created_at_utc,
         ),
      )
      conn.commit()


def read_trial_rows(sqlite_path: Path, study_name: str) -> list[dict[str, Any]]:
   with closing(sqlite3.connect(sqlite_path, timeout=60)) as conn:
      conn.row_factory = sqlite3.Row
      rows = conn.execute(
         """
         SELECT study_name, trial_number, state, objective, params_json,
                aggregate_metrics_json, created_at_utc, updated_at_utc
         FROM phase2_trial_results
         WHERE study_name = ?
         ORDER BY trial_number ASC
         """,
         (study_name,),
      ).fetchall()
   return [dict(row) for row in rows]


def read_run_rows(sqlite_path: Path, study_name: str) -> list[dict[str, Any]]:
   with closing(sqlite3.connect(sqlite_path, timeout=60)) as conn:
      conn.row_factory = sqlite3.Row
      rows = conn.execute(
         """
         SELECT study_name, trial_number, window_id, scenario_id, cache_key, run_dir,
                summary_path, daily_path, report_path, run_metrics_json, created_at_utc
         FROM phase2_run_records
         WHERE study_name = ?
         ORDER BY trial_number ASC, window_id ASC, scenario_id ASC
         """,
         (study_name,),
      ).fetchall()
   return [dict(row) for row in rows]


def count_trial_run_rows(sqlite_path: Path, study_name: str, trial_number: int) -> int:
   with closing(sqlite3.connect(sqlite_path, timeout=60)) as conn:
      row = conn.execute(
         """
         SELECT COUNT(*)
         FROM phase2_run_records
         WHERE study_name = ? AND trial_number = ?
         """,
         (study_name, trial_number),
      ).fetchone()
   return int(row[0]) if row is not None else 0


def decode_trial_row(row: dict[str, Any]) -> dict[str, Any]:
   decoded = dict(row)
   decoded["params"] = json.loads(decoded.pop("params_json"))
   decoded["aggregate_metrics"] = json.loads(decoded.pop("aggregate_metrics_json"))
   return decoded


def decode_run_row(row: dict[str, Any]) -> dict[str, Any]:
   decoded = dict(row)
   metrics = json.loads(decoded.pop("run_metrics_json"))
   decoded.update(metrics)
   return decoded


def select_best_valid_trial(trial_rows: list[dict[str, Any]]) -> dict[str, Any] | None:
   best_trial: dict[str, Any] | None = None
   for row in trial_rows:
      aggregate = row.get("aggregate_metrics", {})
      if not aggregate.get("valid", False):
         continue
      if best_trial is None or row["objective"] > best_trial["objective"]:
         best_trial = row
   return best_trial


def export_study_artifacts(paths: StudyPaths, study_name: str) -> dict[str, str]:
   trial_rows = [decode_trial_row(row) for row in read_trial_rows(paths.sqlite_path, study_name)]
   run_rows = [decode_run_row(row) for row in read_run_rows(paths.sqlite_path, study_name)]

   trial_columns = [
      "study_name",
      "trial_number",
      "state",
      "objective",
      "valid",
      "run_count",
      "window_count",
      "scenario_count",
      "pass_rate",
      "breach_rate",
      "zero_trade_rate",
      "progress_ratio_mean",
      "daily_slack_mean",
      "overall_slack_mean",
      "speed_mean",
      "reset_exposure_mean",
      "cache_hit_rate",
      "failure_reason",
      "params_json",
      "aggregate_metrics_json",
      "created_at_utc",
      "updated_at_utc",
   ]
   ensure_directory(paths.study_dir)
   with paths.trial_results_csv_path.open("w", encoding="utf-8", newline="") as handle:
      writer = csv.DictWriter(handle, fieldnames=trial_columns)
      writer.writeheader()
      for row in trial_rows:
         aggregate = row["aggregate_metrics"]
         writer.writerow(
            {
               "study_name": row["study_name"],
               "trial_number": row["trial_number"],
               "state": row["state"],
               "objective": row["objective"],
               "valid": aggregate.get("valid"),
               "run_count": aggregate.get("run_count"),
               "window_count": aggregate.get("window_count"),
               "scenario_count": aggregate.get("scenario_count"),
               "pass_rate": aggregate.get("pass_rate"),
               "breach_rate": aggregate.get("breach_rate"),
               "zero_trade_rate": aggregate.get("zero_trade_rate"),
               "progress_ratio_mean": aggregate.get("progress_ratio_mean"),
               "daily_slack_mean": aggregate.get("daily_slack_mean"),
               "overall_slack_mean": aggregate.get("overall_slack_mean"),
               "speed_mean": aggregate.get("speed_mean"),
               "reset_exposure_mean": aggregate.get("reset_exposure_mean"),
               "cache_hit_rate": aggregate.get("cache_hit_rate"),
               "failure_reason": aggregate.get("failure_reason"),
               "params_json": stable_json(row["params"]),
               "aggregate_metrics_json": stable_json(aggregate),
               "created_at_utc": row["created_at_utc"],
               "updated_at_utc": row["updated_at_utc"],
            }
         )

   with paths.trial_results_jsonl_path.open("w", encoding="utf-8") as handle:
      for row in trial_rows:
         handle.write(json.dumps(row, sort_keys=True) + "\n")

   with paths.run_records_jsonl_path.open("w", encoding="utf-8") as handle:
      for row in run_rows:
         handle.write(json.dumps(row, sort_keys=True) + "\n")

   write_json_file(
      paths.best_trial_summary_path,
      {
         "generated_at_utc": utc_now_iso(),
         "study_name": study_name,
         "trial_count": len(trial_rows),
         "run_record_count": len(run_rows),
         "best_trial": select_best_valid_trial(trial_rows),
      },
   )

   return {
      "trial_results_csv": str(paths.trial_results_csv_path),
      "trial_results_jsonl": str(paths.trial_results_jsonl_path),
      "run_records_jsonl": str(paths.run_records_jsonl_path),
      "best_trial_summary": str(paths.best_trial_summary_path),
   }


def parse_report_value(report_text: str, label: str) -> str | None:
   import re

   pattern = re.compile(
      rf"<td[^>]*>\s*{re.escape(label)}\s*</td>\s*<td[^>]*>\s*(?:<b>)?([^<]+)",
      flags=re.IGNORECASE | re.DOTALL,
   )
   match = pattern.search(report_text)
   if not match:
      return None
   value = html.unescape(match.group(1)).strip()
   return value or None


def parse_report_number(value: str | None) -> float | None:
   if value is None:
      return None
   cleaned = value.replace("\xa0", " ").replace(",", "").replace(" ", "").strip()
   cleaned = cleaned.rstrip("%")
   if not cleaned:
      return None
   try:
      return float(cleaned)
   except ValueError:
      return None


def parse_mt5_report_metrics(report_path: Path | None) -> dict[str, Any]:
   metrics = {
      "total_net_profit": None,
      "profit_factor": None,
      "recovery_factor": None,
      "sharpe_ratio": None,
      "total_trades": None,
      "report_parse_error": None,
   }
   if report_path is None or not report_path.exists():
      return metrics

   try:
      report_text = read_text_with_encodings(report_path)
   except OSError as exc:
      metrics["report_parse_error"] = str(exc)
      return metrics

   metrics["total_net_profit"] = parse_report_number(parse_report_value(report_text, "Total Net Profit:"))
   metrics["profit_factor"] = parse_report_number(parse_report_value(report_text, "Profit Factor:"))
   metrics["recovery_factor"] = parse_report_number(parse_report_value(report_text, "Recovery Factor:"))
   metrics["sharpe_ratio"] = parse_report_number(parse_report_value(report_text, "Sharpe Ratio:"))
   total_trades = parse_report_number(parse_report_value(report_text, "Total Trades:"))
   metrics["total_trades"] = int(total_trades) if total_trades is not None else None
   return metrics


def validate_summary(summary: dict[str, Any], summary_path: Path) -> None:
   missing = [field for field in REQUIRED_SUMMARY_FIELDS if field not in summary]
   if missing:
      raise ValueError(f"Summary missing required fields {missing}: {summary_path}")


def normalize_run_result(
   *,
   study_name: str,
   trial_number: int,
   window: StudyWindow,
   scenario: ScenarioSpec,
   result: dict[str, Any],
   rules_profile: RulesProfile,
   window_length_trading_days: int,
) -> dict[str, Any]:
   manifest_path = Path(result["manifest_path"])
   summary_path = Path(result["summary_path"])
   daily_path = Path(result["daily_path"])
   report_path_value = result.get("report_path")
   report_path = Path(report_path_value) if report_path_value else None

   if not manifest_path.exists():
      raise ValueError(f"Runner manifest missing: {manifest_path}")
   if not summary_path.exists():
      raise ValueError(f"Summary artifact missing: {summary_path}")
   if not daily_path.exists():
      raise ValueError(f"Daily artifact missing: {daily_path}")

   manifest = load_json_file(manifest_path)
   summary = load_json_file(summary_path)
   validate_summary(summary, summary_path)
   daily_rows = load_csv_rows(daily_path)
   report_metrics = parse_mt5_report_metrics(report_path)

   pass_flag = parse_bool(summary["pass"], "pass")
   breach_flag = parse_bool(summary["any_daily_breach"], "any_daily_breach") or parse_bool(
      summary["overall_breach"], "overall_breach"
   )
   final_return_pct = parse_float(summary["final_return_pct"], "final_return_pct")
   max_daily_dd_pct = parse_float(summary["max_daily_dd_pct"], "max_daily_dd_pct")
   max_overall_dd_pct = parse_float(summary["max_overall_dd_pct"], "max_overall_dd_pct")
   pass_days_traded = parse_int(summary["pass_days_traded"], "pass_days_traded")
   trades_total = parse_int(summary["trades_total"], "trades_total")
   days_traded = parse_int(summary.get("days_traded", 0), "days_traded")

   progress_ratio = clamp(final_return_pct / rules_profile.target_profit_pct, -1.0, 1.0)
   daily_slack_ratio = clamp(
      (rules_profile.daily_loss_cap_pct - max_daily_dd_pct) / rules_profile.daily_loss_cap_pct,
      0.0,
      1.0,
   )
   overall_slack_ratio = clamp(
      (rules_profile.overall_loss_cap_pct - max_overall_dd_pct) / rules_profile.overall_loss_cap_pct,
      0.0,
      1.0,
   )
   if not pass_flag:
      speed_ratio = 0.0
   else:
      denominator = window_length_trading_days - rules_profile.min_trade_days
      if denominator <= 0:
         speed_ratio = 1.0
      else:
         speed_ratio = clamp(
            1.0 - ((pass_days_traded - rules_profile.min_trade_days) / denominator),
            0.0,
            1.0,
         )
   zero_trade_flag = (trades_total == 0)
   reset_exposure_ratio = clamp(max_daily_dd_pct / rules_profile.daily_loss_cap_pct, 0.0, 1.0)

   return {
      "study_name": study_name,
      "trial_number": trial_number,
      "window_id": window.id,
      "scenario_id": scenario.id,
      "scenario_weight": scenario.weight,
      "cache_key": result.get("cache_key"),
      "run_dir": result.get("run_dir"),
      "manifest_path": str(manifest_path),
      "summary_path": str(summary_path),
      "daily_path": str(daily_path),
      "report_path": str(report_path) if report_path else None,
      "status": result.get("status"),
      "from_date": iso_date(window.from_date),
      "to_date": iso_date(window.to_date),
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
         "min_trade_days_required": parse_int(
            summary.get("min_trade_days_required", rules_profile.min_trade_days),
            "min_trade_days_required",
         ),
         "observed_server_days": parse_int(summary.get("observed_server_days", len(daily_rows)), "observed_server_days"),
      },
      "report_metrics": report_metrics,
      "daily_row_count": len(daily_rows),
      "run_manifest_spec": manifest.get("spec"),
   }


def aggregate_trial_runs(
   run_records: list[dict[str, Any]],
   scenario_count: int,
   window_count: int,
) -> tuple[dict[str, Any], float]:
   if not run_records:
      aggregate = {
         "valid": False,
         "failure_reason": "No run records were produced",
         "run_count": 0,
         "window_count": window_count,
         "scenario_count": scenario_count,
      }
      return aggregate, INVALID_OBJECTIVE

   invalid_records = [record for record in run_records if not record.get("valid", False)]
   if invalid_records:
      aggregate = {
         "valid": False,
         "failure_reason": invalid_records[0].get("failure_reason", "Invalid run record"),
         "run_count": len(run_records),
         "window_count": window_count,
         "scenario_count": scenario_count,
      }
      return aggregate, INVALID_OBJECTIVE

   total_weight = sum(float(record["scenario_weight"]) for record in run_records)
   if total_weight <= 0.0:
      aggregate = {
         "valid": False,
         "failure_reason": "Scenario weights summed to zero",
         "run_count": len(run_records),
         "window_count": window_count,
         "scenario_count": scenario_count,
      }
      return aggregate, INVALID_OBJECTIVE

   def weighted_mean(field_name: str) -> float:
      return sum(float(record[field_name]) * float(record["scenario_weight"]) for record in run_records) / total_weight

   aggregate = {
      "valid": True,
      "run_count": len(run_records),
      "window_count": window_count,
      "scenario_count": scenario_count,
      "pass_rate": weighted_mean("pass_flag"),
      "breach_rate": weighted_mean("breach_flag"),
      "zero_trade_rate": weighted_mean("zero_trade_flag"),
      "progress_ratio_mean": weighted_mean("progress_ratio"),
      "daily_slack_mean": weighted_mean("daily_slack_ratio"),
      "overall_slack_mean": weighted_mean("overall_slack_ratio"),
      "speed_mean": weighted_mean("speed_ratio"),
      "reset_exposure_mean": weighted_mean("reset_exposure_ratio"),
      "cache_hit_rate": sum(
         (1.0 if record.get("status") == "cache_hit" else 0.0) * float(record["scenario_weight"])
         for record in run_records
      ) / total_weight,
      "failure_reason": None,
   }
   objective = (
      500.0 * aggregate["pass_rate"]
      + 80.0 * aggregate["progress_ratio_mean"]
      + 25.0 * aggregate["daily_slack_mean"]
      + 25.0 * aggregate["overall_slack_mean"]
      + 20.0 * aggregate["speed_mean"]
      - 100.0 * aggregate["breach_rate"]
      - 30.0 * aggregate["zero_trade_rate"]
      - 20.0 * aggregate["reset_exposure_mean"]
   )
   return aggregate, objective


def write_windows_artifact(paths: StudyPaths, windows: tuple[StudyWindow, ...]) -> None:
   write_json_file(
      paths.windows_path,
      {
         "generated_at_utc": utc_now_iso(),
         "window_count": len(windows),
         "windows": windows_to_payload(windows),
      },
   )


def write_study_manifest(
   paths: StudyPaths,
   spec: StudySpec,
   rules_profile: RulesProfile,
   windows: tuple[StudyWindow, ...],
) -> None:
   write_json_file(
      paths.manifest_path,
      {
         "generated_at_utc": utc_now_iso(),
         "study_name": spec.name,
         "study_spec_path": str(spec.source_path),
         "rules_profile_id": rules_profile.id,
         "rules_profile_path": str(rules_profile_path(rules_profile.id)),
         "study_dir": str(paths.study_dir),
         "study_sqlite_path": str(paths.sqlite_path),
         "windows_path": str(paths.windows_path),
         "window_count": len(windows),
         "scenario_count": len(spec.scenarios),
         "search_space": [dataclasses.asdict(dimension) for dimension in spec.search_space],
      },
   )


def sample_trial_params(trial: Any, spec: StudySpec) -> dict[str, Any]:
   params: dict[str, Any] = {}
   for dimension in spec.search_space:
      if dimension.kind == "float":
         params[dimension.name] = trial.suggest_float(
            dimension.name,
            dimension.low,
            dimension.high,
            step=dimension.step,
         )
         continue
      if dimension.kind == "categorical":
         params[dimension.name] = trial.suggest_categorical(dimension.name, list(dimension.choices))
         continue
      raise ValueError(f"Unsupported search dimension kind: {dimension.kind}")
   return params


def evaluate_trial(
   trial: Any,
   *,
   spec: StudySpec,
   rules_profile: RulesProfile,
   windows: tuple[StudyWindow, ...],
   paths: StudyPaths,
   runner_paths: mt5_runner.RunnerPaths,
   runner_module: Any,
   stop_existing: bool,
) -> float:
   created_at_utc = utc_now_iso()
   trial_number = trial.number
   trial_params = sample_trial_params(trial, spec)
   clear_trial_run_records(paths.sqlite_path, spec.name, trial_number)

   run_records: list[dict[str, Any]] = []
   objective = INVALID_OBJECTIVE
   aggregate_metrics: dict[str, Any]
   failure_reason: str | None = None
   try:
      pending_sync = True
      pending_compile = True
      for window in windows:
         for scenario in spec.scenarios:
            set_overrides = dict(trial_params)
            set_overrides.update(scenario.set_overrides)
            run_data = {
               "name": f"{spec.name}__t{trial_number:04d}__{window.id}__{scenario.id}",
               "symbol": spec.symbol,
               "period": spec.period,
               "from_date": to_mt5_date(window.from_date),
               "to_date": to_mt5_date(window.to_date),
               "base_set": str(spec.base_set),
               "scenario": scenario.id,
               "rules_profile": rules_profile.id,
               "set_overrides": set_overrides,
            }
            run_spec = runner_module.build_spec(run_data)
            result = runner_module.run_single_backtest(
               run_spec,
               runner_paths,
               dry_run=False,
               sync_before_run=pending_sync,
               compile_before_run=pending_compile,
               force=False,
               stop_existing=stop_existing,
            )
            if pending_sync and result.get("status") != "cache_hit":
               pending_sync = False
               pending_compile = False
            run_record = normalize_run_result(
               study_name=spec.name,
               trial_number=trial_number,
               window=window,
               scenario=scenario,
               result=result,
               rules_profile=rules_profile,
               window_length_trading_days=spec.window_length_trading_days,
            )
            run_records.append(run_record)
            upsert_run_record(paths.sqlite_path, run_record, created_at_utc)

      aggregate_metrics, objective = aggregate_trial_runs(
         run_records,
         scenario_count=len(spec.scenarios),
         window_count=len(windows),
      )
      if not bool(aggregate_metrics.get("valid", False)):
         failure_reason = str(
            aggregate_metrics.get("failure_reason")
            or "Phase 2 trial produced invalid aggregate metrics"
         )
   except Exception as exc:
      failure_reason = str(exc)
      aggregate_metrics = {
         "valid": False,
         "failure_reason": failure_reason,
         "run_count": len(run_records),
         "window_count": len(windows),
         "scenario_count": len(spec.scenarios),
      }
      objective = INVALID_OBJECTIVE

   valid_trial = bool(aggregate_metrics.get("valid", False)) and failure_reason is None
   trial.set_user_attr("phase2_objective", objective)
   trial.set_user_attr("phase2_run_count", len(run_records))
   trial.set_user_attr("phase2_valid", valid_trial)
   upsert_trial_result(
      paths.sqlite_path,
      study_name=spec.name,
      trial_number=trial_number,
      state="COMPLETE" if valid_trial else "FAIL",
      objective=objective,
      params=trial_params,
      aggregate_metrics=aggregate_metrics,
      created_at_utc=created_at_utc,
   )
   export_study_artifacts(paths, spec.name)
   if not valid_trial:
      raise Phase2TrialFailure(failure_reason or "Phase 2 trial failed")
   return objective


def recover_stale_running_trials(
   study: Any,
   *,
   spec: StudySpec,
   paths: StudyPaths,
   window_count: int,
   scenario_count: int,
) -> int:
   optuna = require_optuna()
   recovered = 0
   storage = getattr(study, "_storage", None)
   set_trial_state_values = getattr(storage, "set_trial_state_values", None)

   for trial in study.trials:
      if trial.state != optuna.trial.TrialState.RUNNING:
         continue
      if not callable(set_trial_state_values):
         raise RuntimeError("Optuna storage does not support stale RUNNING trial recovery")
      trial_id = getattr(trial, "_trial_id", None)
      if trial_id is None:
         raise RuntimeError("Optuna trial id missing for stale RUNNING trial recovery")

      set_trial_state_values(trial_id, optuna.trial.TrialState.FAIL)
      created_at_utc = utc_now_iso()
      upsert_trial_result(
         paths.sqlite_path,
         study_name=spec.name,
         trial_number=trial.number,
         state="FAIL",
         objective=INVALID_OBJECTIVE,
         params=dict(trial.params),
         aggregate_metrics={
            "valid": False,
            "failure_reason": "Recovered stale RUNNING trial on resume after interrupted process",
            "run_count": count_trial_run_rows(paths.sqlite_path, spec.name, trial.number),
            "window_count": window_count,
            "scenario_count": scenario_count,
         },
         created_at_utc=created_at_utc,
      )
      recovered += 1

   if recovered > 0:
      export_study_artifacts(paths, spec.name)
   return recovered


def run_study(
   study_spec_path: Path,
   *,
   n_trials_override: int | None = None,
   resume: bool,
   mt5_install_path: str | None = None,
   terminal_data_path: str | None = None,
   output_root: str | Path = mt5_runner.DEFAULT_OUTPUT_ROOT,
   stop_existing: bool = False,
   runner_paths: mt5_runner.RunnerPaths | None = None,
   runner_module: Any = mt5_runner,
) -> dict[str, Any]:
   optuna = require_optuna()
   spec = load_study_spec(study_spec_path)
   rules = load_rules_profile(rules_profile_path(spec.rules_profile))
   windows = build_windows(spec)
   paths = build_study_paths(spec.name)

   if paths.sqlite_path.exists() and not resume:
      raise RuntimeError(
         f"Study storage already exists for {spec.name}. Rerun with --resume to continue."
      )

   ensure_directory(paths.study_dir)
   ensure_custom_tables(paths.sqlite_path)
   write_windows_artifact(paths, windows)
   write_study_manifest(paths, spec, rules, windows)

   if runner_paths is None:
      runner_paths = runner_module.build_runner_paths(
         mt5_install_path=mt5_install_path,
         terminal_data_path=terminal_data_path,
         output_root=output_root,
      )

   sampler = optuna.samplers.TPESampler(seed=spec.seed)
   storage = build_storage_url(paths.sqlite_path)
   study = optuna.create_study(
      study_name=spec.name,
      direction="maximize",
      sampler=sampler,
      storage=storage,
      load_if_exists=True,
   )
   try:
      target_trials = n_trials_override or spec.n_trials
      recovered_stale_trials = 0
      if resume:
         recovered_stale_trials = recover_stale_running_trials(
            study,
            spec=spec,
            paths=paths,
            window_count=len(windows),
            scenario_count=len(spec.scenarios),
         )
      completed_trials = [
         trial
         for trial in study.trials
         if getattr(trial.state, "name", str(trial.state)) == "COMPLETE"
      ]
      remaining_trials = max(0, target_trials - len(completed_trials))
      if remaining_trials > 0:
         study.optimize(
            lambda trial: evaluate_trial(
               trial,
               spec=spec,
               rules_profile=rules,
               windows=windows,
               paths=paths,
               runner_paths=runner_paths,
               runner_module=runner_module,
               stop_existing=stop_existing,
            ),
            n_trials=remaining_trials,
            n_jobs=1,
            catch=(Phase2TrialFailure,),
         )

      exports = export_study_artifacts(paths, spec.name)
      trial_rows = [decode_trial_row(row) for row in read_trial_rows(paths.sqlite_path, spec.name)]
      completed_trial_rows = [row for row in trial_rows if row["state"] == "COMPLETE"]
      return {
         "study_name": spec.name,
         "study_dir": str(paths.study_dir),
         "study_sqlite_path": str(paths.sqlite_path),
         "windows_path": str(paths.windows_path),
         "window_count": len(windows),
         "scenario_count": len(spec.scenarios),
         "runs_per_trial": len(windows) * len(spec.scenarios),
         "target_trials": target_trials,
         "completed_trials": len(completed_trial_rows),
         "recovered_stale_trials": recovered_stale_trials,
         "best_trial": select_best_valid_trial(trial_rows),
         "exports": exports,
      }
   finally:
      storage_backend = getattr(study, "_storage", None)
      remove_session = getattr(storage_backend, "remove_session", None)
      if callable(remove_session):
         remove_session()
      backend = getattr(storage_backend, "_backend", None)
      backend_remove_session = getattr(backend, "remove_session", None)
      if callable(backend_remove_session):
         backend_remove_session()
      engine = getattr(backend, "engine", None) or getattr(storage_backend, "engine", None)
      if engine is not None:
         engine.dispose()


def export_study(study_dir: Path) -> dict[str, Any]:
   manifest_path = study_dir / "study_manifest.json"
   if not manifest_path.exists():
      raise FileNotFoundError(f"Study manifest not found: {manifest_path}")
   manifest = load_json_file(manifest_path)
   study_name = str(manifest.get("study_name", "")).strip()
   if not study_name:
      raise ValueError(f"study_name missing from manifest: {manifest_path}")
   paths = build_study_paths(study_name, repo=study_dir.parents[2])
   exports = export_study_artifacts(paths, study_name)
   return {
      "study_name": study_name,
      "study_dir": str(paths.study_dir),
      "exports": exports,
   }


def add_shared_study_args(parser: argparse.ArgumentParser) -> None:
   parser.add_argument("--mt5-install-path", default=None)
   parser.add_argument("--terminal-data-path", default=None)
   parser.add_argument("--output-root", default=str(mt5_runner.DEFAULT_OUTPUT_ROOT))


def build_parser() -> argparse.ArgumentParser:
   parser = argparse.ArgumentParser(description="FundingPips Phase 2 HPO tooling")
   subparsers = parser.add_subparsers(dest="command", required=True)

   generate_parser = subparsers.add_parser("generate-windows", help="Generate deterministic rolling windows")
   generate_parser.add_argument("--study-spec", required=True)

   run_parser = subparsers.add_parser("run-study", help="Run or resume a Phase 2 study")
   run_parser.add_argument("--study-spec", required=True)
   run_parser.add_argument("--n-trials", type=int, default=None)
   run_parser.add_argument("--resume", action="store_true")
   run_parser.add_argument("--stop-existing", action="store_true")
   add_shared_study_args(run_parser)

   export_parser = subparsers.add_parser("export-study", help="Regenerate flat exports from study SQLite data")
   export_parser.add_argument("--study-dir", required=True)

   return parser


def main(argv: list[str] | None = None) -> int:
   parser = build_parser()
   args = parser.parse_args(argv)

   if args.command == "generate-windows":
      spec_path = mt5_runner.resolve_repo_path(repo_root(), Path(args.study_spec))
      spec = load_study_spec(spec_path)
      windows = build_windows(spec)
      paths = build_study_paths(spec.name)
      ensure_directory(paths.study_dir)
      write_windows_artifact(paths, windows)
      print(
         json.dumps(
            {
               "study_name": spec.name,
               "study_dir": str(paths.study_dir),
               "windows_path": str(paths.windows_path),
               "window_count": len(windows),
               "windows": windows_to_payload(windows),
            },
            indent=2,
            sort_keys=True,
         )
      )
      return 0

   if args.command == "run-study":
      result = run_study(
         mt5_runner.resolve_repo_path(repo_root(), Path(args.study_spec)),
         n_trials_override=args.n_trials,
         resume=args.resume,
         mt5_install_path=args.mt5_install_path,
         terminal_data_path=args.terminal_data_path,
         output_root=args.output_root,
         stop_existing=args.stop_existing,
      )
      print(json.dumps(result, indent=2, sort_keys=True))
      return 0

   if args.command == "export-study":
      study_dir = mt5_runner.resolve_repo_path(repo_root(), Path(args.study_dir))
      result = export_study(study_dir)
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
