import json
import re
import tempfile
import unittest
from pathlib import Path

from tools import fundingpips_mt5_runner as runner
from tools import fundingpips_phase5 as phase5


class FakePhase5RunnerModule:
   calls: list[dict[str, object]] = []
   call_count = 0

   @classmethod
   def reset(cls) -> None:
      cls.calls = []
      cls.call_count = 0

   @staticmethod
   def build_spec(run_data, defaults=None):
      return runner.build_spec(run_data, defaults)

   @classmethod
   def run_single_backtest(cls, spec, paths, **kwargs):
      cls.call_count += 1
      cls.calls.append(
         {
            "name": spec.name,
            "staged_files": [item.terminal_relative_path for item in spec.staged_files],
            "timeout_seconds": spec.timeout_seconds,
            **kwargs,
         }
      )
      cache_key = f"phase5{cls.call_count:04d}"
      run_dir = paths.output_root / f"{runner.safe_name(spec.name)}__{cache_key}"
      collected_dir = run_dir / "collected"
      collected_dir.mkdir(parents=True, exist_ok=True)

      enable_mr = int(spec.set_overrides.get("EnableMR", 1))
      use_bandit = int(spec.set_overrides.get("UseBanditMetaPolicy", 0))
      ql_mode = str(spec.set_overrides.get("QLMode", "enabled"))
      final_return_pct = 0.60
      trades_total = 4
      if enable_mr:
         final_return_pct = 1.35
         trades_total = 8
      if enable_mr and ql_mode == "disabled":
         final_return_pct -= 0.15
      if use_bandit:
         final_return_pct -= 0.10

      manifest_path = run_dir / "run_manifest.json"
      summary_path = collected_dir / runner.SUMMARY_FILENAME
      daily_path = collected_dir / runner.DAILY_FILENAME
      report_path = collected_dir / f"{spec.report_stem}_{cache_key}.xml.htm"

      manifest_path.write_text(
         json.dumps({"spec": runner.spec_to_manifest_dict(spec)}, indent=2, sort_keys=True),
         encoding="ascii",
      )
      summary_path.write_text(
         json.dumps(
            {
               "pass": False,
               "pass_days_traded": 0,
               "final_return_pct": round(final_return_pct, 6),
               "max_daily_dd_pct": 0.45,
               "max_overall_dd_pct": 0.10,
               "any_daily_breach": False,
               "overall_breach": False,
               "trades_total": trades_total,
               "days_traded": 4,
               "min_trade_days_required": 3,
               "observed_server_days": 10,
               "initial_baseline": 10000.0,
            },
            indent=2,
            sort_keys=True,
         ),
         encoding="ascii",
      )
      daily_path.write_text(
         "\n".join(
            [
               "server_date,server_midnight_ts,baseline_capture_time,baseline_equity,baseline_balance,baseline_used,daily_floor,min_equity,end_equity,max_daily_dd_money,max_daily_dd_pct,daily_breach",
               "2025-08-01,2025-08-01T00:00:00Z,2025-08-01T00:00:00Z,10000.00,10000.00,10000.00,9600.00,9980.00,10040.00,20.00,0.200000,false",
            ]
         )
         + "\n",
         encoding="utf-8",
      )
      report_path.write_text(
         "\n".join(
            [
               "<html><body><table>",
               f"<tr><td>Total Net Profit:</td><td><b>{final_return_pct * 100.0:.2f}</b></td></tr>",
               "<tr><td>Profit Factor:</td><td><b>1.50</b></td></tr>",
               "<tr><td>Recovery Factor:</td><td><b>1.10</b></td></tr>",
               "<tr><td>Sharpe Ratio:</td><td><b>0.50</b></td></tr>",
               f"<tr><td>Total Trades:</td><td><b>{trades_total}</b></td></tr>",
               "</table></body></html>",
            ]
         ),
         encoding="utf-8",
      )
      return {
         "status": "completed",
         "cache_key": cache_key,
         "run_dir": str(run_dir),
         "manifest_path": str(manifest_path),
         "summary_path": str(summary_path),
         "daily_path": str(daily_path),
         "report_path": str(report_path),
         "decision_logs": [],
         "event_logs": [],
      }


