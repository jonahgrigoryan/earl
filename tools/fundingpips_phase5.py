#!/usr/bin/env python3
"""FundingPips Phase 5 architecture -> threshold -> QL harness."""

from __future__ import annotations

import argparse
import collections
import dataclasses
import hashlib
import itertools
import json
import sys
from pathlib import Path
from typing import Any

try:
   from tools import fundingpips_hpo as hpo
   from tools import fundingpips_mt5_runner as mt5_runner
   from tools import fundingpips_phase4 as phase4
except ModuleNotFoundError:  # pragma: no cover - script execution fallback
   sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
   from tools import fundingpips_hpo as hpo
   from tools import fundingpips_mt5_runner as mt5_runner
   from tools import fundingpips_phase4 as phase4


DEFAULT_PHASE5_ROOT = Path(".tmp") / "fundingpips_phase5"


@dataclasses.dataclass(frozen=True)
class Phase5BaselineSpec:
   phase4_candidate_id: str
   behavior_controls: dict[str, Any]
   rl_mode_default: str
   bandit_state_mode_default: str
   qtable_path: Path
   qtable_artifact_id: str | None
   thresholds_path: Path
   thresholds_artifact_id: str | None
   bandit_snapshot_path: Path
   bandit_snapshot_artifact_id: str | None
   study_seed: int
   notes: str


@dataclasses.dataclass(frozen=True)
class Phase5Stage2Spec:
   search_space: tuple[hpo.SearchDimension, ...]


@dataclasses.dataclass(frozen=True)
class Phase5QLArtifactCandidate:
   id: str
   qtable_path: Path | None
   qtable_artifact_id: str | None
   thresholds_path: Path | None
   thresholds_artifact_id: str | None
   artifact_manifest_path: Path | None
   training_params: dict[str, Any]
   notes: str


@dataclasses.dataclass(frozen=True)
class Phase5Spec:
   name: str
   phase4_spec_path: Path
   phase4_manifest_path: Path | None
   baseline: Phase5BaselineSpec
   stage2: Phase5Stage2Spec
   stage3_candidates: tuple[Phase5QLArtifactCandidate, ...]
   source_path: Path


@dataclasses.dataclass(frozen=True)
class Phase5Paths:
   phase5_dir: Path
   manifest_path: Path
   cycles_path: Path
   baseline_dir: Path
   baseline_bundle_path: Path
   baseline_artifact_manifest_path: Path
   actual_runs_dir: Path
   resolved_sets_dir: Path
   run_rows_path: Path
   summary_path: Path


@dataclasses.dataclass(frozen=True)
class Phase5TrialPlan:
   stage: str
   stage_token: str
   trial_id: str
   arch_token: str
   threshold_token: str | None
   ql_candidate_token: str | None
   set_overrides: dict[str, Any]
   staged_files: tuple[mt5_runner.StagedFileSpec, ...]
   ql_mode: str
   bandit_state_mode: str
   bandit_shadow_mode: bool
   bandit_ready: bool
   bandit_snapshot_id: str | None
   bandit_snapshot_path: str | None
   bandit_snapshot_sha256: str | None
   bandit_snapshot_runtime_path: str | None
   qtable_artifact_id: str | None
   qtable_path: str | None
   qtable_sha256: str | None
   qtable_runtime_path: str | None
   thresholds_artifact_id: str | None
   thresholds_path: str | None
   thresholds_sha256: str | None
   thresholds_runtime_path: str | None
   artifact_manifest_path: str | None
   training_params: dict[str, Any]
   failure_reason: str | None = None
   blocked: bool = False


def repo_root() -> Path:
   return mt5_runner.repo_root()


def resolve_repo_path(path: Path) -> Path:
   return mt5_runner.resolve_repo_path(repo_root(), path)


def sha256_text(text: str) -> str:
   return hashlib.sha256(text.encode("utf-8")).hexdigest()


def artifact_id(prefix: str, sha256: str, explicit_id: str | None = None) -> str:
   if explicit_id:
      return explicit_id
   return f"{mt5_runner.safe_name(prefix)}_{sha256[:12]}"


def parse_bool_value(value: Any, *, field_name: str) -> bool:
   if isinstance(value, (int, float)) and not isinstance(value, bool):
      if float(value) == 1.0:
         return True
      if float(value) == 0.0:
         return False
   return hpo.parse_bool(value, field_name)


def ranking_enable_mr(ranking: dict[str, Any]) -> bool:
   overrides = ranking.get("effective_set_overrides") or {}
   try:
      return parse_bool_value(overrides.get("EnableMR", 0), field_name="EnableMR")
   except ValueError:
      return False


def parse_bandit_snapshot(path: Path) -> dict[str, Any]:
   data = {
      "schema_version": 0,
      "total_updates": 0,
      "bwisc_pulls": 0,
      "mr_pulls": 0,
      "ready": False,
   }
   if not path.exists():
      return data

   for raw_line in hpo.read_text_with_encodings(path).splitlines():
      line = raw_line.strip()
      if not line or line.startswith("#") or "=" not in line:
         continue
      key, value = line.split("=", 1)
      key = key.strip()
      value = value.strip()
      if key in ("schema_version", "total_updates", "bwisc_pulls", "mr_pulls"):
         data[key] = int(value)
   data["ready"] = (
      data["schema_version"] == 1
      and data["total_updates"] >= 6
      and data["bwisc_pulls"] > 0
      and data["mr_pulls"] > 0
   )
   return data


def build_phase5_paths(phase5_name: str, repo: Path | None = None) -> Phase5Paths:
   root = repo or repo_root()
   phase5_dir = (root / DEFAULT_PHASE5_ROOT / phase5_name).resolve()
   baseline_dir = phase5_dir / "baseline"
   return Phase5Paths(
      phase5_dir=phase5_dir,
      manifest_path=phase5_dir / "phase5_manifest.json",
      cycles_path=phase5_dir / "walk_forward_cycles.json",
      baseline_dir=baseline_dir,
      baseline_bundle_path=baseline_dir / "phase5_baseline_bundle.json",
      baseline_artifact_manifest_path=baseline_dir / "baseline_rl_artifact_manifest.json",
      actual_runs_dir=phase5_dir / "actual_runs",
      resolved_sets_dir=phase5_dir / "resolved_sets",
      run_rows_path=phase5_dir / "phase5_run_rows.jsonl",
      summary_path=phase5_dir / "phase5_summary.json",
   )


