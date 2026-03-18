import json
import shutil
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from tools import fundingpips_hpo as hpo
from tools import fundingpips_mt5_runner as runner


class FakeRunnerModule:
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
      cls.calls.append({"name": spec.name, **kwargs})
      cache_key = f"fake{cls.call_count:04d}"
      run_dir = paths.output_root / f"{runner.safe_name(spec.name)}__{cache_key}"
      collected_dir = run_dir / "collected"
      collected_dir.mkdir(parents=True, exist_ok=True)

      risk_pct = float(spec.set_overrides.get("RiskPct", 1.5))
      mr_risk_pct = float(spec.set_overrides.get("MR_RiskPct_Default", 0.9))
      or_minutes = int(spec.set_overrides.get("ORMinutes", 30))
      start_hour = int(spec.set_overrides.get("StartHourLO", 1))
      scenario_penalty = 1.0 if spec.scenario == "compliance_restore" else 0.0

      final_return_pct = round(
         ((2.25 - risk_pct) * 6.0)
         + ((1.35 - mr_risk_pct) * 5.0)
         + ((45 - or_minutes) * 0.08)
         + ((8 - start_hour) * 0.10)
         - scenario_penalty,
         6,
      )
      max_daily_dd_pct = round(max(0.25, risk_pct * 1.2 + scenario_penalty * 0.4), 6)
      max_overall_dd_pct = round(max(0.35, mr_risk_pct * 2.2 + scenario_penalty * 0.5), 6)
      daily_breach = max_daily_dd_pct >= 4.0
      overall_breach = max_overall_dd_pct >= 6.0
      trades_total = 0 if or_minutes == 45 else 2
      pass_flag = final_return_pct >= 10.0 and not daily_breach and not overall_breach
      pass_days = 3 if pass_flag else 0

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
               "pass": pass_flag,
               "pass_days_traded": pass_days,
               "final_return_pct": final_return_pct,
               "max_daily_dd_pct": max_daily_dd_pct,
               "max_overall_dd_pct": max_overall_dd_pct,
               "any_daily_breach": daily_breach,
               "overall_breach": overall_breach,
               "trades_total": trades_total,
               "days_traded": 3,
               "min_trade_days_required": 3,
               "observed_server_days": 10,
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
               "2025-06-03,2025-06-03T00:00:00Z,2025-06-03T00:00:00Z,10000.00,10000.00,10000.00,9600.00,9950.00,10050.00,50.00,0.500000,false",
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
      }


class FailingRunnerModule:
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
      cls.calls.append({"name": spec.name, **kwargs})
      raise RuntimeError("Synthetic MT5 artifact timeout")


