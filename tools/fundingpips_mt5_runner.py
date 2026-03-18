#!/usr/bin/env python3
"""FundingPips Phase 1 MT5 single-run automation.

This runner generates a per-run .set and .ini, launches MT5 headlessly via
`/config:...`, waits for Phase 0 evaluation artifacts, and collects outputs
into a deterministic cache-keyed run folder.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


DEFAULT_MT5_INSTALL = Path(r"C:\Program Files\MetaTrader 5")
DEFAULT_TIMEOUT_SECONDS = 900
DEFAULT_OUTPUT_ROOT = Path(".tmp") / "fundingpips_hpo_runs"
DEFAULT_TEMPLATE_INI = Path("Tests") / "RPEA" / "RPEA_10k_single.ini"
DEFAULT_BASE_SET = Path("Tests") / "RPEA" / "RPEA_10k_default.set"
DEFAULT_EXPERT = r"FundingPips\RPEA"
DEFAULT_RULES_PROFILE = "fundingpips_1step_eval"
DEFAULT_SCENARIO = "baseline"
MAX_RUN_SLUG_LENGTH = 64
MAX_REPORT_STEM_LENGTH = 64

SUMMARY_FILENAME = "fundingpips_eval_summary.json"
DAILY_FILENAME = "fundingpips_eval_daily.csv"


@dataclasses.dataclass(frozen=True)
class RunnerPaths:
   repo_root: Path
   terminal_exe: Path
   metaeditor_exe: Path
   terminal_data_path: Path
   tester_root: Path
   tester_profiles_dir: Path
   config_dir: Path
   output_root: Path


@dataclasses.dataclass(frozen=True)
class StagedFileSpec:
   source_path: Path
   terminal_relative_path: str
   artifact_id: str | None = None
   sha256: str | None = None


@dataclasses.dataclass(frozen=True)
class BacktestSpec:
   name: str
   expert: str
   symbol: str
   period: str
   from_date: str
   to_date: str
   deposit: int
   currency: str
   leverage: int
   model: int
   execution_mode: int
   optimization: int
   optimization_criterion: int
   forward_mode: int
   use_local: int
   use_remote: int
   use_cloud: int
   visual: int
   shutdown_terminal: int
   replace_report: int
   template_ini: Path
   base_set: Path
   scenario: str
   rules_profile: str
   set_overrides: dict[str, Any]
   staged_files: tuple[StagedFileSpec, ...]
   report_stem: str
   timeout_seconds: int


def spec_to_manifest_dict(spec: BacktestSpec) -> dict[str, Any]:
   data = dataclasses.asdict(spec)
   data["template_ini"] = str(spec.template_ini)
   data["base_set"] = str(spec.base_set)
   data["staged_files"] = [
      {
         "source_path": str(item.source_path),
         "terminal_relative_path": item.terminal_relative_path,
         "artifact_id": item.artifact_id,
         "sha256": item.sha256,
      }
      for item in spec.staged_files
   ]
   return data


def repo_root() -> Path:
   return Path(__file__).resolve().parents[1]


def normalize_override_value(value: Any) -> str:
   if isinstance(value, bool):
      return "1" if value else "0"
   if value is None:
      return ""
   return str(value)


def sha256_file(path: Path) -> str:
   digest = hashlib.sha256()
   with path.open("rb") as handle:
      while True:
         chunk = handle.read(65536)
         if not chunk:
            break
         digest.update(chunk)
   return digest.hexdigest()


def parse_staged_files(raw_files: Any) -> tuple[StagedFileSpec, ...]:
   if raw_files is None:
      return ()
   if not isinstance(raw_files, list):
      raise ValueError("staged_files must be a list when provided")

   parsed: list[StagedFileSpec] = []
   for index, raw_item in enumerate(raw_files):
      if not isinstance(raw_item, dict):
         raise ValueError(f"staged_files[{index}] must be an object")
      raw_source_path = str(raw_item.get("source_path", "")).strip()
      terminal_relative_path = str(raw_item.get("terminal_relative_path", "")).strip()
      if not raw_source_path:
         raise ValueError(f"staged_files[{index}].source_path is required")
      if not terminal_relative_path:
         raise ValueError(f"staged_files[{index}].terminal_relative_path is required")
      source_path = Path(raw_source_path)
      artifact_id = raw_item.get("artifact_id")
      parsed.append(
         StagedFileSpec(
            source_path=source_path,
            terminal_relative_path=terminal_relative_path,
            artifact_id=str(artifact_id).strip() or None if artifact_id is not None else None,
            sha256=str(raw_item.get("sha256", "")).strip() or None,
         )
      )
   return tuple(parsed)


def parse_key_value_pairs(pairs: list[str]) -> dict[str, str]:
   overrides: dict[str, str] = {}
   for pair in pairs:
      if "=" not in pair:
         raise ValueError(f"Override must use KEY=VALUE format: {pair}")
      key, value = pair.split("=", 1)
      key = key.strip()
      if not key:
         raise ValueError(f"Override key cannot be empty: {pair}")
      overrides[key] = value.strip()
   return overrides


def safe_name(value: str) -> str:
   chars = []
   for ch in value:
      if ch.isalnum() or ch in ("-", "_"):
         chars.append(ch)
      else:
         chars.append("_")
   collapsed = "".join(chars).strip("_")
   return collapsed or "run"


def compact_slug(value: str, *, max_length: int) -> str:
   slug = safe_name(value)
   if len(slug) <= max_length:
      return slug

   digest = hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]
   head_budget = max_length - len(digest) - 1
   if head_budget < 1:
      return digest[:max_length]
   return f"{slug[:head_budget]}_{digest}"


def resolve_terminal_data_path(preferred: str | None) -> Path:
   if preferred:
      candidate = Path(preferred).expanduser()
      if candidate.exists():
         return candidate.resolve()
      raise FileNotFoundError(f"MT5 data path not found: {preferred}")

   terminal_root = Path(os.environ["APPDATA"]) / "MetaQuotes" / "Terminal"
   profiles = [p for p in terminal_root.iterdir() if p.is_dir()]
   if not profiles:
      raise FileNotFoundError(f"MT5 data folder not found under {terminal_root}")
   profiles.sort(key=lambda p: p.stat().st_mtime, reverse=True)
   return profiles[0].resolve()


def resolve_tester_root(terminal_data_path: Path) -> Path:
   resolved_terminal_data = terminal_data_path.resolve()
   for candidate in (resolved_terminal_data, *resolved_terminal_data.parents):
      if (
         candidate.name.lower() == "terminal"
         and candidate.parent.name.lower() == "metaquotes"
      ):
         return (candidate.parent / "Tester").resolve()
   return (resolved_terminal_data.parent / "Tester").resolve()


def resolve_terminal_exe(mt5_install_path: str | None, terminal_data_path: Path) -> Path:
   candidates = []
   if mt5_install_path:
      candidates.append(Path(mt5_install_path).expanduser() / "terminal64.exe")
   candidates.append(DEFAULT_MT5_INSTALL / "terminal64.exe")
   candidates.append(terminal_data_path / "terminal64.exe")

   for candidate in candidates:
      if candidate.exists():
         return candidate.resolve()

   joined = ", ".join(str(path) for path in candidates)
   raise FileNotFoundError(f"terminal64.exe not found. Tried: {joined}")


def resolve_metaeditor_exe(mt5_install_path: str | None, terminal_data_path: Path) -> Path:
   candidates = []
   if mt5_install_path:
      candidates.append(Path(mt5_install_path).expanduser() / "metaeditor64.exe")
   candidates.append(DEFAULT_MT5_INSTALL / "metaeditor64.exe")
   candidates.append(terminal_data_path / "metaeditor64.exe")

   for candidate in candidates:
      if candidate.exists():
         return candidate.resolve()

   joined = ", ".join(str(path) for path in candidates)
   raise FileNotFoundError(f"metaeditor64.exe not found. Tried: {joined}")


def terminal_fingerprint(terminal_exe: Path) -> dict[str, Any]:
   stat = terminal_exe.stat()
   return {
      "path": str(terminal_exe),
      "size": stat.st_size,
      "mtime_ns": stat.st_mtime_ns,
   }


def ensure_directory(path: Path) -> None:
   path.mkdir(parents=True, exist_ok=True)


def sync_repo(repo: Path) -> None:
   script_path = repo / "SyncRepoToTerminal.ps1"
   if not script_path.exists():
      raise FileNotFoundError(f"Sync script not found: {script_path}")
   command = [
      "powershell",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      str(script_path),
   ]
   subprocess.run(command, cwd=str(repo), check=True)


def assert_no_running_mt5() -> None:
   command = [
      "powershell",
      "-NoProfile",
      "-Command",
      "Get-Process terminal64,metatester64,metatester -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName",
   ]
   proc = subprocess.run(command, capture_output=True, text=True, check=False)
   names = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
   if names:
      joined = ", ".join(sorted(set(names)))
      raise RuntimeError(
         "Existing MT5 processes detected. Close them first or rerun with --stop-existing: "
         + joined
      )


def stop_existing_mt5() -> None:
   command = [
      "powershell",
      "-NoProfile",
      "-Command",
      "Get-Process terminal64,metatester64,metatester -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue",
   ]
   subprocess.run(command, check=False)
   time.sleep(2)


def stable_json(data: Any) -> str:
   return json.dumps(data, sort_keys=True, separators=(",", ":"))


def compute_cache_key(
   spec: BacktestSpec,
   base_set_text: str,
   terminal_info: dict[str, Any],
   expert_dependency_hash: str,
   staged_files_fingerprint: list[dict[str, Any]] | None = None,
) -> str:
   payload = {
      "expert": spec.expert,
      "symbol": spec.symbol,
      "period": spec.period,
      "from_date": spec.from_date,
      "to_date": spec.to_date,
      "deposit": spec.deposit,
      "currency": spec.currency,
      "leverage": spec.leverage,
      "model": spec.model,
      "execution_mode": spec.execution_mode,
      "optimization": spec.optimization,
      "optimization_criterion": spec.optimization_criterion,
      "forward_mode": spec.forward_mode,
      "use_local": spec.use_local,
      "use_remote": spec.use_remote,
      "use_cloud": spec.use_cloud,
      "scenario": spec.scenario,
      "rules_profile": spec.rules_profile,
      "set_overrides": spec.set_overrides,
      "staged_files": staged_files_fingerprint or [],
      "base_set_text": base_set_text,
      "expert_dependency_hash": expert_dependency_hash,
      "terminal": terminal_info,
   }
   digest = hashlib.sha256(stable_json(payload).encode("utf-8")).hexdigest()
   return digest[:16]


def compute_directory_tree_hash(root: Path, *, suffixes: tuple[str, ...]) -> str:
   digest = hashlib.sha256()
   files = sorted(
      path
      for path in root.rglob("*")
      if path.is_file() and path.suffix.lower() in suffixes
   )
   for path in files:
      relative_path = path.relative_to(root).as_posix()
      digest.update(relative_path.encode("utf-8"))
      digest.update(b"\0")
      with path.open("rb") as handle:
         while True:
            chunk = handle.read(65536)
            if not chunk:
               break
            digest.update(chunk)
      digest.update(b"\0")
   return digest.hexdigest()


def compute_ea_dependency_hash(repo: Path) -> str:
   digest = hashlib.sha256()
   roots = [
      resolve_repo_path(repo, Path("MQL5/Experts/FundingPips")),
      resolve_repo_path(repo, Path("MQL5/Include/RPEA")),
   ]
   for root in roots:
      digest.update(root.relative_to(repo).as_posix().encode("utf-8"))
      digest.update(b"\0")
      digest.update(compute_directory_tree_hash(root, suffixes=(".mq5", ".mqh")).encode("ascii"))
      digest.update(b"\0")
   return digest.hexdigest()


def fingerprint_staged_files(staged_files: tuple[StagedFileSpec, ...], repo: Path) -> list[dict[str, Any]]:
   fingerprints: list[dict[str, Any]] = []
   for item in staged_files:
      source_path = resolve_repo_path(repo, item.source_path)
      if not source_path.exists():
         raise FileNotFoundError(f"Staged artifact source not found: {source_path}")
      if not source_path.is_file():
         raise ValueError(f"Staged artifact source must be a file: {source_path}")
      computed_sha256 = sha256_file(source_path)
      if item.sha256 and item.sha256.strip().lower() != computed_sha256.lower():
         raise ValueError(
            f"Staged artifact sha256 mismatch for {source_path}: "
            f"expected {item.sha256.strip().lower()}, got {computed_sha256.lower()}"
         )
      sha256 = computed_sha256
      artifact_id = item.artifact_id or f"{safe_name(source_path.stem)}_{sha256[:12]}"
      fingerprints.append(
         {
            "artifact_id": artifact_id,
            "source_path": str(source_path),
            "terminal_relative_path": item.terminal_relative_path.replace("\\", "/"),
            "sha256": sha256,
            "size": source_path.stat().st_size,
         }
      )
   fingerprints.sort(key=lambda row: (row["terminal_relative_path"], row["sha256"]))
   return fingerprints


def stage_runtime_files(
   staged_files: tuple[StagedFileSpec, ...],
   *,
   repo: Path,
   terminal_data_path: Path,
   tester_root: Path | None = None,
) -> list[dict[str, Any]]:
   terminal_root = terminal_data_path / "MQL5" / "Files"
   common_root = terminal_data_path.parent / "Common" / "Files"
   tester_agent_roots: list[Path] = []
   if tester_root is not None and tester_root.exists():
      for child in sorted(tester_root.iterdir()):
         if not child.is_dir():
            continue
         if child.name.startswith("Agent-"):
            tester_agent_roots.append(child / "MQL5" / "Files")
            continue
         for grandchild in sorted(child.iterdir()):
            if not grandchild.is_dir() or not grandchild.name.startswith("Agent-"):
               continue
            tester_agent_roots.append(grandchild / "MQL5" / "Files")

   staged_rows = fingerprint_staged_files(staged_files, repo)
   for row in staged_rows:
      source_path = Path(str(row["source_path"]))
      terminal_destination = terminal_root / Path(str(row["terminal_relative_path"]))
      common_destination = common_root / Path(str(row["terminal_relative_path"]))
      agent_destinations: list[str] = []

      for destination in (terminal_destination, common_destination):
         ensure_directory(destination.parent)
         shutil.copy2(source_path, destination)

      for root in tester_agent_roots:
         destination = root / Path(str(row["terminal_relative_path"]))
         ensure_directory(destination.parent)
         shutil.copy2(source_path, destination)
         agent_destinations.append(str(destination))

      row["terminal_destination_path"] = str(terminal_destination)
      row["common_destination_path"] = str(common_destination)
      row["tester_agent_destination_paths"] = agent_destinations
      row["runtime_destination_paths"] = [
         str(terminal_destination),
         str(common_destination),
         *agent_destinations,
      ]
   return staged_rows


def load_text(path: Path) -> str:
   return path.read_text(encoding="ascii")


def load_json_text(path: Path) -> dict[str, Any] | None:
   try:
      return json.loads(path.read_text(encoding="ascii"))
   except (OSError, ValueError):
      return None


def load_ini_text_with_encoding(path: Path) -> tuple[str, str]:
   for encoding in ("ascii", "utf-8-sig", "utf-16", "utf-16-le", "utf-16-be"):
      try:
         return path.read_text(encoding=encoding).lstrip("\ufeff"), encoding
      except UnicodeDecodeError:
         continue
   raise UnicodeDecodeError("unknown", b"", 0, 1, f"Could not decode INI text: {path}")


def write_single_run_set(base_set_text: str, overrides: dict[str, Any], output_path: Path) -> None:
   normalized_overrides = {key: normalize_override_value(value) for key, value in overrides.items()}
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

   output_path.write_text("\n".join(output_lines) + "\n", encoding="ascii")


def parse_template_ini(template_text: str) -> dict[str, str]:
   values: dict[str, str] = {}
   for raw_line in template_text.splitlines():
      line = raw_line.strip()
      if not line or line.startswith(";") or line.startswith("[") or "=" not in line:
         continue
      key, value = line.split("=", 1)
      values[key.strip()] = value.strip()
   return values


def build_tester_ini(spec: BacktestSpec, profile_set_name: str, report_relative_path: str) -> str:
   template_values = parse_template_ini(load_text(resolve_repo_path(repo_root(), spec.template_ini)))
   values = {
      "Expert": spec.expert,
      "ExpertParameters": profile_set_name,
      "Symbol": spec.symbol,
      "Period": spec.period,
      "Deposit": str(spec.deposit),
      "Currency": spec.currency,
      "Leverage": str(spec.leverage),
      "Model": str(spec.model),
      "ExecutionMode": str(spec.execution_mode),
      "Optimization": str(spec.optimization),
      "OptimizationCriterion": str(spec.optimization_criterion),
      "FromDate": spec.from_date,
      "ToDate": spec.to_date,
      "ForwardMode": str(spec.forward_mode),
      "ShutdownTerminal": str(spec.shutdown_terminal),
      "ReplaceReport": str(spec.replace_report),
      "UseLocal": str(spec.use_local),
      "UseRemote": str(spec.use_remote),
      "UseCloud": str(spec.use_cloud),
      "Visual": str(spec.visual),
      "Report": report_relative_path,
   }
   template_values.update(values)

   ordered_keys = [
      "Expert",
      "ExpertParameters",
      "Symbol",
      "Period",
      "Deposit",
      "Currency",
      "Leverage",
      "Model",
      "ExecutionMode",
      "Optimization",
      "OptimizationCriterion",
      "FromDate",
      "ToDate",
      "ForwardMode",
      "ShutdownTerminal",
      "ReplaceReport",
      "UseLocal",
      "UseRemote",
      "UseCloud",
      "Visual",
      "Report",
   ]

   lines = [
      "; Auto-generated by tools/fundingpips_mt5_runner.py",
      "[Tester]",
   ]
   for key in ordered_keys:
      if key in template_values:
         lines.append(f"{key}={template_values[key]}")
   return "\n".join(lines) + "\n"


def extract_ini_section(ini_text: str, section_name: str) -> str:
   wanted = f"[{section_name}]"
   lines = ini_text.splitlines()
   section: list[str] = []
   in_section = False
   for line in lines:
      stripped = line.strip().lstrip("\ufeff")
      if stripped.startswith("[") and stripped.endswith("]"):
         if stripped == wanted:
            in_section = True
            section.append(line)
            continue
         if in_section:
            break
      elif in_section:
         section.append(line)
         continue

      if in_section:
         section.append(line)

   return "\n".join(section).strip()


def prepend_common_section(ini_text: str, common_ini_text: str | None) -> str:
   if "[Common]" in ini_text or not common_ini_text:
      return ini_text

   common_section = extract_ini_section(common_ini_text, "Common")
   if not common_section:
      return ini_text

   return common_section + "\n\n" + ini_text


def locate_recent_file(root: Path, filename: str, not_before: float) -> Path | None:
   if not root.exists():
      return None

   latest: Path | None = None
   latest_mtime = -1.0
   for path in root.rglob(filename):
      try:
         mtime = path.stat().st_mtime
      except FileNotFoundError:
         continue
      if mtime < not_before:
         continue
      if mtime > latest_mtime:
         latest = path
         latest_mtime = mtime
   return latest


def locate_recent_log_files(
   root: Path,
   prefix: str,
   *,
   suffix: str = ".csv",
   not_before: float,
) -> list[Path]:
   if not root.exists():
      return []

   matches: list[tuple[float, Path]] = []
   pattern = f"{prefix}*{suffix}"
   for path in root.rglob(pattern):
      if not path.is_file():
         continue
      if "RPEA" not in path.parts or "logs" not in path.parts:
         continue
      try:
         mtime = path.stat().st_mtime
      except FileNotFoundError:
         continue
      if mtime < not_before:
         continue
      matches.append((mtime, path))

   matches.sort(key=lambda item: (item[0], str(item[1])))
   return [path for _, path in matches]


def resolve_cached_report_path(
   manifest_path: Path,
   collected_dir: Path,
   report_stem: str,
   cache_key: str,
) -> Path | None:
   manifest = load_json_text(manifest_path) if manifest_path.exists() else None
   manifest_report = manifest.get("collected_report") if isinstance(manifest, dict) else None
   if manifest_report:
      candidate = Path(str(manifest_report))
      if candidate.exists():
         return candidate

   expected_names = [
      f"{report_stem}_{cache_key}.xml",
      f"{report_stem}_{cache_key}.xml.htm",
   ]
   for name in expected_names:
      candidate = collected_dir / name
      if candidate.exists():
         return candidate

   return None


def wait_for_artifacts(
   process: subprocess.Popen[str],
   tester_root: Path,
   expected_report_path: Path,
   timeout_seconds: int,
   started_at: float,
) -> dict[str, Path]:
   deadline = time.time() + timeout_seconds
   summary_path: Path | None = None
   daily_path: Path | None = None
   report_path: Path | None = None

   while time.time() < deadline:
      summary_path = locate_recent_file(tester_root, SUMMARY_FILENAME, started_at)
      daily_path = locate_recent_file(tester_root, DAILY_FILENAME, started_at)
      report_path = None
      report_candidates: list[tuple[float, Path]] = []
      if expected_report_path.exists():
         try:
            report_mtime = expected_report_path.stat().st_mtime
            if report_mtime >= started_at:
               report_candidates.append((report_mtime, expected_report_path))
         except FileNotFoundError:
            pass
      alt_report = expected_report_path.with_suffix(expected_report_path.suffix + ".htm")
      if alt_report.exists():
         try:
            alt_report_mtime = alt_report.stat().st_mtime
            if alt_report_mtime >= started_at:
               report_candidates.append((alt_report_mtime, alt_report))
         except FileNotFoundError:
            pass
      if report_candidates:
         report_path = max(report_candidates, key=lambda candidate: candidate[0])[1]

      if summary_path and daily_path and report_path:
         return {
            "summary": summary_path,
            "daily": daily_path,
            "report": report_path,
         }

      if process.poll() is not None:
         time.sleep(2)

      time.sleep(1)

   raise TimeoutError(
      f"Timed out waiting for MT5 artifacts after {timeout_seconds}s. "
      f"summary={summary_path}, daily={daily_path}, report={report_path}"
   )


def copy_if_present(source: Path | None, destination: Path) -> str | None:
   if source is None or not source.exists():
      return None
   ensure_directory(destination.parent)
   shutil.copy2(source, destination)
   return str(destination)


def copy_files_preserving_relative(
   sources: list[Path],
   root: Path,
   destination_root: Path,
) -> list[str]:
   copied: list[str] = []
   for source in sources:
      if not source.exists():
         continue
      try:
         relative = source.relative_to(root)
      except ValueError:
         relative = Path(source.name)
      destination = destination_root / relative
      ensure_directory(destination.parent)
      shutil.copy2(source, destination)
      copied.append(str(destination))
   return copied


def build_runner_paths(
   mt5_install_path: str | None = None,
   terminal_data_path: str | None = None,
   output_root: str | Path = DEFAULT_OUTPUT_ROOT,
) -> RunnerPaths:
   repo = repo_root()
   terminal_data = resolve_terminal_data_path(terminal_data_path)
   terminal_exe = resolve_terminal_exe(mt5_install_path, terminal_data)
   metaeditor_exe = resolve_metaeditor_exe(mt5_install_path, terminal_data)
   tester_root = resolve_tester_root(terminal_data)
   output_root_path = Path(output_root)
   resolved_output_root = (
      (repo / output_root_path).resolve()
      if not output_root_path.is_absolute()
      else output_root_path.resolve()
   )
   tester_profiles = terminal_data / "MQL5" / "Profiles" / "Tester"
   config_dir = terminal_data / "config"
   ensure_directory(resolved_output_root)
   ensure_directory(tester_profiles)
   return RunnerPaths(
      repo_root=repo,
      terminal_exe=terminal_exe,
      metaeditor_exe=metaeditor_exe,
      terminal_data_path=terminal_data,
      tester_root=tester_root,
      tester_profiles_dir=tester_profiles,
      config_dir=config_dir,
      output_root=resolved_output_root,
   )


def create_runner_paths(args: argparse.Namespace) -> RunnerPaths:
   return build_runner_paths(
      mt5_install_path=args.mt5_install_path,
      terminal_data_path=args.terminal_data_path,
      output_root=args.output_root,
   )


def build_spec(run_data: dict[str, Any], defaults: dict[str, Any] | None = None) -> BacktestSpec:
   merged = dict(defaults or {})
   merged.update(run_data)
   merged_set_overrides = dict((defaults or {}).get("set_overrides") or {})
   merged_set_overrides.update(run_data.get("set_overrides") or {})

   name = merged.get("name") or f"{merged.get('symbol', 'run')}_{merged.get('from_date', '')}_{merged.get('to_date', '')}"
   template_ini = Path(merged.get("template_ini", DEFAULT_TEMPLATE_INI))
   base_set = Path(merged.get("base_set", DEFAULT_BASE_SET))
   report_stem = merged.get("report_stem") or safe_name(name)
   set_overrides = merged_set_overrides
   staged_files = parse_staged_files(merged.get("staged_files"))

   return BacktestSpec(
      name=name,
      expert=merged.get("expert", DEFAULT_EXPERT),
      symbol=merged.get("symbol", "EURUSD"),
      period=merged.get("period", "M1"),
      from_date=merged.get("from_date", "2024.01.02"),
      to_date=merged.get("to_date", "2024.01.05"),
      deposit=int(merged.get("deposit", 10000)),
      currency=merged.get("currency", "USD"),
      leverage=int(merged.get("leverage", 50)),
      model=int(merged.get("model", 4)),
      execution_mode=int(merged.get("execution_mode", 0)),
      optimization=int(merged.get("optimization", 0)),
      optimization_criterion=int(merged.get("optimization_criterion", 1)),
      forward_mode=int(merged.get("forward_mode", 0)),
      use_local=int(merged.get("use_local", 1)),
      use_remote=int(merged.get("use_remote", 0)),
      use_cloud=int(merged.get("use_cloud", 0)),
      visual=int(merged.get("visual", 0)),
      shutdown_terminal=int(merged.get("shutdown_terminal", 1)),
      replace_report=int(merged.get("replace_report", 1)),
      template_ini=template_ini,
      base_set=base_set,
      scenario=merged.get("scenario", DEFAULT_SCENARIO),
      rules_profile=merged.get("rules_profile", DEFAULT_RULES_PROFILE),
      set_overrides=set_overrides,
      staged_files=staged_files,
      report_stem=report_stem,
      timeout_seconds=int(merged.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS)),
   )


def resolve_repo_path(repo: Path, path: Path) -> Path:
   return path if path.is_absolute() else (repo / path).resolve()


def parse_compile_errors(compile_log: Path) -> int:
   if not compile_log.exists():
      return -1
   contents = None
   for encoding in ("utf-8", "utf-8-sig", "utf-16", "utf-16-le", "utf-16-be", "cp1252"):
      try:
         contents = compile_log.read_text(encoding=encoding)
         break
      except UnicodeDecodeError:
         continue
   if contents is None:
      contents = compile_log.read_text(encoding="utf-8", errors="ignore")

   matches = re.findall(r"Result:\s*(\d+)\s+errors?", contents, flags=re.IGNORECASE)
   if matches:
      return int(matches[-1])
   return -1


def compile_ea(paths: RunnerPaths) -> Path:
   compile_log_relative = Path("MQL5") / "Experts" / "FundingPips" / "compile_rpea.log"
   compile_log_absolute = paths.terminal_data_path / compile_log_relative
   command = [
      str(paths.metaeditor_exe),
      "/compile:MQL5\\Experts\\FundingPips\\RPEA.mq5",
      f"/log:{compile_log_relative.as_posix().replace('/', '\\')}",
   ]
   subprocess.run(command, cwd=str(paths.terminal_data_path), check=False)
   errors = parse_compile_errors(compile_log_absolute)
   if errors != 0:
      raise RuntimeError(
         f"EA compile failed before runner launch. errors={errors}, log={compile_log_absolute}"
      )
   return compile_log_absolute


def run_single_backtest(
   spec: BacktestSpec,
   paths: RunnerPaths,
   *,
   dry_run: bool,
   sync_before_run: bool,
   compile_before_run: bool,
   force: bool,
   stop_existing: bool,
) -> dict[str, Any]:
   base_set_path = resolve_repo_path(paths.repo_root, spec.base_set)
   base_set_text = load_text(base_set_path)
   terminal_info = terminal_fingerprint(paths.terminal_exe)
   expert_dependency_hash = compute_ea_dependency_hash(paths.repo_root)
   staged_files_fingerprint = fingerprint_staged_files(spec.staged_files, paths.repo_root)
   cache_key = compute_cache_key(
      spec,
      base_set_text,
      terminal_info,
      expert_dependency_hash,
      staged_files_fingerprint=staged_files_fingerprint,
   )

   run_name = compact_slug(spec.name, max_length=MAX_RUN_SLUG_LENGTH)
   report_stem = compact_slug(spec.report_stem, max_length=MAX_REPORT_STEM_LENGTH)
   run_dir = paths.output_root / f"{run_name}__{cache_key}"
   inputs_dir = run_dir / "inputs"
   collected_dir = run_dir / "collected"
   ensure_directory(inputs_dir)
   ensure_directory(collected_dir)

   manifest_path = run_dir / "run_manifest.json"
   cached_summary = collected_dir / SUMMARY_FILENAME
   cached_daily = collected_dir / DAILY_FILENAME
   cached_report = resolve_cached_report_path(manifest_path, collected_dir, report_stem, cache_key)
   cached_manifest = load_json_text(manifest_path) if manifest_path.exists() else None
   if (
      manifest_path.exists()
      and cached_summary.exists()
      and cached_daily.exists()
      and cached_report is not None
      and not force
   ):
      return {
         "status": "cache_hit",
         "cache_key": cache_key,
         "run_dir": str(run_dir),
         "manifest_path": str(manifest_path),
         "summary_path": str(cached_summary),
         "daily_path": str(cached_daily),
         "report_path": str(cached_report),
         "decision_logs": (cached_manifest or {}).get("collected_decision_logs", []),
         "event_logs": (cached_manifest or {}).get("collected_event_logs", []),
         "staged_files": (cached_manifest or {}).get("staged_files", []),
      }

   if sync_before_run:
      sync_repo(paths.repo_root)

   staged_files = []
   if spec.staged_files and not dry_run:
      staged_files = stage_runtime_files(
         spec.staged_files,
         repo=paths.repo_root,
         terminal_data_path=paths.terminal_data_path,
         tester_root=paths.tester_root,
      )

   compile_log_path = None
   if compile_before_run and not dry_run:
      compile_log_path = compile_ea(paths)

   if stop_existing:
      stop_existing_mt5()
   else:
      assert_no_running_mt5()

   generated_set_path = inputs_dir / f"{run_name}.set"
   write_single_run_set(base_set_text, spec.set_overrides, generated_set_path)

   profile_set_name = f"{run_name}_{cache_key}.set"
   profile_set_path = paths.tester_profiles_dir / profile_set_name
   shutil.copy2(generated_set_path, profile_set_path)

   report_relative_path = rf"Tester\reports\{report_stem}_{cache_key}.xml"
   expected_report_path = paths.terminal_data_path / Path(report_relative_path)
   ensure_directory(expected_report_path.parent)

   generated_ini_path = inputs_dir / f"{run_name}.ini"
   common_ini_path = paths.config_dir / "common.ini"
   common_ini_text = None
   generated_ini_encoding = "ascii"
   if common_ini_path.exists():
      common_ini_text, generated_ini_encoding = load_ini_text_with_encoding(common_ini_path)
   generated_ini_path.write_text(
      prepend_common_section(
         build_tester_ini(spec, profile_set_name, report_relative_path),
         common_ini_text,
      ),
      encoding=generated_ini_encoding,
   )

   manifest: dict[str, Any] = {
      "created_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
      "cache_key": cache_key,
      "status": "prepared" if dry_run else "running",
      "run_dir": str(run_dir),
      "generated_ini": str(generated_ini_path),
      "generated_set": str(generated_set_path),
      "profile_set_path": str(profile_set_path),
      "report_slug": report_stem,
      "run_slug": run_name,
      "report_relative_path": report_relative_path,
      "terminal_exe": str(paths.terminal_exe),
      "metaeditor_exe": str(paths.metaeditor_exe),
      "terminal_data_path": str(paths.terminal_data_path),
      "tester_root": str(paths.tester_root),
      "terminal_fingerprint": terminal_info,
      "expert_dependency_hash": expert_dependency_hash,
      "staged_files": staged_files_fingerprint,
      "staged_files_runtime": staged_files,
      "compile_log_path": str(compile_log_path) if compile_log_path else None,
      "spec": spec_to_manifest_dict(spec),
   }
   manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="ascii")

   if dry_run:
      return {
         "status": "dry_run",
         "cache_key": cache_key,
         "run_dir": str(run_dir),
         "manifest_path": str(manifest_path),
      }

   started_at = time.time()
   process = subprocess.Popen([str(paths.terminal_exe), f"/config:{generated_ini_path}"])
   try:
      artifacts = wait_for_artifacts(
         process=process,
         tester_root=paths.tester_root,
         expected_report_path=expected_report_path,
         timeout_seconds=spec.timeout_seconds,
         started_at=started_at,
      )
   finally:
      if process.poll() is None:
         process.terminate()
         try:
            process.wait(timeout=10)
         except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)

   summary_copy = copy_if_present(artifacts.get("summary"), collected_dir / SUMMARY_FILENAME)
   daily_copy = copy_if_present(artifacts.get("daily"), collected_dir / DAILY_FILENAME)
   report_source = artifacts.get("report")
   report_destination = collected_dir / (report_source.name if report_source else Path(report_relative_path).name)
   report_copy = copy_if_present(report_source, report_destination)
   logs_root = collected_dir / "logs"
   decision_sources = locate_recent_log_files(
      paths.tester_root,
      "decisions_",
      not_before=started_at,
   )
   event_sources = locate_recent_log_files(
      paths.tester_root,
      "events_",
      not_before=started_at,
   )
   decision_copies = copy_files_preserving_relative(decision_sources, paths.tester_root, logs_root)
   event_copies = copy_files_preserving_relative(event_sources, paths.tester_root, logs_root)

   manifest.update(
      {
         "status": "completed",
         "completed_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
         "collected_summary": summary_copy,
         "collected_daily": daily_copy,
         "collected_report": report_copy,
         "collected_decision_logs": decision_copies,
         "collected_event_logs": event_copies,
         "source_summary": str(artifacts.get("summary")) if artifacts.get("summary") else None,
         "source_daily": str(artifacts.get("daily")) if artifacts.get("daily") else None,
         "source_report": str(report_source) if report_source else None,
         "source_decision_logs": [str(path) for path in decision_sources],
         "source_event_logs": [str(path) for path in event_sources],
      }
   )
   manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="ascii")

   return {
      "status": "completed",
      "cache_key": cache_key,
      "run_dir": str(run_dir),
      "manifest_path": str(manifest_path),
      "summary_path": summary_copy,
      "daily_path": daily_copy,
      "report_path": report_copy,
      "decision_logs": decision_copies,
      "event_logs": event_copies,
   }


def run_batch(
   batch_path: Path,
   paths: RunnerPaths,
   *,
   dry_run: bool,
   sync_before_run: bool,
   compile_before_run: bool,
   force: bool,
   stop_existing: bool,
) -> dict[str, Any]:
   batch_data = json.loads(batch_path.read_text(encoding="ascii"))
   defaults = batch_data.get("defaults") or {}
   runs = batch_data.get("runs") or []
   if not runs:
      raise ValueError(f"Batch file contains no runs: {batch_path}")

   results = []
   pending_sync = sync_before_run
   for index, run_data in enumerate(runs, start=1):
      spec = build_spec(run_data, defaults)
      result = run_single_backtest(
         spec,
         paths,
         dry_run=dry_run,
         sync_before_run=pending_sync,
         compile_before_run=compile_before_run,
         force=force,
         stop_existing=stop_existing,
      )
      if pending_sync and result.get("status") != "cache_hit":
         pending_sync = False
      results.append(result)
   return {
      "batch_path": str(batch_path),
      "results": results,
   }


def add_common_args(parser: argparse.ArgumentParser) -> None:
   parser.add_argument("--mt5-install-path", default=None)
   parser.add_argument("--terminal-data-path", default=None)
   parser.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT))
   parser.add_argument("--dry-run", action="store_true")
   parser.add_argument("--skip-sync", action="store_true")
   parser.add_argument("--skip-compile", action="store_true")
   parser.add_argument("--force", action="store_true")
   parser.add_argument("--stop-existing", action="store_true")


def build_parser() -> argparse.ArgumentParser:
   parser = argparse.ArgumentParser(description="FundingPips MT5 single-run automation")
   subparsers = parser.add_subparsers(dest="command", required=True)

   run_parser = subparsers.add_parser("run", help="Run a single MT5 backtest")
   add_common_args(run_parser)
   run_parser.add_argument("--name", required=True)
   run_parser.add_argument("--expert", default=DEFAULT_EXPERT)
   run_parser.add_argument("--symbol", default="EURUSD")
   run_parser.add_argument("--period", default="M1")
   run_parser.add_argument("--from-date", default="2024.01.02")
   run_parser.add_argument("--to-date", default="2024.01.05")
   run_parser.add_argument("--deposit", type=int, default=10000)
   run_parser.add_argument("--currency", default="USD")
   run_parser.add_argument("--leverage", type=int, default=50)
   run_parser.add_argument("--model", type=int, default=4)
   run_parser.add_argument("--execution-mode", type=int, default=0)
   run_parser.add_argument("--optimization", type=int, default=0)
   run_parser.add_argument("--optimization-criterion", type=int, default=1)
   run_parser.add_argument("--forward-mode", type=int, default=0)
   run_parser.add_argument("--template-ini", default=str(DEFAULT_TEMPLATE_INI))
   run_parser.add_argument("--base-set", default=str(DEFAULT_BASE_SET))
   run_parser.add_argument("--scenario", default=DEFAULT_SCENARIO)
   run_parser.add_argument("--rules-profile", default=DEFAULT_RULES_PROFILE)
   run_parser.add_argument("--report-stem", default=None)
   run_parser.add_argument("--timeout-seconds", type=int, default=DEFAULT_TIMEOUT_SECONDS)
   run_parser.add_argument("--param", action="append", default=[], help="Override in KEY=VALUE form")

   batch_parser = subparsers.add_parser("batch", help="Run a JSON batch of backtests")
   add_common_args(batch_parser)
   batch_parser.add_argument("--batch-file", required=True)

   return parser


def main(argv: list[str] | None = None) -> int:
   parser = build_parser()
   args = parser.parse_args(argv)
   paths = create_runner_paths(args)

   if args.command == "run":
      run_data = {
         "name": args.name,
         "expert": args.expert,
         "symbol": args.symbol,
         "period": args.period,
         "from_date": args.from_date,
         "to_date": args.to_date,
         "deposit": args.deposit,
         "currency": args.currency,
         "leverage": args.leverage,
         "model": args.model,
         "execution_mode": args.execution_mode,
         "optimization": args.optimization,
         "optimization_criterion": args.optimization_criterion,
         "forward_mode": args.forward_mode,
         "template_ini": args.template_ini,
         "base_set": args.base_set,
         "scenario": args.scenario,
         "rules_profile": args.rules_profile,
         "report_stem": args.report_stem or safe_name(args.name),
         "timeout_seconds": args.timeout_seconds,
         "set_overrides": parse_key_value_pairs(args.param),
      }
      spec = build_spec(run_data)
      result = run_single_backtest(
         spec,
         paths,
         dry_run=args.dry_run,
         sync_before_run=not args.skip_sync,
         compile_before_run=not args.skip_compile,
         force=args.force,
         stop_existing=args.stop_existing,
      )
      print(json.dumps(result, indent=2, sort_keys=True))
      return 0

   if args.command == "batch":
      batch_path = resolve_repo_path(paths.repo_root, Path(args.batch_file))
      result = run_batch(
         batch_path,
         paths,
         dry_run=args.dry_run,
         sync_before_run=not args.skip_sync,
         compile_before_run=not args.skip_compile,
         force=args.force,
         stop_existing=args.stop_existing,
      )
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