def load_phase5_spec(path: Path) -> Phase5Spec:
   raw = hpo.load_json_file(path)
   name = str(raw.get("name", "")).strip()
   if not name:
      raise ValueError(f"Phase 5 spec name is required: {path}")

   phase4_spec_path = resolve_repo_path(Path(str(raw.get("phase4_spec_path", "")).strip()))
   if not phase4_spec_path.exists():
      raise FileNotFoundError(f"Phase 4 spec not found: {phase4_spec_path}")

   raw_phase4_manifest = str(raw.get("phase4_manifest_path", "")).strip()
   phase4_manifest_path = resolve_repo_path(Path(raw_phase4_manifest)) if raw_phase4_manifest else None

   baseline_raw = raw.get("baseline")
   if not isinstance(baseline_raw, dict):
      raise ValueError("baseline must be an object")
   behavior_controls = baseline_raw.get("behavior_controls") or {}
   if not isinstance(behavior_controls, dict):
      raise ValueError("baseline.behavior_controls must be an object")

   baseline = Phase5BaselineSpec(
      phase4_candidate_id=str(baseline_raw.get("phase4_candidate_id", "")).strip(),
      behavior_controls=dict(behavior_controls),
      rl_mode_default=str(baseline_raw.get("rl_mode_default", "enabled")).strip() or "enabled",
      bandit_state_mode_default=str(baseline_raw.get("bandit_state_mode_default", "live")).strip() or "live",
      qtable_path=resolve_repo_path(Path(str(baseline_raw.get("qtable_path", "")).strip())),
      qtable_artifact_id=str(baseline_raw.get("qtable_artifact_id", "")).strip() or None,
      thresholds_path=resolve_repo_path(Path(str(baseline_raw.get("thresholds_path", "")).strip())),
      thresholds_artifact_id=str(baseline_raw.get("thresholds_artifact_id", "")).strip() or None,
      bandit_snapshot_path=resolve_repo_path(Path(str(baseline_raw.get("bandit_snapshot_path", "")).strip())),
      bandit_snapshot_artifact_id=str(baseline_raw.get("bandit_snapshot_artifact_id", "")).strip() or None,
      study_seed=hpo.parse_int(baseline_raw.get("study_seed", 0), "baseline.study_seed"),
      notes=str(baseline_raw.get("notes", "")).strip(),
   )
   if not baseline.phase4_candidate_id:
      raise ValueError("baseline.phase4_candidate_id is required")

   stage2_raw = raw.get("stage2") or {}
   if not isinstance(stage2_raw, dict):
      raise ValueError("stage2 must be an object when provided")
   stage2 = Phase5Stage2Spec(
      search_space=hpo.parse_search_space(stage2_raw.get("search_space")),
   )

   raw_stage3_candidates = (raw.get("stage3") or {}).get("artifact_candidates") or []
   if not isinstance(raw_stage3_candidates, list):
      raise ValueError("stage3.artifact_candidates must be a list when provided")
   stage3_candidates: list[Phase5QLArtifactCandidate] = []
   for index, raw_candidate in enumerate(raw_stage3_candidates):
      if not isinstance(raw_candidate, dict):
         raise ValueError(f"stage3.artifact_candidates[{index}] must be an object")
      candidate_id = str(raw_candidate.get("id", "")).strip()
      if not candidate_id:
         raise ValueError(f"stage3.artifact_candidates[{index}].id is required")
      qtable_path_text = str(raw_candidate.get("qtable_path", "")).strip()
      thresholds_path_text = str(raw_candidate.get("thresholds_path", "")).strip()
      manifest_path_text = str(raw_candidate.get("artifact_manifest_path", "")).strip()
      training_params = raw_candidate.get("training_params") or {}
      if not isinstance(training_params, dict):
         raise ValueError(f"stage3.artifact_candidates[{index}].training_params must be an object")
      stage3_candidates.append(
         Phase5QLArtifactCandidate(
            id=candidate_id,
            qtable_path=resolve_repo_path(Path(qtable_path_text)) if qtable_path_text else None,
            qtable_artifact_id=str(raw_candidate.get("qtable_artifact_id", "")).strip() or None,
            thresholds_path=resolve_repo_path(Path(thresholds_path_text)) if thresholds_path_text else None,
            thresholds_artifact_id=str(raw_candidate.get("thresholds_artifact_id", "")).strip() or None,
            artifact_manifest_path=resolve_repo_path(Path(manifest_path_text)) if manifest_path_text else None,
            training_params=dict(training_params),
            notes=str(raw_candidate.get("notes", "")).strip(),
         )
      )

   return Phase5Spec(
      name=name,
      phase4_spec_path=phase4_spec_path,
      phase4_manifest_path=phase4_manifest_path,
      baseline=baseline,
      stage2=stage2,
      stage3_candidates=tuple(stage3_candidates),
      source_path=path.resolve(),
   )


def phase4_candidate_index(spec: phase4.Phase4Spec) -> dict[str, phase4.Phase4CandidateSpec]:
   return {
      candidate.id: candidate
      for candidate in (spec.primary_candidates + spec.neighbor_candidates)
   }


def write_json(path: Path, payload: dict[str, Any]) -> None:
   hpo.write_json_file(path, payload)


def load_baseline_bundle(paths: Phase5Paths) -> dict[str, Any]:
   if not paths.baseline_bundle_path.exists():
      raise FileNotFoundError(f"Phase 5 baseline bundle not found: {paths.baseline_bundle_path}")
   return hpo.load_json_file(paths.baseline_bundle_path)


def write_phase5_cycles(paths: Phase5Paths, cycles: tuple[phase4.WalkForwardCycle, ...]) -> None:
   write_json(
      paths.cycles_path,
      {
         "generated_at_utc": hpo.utc_now_iso(),
         "cycle_count": len(cycles),
         "cycles": phase4.cycles_to_payload(cycles),
      },
   )


def build_stage1_trial_specs(bundle: dict[str, Any]) -> list[dict[str, Any]]:
   return [
      {
         "stage_token": "arch_bwisc_only",
         "arch_token": "arch_bwisc_only",
         "set_overrides": {
            "EnableMR": 0,
            "UseBanditMetaPolicy": 0,
            "BanditShadowMode": 0,
            "QLMode": "disabled",
            "BanditStateMode": "disabled",
         },
      },
      {
         "stage_token": "arch_mr_deterministic",
         "arch_token": "arch_mr_deterministic",
         "set_overrides": {
            "EnableMR": 1,
            "UseBanditMetaPolicy": 0,
            "BanditShadowMode": 0,
            "QLMode": bundle["rl_mode_default"],
            "BanditStateMode": "disabled",
         },
      },
      {
         "stage_token": "arch_mr_bandit_frozen",
         "arch_token": "arch_mr_bandit_frozen",
         "set_overrides": {
            "EnableMR": 1,
            "UseBanditMetaPolicy": 1,
            "BanditShadowMode": 0,
            "QLMode": bundle["rl_mode_default"],
            "BanditStateMode": "frozen",
         },
      },
   ]


def write_phase5_manifest(
   paths: Phase5Paths,
   spec: Phase5Spec,
   phase4_spec: phase4.Phase4Spec,
   rules_profile: hpo.RulesProfile,
   cycles: tuple[phase4.WalkForwardCycle, ...],
   baseline_bundle: dict[str, Any],
) -> None:
   write_json(
      paths.manifest_path,
      {
         "generated_at_utc": hpo.utc_now_iso(),
         "phase5_name": spec.name,
         "phase5_spec_path": str(spec.source_path),
         "phase4_spec_path": str(phase4_spec.source_path),
         "phase4_manifest_path": str(spec.phase4_manifest_path) if spec.phase4_manifest_path else None,
         "rules_profile_id": rules_profile.id,
         "rules_profile_path": str(hpo.rules_profile_path(rules_profile.id)),
         "phase5_dir": str(paths.phase5_dir),
         "cycles_path": str(paths.cycles_path),
         "baseline_bundle_path": str(paths.baseline_bundle_path),
         "baseline_bundle_id": baseline_bundle["baseline_bundle_id"],
         "baseline_artifact_manifest_path": str(paths.baseline_artifact_manifest_path),
         "actual_runs_dir": str(paths.actual_runs_dir),
         "resolved_sets_dir": str(paths.resolved_sets_dir),
         "phase5_run_rows_path": str(paths.run_rows_path),
         "phase5_summary_path": str(paths.summary_path),
         "cycle_count": len(cycles),
         "scenario_ids": [scenario.id for scenario in phase4_spec.scenarios],
         "stage1_arch_tokens": [plan["stage_token"] for plan in build_stage1_trial_specs(baseline_bundle)],
         "stage2_search_space": [dataclasses.asdict(item) for item in spec.stage2.search_space],
         "stage3_artifact_candidate_ids": [candidate.id for candidate in spec.stage3_candidates],
      },
   )