class FundingPipsPhase2Tests(unittest.TestCase):
   def test_render_set_with_overrides_updates_and_appends_missing_keys(self) -> None:
      base_text = "\n".join(
         [
            "; header",
            "RiskPct=1.5||0.5||0.1||2.0||Y",
            "EnableMR=0",
            "",
         ]
      )

      rendered = hpo.render_set_with_overrides(
         base_text,
         {
            "RiskPct": 1.25,
            "EnableMR": 1,
            "EnableMRBypassOnRLUnloaded": 1,
         },
      )

      self.assertIn("RiskPct=1.25", rendered)
      self.assertIn("EnableMR=1", rendered)
      self.assertIn("EnableMRBypassOnRLUnloaded=1", rendered)
      self.assertNotIn("||", rendered)

   def test_load_rules_profile_and_study_spec(self) -> None:
      rules = hpo.load_rules_profile(Path("tools/fundingpips_rules_profiles/fundingpips_1step_eval.json"))
      spec = hpo.load_study_spec(Path("tools/fundingpips_studies/phase2_baseline.json"))

      self.assertEqual(rules.id, "fundingpips_1step_eval")
      self.assertEqual(rules.daily_loss_cap_pct, 4.0)
      self.assertEqual(spec.name, "phase2_baseline")
      self.assertEqual(spec.rules_profile, rules.id)
      self.assertEqual(spec.n_trials, 4)
      self.assertEqual(len(spec.scenarios), 2)
      self.assertEqual(spec.search_space[0].name, "RiskPct")

   def test_build_windows_for_phase2_baseline(self) -> None:
      spec = hpo.load_study_spec(Path("tools/fundingpips_studies/phase2_baseline.json"))
      windows = hpo.build_windows(spec)

      self.assertEqual(len(windows), 12)
      self.assertEqual(windows[0].id, "w001_20250603_20250616")
      self.assertEqual(windows[0].from_date.isoformat(), "2025-06-03")
      self.assertEqual(windows[-1].id, "w012_20250819_20250901")
      self.assertEqual(windows[-1].to_date.isoformat(), "2025-09-01")

   def test_parse_mt5_report_metrics_supports_xml_and_xml_htm(self) -> None:
      report_text = "\n".join(
         [
            "<html><body><table>",
            "<tr><td>Total Net Profit:</td><td><b>123.45</b></td></tr>",
            "<tr><td>Profit Factor:</td><td><b>1.23</b></td></tr>",
            "<tr><td>Recovery Factor:</td><td><b>2.34</b></td></tr>",
            "<tr><td>Sharpe Ratio:</td><td><b>0.56</b></td></tr>",
            "<tr><td>Total Trades:</td><td><b>7</b></td></tr>",
            "</table></body></html>",
         ]
      )

      with tempfile.TemporaryDirectory() as tmp_dir:
         root = Path(tmp_dir)
         xml_path = root / "report.xml"
         htm_path = root / "report.xml.htm"
         xml_path.write_text(report_text, encoding="utf-8")
         htm_path.write_text(report_text, encoding="utf-8")

         xml_metrics = hpo.parse_mt5_report_metrics(xml_path)
         htm_metrics = hpo.parse_mt5_report_metrics(htm_path)

      self.assertEqual(xml_metrics["total_net_profit"], 123.45)
      self.assertEqual(xml_metrics["profit_factor"], 1.23)
      self.assertEqual(xml_metrics["recovery_factor"], 2.34)
      self.assertEqual(htm_metrics["sharpe_ratio"], 0.56)
      self.assertEqual(htm_metrics["total_trades"], 7)

   def test_normalize_run_result_computes_phase2_metrics(self) -> None:
      rules = hpo.RulesProfile(
         id="fundingpips_1step_eval",
         target_profit_pct=10.0,
         daily_loss_cap_pct=4.0,
         overall_loss_cap_pct=6.0,
         min_trade_days=3,
      )
      window = hpo.StudyWindow(
         id="w001_20250603_20250616",
         from_date=hpo.parse_iso_date("2025-06-03"),
         to_date=hpo.parse_iso_date("2025-06-16"),
      )
      scenario = hpo.ScenarioSpec(id="baseline", weight=0.75, set_overrides={})

      with tempfile.TemporaryDirectory() as tmp_dir:
         root = Path(tmp_dir)
         manifest_path = root / "run_manifest.json"
         summary_path = root / "fundingpips_eval_summary.json"
         daily_path = root / "fundingpips_eval_daily.csv"
         report_path = root / "report.xml.htm"

         manifest_path.write_text(json.dumps({"spec": {"name": "probe"}}), encoding="ascii")
         summary_path.write_text(
            json.dumps(
               {
                  "pass": True,
                  "pass_days_traded": 4,
                  "final_return_pct": 8.0,
                  "max_daily_dd_pct": 1.5,
                  "max_overall_dd_pct": 2.5,
                  "any_daily_breach": False,
                  "overall_breach": False,
                  "trades_total": 3,
                  "days_traded": 4,
                  "min_trade_days_required": 3,
                  "observed_server_days": 10,
               }
            ),
            encoding="ascii",
         )
         daily_path.write_text(
            "\n".join(
               [
                  "server_date,server_midnight_ts,baseline_capture_time,baseline_equity,baseline_balance,baseline_used,daily_floor,min_equity,end_equity,max_daily_dd_money,max_daily_dd_pct,daily_breach",
                  "2025-06-03,2025-06-03T00:00:00Z,2025-06-03T00:00:00Z,10000.00,10000.00,10000.00,9600.00,9850.00,10080.00,150.00,1.500000,false",
               ]
            )
            + "\n",
            encoding="utf-8",
         )
         report_path.write_text(
            "<tr><td>Total Net Profit:</td><td><b>123.00</b></td></tr>",
            encoding="utf-8",
         )

         run_record = hpo.normalize_run_result(
            study_name="phase2_baseline",
            trial_number=0,
            window=window,
            scenario=scenario,
            result={
               "status": "completed",
               "cache_key": "abc123",
               "run_dir": str(root),
               "manifest_path": str(manifest_path),
               "summary_path": str(summary_path),
               "daily_path": str(daily_path),
               "report_path": str(report_path),
            },
            rules_profile=rules,
            window_length_trading_days=10,
         )

      self.assertTrue(run_record["pass_flag"])
      self.assertFalse(run_record["breach_flag"])
      self.assertAlmostEqual(run_record["progress_ratio"], 0.8)
      self.assertAlmostEqual(run_record["daily_slack_ratio"], 0.625)
      self.assertAlmostEqual(run_record["overall_slack_ratio"], (6.0 - 2.5) / 6.0)
      self.assertAlmostEqual(run_record["speed_ratio"], 1.0 - ((4 - 3) / 7.0))

   def test_aggregate_trial_runs_uses_weighted_means(self) -> None:
      run_records = [
         {
            "scenario_weight": 0.75,
            "pass_flag": 1.0,
            "breach_flag": 0.0,
            "zero_trade_flag": 0.0,
            "progress_ratio": 0.8,
            "daily_slack_ratio": 0.6,
            "overall_slack_ratio": 0.7,
            "speed_ratio": 0.5,
            "reset_exposure_ratio": 0.2,
            "status": "cache_hit",
            "valid": True,
         },
         {
            "scenario_weight": 0.25,
            "pass_flag": 0.0,
            "breach_flag": 1.0,
            "zero_trade_flag": 1.0,
            "progress_ratio": -0.2,
            "daily_slack_ratio": 0.1,
            "overall_slack_ratio": 0.2,
            "speed_ratio": 0.0,
            "reset_exposure_ratio": 0.7,
            "status": "completed",
            "valid": True,
         },
      ]

      aggregate, objective = hpo.aggregate_trial_runs(run_records, scenario_count=2, window_count=1)

      self.assertTrue(aggregate["valid"])
      self.assertAlmostEqual(aggregate["pass_rate"], 0.75)
      self.assertAlmostEqual(aggregate["breach_rate"], 0.25)
      self.assertAlmostEqual(aggregate["cache_hit_rate"], 0.75)
      self.assertGreater(objective, 0.0)

   def test_objective_prefers_pass_and_penalizes_breach_zero_trades(self) -> None:
      pass_record = {
         "scenario_weight": 1.0,
         "pass_flag": 1.0,
         "breach_flag": 0.0,
         "zero_trade_flag": 0.0,
         "progress_ratio": 1.0,
         "daily_slack_ratio": 0.8,
         "overall_slack_ratio": 0.8,
         "speed_ratio": 0.8,
         "reset_exposure_ratio": 0.2,
         "status": "completed",
         "valid": True,
      }
      fail_record = {
         "scenario_weight": 1.0,
         "pass_flag": 0.0,
         "breach_flag": 1.0,
         "zero_trade_flag": 1.0,
         "progress_ratio": 0.2,
         "daily_slack_ratio": 0.2,
         "overall_slack_ratio": 0.2,
         "speed_ratio": 0.0,
         "reset_exposure_ratio": 0.8,
         "status": "completed",
         "valid": True,
      }

      pass_objective = hpo.aggregate_trial_runs([pass_record], 1, 1)[1]
      fail_objective = hpo.aggregate_trial_runs([fail_record], 1, 1)[1]

      self.assertGreater(pass_objective, fail_objective)

   def test_speed_ratio_clamps_to_zero_when_pass_days_exceed_window(self) -> None:
      rules = hpo.RulesProfile("fundingpips_1step_eval", 10.0, 4.0, 6.0, 3)
      window = hpo.StudyWindow("w001_20250603_20250616", hpo.parse_iso_date("2025-06-03"), hpo.parse_iso_date("2025-06-16"))
      scenario = hpo.ScenarioSpec("baseline", 1.0, {})

      with tempfile.TemporaryDirectory() as tmp_dir:
         root = Path(tmp_dir)
         (root / "run_manifest.json").write_text("{}", encoding="ascii")
         (root / "fundingpips_eval_summary.json").write_text(
            json.dumps(
               {
                  "pass": True,
                  "pass_days_traded": 20,
                  "final_return_pct": 11.0,
                  "max_daily_dd_pct": 1.0,
                  "max_overall_dd_pct": 1.0,
                  "any_daily_breach": False,
                  "overall_breach": False,
                  "trades_total": 2,
               }
            ),
            encoding="ascii",
         )
         (root / "fundingpips_eval_daily.csv").write_text(
            "server_date,server_midnight_ts,baseline_capture_time,baseline_equity,baseline_balance,baseline_used,daily_floor,min_equity,end_equity,max_daily_dd_money,max_daily_dd_pct,daily_breach\n",
            encoding="utf-8",
         )

         run_record = hpo.normalize_run_result(
            study_name="phase2_baseline",
            trial_number=0,
            window=window,
            scenario=scenario,
            result={
               "status": "completed",
               "cache_key": "abc",
               "run_dir": str(root),
               "manifest_path": str(root / "run_manifest.json"),
               "summary_path": str(root / "fundingpips_eval_summary.json"),
               "daily_path": str(root / "fundingpips_eval_daily.csv"),
               "report_path": None,
            },
            rules_profile=rules,
            window_length_trading_days=10,
         )

      self.assertEqual(run_record["speed_ratio"], 0.0)

   def test_select_best_valid_trial_ignores_invalid_rows(self) -> None:
      trial_rows = [
         {"trial_number": 0, "objective": hpo.INVALID_OBJECTIVE, "aggregate_metrics": {"valid": False}},
         {"trial_number": 1, "objective": 42.5, "aggregate_metrics": {"valid": True}},
      ]

      best_trial = hpo.select_best_valid_trial(trial_rows)

      self.assertIsNotNone(best_trial)
      self.assertEqual(best_trial["trial_number"], 1)
      self.assertIsNone(
         hpo.select_best_valid_trial(
            [{"trial_number": 9, "objective": hpo.INVALID_OBJECTIVE, "aggregate_metrics": {"valid": False}}]
         )
      )

   def test_export_study_regenerates_flat_files_from_sqlite(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo = Path(tmp_dir)
         paths = hpo.build_study_paths("export_case", repo=repo)
         hpo.ensure_directory(paths.study_dir)
         hpo.ensure_custom_tables(paths.sqlite_path)
         hpo.write_json_file(paths.manifest_path, {"study_name": "export_case"})

         created_at = hpo.utc_now_iso()
         hpo.upsert_trial_result(
            paths.sqlite_path,
            study_name="export_case",
            trial_number=0,
            state="COMPLETE",
            objective=12.5,
            params={"RiskPct": 1.25},
            aggregate_metrics={
               "valid": True,
               "run_count": 24,
               "window_count": 12,
               "scenario_count": 2,
               "pass_rate": 0.0,
               "breach_rate": 0.0,
               "zero_trade_rate": 0.0,
               "progress_ratio_mean": 0.1,
               "daily_slack_mean": 0.8,
               "overall_slack_mean": 0.8,
               "speed_mean": 0.0,
               "reset_exposure_mean": 0.2,
               "cache_hit_rate": 0.0,
               "failure_reason": None,
            },
            created_at_utc=created_at,
         )
         hpo.upsert_run_record(
            paths.sqlite_path,
            {
               "study_name": "export_case",
               "trial_number": 0,
               "window_id": "w001",
               "scenario_id": "baseline",
               "cache_key": "abc",
               "run_dir": str(paths.study_dir / "run"),
               "summary_path": "summary.json",
               "daily_path": "daily.csv",
               "report_path": "report.htm",
               "valid": True,
               "status": "completed",
            },
            created_at_utc=created_at,
         )
         exports = hpo.export_study_artifacts(paths, "export_case")
         Path(exports["trial_results_csv"]).unlink()
         Path(exports["run_records_jsonl"]).unlink()

         regenerated = hpo.export_study(paths.study_dir)
         trial_csv_exists = Path(regenerated["exports"]["trial_results_csv"]).exists()
         run_records_exists = Path(regenerated["exports"]["run_records_jsonl"]).exists()
         best_summary_exists = Path(regenerated["exports"]["best_trial_summary"]).exists()

      self.assertTrue(trial_csv_exists)
      self.assertTrue(run_records_exists)
      self.assertTrue(best_summary_exists)

   def test_export_study_uses_caller_provided_study_directory(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo = Path(tmp_dir)
         paths = hpo.build_study_paths("export_case", repo=repo)
         hpo.ensure_directory(paths.study_dir)
         hpo.ensure_custom_tables(paths.sqlite_path)
         hpo.write_json_file(paths.manifest_path, {"study_name": "export_case"})

         created_at = hpo.utc_now_iso()
         hpo.upsert_trial_result(
            paths.sqlite_path,
            study_name="export_case",
            trial_number=0,
            state="COMPLETE",
            objective=12.5,
            params={"RiskPct": 1.25},
            aggregate_metrics={
               "valid": True,
               "run_count": 24,
               "window_count": 12,
               "scenario_count": 2,
               "pass_rate": 0.0,
               "breach_rate": 0.0,
               "zero_trade_rate": 0.0,
               "progress_ratio_mean": 0.1,
               "daily_slack_mean": 0.8,
               "overall_slack_mean": 0.8,
               "speed_mean": 0.0,
               "reset_exposure_mean": 0.2,
               "cache_hit_rate": 0.0,
               "failure_reason": None,
            },
            created_at_utc=created_at,
         )
         hpo.upsert_run_record(
            paths.sqlite_path,
            {
               "study_name": "export_case",
               "trial_number": 0,
               "window_id": "w001",
               "scenario_id": "baseline",
               "cache_key": "abc",
               "run_dir": str(paths.study_dir / "run"),
               "summary_path": "summary.json",
               "daily_path": "daily.csv",
               "report_path": "report.htm",
               "valid": True,
               "status": "completed",
            },
            created_at_utc=created_at,
         )

         relocated_study_dir = repo / "copied" / "export_case"
         relocated_study_dir.parent.mkdir(parents=True, exist_ok=True)
         shutil.move(str(paths.study_dir), str(relocated_study_dir))
         regenerated = hpo.export_study(relocated_study_dir)

         relocated_trial_csv = relocated_study_dir / "trial_results.csv"
         relocated_run_records = relocated_study_dir / "run_records.jsonl"
         relocated_best_summary = relocated_study_dir / "best_trial_summary.json"
         self.assertTrue(relocated_trial_csv.exists())
         self.assertTrue(relocated_run_records.exists())
         self.assertTrue(relocated_best_summary.exists())
         self.assertEqual(regenerated["study_dir"], str(relocated_study_dir.resolve()))
         self.assertEqual(
            regenerated["exports"]["trial_results_csv"],
            str(relocated_trial_csv.resolve()),
         )
         self.assertEqual(
            regenerated["exports"]["run_records_jsonl"],
            str(relocated_run_records.resolve()),
         )
         self.assertEqual(
            regenerated["exports"]["best_trial_summary"],
            str(relocated_best_summary.resolve()),
         )

   def test_run_study_resume_recovers_stale_running_trial(self) -> None:
      FakeRunnerModule.reset()

      def close_study_sessions(study_obj) -> None:
         storage_backend = getattr(study_obj, "_storage", None)
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

      with tempfile.TemporaryDirectory() as tmp_dir:
         repo = Path(tmp_dir)
         rules_dir = repo / "tools" / "fundingpips_rules_profiles"
         tests_dir = repo / "Tests" / "RPEA"
         rules_dir.mkdir(parents=True)
         tests_dir.mkdir(parents=True)

         rules_path = rules_dir / "fundingpips_1step_eval.json"
         rules_path.write_text(
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
         base_set_path.write_text("RiskPct=1.5\nMR_RiskPct_Default=0.9\nORMinutes=30\nCutoffHour=23\nStartHourLO=1\n", encoding="ascii")
         study_spec_path = repo / "phase2_baseline.json"
         study_spec_path.write_text(
            json.dumps(
               {
                  "name": "phase2_baseline",
                  "rules_profile": "fundingpips_1step_eval",
                  "symbol": "EURUSD",
                  "period": "M1",
                  "from_date": "2025-06-03",
                  "to_date": "2025-09-03",
                  "window_length_trading_days": 10,
                  "window_step_trading_days": 5,
                  "base_set": str(base_set_path),
                  "seed": 20260310,
                  "n_trials": 4,
                  "search_space": {
                     "RiskPct": {"type": "float", "low": 1.25, "high": 1.5, "step": 0.25},
                     "MR_RiskPct_Default": {"type": "float", "low": 0.75, "high": 0.90, "step": 0.15},
                     "ORMinutes": {"type": "categorical", "choices": [15, 30]},
                     "CutoffHour": {"type": "categorical", "choices": [20, 23]},
                     "StartHourLO": {"type": "categorical", "choices": [1, 3]}
                  },
                  "scenarios": [
                     {"id": "baseline", "weight": 0.75, "set_overrides": {}},
                     {"id": "compliance_restore", "weight": 0.25, "set_overrides": {"NewsBufferS": 300}}
                  ]
               }
            ),
            encoding="utf-8",
         )

         runner_paths = runner.RunnerPaths(
            repo_root=repo,
            terminal_exe=repo / "terminal64.exe",
            metaeditor_exe=repo / "metaeditor64.exe",
            terminal_data_path=repo / "terminal_data",
            tester_root=repo / "tester_root",
            tester_profiles_dir=repo / "tester_profiles",
            config_dir=repo / "config",
            output_root=repo / ".tmp" / "fundingpips_hpo_runs",
         )
         runner_paths.output_root.mkdir(parents=True)
         runner_paths.tester_profiles_dir.mkdir(parents=True)
         runner_paths.config_dir.mkdir(parents=True)
         runner_paths.terminal_data_path.mkdir(parents=True)
         runner_paths.tester_root.mkdir(parents=True)

         with mock.patch("tools.fundingpips_hpo.repo_root", return_value=repo):
            spec = hpo.load_study_spec(study_spec_path)
            study_paths = hpo.build_study_paths(spec.name, repo=repo)
            hpo.ensure_directory(study_paths.study_dir)
            hpo.ensure_custom_tables(study_paths.sqlite_path)

            optuna = hpo.require_optuna()
            stale_study = optuna.create_study(
               study_name=spec.name,
               direction="maximize",
               sampler=optuna.samplers.TPESampler(seed=spec.seed),
               storage=hpo.build_storage_url(study_paths.sqlite_path),
               load_if_exists=True,
            )
            stale_trial = stale_study.ask()
            hpo.upsert_run_record(
               study_paths.sqlite_path,
               {
                  "study_name": spec.name,
                  "trial_number": stale_trial.number,
                  "window_id": "w001_20250603_20250616",
                  "scenario_id": "baseline",
                  "cache_key": "partial",
                  "run_dir": str(study_paths.study_dir / "partial"),
                  "summary_path": "summary.json",
                  "daily_path": "daily.csv",
                  "report_path": "report.htm",
                  "valid": True,
                  "status": "completed",
               },
               created_at_utc=hpo.utc_now_iso(),
            )
            close_study_sessions(stale_study)

            result = hpo.run_study(
               study_spec_path,
               n_trials_override=1,
               resume=True,
               runner_paths=runner_paths,
               runner_module=FakeRunnerModule,
            )
            trial_rows = [hpo.decode_trial_row(row) for row in hpo.read_trial_rows(study_paths.sqlite_path, "phase2_baseline")]
            run_rows = hpo.read_run_rows(study_paths.sqlite_path, "phase2_baseline")
            reloaded_study = optuna.load_study(
               study_name=spec.name,
               storage=hpo.build_storage_url(study_paths.sqlite_path),
            )
            trial_states = [trial.state.name for trial in reloaded_study.trials]
            close_study_sessions(reloaded_study)

      self.assertEqual(result["recovered_stale_trials"], 1)
      self.assertEqual(result["completed_trials"], 1)
      self.assertEqual([row["state"] for row in trial_rows], ["FAIL", "COMPLETE"])
      self.assertIn("Recovered stale RUNNING trial", trial_rows[0]["aggregate_metrics"]["failure_reason"])
      self.assertEqual(trial_states, ["FAIL", "COMPLETE"])
      self.assertEqual(len(run_rows), 25)
      self.assertEqual(FakeRunnerModule.call_count, 24)

   def test_run_study_resumes_without_duplicate_trials(self) -> None:
      FakeRunnerModule.reset()
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo = Path(tmp_dir)
         rules_dir = repo / "tools" / "fundingpips_rules_profiles"
         tests_dir = repo / "Tests" / "RPEA"
         rules_dir.mkdir(parents=True)
         tests_dir.mkdir(parents=True)

         rules_path = rules_dir / "fundingpips_1step_eval.json"
         rules_path.write_text(
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
         base_set_path.write_text("RiskPct=1.5\nMR_RiskPct_Default=0.9\nORMinutes=30\nCutoffHour=23\nStartHourLO=1\n", encoding="ascii")
         study_spec_path = repo / "phase2_baseline.json"
         study_spec_path.write_text(
            json.dumps(
               {
                  "name": "phase2_baseline",
                  "rules_profile": "fundingpips_1step_eval",
                  "symbol": "EURUSD",
                  "period": "M1",
                  "from_date": "2025-06-03",
                  "to_date": "2025-09-03",
                  "window_length_trading_days": 10,
                  "window_step_trading_days": 5,
                  "base_set": str(base_set_path),
                  "seed": 20260310,
                  "n_trials": 4,
                  "search_space": {
                     "RiskPct": {"type": "float", "low": 1.25, "high": 1.5, "step": 0.25},
                     "MR_RiskPct_Default": {"type": "float", "low": 0.75, "high": 0.90, "step": 0.15},
                     "ORMinutes": {"type": "categorical", "choices": [15, 30]},
                     "CutoffHour": {"type": "categorical", "choices": [20, 23]},
                     "StartHourLO": {"type": "categorical", "choices": [1, 3]}
                  },
                  "scenarios": [
                     {"id": "baseline", "weight": 0.75, "set_overrides": {}},
                     {"id": "compliance_restore", "weight": 0.25, "set_overrides": {"NewsBufferS": 300}}
                  ]
               }
            ),
            encoding="utf-8",
         )

         runner_paths = runner.RunnerPaths(
            repo_root=repo,
            terminal_exe=repo / "terminal64.exe",
            metaeditor_exe=repo / "metaeditor64.exe",
            terminal_data_path=repo / "terminal_data",
            tester_root=repo / "tester_root",
            tester_profiles_dir=repo / "tester_profiles",
            config_dir=repo / "config",
            output_root=repo / ".tmp" / "fundingpips_hpo_runs",
         )
         runner_paths.output_root.mkdir(parents=True)
         runner_paths.tester_profiles_dir.mkdir(parents=True)
         runner_paths.config_dir.mkdir(parents=True)
         runner_paths.terminal_data_path.mkdir(parents=True)
         runner_paths.tester_root.mkdir(parents=True)

         with mock.patch("tools.fundingpips_hpo.repo_root", return_value=repo):
            first = hpo.run_study(
               study_spec_path,
               n_trials_override=2,
               resume=False,
               runner_paths=runner_paths,
               runner_module=FakeRunnerModule,
            )
            second = hpo.run_study(
               study_spec_path,
               n_trials_override=4,
               resume=True,
               runner_paths=runner_paths,
               runner_module=FakeRunnerModule,
            )
            study_paths = hpo.build_study_paths("phase2_baseline", repo=repo)
            trial_rows = hpo.read_trial_rows(study_paths.sqlite_path, "phase2_baseline")
            run_rows = hpo.read_run_rows(study_paths.sqlite_path, "phase2_baseline")

      self.assertEqual(first["completed_trials"], 2)
      self.assertEqual(second["completed_trials"], 4)
      self.assertEqual(len(trial_rows), 4)
      self.assertEqual(len(run_rows), 4 * 24)
      self.assertEqual(FakeRunnerModule.call_count, 4 * 24)

   def test_run_study_resume_replaces_failed_trial_without_counting_it_complete(self) -> None:
      FakeRunnerModule.reset()
      FailingRunnerModule.reset()
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo = Path(tmp_dir)
         rules_dir = repo / "tools" / "fundingpips_rules_profiles"
         tests_dir = repo / "Tests" / "RPEA"
         rules_dir.mkdir(parents=True)
         tests_dir.mkdir(parents=True)

         rules_path = rules_dir / "fundingpips_1step_eval.json"
         rules_path.write_text(
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
         base_set_path.write_text("RiskPct=1.5\nMR_RiskPct_Default=0.9\nORMinutes=30\nCutoffHour=23\nStartHourLO=1\n", encoding="ascii")
         study_spec_path = repo / "phase2_baseline.json"
         study_spec_path.write_text(
            json.dumps(
               {
                  "name": "phase2_baseline",
                  "rules_profile": "fundingpips_1step_eval",
                  "symbol": "EURUSD",
                  "period": "M1",
                  "from_date": "2025-06-03",
                  "to_date": "2025-09-03",
                  "window_length_trading_days": 10,
                  "window_step_trading_days": 5,
                  "base_set": str(base_set_path),
                  "seed": 20260310,
                  "n_trials": 4,
                  "search_space": {
                     "RiskPct": {"type": "float", "low": 1.25, "high": 1.5, "step": 0.25},
                     "MR_RiskPct_Default": {"type": "float", "low": 0.75, "high": 0.90, "step": 0.15},
                     "ORMinutes": {"type": "categorical", "choices": [15, 30]},
                     "CutoffHour": {"type": "categorical", "choices": [20, 23]},
                     "StartHourLO": {"type": "categorical", "choices": [1, 3]}
                  },
                  "scenarios": [
                     {"id": "baseline", "weight": 0.75, "set_overrides": {}},
                     {"id": "compliance_restore", "weight": 0.25, "set_overrides": {"NewsBufferS": 300}}
                  ]
               }
            ),
            encoding="utf-8",
         )

         runner_paths = runner.RunnerPaths(
            repo_root=repo,
            terminal_exe=repo / "terminal64.exe",
            metaeditor_exe=repo / "metaeditor64.exe",
            terminal_data_path=repo / "terminal_data",
            tester_root=repo / "tester_root",
            tester_profiles_dir=repo / "tester_profiles",
            config_dir=repo / "config",
            output_root=repo / ".tmp" / "fundingpips_hpo_runs",
         )
         runner_paths.output_root.mkdir(parents=True)
         runner_paths.tester_profiles_dir.mkdir(parents=True)
         runner_paths.config_dir.mkdir(parents=True)
         runner_paths.terminal_data_path.mkdir(parents=True)
         runner_paths.tester_root.mkdir(parents=True)

         with mock.patch("tools.fundingpips_hpo.repo_root", return_value=repo):
            first = hpo.run_study(
               study_spec_path,
               n_trials_override=1,
               resume=False,
               runner_paths=runner_paths,
               runner_module=FailingRunnerModule,
            )
            second = hpo.run_study(
               study_spec_path,
               n_trials_override=1,
               resume=True,
               runner_paths=runner_paths,
               runner_module=FakeRunnerModule,
            )
            study_paths = hpo.build_study_paths("phase2_baseline", repo=repo)
            trial_rows = [hpo.decode_trial_row(row) for row in hpo.read_trial_rows(study_paths.sqlite_path, "phase2_baseline")]
            run_rows = hpo.read_run_rows(study_paths.sqlite_path, "phase2_baseline")

      self.assertEqual(first["completed_trials"], 0)
      self.assertEqual(second["completed_trials"], 1)
      self.assertEqual([row["state"] for row in trial_rows], ["FAIL", "COMPLETE"])
      self.assertIn("Synthetic MT5 artifact timeout", trial_rows[0]["aggregate_metrics"]["failure_reason"])
      self.assertEqual(len(run_rows), 24)
      self.assertEqual(FailingRunnerModule.call_count, 1)
      self.assertEqual(FakeRunnerModule.call_count, 24)


if __name__ == "__main__":
   unittest.main()