class FundingPipsPhase5Tests(unittest.TestCase):
   def test_runtime_string_config_getters_use_ea_inputs_in_non_test_builds(self) -> None:
      source = (
         Path(__file__).resolve().parents[2]
         / "MQL5"
         / "Include"
         / "RPEA"
         / "config.mqh"
      ).read_text(encoding="utf-8")

      self.assertRegex(
         source,
         re.compile(
            r"inline string Config_GetQLMode\(\)\s*\{.*?#else\s+return Config_NormalizeQLMode\(QLMode\);",
            re.DOTALL,
         ),
      )
      self.assertRegex(
         source,
         re.compile(
            r"inline string Config_GetQLQTablePath\(\)\s*\{.*?#else\s+return Config_NormalizePathString\(QLQTablePath, DEFAULT_QLQTablePath\);",
            re.DOTALL,
         ),
      )
      self.assertRegex(
         source,
         re.compile(
            r"inline string Config_GetQLThresholdsPath\(\)\s*\{.*?#else\s+return Config_NormalizePathString\(QLThresholdsPath, DEFAULT_QLThresholdsPath\);",
            re.DOTALL,
         ),
      )
      self.assertRegex(
         source,
         re.compile(
            r"inline string Config_GetBanditStateMode\(\)\s*\{.*?#else\s+return Config_NormalizeBanditStateMode\(BanditStateMode\);",
            re.DOTALL,
         ),
      )
      self.assertRegex(
         source,
         re.compile(
            r"inline string Config_GetBanditSnapshotPath\(\)\s*\{.*?#else\s+return Config_NormalizePathString\(BanditSnapshotPath, DEFAULT_BanditSnapshotPath\);",
            re.DOTALL,
         ),
      )

   def test_select_best_trial_can_filter_for_mr_enabled_rows(self) -> None:
      summary = {
         "trial_rankings": [
            {
               "stage": "stage1",
               "trial_id": "stage1__arch_bwisc_only",
               "arch_token": "arch_bwisc_only",
               "effective_set_overrides": {"EnableMR": 0},
            },
            {
               "stage": "stage1",
               "trial_id": "stage1__arch_mr_deterministic",
               "arch_token": "arch_mr_deterministic",
               "effective_set_overrides": {"EnableMR": 1},
            },
         ]
      }

      winner = phase5.select_best_trial(
         summary,
         "stage1",
         predicate=phase5.ranking_enable_mr,
         predicate_label="MR-enabled architectures",
      )

      self.assertEqual(winner["trial_id"], "stage1__arch_mr_deterministic")

   def write_fixture_repo(self, repo: Path, *, bandit_ready: bool) -> Path:
      rules_dir = repo / "tools" / "fundingpips_rules_profiles"
      studies_dir = repo / "tools" / "fundingpips_studies"
      tests_dir = repo / "Tests" / "RPEA"
      artifacts_dir = repo / "artifacts"
      rules_dir.mkdir(parents=True)
      studies_dir.mkdir(parents=True)
      tests_dir.mkdir(parents=True)
      artifacts_dir.mkdir(parents=True)

      (rules_dir / "fundingpips_1step_eval.json").write_text(
         json.dumps(
            {
               "id": "fundingpips_1step_eval",
               "target_profit_pct": 10.0,
               "daily_loss_cap_pct": 4.0,
               "overall_loss_cap_pct": 6.0,
               "min_trade_days": 3,
            }
         ),
         encoding="ascii",
      )
      base_set_path = tests_dir / "RPEA_candidate_B_2024H2.set"
      base_set_path.write_text(
         "\n".join(
            [
               "RiskPct=2.0",
               "MR_RiskPct_Default=1.0",
               "ORMinutes=45",
               "CutoffHour=23",
               "StartHourLO=5",
               "SpreadMultATR=0.005",
               "UseXAUEURProxy=1",
               "EnableMR=1",
               "UseBanditMetaPolicy=0",
               "BanditShadowMode=0",
               "EnableMRBypassOnRLUnloaded=1",
               "EnableAdaptiveRisk=0",
               "MR_UseLogRatio=1",
            ]
         )
         + "\n",
         encoding="ascii",
      )

      qtable_path = artifacts_dir / "mr_qtable.bin"
      thresholds_path = artifacts_dir / "thresholds.json"
      bandit_path = artifacts_dir / "posterior.txt"
      qtable_path.write_bytes(b"\x00\x01phase5")
      thresholds_path.write_text("{\"k_thresholds\":[-0.02,0.0,0.02],\"sigma_ref\":0.015}", encoding="ascii")
      if bandit_ready:
         bandit_path.write_text(
            "\n".join(
               [
                  "schema_version=1",
                  "total_updates=8",
                  "bwisc_pulls=4",
                  "mr_pulls=4",
                  "bwisc_reward_sum=2.00000000",
                  "mr_reward_sum=2.00000000",
                  "updated_at=1700000000",
               ]
            )
            + "\n",
            encoding="ascii",
         )
      else:
         bandit_path.write_text("{}\n", encoding="ascii")

      phase4_spec_path = studies_dir / "phase4_anchor_wfo_stress.json"
      phase4_spec_path.write_text(
         json.dumps(
            {
               "name": "phase4_anchor_wfo_stress",
               "rules_profile": "fundingpips_1step_eval",
               "symbol": "EURUSD",
               "period": "M1",
               "from_date": "2025-06-03",
               "to_date": "2025-08-29",
               "base_set": str(base_set_path),
               "walk_forward": {
                  "search_window_months": 2,
                  "report_window_months": 1,
                  "roll_months": 1,
               },
               "primary_candidates": [
                  {
                     "id": "anchor_mr100",
                     "set_overrides": {
                        "RiskPct": 2.0,
                        "MR_RiskPct_Default": 1.0,
                        "ORMinutes": 45,
                        "CutoffHour": 23,
                        "StartHourLO": 5,
                        "SpreadMultATR": 0.005,
                     },
                  }
               ],
               "neighbor_candidates": [],
               "scenarios": [
                  {
                     "id": "baseline",
                     "severity": "baseline",
                     "weight": 1.0,
                     "set_overrides": {}
                  },
                  {
                     "id": "mild_delay_commission",
                     "severity": "mild",
                     "weight": 0.5,
                     "source_scenario_id": "baseline",
                     "synthetic_stress": {
                        "delay_return_penalty_pct_per_trade": 0.0015,
                        "commission_money_per_trade": 0.25,
                        "daily_dd_multiplier": 1.05,
                        "overall_dd_multiplier": 1.05
                     }
                  }
               ]
            },
            indent=2,
            sort_keys=True,
         ),
         encoding="ascii",
      )

      phase5_spec_path = studies_dir / "phase5_smoke.json"
      phase5_spec_path.write_text(
         json.dumps(
            {
               "name": "phase5_smoke",
               "phase4_spec_path": str(phase4_spec_path),
               "baseline": {
                  "phase4_candidate_id": "anchor_mr100",
                  "behavior_controls": {
                     "UseXAUEURProxy": 1,
                     "EnableMR": 1,
                     "UseBanditMetaPolicy": 0,
                     "BanditShadowMode": 0,
                     "EnableMRBypassOnRLUnloaded": 1,
                     "EnableAdaptiveRisk": 0,
                     "MR_UseLogRatio": 1,
                     "MR_ConfCut": 0.0,
                     "EMRT_FastThresholdPct": 100,
                     "MR_EMRTWeight": 0.0,
                     "MR_TimeStopMin": 60,
                     "MR_TimeStopMax": 90,
                     "QLMode": "enabled",
                     "QLQTablePath": "RPEA/qtable/mr_qtable.bin",
                     "QLThresholdsPath": "RPEA/rl/thresholds.json",
                     "BanditStateMode": "disabled",
                     "BanditSnapshotPath": "RPEA/bandit/posterior.json"
                  },
                  "rl_mode_default": "enabled",
                  "bandit_state_mode_default": "disabled",
                  "qtable_path": str(qtable_path),
                  "thresholds_path": str(thresholds_path),
                  "bandit_snapshot_path": str(bandit_path),
                  "study_seed": 20260316,
                  "notes": "Phase 5 smoke spec"
               },
               "stage2": {
                  "search_space": {
                     "MR_ConfCut": {
                        "type": "categorical",
                        "choices": [0.0, 0.05]
                     },
                     "EMRT_FastThresholdPct": {
                        "type": "categorical",
                        "choices": [95, 100]
                     },
                     "MR_EMRTWeight": {
                        "type": "categorical",
                        "choices": [0.0, 0.2]
                     },
                     "MR_TimeStopMin": {
                        "type": "categorical",
                        "choices": [60]
                     },
                     "MR_TimeStopMax": {
                        "type": "categorical",
                        "choices": [90]
                     }
                  }
               }
            },
            indent=2,
            sort_keys=True,
         ),
         encoding="ascii",
      )
      return phase5_spec_path

   def test_prepare_phase5_builds_baseline_bundle(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo = Path(tmp_dir)
         phase5_spec_path = self.write_fixture_repo(repo, bandit_ready=True)
         original_repo_root = runner.repo_root
         try:
            runner.repo_root = lambda: repo
            result = phase5.prepare_phase5(phase5_spec_path)
         finally:
            runner.repo_root = original_repo_root

         bundle_path = Path(result["baseline_bundle_path"])
         manifest_path = Path(result["manifest_path"])
         summary_path = Path(result["exports"]["phase5_summary_path"])

         self.assertTrue(bundle_path.exists())
         self.assertTrue(manifest_path.exists())
         self.assertTrue(summary_path.exists())

         bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
         self.assertTrue(bundle["baseline_bundle_id"])
         self.assertEqual(bundle["rl_mode_default"], "enabled")
         self.assertEqual(bundle["bandit_state_mode_default"], "disabled")
         self.assertTrue(bundle["bandit_ready"])
         self.assertTrue(bundle["resolved_set_sha256"])

   def test_run_phase5_stage1_writes_provenance_and_blocks_unready_bandit(self) -> None:
      FakePhase5RunnerModule.reset()
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo = Path(tmp_dir)
         phase5_spec_path = self.write_fixture_repo(repo, bandit_ready=False)
         fake_paths = runner.RunnerPaths(
            repo_root=repo,
            terminal_exe=repo / "terminal64.exe",
            metaeditor_exe=repo / "metaeditor64.exe",
            terminal_data_path=repo / "terminal_data",
            tester_root=repo / "tester_root",
            tester_profiles_dir=repo / "terminal_data" / "MQL5" / "Profiles" / "Tester",
            config_dir=repo / "terminal_data" / "config",
            output_root=repo / "output",
         )
         fake_paths.terminal_exe.parent.mkdir(parents=True, exist_ok=True)
         fake_paths.terminal_data_path.mkdir(parents=True, exist_ok=True)
         fake_paths.tester_profiles_dir.mkdir(parents=True, exist_ok=True)
         fake_paths.config_dir.mkdir(parents=True, exist_ok=True)
         fake_paths.output_root.mkdir(parents=True, exist_ok=True)
         fake_paths.terminal_exe.write_text("terminal", encoding="ascii")
         fake_paths.metaeditor_exe.write_text("metaeditor", encoding="ascii")

         original_repo_root = runner.repo_root
         try:
            runner.repo_root = lambda: repo
            result = phase5.run_phase5(
               phase5_spec_path,
               stage="stage1",
               cycle_ids=("wf001_202508",),
               window_phase="report",
               output_root=fake_paths.output_root,
               runner_paths=fake_paths,
               runner_module=FakePhase5RunnerModule,
            )
         finally:
            runner.repo_root = original_repo_root

         run_rows_path = Path(result["exports"]["phase5_run_rows_path"])
         summary_path = Path(result["exports"]["phase5_summary_path"])
         self.assertTrue(run_rows_path.exists())
         self.assertTrue(summary_path.exists())

         run_rows = [
            json.loads(line)
            for line in run_rows_path.read_text(encoding="utf-8").splitlines()
            if line.strip()
         ]
         self.assertTrue(run_rows)
         self.assertEqual(result["executed_runs"], 2)
         staged_runtime_paths = [
            path
            for call in FakePhase5RunnerModule.calls
            for path in call["staged_files"]
         ]
         normalized_staged_paths = [path.replace("\\", "/") for path in staged_runtime_paths]
         self.assertTrue(any("/qtable_" in path or path.endswith("/mr_qtable.bin") for path in normalized_staged_paths))
         self.assertTrue(any("/thresholds_" in path or path.endswith("/thresholds.json") for path in normalized_staged_paths))

         deterministic_row = next(
            row for row in run_rows
            if row["stage_token"] == "arch_mr_deterministic" and row["scenario_id"] == "baseline"
         )
         self.assertEqual(deterministic_row["rl_mode"], "enabled")
         self.assertEqual(deterministic_row["bandit_state_mode"], "disabled")
         self.assertTrue(deterministic_row["baseline_bundle_id"])
         self.assertTrue(deterministic_row["qtable_artifact_id"])
         self.assertTrue(deterministic_row["thresholds_artifact_id"])
         self.assertTrue(deterministic_row["effective_input_hash"])

         blocked_row = next(
            row for row in run_rows
            if row["stage_token"] == "arch_mr_bandit_frozen" and row["scenario_id"] == "baseline"
         )
         self.assertEqual(blocked_row["status"], "blocked")
         self.assertEqual(blocked_row["failure_reason"], "bandit_snapshot_not_ready")
         self.assertFalse(blocked_row["bandit_ready"])

         summary = json.loads(summary_path.read_text(encoding="utf-8"))
         self.assertEqual(summary["phase_totals"]["blocked_rows"], 2)
         self.assertEqual(summary["best_rows"]["by_stage"]["stage1"]["stage_token"], "arch_mr_deterministic")

   def test_run_phase5_forwards_timeout_seconds_to_runner_spec(self) -> None:
      FakePhase5RunnerModule.reset()
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo = Path(tmp_dir)
         phase5_spec_path = self.write_fixture_repo(repo, bandit_ready=True)
         fake_paths = runner.RunnerPaths(
            repo_root=repo,
            terminal_exe=repo / "terminal64.exe",
            metaeditor_exe=repo / "metaeditor64.exe",
            terminal_data_path=repo / "terminal_data",
            tester_root=repo / "tester_root",
            tester_profiles_dir=repo / "terminal_data" / "MQL5" / "Profiles" / "Tester",
            config_dir=repo / "terminal_data" / "config",
            output_root=repo / "output",
         )
         fake_paths.terminal_exe.parent.mkdir(parents=True, exist_ok=True)
         fake_paths.terminal_data_path.mkdir(parents=True, exist_ok=True)
         fake_paths.tester_profiles_dir.mkdir(parents=True, exist_ok=True)
         fake_paths.config_dir.mkdir(parents=True, exist_ok=True)
         fake_paths.output_root.mkdir(parents=True, exist_ok=True)
         fake_paths.terminal_exe.write_text("terminal", encoding="ascii")
         fake_paths.metaeditor_exe.write_text("metaeditor", encoding="ascii")

         original_repo_root = runner.repo_root
         try:
            runner.repo_root = lambda: repo
            phase5.run_phase5(
               phase5_spec_path,
               stage="stage1",
               cycle_ids=("wf001_202508",),
               window_phase="report",
               timeout_seconds=1800,
               output_root=fake_paths.output_root,
               runner_paths=fake_paths,
               runner_module=FakePhase5RunnerModule,
            )
         finally:
            runner.repo_root = original_repo_root

         executed_timeouts = {
            int(call["timeout_seconds"])
            for call in FakePhase5RunnerModule.calls
            if call["name"].startswith("phase5_smoke__stage1__")
         }
         self.assertEqual(executed_timeouts, {1800})


if __name__ == "__main__":
   unittest.main()