def prepare_baseline_bundle(
   spec: Phase5Spec,
   phase4_spec: phase4.Phase4Spec,
   paths: Phase5Paths,
) -> dict[str, Any]:
   candidate_map = phase4_candidate_index(phase4_spec)
   candidate = candidate_map.get(spec.baseline.phase4_candidate_id)
   if candidate is None:
      raise ValueError(
         f"Baseline candidate {spec.baseline.phase4_candidate_id!r} not found in {phase4_spec.source_path}"
      )

   base_set_path = resolve_repo_path(phase4_spec.base_set)
   if not base_set_path.exists():
      raise FileNotFoundError(f"Phase 5 base set not found: {base_set_path}")
   for artifact_path in (
      spec.baseline.qtable_path,
      spec.baseline.thresholds_path,
      spec.baseline.bandit_snapshot_path,
   ):
      if not artifact_path.exists():
         raise FileNotFoundError(f"Phase 5 baseline artifact missing: {artifact_path}")

   base_set_text = mt5_runner.load_text(base_set_path)
   resolved_overrides = dict(candidate.set_overrides) | dict(spec.baseline.behavior_controls)
   resolved_set_text = hpo.render_set_with_overrides(base_set_text, resolved_overrides)

   hpo.ensure_directory(paths.baseline_dir)
   resolved_set_path = paths.baseline_dir / f"{candidate.id}__phase5_resolved.set"
   resolved_set_path.write_text(resolved_set_text, encoding="ascii")
   resolved_set_sha256 = mt5_runner.sha256_file(resolved_set_path)

   qtable_sha256 = mt5_runner.sha256_file(spec.baseline.qtable_path)
   thresholds_sha256 = mt5_runner.sha256_file(spec.baseline.thresholds_path)
   bandit_snapshot_sha256 = mt5_runner.sha256_file(spec.baseline.bandit_snapshot_path)
   bandit_state = parse_bandit_snapshot(spec.baseline.bandit_snapshot_path)

   stable_identity = {
      "base_set_path": str(base_set_path),
      "resolved_set_sha256": resolved_set_sha256,
      "cluster_overrides": dict(candidate.set_overrides),
      "inherited_set_includes": sorted(spec.baseline.behavior_controls.keys()),
      "rl_mode_default": spec.baseline.rl_mode_default,
      "qtable_sha256": qtable_sha256,
      "thresholds_sha256": thresholds_sha256,
      "bandit_state_mode_default": spec.baseline.bandit_state_mode_default,
      "bandit_snapshot_sha256": bandit_snapshot_sha256,
      "bandit_ready": bool(bandit_state["ready"]),
      "study_seed": spec.baseline.study_seed,
      "notes": spec.baseline.notes,
   }
   baseline_bundle_id = artifact_id("baseline_bundle", sha256_text(json.dumps(stable_identity, sort_keys=True)))

   bundle = {
      "baseline_bundle_id": baseline_bundle_id,
      "base_set_path": str(base_set_path),
      "resolved_set_path": str(resolved_set_path),
      "resolved_set_sha256": resolved_set_sha256,
      "cluster_overrides": dict(candidate.set_overrides),
      "inherited_set_includes": sorted(spec.baseline.behavior_controls.keys()),
      "rl_mode_default": spec.baseline.rl_mode_default,
      "qtable_artifact_id": artifact_id("qtable", qtable_sha256, spec.baseline.qtable_artifact_id),
      "qtable_path": str(spec.baseline.qtable_path),
      "qtable_sha256": qtable_sha256,
      "thresholds_artifact_id": artifact_id("thresholds", thresholds_sha256, spec.baseline.thresholds_artifact_id),
      "thresholds_path": str(spec.baseline.thresholds_path),
      "thresholds_sha256": thresholds_sha256,
      "bandit_state_mode_default": spec.baseline.bandit_state_mode_default,
      "bandit_snapshot_artifact_id": artifact_id(
         "bandit_snapshot",
         bandit_snapshot_sha256,
         spec.baseline.bandit_snapshot_artifact_id,
      ),
      "bandit_snapshot_path": str(spec.baseline.bandit_snapshot_path),
      "bandit_snapshot_sha256": bandit_snapshot_sha256,
      "bandit_ready": bool(bandit_state["ready"]),
      "study_seed": spec.baseline.study_seed,
      "build_timestamp": hpo.utc_now_iso(),
      "notes": spec.baseline.notes,
   }
   write_json(paths.baseline_bundle_path, bundle)

   write_json(
      paths.baseline_artifact_manifest_path,
      {
         "generated_at_utc": hpo.utc_now_iso(),
         "source": "inherited_phase4_baseline",
         "baseline_bundle_id": baseline_bundle_id,
         "qtable_artifact_id": bundle["qtable_artifact_id"],
         "qtable_path": bundle["qtable_path"],
         "qtable_sha256": bundle["qtable_sha256"],
         "thresholds_artifact_id": bundle["thresholds_artifact_id"],
         "thresholds_path": bundle["thresholds_path"],
         "thresholds_sha256": bundle["thresholds_sha256"],
         "params": {
            key: spec.baseline.behavior_controls.get(key)
            for key in (
               "QL_LearningRate",
               "QL_DiscountFactor",
               "QL_EpsilonTrain",
               "QL_TrainingEpisodes",
            )
            if key in spec.baseline.behavior_controls
         },
         "notes": "Inherited Phase 4 RL artifacts pinned for Phase 5 comparisons.",
      },
   )
   return bundle


def prepare_phase5(phase5_spec_path: Path) -> dict[str, Any]:
   spec = load_phase5_spec(phase5_spec_path)
   phase4_spec = phase4.load_phase4_spec(spec.phase4_spec_path)
   rules_profile = hpo.load_rules_profile(hpo.rules_profile_path(phase4_spec.rules_profile))
   cycles = phase4.build_walk_forward_cycles(phase4_spec)
   paths = build_phase5_paths(spec.name)
   hpo.ensure_directory(paths.phase5_dir)
   baseline_bundle = prepare_baseline_bundle(spec, phase4_spec, paths)
   write_phase5_cycles(paths, cycles)
   write_phase5_manifest(paths, spec, phase4_spec, rules_profile, cycles, baseline_bundle)
   if not paths.run_rows_path.exists():
      paths.run_rows_path.write_text("", encoding="utf-8")
   export = export_phase5(paths.phase5_dir)
   return {
      "phase5_name": spec.name,
      "phase5_dir": str(paths.phase5_dir),
      "manifest_path": str(paths.manifest_path),
      "baseline_bundle_path": str(paths.baseline_bundle_path),
      "baseline_bundle_id": baseline_bundle["baseline_bundle_id"],
      "cycles_path": str(paths.cycles_path),
      "cycle_count": len(cycles),
      "exports": export,
   }


def concrete_scenarios(phase4_spec: phase4.Phase4Spec) -> tuple[phase4.Phase4ScenarioSpec, ...]:
   return tuple(scenario for scenario in phase4_spec.scenarios if scenario.source_scenario_id is None)


