import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import fundingpips_hpo as hpo
from tools import fundingpips_mt5_runner as runner
from tools import fundingpips_phase4 as phase4


class FakePhase4RunnerModule:
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
      cache_key = f"phase4{cls.call_count:04d}"
      run_dir = paths.output_root / f"{runner.safe_name(spec.name)}__{cache_key}"
      collected_dir = run_dir / "collected"
      logs_dir = collected_dir / "logs" / "Agent-127.0.0.1-3000" / "MQL5" / "Files" / "RPEA" / "logs"
      collected_dir.mkdir(parents=True, exist_ok=True)
      logs_dir.mkdir(parents=True, exist_ok=True)

      mr_risk = float(spec.set_overrides.get("MR_RiskPct_Default", 1.0))
      start_hour = int(spec.set_overrides.get("StartHourLO", 5))
      search_window = ".2025.06." in spec.name or ".2025.07." in spec.name
      report_bonus = 0.10 if "report" in spec.name else 0.0
      final_return_pct = round(1.20 + ((mr_risk - 1.0) * 2.0) - ((start_hour - 5) * 0.12) + report_bonus, 6)
      max_daily_dd_pct = round(0.40 + ((mr_risk - 1.0) * 0.20) + ((start_hour - 5) * 0.05), 6)
      max_overall_dd_pct = round(0.08 + ((mr_risk - 1.0) * 0.05), 6)
      trades_total = 18 if search_window else 9

      manifest_path = run_dir / "run_manifest.json"
      summary_path = collected_dir / runner.SUMMARY_FILENAME
      daily_path = collected_dir / runner.DAILY_FILENAME
      report_path = collected_dir / f"{spec.report_stem}_{cache_key}.xml.htm"
      decision_log_path = logs_dir / "decisions_20250801.csv"
      event_log_path = logs_dir / "events_20250801.csv"

      manifest_path.write_text(
         json.dumps({"spec": runner.spec_to_manifest_dict(spec)}, indent=2, sort_keys=True),
         encoding="ascii",
      )
      summary_path.write_text(
         json.dumps(
            {
               "pass": False,
               "pass_days_traded": 0,
               "final_return_pct": final_return_pct,
               "max_daily_dd_pct": max_daily_dd_pct,
               "max_overall_dd_pct": max_overall_dd_pct,
               "any_daily_breach": False,
               "overall_breach": False,
               "trades_total": trades_total,
               "days_traded": 6,
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
               "2025-08-04,2025-08-04T00:00:00Z,2025-08-04T00:00:00Z,10040.00,10040.00,10040.00,9638.40,10020.00,10090.00,20.00,0.200000,false",
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
      decision_log_path.write_text(
         "\n".join(
            [
               "date,time,event,component,level,message,fields_json",
               '2025-08-01,01:00:00,DECISION,MetaPolicy,1,EVAL,{"symbol":"XAUUSD","choice":"MR","gating_reason":"RULE_2_MR_LOCK","regime":"TRENDING"}',
               '2025-08-01,01:30:00,DECISION,MetaPolicy,1,EVAL,{"symbol":"XAUUSD","choice":"MR","gating_reason":"RULE_2_MR_LOCK","regime":"TRENDING"}',
               '2025-08-04,01:00:00,DECISION,MetaPolicy,1,EVAL,{"symbol":"XAUUSD","choice":"MR","gating_reason":"RULE_4_BWISC_REPLACE","regime":"RANGING"}',
            ]
         )
         + "\n",
         encoding="utf-8",
      )
      event_log_path.write_text(
         "\n".join(
            [
               "date,time,event,component,level,message,fields_json",
               "2025-08-01,01:00:00,SCHED_TICK,Scheduler,1,heartbeat,{}",
            ]
         )
         + "\n",
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
         "decision_logs": [str(decision_log_path)],
         "event_logs": [str(event_log_path)],
      }


class FundingPipsPhase4Tests(unittest.TestCase):
   def test_load_phase4_spec_and_build_cycles(self) -> None:
      spec = phase4.load_phase4_spec(Path("tools/fundingpips_studies/phase4_anchor_wfo_stress.json"))
      cycles = phase4.build_walk_forward_cycles(spec)

      self.assertEqual(spec.name, "phase4_anchor_wfo_stress")
      self.assertEqual(len(spec.primary_candidates), 2)
      self.assertEqual(len(spec.neighbor_candidates), 10)
      self.assertEqual(len(spec.scenarios), 5)
      self.assertEqual([cycle.id for cycle in cycles], ["wf001_202508", "wf002_202509", "wf003_202510"])
      self.assertEqual(cycles[0].search_from_date.isoformat(), "2025-06-03")
      self.assertEqual(cycles[0].report_to_date.isoformat(), "2025-08-29")
      self.assertEqual(cycles[1].report_to_date.isoformat(), "2025-09-30")
      self.assertEqual(cycles[2].report_to_date.isoformat(), "2025-10-31")

   def test_apply_synthetic_stress_reprices_return_and_drawdown(self) -> None:
      scenario = phase4.Phase4ScenarioSpec(
         id="moderate_delay_commission",
         severity="moderate",
         weight=0.25,
         set_overrides={},
         execution_mode=None,
         source_scenario_id="baseline",
         stress=phase4.SyntheticStressSpec(
            delay_return_penalty_pct_per_trade=0.003,
            commission_money_per_trade=0.5,
            daily_dd_multiplier=1.1,
            overall_dd_multiplier=1.1,
         ),
      )
      source_record = {
         "summary_metrics": {
            "final_return_pct": 1.5,
            "max_daily_dd_pct": 0.5,
            "max_overall_dd_pct": 0.1,
            "pass_days_traded": 0,
            "trades_total": 10,
            "days_traded": 5,
            "min_trade_days_required": 3,
            "observed_server_days": 10,
         },
         "window_trading_days": 22,
         "initial_baseline": 10000.0,
         "scenario_id": "baseline",
      }
      rules = hpo.RulesProfile("fundingpips_1step_eval", 10.0, 4.0, 6.0, 3)

      stressed = phase4.apply_synthetic_stress(source_record, scenario, rules)

      self.assertEqual(stressed["source_scenario_id"], "baseline")
      self.assertLess(stressed["summary_metrics"]["final_return_pct"], 1.5)
      self.assertGreater(stressed["summary_metrics"]["max_daily_dd_pct"], 0.5)
      self.assertGreater(stressed["summary_metrics"]["max_overall_dd_pct"], 0.1)

   def test_run_phase4_generates_summary_artifacts(self) -> None:
      FakePhase4RunnerModule.reset()
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo = Path(tmp_dir)
         rules_dir = repo / "tools" / "fundingpips_rules_profiles"
         studies_dir = repo / "tools" / "fundingpips_studies"
         tests_dir = repo / "Tests" / "RPEA"
         rules_dir.mkdir(parents=True)
         studies_dir.mkdir(parents=True)
         tests_dir.mkdir(parents=True)

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
         base_set_path.write_text("RiskPct=2.0\nMR_RiskPct_Default=1.0\nORMinutes=45\nCutoffHour=23\nStartHourLO=5\nSpreadMultATR=0.005\n", encoding="ascii")

         spec_path = studies_dir / "phase4_anchor_wfo_stress.json"
         spec_path.write_text(
            json.dumps(
               {
                  "name": "phase4_anchor_wfo_stress",
                  "rules_profile": "fundingpips_1step_eval",
                  "symbol": "EURUSD",
                  "period": "M1",
                  "from_date": "2025-06-03",
                  "to_date": "2025-09-03",
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
                     },
                     {
                        "id": "anchor_mr105",
                        "set_overrides": {
                           "RiskPct": 2.0,
                           "MR_RiskPct_Default": 1.05,
                           "ORMinutes": 45,
                           "CutoffHour": 23,
                           "StartHourLO": 5,
                           "SpreadMultATR": 0.005,
                        },
                     },
                  ],
                  "scenarios": [
                     {
                        "id": "baseline",
                        "severity": "baseline",
                        "weight": 1.0,
                        "set_overrides": {},
                     },
                     {
                        "id": "mild_spread_slippage",
                        "severity": "mild",
                        "weight": 0.5,
                        "source_scenario_id": "baseline",
                        "synthetic_stress": {
                           "spread_return_penalty_pct_per_trade": 0.0025,
                           "slippage_return_penalty_pct_per_trade": 0.0015,
                           "daily_dd_multiplier": 1.1,
                           "overall_dd_multiplier": 1.1,
                        },
                     },
                     {
                        "id": "moderate_spread_slippage",
                        "severity": "moderate",
                        "weight": 0.25,
                        "source_scenario_id": "baseline",
                        "synthetic_stress": {
                           "spread_return_penalty_pct_per_trade": 0.005,
                           "slippage_return_penalty_pct_per_trade": 0.003,
                           "daily_dd_multiplier": 1.25,
                           "overall_dd_multiplier": 1.25,
                        },
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
                           "overall_dd_multiplier": 1.05,
                        },
                     },
                     {
                        "id": "moderate_delay_commission",
                        "severity": "moderate",
                        "weight": 0.25,
                        "source_scenario_id": "baseline",
                        "synthetic_stress": {
                           "delay_return_penalty_pct_per_trade": 0.003,
                           "commission_money_per_trade": 0.5,
                           "daily_dd_multiplier": 1.1,
                           "overall_dd_multiplier": 1.1,
                        },
                     },
                  ],
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

         with mock.patch("tools.fundingpips_hpo.repo_root", return_value=repo), mock.patch(
            "tools.fundingpips_phase4.repo_root",
            return_value=repo,
         ):
            result = phase4.run_phase4(
               spec_path,
               cycle_ids=("wf001_202508",),
               candidate_scope="primary",
               window_phase="both",
               runner_paths=runner_paths,
               runner_module=FakePhase4RunnerModule,
            )
            exported = result["exports"]
            summary = json.loads(Path(exported["phase4_summary_path"]).read_text(encoding="utf-8"))
            actual_record = json.loads(
               (
                  repo
                  / ".tmp"
                  / "fundingpips_phase4"
                  / "phase4_anchor_wfo_stress"
                  / "actual_runs"
                  / "wf001_202508"
                  / "report"
                  / "anchor_mr105"
                  / "baseline.json"
               ).read_text(encoding="utf-8")
            )

      self.assertEqual(result["executed_runs"], 4)
      self.assertEqual(exported["actual_run_record_count"], 4)
      self.assertEqual(exported["scenario_record_count"], 20)
      self.assertTrue(summary["gate_signals"]["mild_report_noncollapse"])
      self.assertTrue(summary["gate_signals"]["moderate_report_noncollapse"])
      self.assertEqual(summary["cycle_summaries"][0]["search_selected_candidate"], "anchor_mr105")
      self.assertEqual(actual_record["regime_summary"]["preferred_symbol"], "XAUUSD")
      self.assertEqual(actual_record["regime_summary"]["dominant_regime"], "TRENDING")


if __name__ == "__main__":
   unittest.main()