def search_dimension_values(dimension: hpo.SearchDimension) -> list[Any]:
   if dimension.kind == "categorical":
      return list(dimension.choices)
   if dimension.kind != "float":
      raise ValueError(f"Unsupported Phase 5 search dimension kind: {dimension.kind}")

   assert dimension.low is not None and dimension.high is not None and dimension.step is not None
   scale = 0
   step_text = f"{dimension.step:.10f}".rstrip("0")
   if "." in step_text:
      scale = len(step_text.split(".", 1)[1])
   values: list[float] = []
   current = dimension.low
   while current <= dimension.high + (dimension.step / 2.0):
      values.append(round(current, scale))
      current += dimension.step
   return values


def build_threshold_trial_specs(
   search_space: tuple[hpo.SearchDimension, ...],
   *,
   arch_token: str,
) -> list[dict[str, Any]]:
   value_sets = [search_dimension_values(dimension) for dimension in search_space]
   trial_specs: list[dict[str, Any]] = []
   for index, combo in enumerate(itertools.product(*value_sets), start=1):
      overrides = {
         dimension.name: value
         for dimension, value in zip(search_space, combo)
      }
      if "MR_TimeStopMin" in overrides and "MR_TimeStopMax" in overrides:
         if int(overrides["MR_TimeStopMax"]) < int(overrides["MR_TimeStopMin"]):
            continue
      trial_specs.append(
         {
            "stage_token": f"threshold_{index:03d}",
            "arch_token": arch_token,
            "threshold_token": f"threshold_{index:03d}",
            "set_overrides": overrides,
         }
      )
   return trial_specs


def baseline_stage3_candidate(bundle: dict[str, Any], paths: Phase5Paths) -> Phase5QLArtifactCandidate:
   return Phase5QLArtifactCandidate(
      id="baseline_artifacts",
      qtable_path=Path(bundle["qtable_path"]),
      qtable_artifact_id=bundle["qtable_artifact_id"],
      thresholds_path=Path(bundle["thresholds_path"]),
      thresholds_artifact_id=bundle["thresholds_artifact_id"],
      artifact_manifest_path=paths.baseline_artifact_manifest_path,
      training_params={},
      notes="Inherited Phase 4 baseline artifacts",
   )


def materialize_artifact(
   *,
   source_path: Path | None,
   explicit_id: str | None,
   phase5_name: str,
   stage: str,
   stage_token: str,
   prefix: str,
) -> dict[str, Any] | None:
   if source_path is None:
      return None
   if not source_path.exists():
      raise FileNotFoundError(f"Phase 5 artifact source not found: {source_path}")
   sha256 = mt5_runner.sha256_file(source_path)
   file_id = artifact_id(prefix, sha256, explicit_id)
   study_token = hashlib.sha256(phase5_name.encode("utf-8")).hexdigest()[:8]
   suffix = source_path.suffix or ""
   runtime_relative_path = f"RPEA/p5/{study_token}/{file_id}{suffix}"
   return {
      "artifact_id": file_id,
      "path": str(source_path),
      "sha256": sha256,
      "runtime_relative_path": runtime_relative_path,
      "staged_file": mt5_runner.StagedFileSpec(
         source_path=source_path,
         terminal_relative_path=runtime_relative_path,
         artifact_id=file_id,
         sha256=sha256,
      ),
   }


def build_trial_plan(
   *,
   phase5_name: str,
   stage: str,
   stage_token: str,
   arch_token: str,
   threshold_token: str | None,
   ql_candidate_token: str | None,
   base_overrides: dict[str, Any],
   plan_overrides: dict[str, Any],
   bundle: dict[str, Any],
   artifact_candidate: Phase5QLArtifactCandidate | None,
   artifact_manifest_path: Path | None,
   training_params: dict[str, Any],
) -> Phase5TrialPlan:
   effective_overrides = dict(base_overrides)
   effective_overrides.update(plan_overrides)

   ql_mode = str(effective_overrides.get("QLMode", bundle["rl_mode_default"])).strip().lower() or "enabled"
   bandit_state_mode = str(
      effective_overrides.get("BanditStateMode", bundle["bandit_state_mode_default"])
   ).strip().lower() or "live"
   use_bandit = parse_bool_value(effective_overrides.get("UseBanditMetaPolicy", 0), field_name="UseBanditMetaPolicy")
   enable_mr = parse_bool_value(effective_overrides.get("EnableMR", 1), field_name="EnableMR")
   bandit_shadow_mode = parse_bool_value(
      effective_overrides.get("BanditShadowMode", 0),
      field_name="BanditShadowMode",
   )

   qtable_source = materialize_artifact(
      source_path=(artifact_candidate.qtable_path if artifact_candidate else Path(bundle["qtable_path"])),
      explicit_id=(artifact_candidate.qtable_artifact_id if artifact_candidate else bundle["qtable_artifact_id"]),
      phase5_name=phase5_name,
      stage=stage,
      stage_token=stage_token,
      prefix="qtable",
   )
   thresholds_source = materialize_artifact(
      source_path=(
         artifact_candidate.thresholds_path if artifact_candidate else Path(bundle["thresholds_path"])
      ),
      explicit_id=(
         artifact_candidate.thresholds_artifact_id if artifact_candidate else bundle["thresholds_artifact_id"]
      ),
      phase5_name=phase5_name,
      stage=stage,
      stage_token=stage_token,
      prefix="thresholds",
   )
   bandit_source = materialize_artifact(
      source_path=Path(bundle["bandit_snapshot_path"]),
      explicit_id=bundle["bandit_snapshot_artifact_id"],
      phase5_name=phase5_name,
      stage=stage,
      stage_token=stage_token,
      prefix="bandit_snapshot",
   )

   staged_files = tuple(
      item["staged_file"]
      for item in (qtable_source, thresholds_source, bandit_source)
      if item is not None and (item is not bandit_source or use_bandit)
   )
   if qtable_source is not None:
      effective_overrides["QLQTablePath"] = qtable_source["runtime_relative_path"]
   if thresholds_source is not None:
      effective_overrides["QLThresholdsPath"] = thresholds_source["runtime_relative_path"]
   if bandit_source is not None:
      effective_overrides["BanditSnapshotPath"] = bandit_source["runtime_relative_path"]

   failure_reason = None
   blocked = False
   if ql_mode == "enabled" and (qtable_source is None or thresholds_source is None):
      failure_reason = "missing_rl_artifacts"
   if use_bandit and not enable_mr:
      blocked = True
      failure_reason = "bandit_requires_mr_enabled"
   elif use_bandit and bandit_shadow_mode:
      blocked = True
      failure_reason = "bandit_shadow_mode_enabled"
   elif use_bandit and bandit_state_mode != "frozen":
      blocked = True
      failure_reason = "bandit_state_mode_not_frozen"
   elif use_bandit and not bool(bundle.get("bandit_ready", False)):
      blocked = True
      failure_reason = "bandit_snapshot_not_ready"

   return Phase5TrialPlan(
      stage=stage,
      stage_token=stage_token,
      trial_id=f"{stage}__{stage_token}",
      arch_token=arch_token,
      threshold_token=threshold_token,
      ql_candidate_token=ql_candidate_token,
      set_overrides=effective_overrides,
      staged_files=staged_files,
      ql_mode=ql_mode,
      bandit_state_mode=bandit_state_mode,
      bandit_shadow_mode=bandit_shadow_mode,
      bandit_ready=bool(bundle.get("bandit_ready", False)),
      bandit_snapshot_id=bandit_source["artifact_id"] if bandit_source else None,
      bandit_snapshot_path=bandit_source["path"] if bandit_source else None,
      bandit_snapshot_sha256=bandit_source["sha256"] if bandit_source else None,
      bandit_snapshot_runtime_path=bandit_source["runtime_relative_path"] if bandit_source else None,
      qtable_artifact_id=qtable_source["artifact_id"] if qtable_source else None,
      qtable_path=qtable_source["path"] if qtable_source else None,
      qtable_sha256=qtable_source["sha256"] if qtable_source else None,
      qtable_runtime_path=qtable_source["runtime_relative_path"] if qtable_source else None,
      thresholds_artifact_id=thresholds_source["artifact_id"] if thresholds_source else None,
      thresholds_path=thresholds_source["path"] if thresholds_source else None,
      thresholds_sha256=thresholds_source["sha256"] if thresholds_source else None,
      thresholds_runtime_path=thresholds_source["runtime_relative_path"] if thresholds_source else None,
      artifact_manifest_path=str(artifact_manifest_path) if artifact_manifest_path else None,
      training_params=dict(training_params),
      failure_reason=failure_reason,
      blocked=blocked,
   )


def select_best_trial(
   summary: dict[str, Any],
   stage: str,
   *,
   predicate: Any | None = None,
   predicate_label: str = "",
) -> dict[str, Any]:
   candidates = [item for item in summary.get("trial_rankings", []) if item.get("stage") == stage]
   if predicate is not None:
      candidates = [item for item in candidates if predicate(item)]
   if not candidates:
      detail = f" matching {predicate_label}" if predicate_label else ""
      raise ValueError(f"No Phase 5 trial rankings available for {stage}{detail}")
   return candidates[0]


def build_trial_plans_for_stage(
   *,
   spec: Phase5Spec,
   bundle: dict[str, Any],
   paths: Phase5Paths,
   stage: str,
   summary: dict[str, Any],
) -> list[Phase5TrialPlan]:
   base_overrides = dict(spec.baseline.behavior_controls)
   plans: list[Phase5TrialPlan] = []

   if stage == "stage1":
      for item in build_stage1_trial_specs(bundle):
         plans.append(
            build_trial_plan(
               phase5_name=spec.name,
               stage="stage1",
               stage_token=item["stage_token"],
               arch_token=item["arch_token"],
               threshold_token=None,
               ql_candidate_token=None,
               base_overrides=base_overrides,
               plan_overrides=item["set_overrides"],
               bundle=bundle,
               artifact_candidate=None,
               artifact_manifest_path=paths.baseline_artifact_manifest_path,
               training_params={},
            )
         )
      return plans

   if stage == "stage2":
      stage1_winner = select_best_trial(
         summary,
         "stage1",
         predicate=ranking_enable_mr,
         predicate_label="MR-enabled architectures",
      )
      arch_token = str(stage1_winner["arch_token"])
      arch_overrides = dict(stage1_winner.get("effective_set_overrides") or {})
      for item in build_threshold_trial_specs(spec.stage2.search_space, arch_token=arch_token):
         plans.append(
            build_trial_plan(
               phase5_name=spec.name,
               stage="stage2",
               stage_token=item["stage_token"],
               arch_token=arch_token,
               threshold_token=item["threshold_token"],
               ql_candidate_token=None,
               base_overrides=arch_overrides,
               plan_overrides=item["set_overrides"],
               bundle=bundle,
               artifact_candidate=None,
               artifact_manifest_path=paths.baseline_artifact_manifest_path,
               training_params={},
            )
         )
      return plans

   if stage == "stage3":
      stage2_winner = select_best_trial(summary, "stage2")
      winner_overrides = dict(stage2_winner.get("effective_set_overrides") or {})
      candidates = list(spec.stage3_candidates) or [baseline_stage3_candidate(bundle, paths)]
      for candidate in candidates:
         for ql_mode in ("enabled", "disabled"):
            stage_token = f"{candidate.id}__ql_{ql_mode}"
            plans.append(
               build_trial_plan(
                  phase5_name=spec.name,
                  stage="stage3",
                  stage_token=stage_token,
                  arch_token=str(stage2_winner["arch_token"]),
                  threshold_token=stage2_winner.get("threshold_token"),
                  ql_candidate_token=candidate.id,
                  base_overrides=winner_overrides,
                  plan_overrides={"QLMode": ql_mode},
                  bundle=bundle,
                  artifact_candidate=candidate,
                  artifact_manifest_path=candidate.artifact_manifest_path,
                  training_params=candidate.training_params,
               )
            )
      return plans

   raise ValueError(f"Unsupported Phase 5 stage: {stage!r}")


def actual_run_record_path(
   paths: Phase5Paths,
   stage: str,
   cycle_id: str,
   window_phase: str,
   stage_token: str,
   scenario_id: str,
) -> Path:
   return paths.actual_runs_dir / stage / cycle_id / window_phase / stage_token / f"{scenario_id}.json"


def resolved_set_output_path(
   paths: Phase5Paths,
   stage: str,
   cycle_id: str,
   window_phase: str,
   stage_token: str,
   scenario_id: str,
) -> Path:
   return paths.resolved_sets_dir / stage / cycle_id / window_phase / stage_token / f"{scenario_id}.set"


def invalid_metric_record(failure_reason: str) -> dict[str, Any]:
   return {
      "valid": False,
      "failure_reason": failure_reason,
      "pass_flag": False,
      "breach_flag": False,
      "progress_ratio": 0.0,
      "daily_slack_ratio": 0.0,
      "overall_slack_ratio": 0.0,
      "speed_ratio": 0.0,
      "zero_trade_flag": True,
      "reset_exposure_ratio": 0.0,
      "summary_metrics": {
         "final_return_pct": 0.0,
         "max_daily_dd_pct": 0.0,
         "max_overall_dd_pct": 0.0,
         "pass_days_traded": 0,
         "trades_total": 0,
         "days_traded": 0,
         "min_trade_days_required": 0,
         "observed_server_days": 0,
      },
   }


def compute_row_objective(record: dict[str, Any]) -> float:
   _, objective = hpo.aggregate_trial_runs([record], scenario_count=1, window_count=1)
   return objective


def enrich_phase5_record(
   record: dict[str, Any],
   *,
   plan: Phase5TrialPlan,
   bundle: dict[str, Any],
   effective_input_hash: str,
   resolved_set_path: Path,
   resolved_set_sha256: str,
   status: str,
) -> dict[str, Any]:
   record = json.loads(json.dumps(record))
   record.update(
      {
         "stage": plan.stage,
         "stage_token": plan.stage_token,
         "trial_id": plan.trial_id,
         "arch_token": plan.arch_token,
         "threshold_token": plan.threshold_token,
         "ql_candidate_token": plan.ql_candidate_token,
         "baseline_bundle_id": bundle["baseline_bundle_id"],
         "window_id": f"{record['cycle_id']}__{record['window_phase']}",
         "window_period": f"{record['from_date']}..{record['to_date']}",
         "bandit_state_mode": plan.bandit_state_mode,
         "bandit_shadow_mode": plan.bandit_shadow_mode,
         "bandit_ready": plan.bandit_ready,
         "bandit_snapshot_id": plan.bandit_snapshot_id,
         "bandit_snapshot_path": plan.bandit_snapshot_path,
         "bandit_snapshot_sha256": plan.bandit_snapshot_sha256,
         "bandit_snapshot_runtime_path": plan.bandit_snapshot_runtime_path,
         "rl_mode": plan.ql_mode,
         "qtable_artifact_id": plan.qtable_artifact_id,
         "qtable_path": plan.qtable_path,
         "qtable_sha256": plan.qtable_sha256,
         "qtable_runtime_path": plan.qtable_runtime_path,
         "thresholds_artifact_id": plan.thresholds_artifact_id,
         "thresholds_path": plan.thresholds_path,
         "thresholds_sha256": plan.thresholds_sha256,
         "thresholds_runtime_path": plan.thresholds_runtime_path,
         "artifact_manifest_path": plan.artifact_manifest_path,
         "resolved_set_path": str(resolved_set_path),
         "resolved_set_sha256": resolved_set_sha256,
         "effective_input_hash": effective_input_hash,
         "effective_set_overrides": dict(plan.set_overrides),
         "training_params": dict(plan.training_params),
         "status": status,
      }
   )
   record["objective"] = compute_row_objective(record)
   return record


def build_invalid_actual_record(
   *,
   cycle: phase4.WalkForwardCycle,
   window_phase: str,
   scenario: phase4.Phase4ScenarioSpec,
   plan: Phase5TrialPlan,
   bundle: dict[str, Any],
   resolved_set_path: Path,
   resolved_set_sha256: str,
   effective_input_hash: str,
) -> dict[str, Any]:
   start_date, end_date = phase4.cycle_window_dates(cycle, window_phase)
   record = {
      "cycle_id": cycle.id,
      "window_phase": window_phase,
      "candidate_id": plan.stage_token,
      "candidate_group": plan.stage,
      "parent_candidate_id": None,
      "scenario_id": scenario.id,
      "source_scenario_id": None,
      "scenario_weight": scenario.weight,
      "scenario_severity": scenario.severity,
      "from_date": hpo.iso_date(start_date),
      "to_date": hpo.iso_date(end_date),
      "window_trading_days": phase4.cycle_window_trading_days(cycle, window_phase),
      "manifest_path": None,
      "summary_path": None,
      "daily_path": None,
      "report_path": None,
      "run_dir": None,
      "cache_key": None,
      "decision_logs": [],
      "event_logs": [],
      "run_manifest_spec": {
         "base_set": str(resolved_set_path),
         "set_overrides": dict(plan.set_overrides),
      },
      "report_metrics": {
         "profit_factor": None,
         "recovery_factor": None,
         "report_parse_error": plan.failure_reason,
         "sharpe_ratio": None,
         "total_net_profit": None,
         "total_trades": 0,
      },
      "regime_summary": {},
      "daily_regime_summary": {},
      "initial_baseline": 10000.0,
      "stress_applied": False,
      "stress_components": {},
   }
   record.update(invalid_metric_record(plan.failure_reason or "invalid_phase5_row"))
   return enrich_phase5_record(
      record,
      plan=plan,
      bundle=bundle,
      effective_input_hash=effective_input_hash,
      resolved_set_path=resolved_set_path,
      resolved_set_sha256=resolved_set_sha256,
      status="blocked" if plan.blocked else "invalid",
   )


def load_actual_records(paths: Phase5Paths) -> list[dict[str, Any]]:
   if not paths.actual_runs_dir.exists():
      return []
   records: list[dict[str, Any]] = []
   for path in sorted(paths.actual_runs_dir.rglob("*.json")):
      records.append(hpo.load_json_file(path))
   return records


def build_phase5_run_rows(
   actual_records: list[dict[str, Any]],
   phase4_spec: phase4.Phase4Spec,
   rules_profile: hpo.RulesProfile,
) -> list[dict[str, Any]]:
   grouped: dict[tuple[str, str, str, str], dict[str, dict[str, Any]]] = collections.defaultdict(dict)
   for record in actual_records:
      grouped[(record["stage"], record["trial_id"], record["cycle_id"], record["window_phase"])][
         record["scenario_id"]
      ] = record

   rows: list[dict[str, Any]] = []
   for key in sorted(grouped.keys()):
      actual_by_scenario = grouped[key]
      for scenario in phase4_spec.scenarios:
         if scenario.source_scenario_id is None:
            actual_record = actual_by_scenario.get(scenario.id)
            if actual_record is not None:
               rows.append(actual_record)
            continue

         source_record = actual_by_scenario.get(scenario.source_scenario_id)
         if source_record is None:
            continue
         if not source_record.get("valid", False):
            derived = json.loads(json.dumps(source_record))
            derived["scenario_id"] = scenario.id
            derived["source_scenario_id"] = scenario.source_scenario_id
            derived["scenario_weight"] = scenario.weight
            derived["scenario_severity"] = scenario.severity
            derived["stress_applied"] = True
            derived["stress_components"] = dataclasses.asdict(scenario.stress)
            derived["objective"] = hpo.INVALID_OBJECTIVE
            rows.append(derived)
            continue
         stressed = phase4.apply_synthetic_stress(source_record, scenario, rules_profile)
         stressed["objective"] = compute_row_objective(stressed)
         rows.append(stressed)

   rows.sort(
      key=lambda item: (
         item["stage"],
         item["trial_id"],
         item["cycle_id"],
         item["window_phase"],
         item["scenario_id"],
      )
   )
   return rows


def build_phase5_summary(
   spec: Phase5Spec,
   phase4_spec: phase4.Phase4Spec,
   run_rows: list[dict[str, Any]],
   bundle: dict[str, Any],
   paths: Phase5Paths,
) -> dict[str, Any]:
   counts = collections.Counter()
   rejection_reasons = collections.Counter()
   for row in run_rows:
      counts["total_rows"] += 1
      if row.get("valid", False):
         counts["valid_rows"] += 1
      elif row.get("status") == "blocked":
         counts["blocked_rows"] += 1
      else:
         counts["invalid_rows"] += 1
      if row.get("failure_reason"):
         rejection_reasons[str(row["failure_reason"])] += 1

   trial_window_groups: dict[tuple[str, str, str, str], list[dict[str, Any]]] = collections.defaultdict(list)
   for row in run_rows:
      trial_window_groups[(row["stage"], row["trial_id"], row["cycle_id"], row["window_phase"])].append(row)

   trial_window_summaries: list[dict[str, Any]] = []
   trial_group_rows: dict[tuple[str, str], list[dict[str, Any]]] = collections.defaultdict(list)
   for key in sorted(trial_window_groups.keys()):
      records = sorted(trial_window_groups[key], key=lambda item: item["scenario_id"])
      aggregate, objective = hpo.aggregate_trial_runs(
         records,
         scenario_count=len(phase4_spec.scenarios),
         window_count=1,
      )
      sample = records[0]
      summary = {
         "stage": key[0],
         "trial_id": key[1],
         "cycle_id": key[2],
         "window_phase": key[3],
         "window_id": f"{key[2]}__{key[3]}",
         "arch_token": sample["arch_token"],
         "threshold_token": sample.get("threshold_token"),
         "ql_candidate_token": sample.get("ql_candidate_token"),
         "stage_token": sample["stage_token"],
         "objective": objective,
         "aggregate_metrics": aggregate,
      }
      trial_window_summaries.append(summary)
      trial_group_rows[(key[0], key[1])].extend(records)

   trial_rankings: list[dict[str, Any]] = []
   for key, records in sorted(trial_group_rows.items()):
      sample = records[0]
      window_summaries = [
         item
         for item in trial_window_summaries
         if item["stage"] == key[0] and item["trial_id"] == key[1]
      ]
      objectives = [float(item["objective"]) for item in window_summaries if item["aggregate_metrics"].get("valid", False)]
      if not objectives:
         continue
      by_phase: dict[str, list[float]] = collections.defaultdict(list)
      for item in window_summaries:
         if item["aggregate_metrics"].get("valid", False):
            by_phase[item["window_phase"]].append(float(item["objective"]))
      report_mean = sum(by_phase["report"]) / len(by_phase["report"]) if by_phase["report"] else hpo.INVALID_OBJECTIVE
      overall_mean = sum(objectives) / len(objectives) if objectives else hpo.INVALID_OBJECTIVE
      mild_report_rows = [
         row for row in records
         if row["window_phase"] == "report" and row["scenario_severity"] == "mild" and row.get("valid", False)
      ]
      moderate_report_rows = [
         row for row in records
         if row["window_phase"] == "report" and row["scenario_severity"] == "moderate" and row.get("valid", False)
      ]
      trial_rankings.append(
         {
            "stage": key[0],
            "trial_id": key[1],
            "stage_token": sample["stage_token"],
            "arch_token": sample["arch_token"],
            "threshold_token": sample.get("threshold_token"),
            "ql_candidate_token": sample.get("ql_candidate_token"),
            "effective_set_overrides": sample.get("effective_set_overrides", {}),
            "window_count": len(window_summaries),
            "complete_window_count": len(objectives),
            "report_objective_mean": report_mean,
            "overall_objective_mean": overall_mean,
            "objective_min": min(objectives) if objectives else hpo.INVALID_OBJECTIVE,
            "robustness_flags": {
               "no_breach": all(not row["breach_flag"] for row in records if row.get("valid", False)),
               "no_zero_trade": all(not row["zero_trade_flag"] for row in records if row.get("valid", False)),
               "mild_report_noncollapse": bool(mild_report_rows)
               and all((not row["breach_flag"]) and (not row["zero_trade_flag"]) for row in mild_report_rows),
               "moderate_report_noncollapse": bool(moderate_report_rows)
               and all((not row["breach_flag"]) and (not row["zero_trade_flag"]) for row in moderate_report_rows),
            },
         }
      )

   trial_rankings.sort(
      key=lambda item: (
         float(item["report_objective_mean"]),
         float(item["overall_objective_mean"]),
         float(item["objective_min"]),
      ),
      reverse=True,
   )

   architecture_groups: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
   for ranking in trial_rankings:
      architecture_groups[str(ranking["arch_token"])].append(ranking)

   architecture_rankings: list[dict[str, Any]] = []
   for arch_token, items in sorted(architecture_groups.items()):
      architecture_rankings.append(
         {
            "arch_token": arch_token,
            "trial_count": len(items),
            "report_objective_mean": (
               sum(float(item["report_objective_mean"]) for item in items) / len(items)
               if items else hpo.INVALID_OBJECTIVE
            ),
            "overall_objective_mean": (
               sum(float(item["overall_objective_mean"]) for item in items) / len(items)
               if items else hpo.INVALID_OBJECTIVE
            ),
            "robustness_flags": {
               "all_no_breach": all(item["robustness_flags"]["no_breach"] for item in items),
               "all_no_zero_trade": all(item["robustness_flags"]["no_zero_trade"] for item in items),
               "any_mild_report_noncollapse": any(item["robustness_flags"]["mild_report_noncollapse"] for item in items),
               "any_moderate_report_noncollapse": any(
                  item["robustness_flags"]["moderate_report_noncollapse"] for item in items
               ),
            },
         }
      )
   architecture_rankings.sort(
      key=lambda item: (
         float(item["report_objective_mean"]),
         float(item["overall_objective_mean"]),
      ),
      reverse=True,
   )

   best_rows = {
      "overall": trial_rankings[0] if trial_rankings else None,
      "by_stage": {
         stage: next((item for item in trial_rankings if item["stage"] == stage), None)
         for stage in ("stage1", "stage2", "stage3")
      },
   }
   stress_gate_markers = {
      "mild_report_noncollapse_count": sum(
         1 for item in trial_rankings if item["robustness_flags"]["mild_report_noncollapse"]
      ),
      "moderate_report_noncollapse_count": sum(
         1 for item in trial_rankings if item["robustness_flags"]["moderate_report_noncollapse"]
      ),
   }

   return {
      "generated_at_utc": hpo.utc_now_iso(),
      "phase5_name": spec.name,
      "phase_totals": dict(counts),
      "best_rows": best_rows,
      "trial_rankings": trial_rankings,
      "architecture_rankings": architecture_rankings,
      "rejection_reasons": dict(rejection_reasons),
      "stress_gate_markers": stress_gate_markers,
      "manifest_links": {
         "baseline_bundle_id": bundle["baseline_bundle_id"],
         "baseline_bundle_path": str(paths.baseline_bundle_path),
         "run_rows_path": str(paths.run_rows_path),
         "manifest_path": str(paths.manifest_path),
      },
      "trial_window_summaries": trial_window_summaries,
   }


def export_phase5(phase5_dir: Path) -> dict[str, Any]:
   manifest_path = phase5_dir / "phase5_manifest.json"
   if not manifest_path.exists():
      raise FileNotFoundError(f"Phase 5 manifest not found: {manifest_path}")

   manifest = hpo.load_json_file(manifest_path)
   spec_path = Path(str(manifest.get("phase5_spec_path", "")).strip())
   if not spec_path:
      raise ValueError(f"phase5_spec_path missing from manifest: {manifest_path}")
   spec = load_phase5_spec(spec_path)
   phase4_spec = phase4.load_phase4_spec(spec.phase4_spec_path)
   rules_profile = hpo.load_rules_profile(hpo.rules_profile_path(phase4_spec.rules_profile))
   paths = build_phase5_paths(spec.name)
   bundle = load_baseline_bundle(paths)
   actual_records = load_actual_records(paths)
   run_rows = build_phase5_run_rows(actual_records, phase4_spec, rules_profile)

   with paths.run_rows_path.open("w", encoding="utf-8") as handle:
      for row in run_rows:
         handle.write(json.dumps(row, sort_keys=True))
         handle.write("\n")

   summary = build_phase5_summary(spec, phase4_spec, run_rows, bundle, paths)
   write_json(paths.summary_path, summary)
   return {
      "phase5_dir": str(paths.phase5_dir),
      "baseline_bundle_path": str(paths.baseline_bundle_path),
      "phase5_run_rows_path": str(paths.run_rows_path),
      "phase5_summary_path": str(paths.summary_path),
      "actual_run_record_count": len(actual_records),
      "phase5_run_row_count": len(run_rows),
      "best_overall_trial": summary["best_rows"]["overall"]["trial_id"] if summary["best_rows"]["overall"] else None,
   }


def run_phase5(
   phase5_spec_path: Path,
   *,
   stage: str,
   cycle_ids: tuple[str, ...] = (),
   window_phase: str = "both",
   timeout_seconds: int | None = None,
   mt5_install_path: str | None = None,
   terminal_data_path: str | None = None,
   output_root: str | Path = mt5_runner.DEFAULT_OUTPUT_ROOT,
   stop_existing: bool = False,
   force: bool = False,
   runner_paths: mt5_runner.RunnerPaths | None = None,
   runner_module: Any = mt5_runner,
) -> dict[str, Any]:
   spec = load_phase5_spec(phase5_spec_path)
   phase4_spec = phase4.load_phase4_spec(spec.phase4_spec_path)
   rules_profile = hpo.load_rules_profile(hpo.rules_profile_path(phase4_spec.rules_profile))
   cycles = phase4.build_walk_forward_cycles(phase4_spec)
   paths = build_phase5_paths(spec.name)
   if not paths.manifest_path.exists():
      prepare_phase5(phase5_spec_path)
   bundle = load_baseline_bundle(paths)
   summary = hpo.load_json_file(paths.summary_path) if paths.summary_path.exists() else {"trial_rankings": []}

   selected_cycle_ids = set(cycle_ids)
   selected_cycles = [
      cycle
      for cycle in cycles
      if not selected_cycle_ids or cycle.id in selected_cycle_ids
   ]
   if selected_cycle_ids and len(selected_cycles) != len(selected_cycle_ids):
      known_cycle_ids = {cycle.id for cycle in cycles}
      missing = sorted(selected_cycle_ids - known_cycle_ids)
      raise ValueError(f"Unknown cycle id(s): {missing}")

   if runner_paths is None:
      runner_paths = runner_module.build_runner_paths(
         mt5_install_path=mt5_install_path,
         terminal_data_path=terminal_data_path,
         output_root=output_root,
      )

   plans = build_trial_plans_for_stage(
      spec=spec,
      bundle=bundle,
      paths=paths,
      stage=stage,
      summary=summary,
   )
   if not plans:
      raise ValueError(f"No Phase 5 trial plans were generated for {stage}")

   base_set_text = mt5_runner.load_text(resolve_repo_path(phase4_spec.base_set))
   concrete_runner_scenarios = concrete_scenarios(phase4_spec)
   pending_sync = True
   pending_compile = True
   executed_runs = 0

   for cycle in selected_cycles:
      for plan in plans:
         for phase_name in ("search", "report"):
            if window_phase == "search" and phase_name != "search":
               continue
            if window_phase == "report" and phase_name != "report":
               continue
            if window_phase not in ("search", "report", "both"):
               raise ValueError(f"Unsupported window_phase: {window_phase!r}")

            start_date, end_date = phase4.cycle_window_dates(cycle, phase_name)
            for scenario in concrete_runner_scenarios:
               resolved_set_path = resolved_set_output_path(
                  paths,
                  stage,
                  cycle.id,
                  phase_name,
                  plan.stage_token,
                  scenario.id,
               )
               hpo.ensure_directory(resolved_set_path.parent)
               resolved_set_text = hpo.render_set_with_overrides(
                  base_set_text,
                  dict(plan.set_overrides) | dict(scenario.set_overrides),
               )
               resolved_set_path.write_text(resolved_set_text, encoding="ascii")
               resolved_set_sha256 = mt5_runner.sha256_file(resolved_set_path)
               effective_input_hash = sha256_text(resolved_set_text)

               if plan.failure_reason:
                  record = build_invalid_actual_record(
                     cycle=cycle,
                     window_phase=phase_name,
                     scenario=scenario,
                     plan=plan,
                     bundle=bundle,
                     resolved_set_path=resolved_set_path,
                     resolved_set_sha256=resolved_set_sha256,
                     effective_input_hash=effective_input_hash,
                  )
               else:
                  run_data = {
                     "name": f"{spec.name}__{stage}__{cycle.id}__{phase_name}__{plan.stage_token}__{scenario.id}",
                     "symbol": phase4_spec.symbol,
                     "period": phase4_spec.period,
                     "from_date": hpo.to_mt5_date(start_date),
                     "to_date": hpo.to_mt5_date(end_date),
                     "base_set": str(phase4_spec.base_set),
                     "scenario": scenario.id,
                     "rules_profile": phase4_spec.rules_profile,
                     "set_overrides": dict(plan.set_overrides) | dict(scenario.set_overrides),
                     "staged_files": [
                        {
                           "source_path": str(item.source_path),
                           "terminal_relative_path": item.terminal_relative_path,
                           "artifact_id": item.artifact_id,
                           "sha256": item.sha256,
                        }
                        for item in plan.staged_files
                     ],
                  }
                  if scenario.execution_mode is not None:
                     run_data["execution_mode"] = scenario.execution_mode
                  if timeout_seconds is not None:
                     run_data["timeout_seconds"] = timeout_seconds
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
                  candidate = phase4.Phase4CandidateSpec(
                     id=plan.stage_token,
                     group=stage,
                     set_overrides={},
                     parent_candidate_id=None,
                     window_phases=(phase_name,),
                  )
                  record = phase4.normalize_actual_run_record(
                     spec=phase4_spec,
                     rules_profile=rules_profile,
                     cycle=cycle,
                     window_phase=phase_name,
                     candidate=candidate,
                     scenario=scenario,
                     result=result,
                  )
                  record = enrich_phase5_record(
                     record,
                     plan=plan,
                     bundle=bundle,
                     effective_input_hash=effective_input_hash,
                     resolved_set_path=resolved_set_path,
                     resolved_set_sha256=resolved_set_sha256,
                     status=str(result.get("status", "completed")),
                  )
                  executed_runs += 1

               record_path = actual_run_record_path(
                  paths,
                  stage,
                  cycle.id,
                  phase_name,
                  plan.stage_token,
                  scenario.id,
               )
               write_json(record_path, record)

   exported = export_phase5(paths.phase5_dir)
   return {
      "phase5_name": spec.name,
      "phase5_dir": str(paths.phase5_dir),
      "stage": stage,
      "cycle_ids": [cycle.id for cycle in selected_cycles],
      "window_phase": window_phase,
      "trial_count": len(plans),
      "executed_runs": executed_runs,
      "exports": exported,
   }


def build_parser() -> argparse.ArgumentParser:
   parser = argparse.ArgumentParser(description="FundingPips Phase 5 pipeline tooling")
   subparsers = parser.add_subparsers(dest="command", required=True)

   prepare_parser = subparsers.add_parser("prepare-phase5", help="Generate Phase 5 baseline bundle and manifest")
   prepare_parser.add_argument("--phase5-spec", required=True)

   run_parser = subparsers.add_parser("run-phase5", help="Run a Phase 5 stage")
   run_parser.add_argument("--phase5-spec", required=True)
   run_parser.add_argument("--stage", choices=("stage1", "stage2", "stage3"), required=True)
   run_parser.add_argument("--cycle-id", action="append", default=[])
   run_parser.add_argument("--window-phase", choices=("search", "report", "both"), default="both")
   run_parser.add_argument("--timeout-seconds", type=int, default=None)
   run_parser.add_argument("--mt5-install-path", default=None)
   run_parser.add_argument("--terminal-data-path", default=None)
   run_parser.add_argument("--output-root", default=str(mt5_runner.DEFAULT_OUTPUT_ROOT))
   run_parser.add_argument("--stop-existing", action="store_true")
   run_parser.add_argument("--force", action="store_true")

   export_parser = subparsers.add_parser("export-phase5", help="Regenerate Phase 5 summary artifacts")
   export_parser.add_argument("--phase5-dir", required=True)

   return parser


def main(argv: list[str] | None = None) -> int:
   parser = build_parser()
   args = parser.parse_args(argv)

   if args.command == "prepare-phase5":
      result = prepare_phase5(resolve_repo_path(Path(args.phase5_spec)))
      print(json.dumps(result, indent=2, sort_keys=True))
      return 0

   if args.command == "run-phase5":
      result = run_phase5(
         resolve_repo_path(Path(args.phase5_spec)),
         stage=args.stage,
         cycle_ids=tuple(args.cycle_id),
         window_phase=args.window_phase,
         timeout_seconds=args.timeout_seconds,
         mt5_install_path=args.mt5_install_path,
         terminal_data_path=args.terminal_data_path,
         output_root=args.output_root,
         stop_existing=args.stop_existing,
         force=args.force,
      )
      print(json.dumps(result, indent=2, sort_keys=True))
      return 0

   if args.command == "export-phase5":
      result = export_phase5(resolve_repo_path(Path(args.phase5_dir)))
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
