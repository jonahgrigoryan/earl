import csv
import json
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

from tools import fundingpips_phase_a_research as phase_a


def make_decision_row(
   *,
   offset_seconds: int,
   component: str,
   message: str,
   fields: dict[str, object],
   symbol: str | None,
) -> phase_a.DecisionRow:
   ts = datetime(2025, 1, 1, 0, 0, 0) + timedelta(seconds=offset_seconds)
   return phase_a.DecisionRow(
      run_id="synthetic",
      baseline_role="synthetic",
      source_path=Path("synthetic.csv"),
      source_row=offset_seconds,
      ts=ts,
      ts_text=ts.strftime("%Y-%m-%dT%H:%M:%S"),
      component=component,
      message=message,
      level=1,
      fields=fields,
      symbol=symbol,
   )


class FundingPipsPhaseAGateIntervalTests(unittest.TestCase):
   def test_build_gate_intervals_collapses_streaks_and_splits_on_plan_capable_lineage(self) -> None:
      rows = [
         make_decision_row(
            offset_seconds=1,
            component="Liquidity",
            message="GATED",
            fields={"reason": "Spread too wide"},
            symbol="XAUUSD",
         ),
         make_decision_row(
            offset_seconds=5,
            component="Liquidity",
            message="GATED",
            fields={"reason": "Spread too wide"},
            symbol="XAUUSD",
         ),
         make_decision_row(
            offset_seconds=9,
            component="Liquidity",
            message="GATED",
            fields={"reason": "Spread too wide"},
            symbol="XAUUSD",
         ),
         make_decision_row(
            offset_seconds=10,
            component="Allocator",
            message="ORDER_PLAN",
            fields={"exec_symbol": "XAUUSD"},
            symbol="XAUUSD",
         ),
         make_decision_row(
            offset_seconds=20,
            component="Liquidity",
            message="GATED",
            fields={"reason": "Spread too wide"},
            symbol="XAUUSD",
         ),
         make_decision_row(
            offset_seconds=30,
            component="Liquidity",
            message="GATED",
            fields={"reason": "Volatility"},
            symbol="XAUUSD",
         ),
         make_decision_row(
            offset_seconds=60,
            component="MetaPolicy",
            message="EVAL",
            fields={
               "choice": "Skip",
               "gating_reason": "SKIP_NO_SETUP",
               "regime": "VOLATILE",
               "news_window_state": "CLEAR",
            },
            symbol="EURUSD",
         ),
         make_decision_row(
            offset_seconds=65,
            component="MetaPolicy",
            message="EVAL",
            fields={
               "choice": "Skip",
               "gating_reason": "SKIP_NO_SETUP",
               "regime": "VOLATILE",
               "news_window_state": "CLEAR",
            },
            symbol="EURUSD",
         ),
         make_decision_row(
            offset_seconds=70,
            component="MetaPolicy",
            message="EVAL",
            fields={
               "choice": "Skip",
               "gating_reason": "RULE_1_SESSION_CAP",
               "regime": "VOLATILE",
               "news_window_state": "CLEAR",
            },
            symbol="EURUSD",
         ),
         make_decision_row(
            offset_seconds=120,
            component="Scheduler",
            message="GATED",
            fields={
               "news": False,
               "spread_ok": True,
               "in_session": False,
               "in_or": False,
               "anomaly_block": False,
               "anomaly_action": "none",
            },
            symbol="EURUSD",
         ),
         make_decision_row(
            offset_seconds=150,
            component="Scheduler",
            message="GATED",
            fields={
               "news": False,
               "spread_ok": True,
               "in_session": False,
               "in_or": False,
               "anomaly_block": False,
               "anomaly_action": "none",
            },
            symbol="EURUSD",
         ),
         make_decision_row(
            offset_seconds=180,
            component="Scheduler",
            message="GATED",
            fields={
               "news": False,
               "spread_ok": True,
               "in_session": True,
               "in_or": False,
               "anomaly_block": False,
               "anomaly_action": "none",
            },
            symbol="EURUSD",
         ),
      ]

      intervals = phase_a.build_gate_intervals(rows)

      self.assertEqual(len(intervals), 7)

      first_liquidity = intervals[0]
      self.assertEqual(first_liquidity["gate_family"], "Liquidity.GATED")
      self.assertEqual(first_liquidity["normalized_key"], "XAUUSD|Spread too wide")
      self.assertEqual(first_liquidity["row_count"], 3)
      self.assertEqual(first_liquidity["start_ts"], "2025-01-01T00:00:01")
      self.assertEqual(first_liquidity["end_ts"], "2025-01-01T00:00:09")
      self.assertEqual(first_liquidity["duration_seconds"], 8)

      second_liquidity = intervals[1]
      self.assertEqual(second_liquidity["normalized_key"], "XAUUSD|Spread too wide")
      self.assertEqual(second_liquidity["row_count"], 1)
      self.assertEqual(second_liquidity["start_ts"], "2025-01-01T00:00:20")

      first_skip = intervals[3]
      self.assertEqual(first_skip["gate_family"], "MetaPolicy.EVAL.Skip")
      self.assertEqual(first_skip["normalized_key"], "EURUSD|Skip|SKIP_NO_SETUP|VOLATILE|CLEAR")
      self.assertEqual(first_skip["row_count"], 2)
      self.assertEqual(first_skip["duration_seconds"], 5)

      first_scheduler = intervals[5]
      self.assertEqual(first_scheduler["gate_family"], "Scheduler.GATED")
      self.assertEqual(first_scheduler["normalized_key"], "EURUSD|false|true|false|false|false|none")
      self.assertEqual(first_scheduler["row_count"], 2)
      self.assertEqual(first_scheduler["duration_seconds"], 30)

      second_scheduler = intervals[6]
      self.assertEqual(second_scheduler["normalized_key"], "EURUSD|false|true|true|false|false|none")
      self.assertEqual(second_scheduler["row_count"], 1)


class FundingPipsPhaseAIntegrationTests(unittest.TestCase):
   @classmethod
   def setUpClass(cls) -> None:
      cls.temp_dir = tempfile.TemporaryDirectory(prefix="fundingpips_phase_a_")
      cls.output_dir = Path(cls.temp_dir.name) / "out"
      cls.result = phase_a.build_phase_a_research(cls.output_dir, phase_a.build_default_runs())
      cls.summary = cls.result["summary"]
      cls.outputs = {name: Path(path) for name, path in cls.result["outputs"].items()}

   @classmethod
   def tearDownClass(cls) -> None:
      cls.temp_dir.cleanup()

   def test_holdout_reconciliation_matches_pinned_baseline(self) -> None:
      acceptance = self.summary["acceptance_checks"]
      self.assertTrue(acceptance["holdout_trade_count_107"])
      self.assertTrue(acceptance["holdout_pnl_78_61"])
      self.assertTrue(acceptance["holdout_daily_csv_match"])

      holdout = self.summary["runs"]["holdout"]
      self.assertEqual(holdout["reconciliation"]["actual_trade_count"], 107)
      self.assertAlmostEqual(holdout["reconciliation"]["actual_realized_pnl"], 78.61, places=2)
      self.assertFalse(self.summary["baseline"]["phase_b_required"])

   def test_candidate_lineage_spot_check_matches_plan_sequence(self) -> None:
      lineage = self.summary["acceptance_checks"]["candidate_lineage_spot_check"]
      self.assertTrue(lineage["passed"])
      self.assertEqual(lineage["missing_steps"], [])
      self.assertEqual(
         lineage["sequence"],
         {
            "MetaPolicy.EVAL": (
               ".tmp\\fundingpips_official_validation\\master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c"
               "\\collected\\logs\\D0E8209F77C8CF37AD8BF550E51FF075\\Agent-127.0.0.1-3000\\MQL5\\Files\\RPEA\\logs"
               "\\decisions_20251103.csv:2958"
            ),
            "Risk.SIZING": (
               ".tmp\\fundingpips_official_validation\\master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c"
               "\\collected\\logs\\D0E8209F77C8CF37AD8BF550E51FF075\\Agent-127.0.0.1-3000\\MQL5\\Files\\RPEA\\logs"
               "\\decisions_20251103.csv:2959"
            ),
            "Allocator.ORDER_PLAN": (
               ".tmp\\fundingpips_official_validation\\master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c"
               "\\collected\\logs\\D0E8209F77C8CF37AD8BF550E51FF075\\Agent-127.0.0.1-3000\\MQL5\\Files\\RPEA\\logs"
               "\\decisions_20251103.csv:2961"
            ),
            "INTENT_ACCEPT": (
               ".tmp\\fundingpips_official_validation\\master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c"
               "\\collected\\logs\\D0E8209F77C8CF37AD8BF550E51FF075\\Agent-127.0.0.1-3000\\MQL5\\Files\\RPEA\\logs"
               "\\decisions_20251103.csv:2962"
            ),
            "EXECUTE_ORDER_SUCCESS": (
               ".tmp\\fundingpips_official_validation\\master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c"
               "\\collected\\logs\\D0E8209F77C8CF37AD8BF550E51FF075\\Agent-127.0.0.1-3000\\MQL5\\Files\\RPEA\\logs"
               "\\decisions_20251103.csv:2970"
            ),
            "PLACE_OK": (
               ".tmp\\fundingpips_official_validation\\master_phase5_holdout_rule3_20251101_20260228__19a3b91f4d7f9f7c"
               "\\collected\\logs\\D0E8209F77C8CF37AD8BF550E51FF075\\Agent-127.0.0.1-3000\\MQL5\\Files\\RPEA\\logs"
               "\\decisions_20251103.csv:2972"
            ),
         },
      )

   def test_research_trade_output_contains_required_fields_and_holdout_truth(self) -> None:
      with self.outputs["research_trades"].open("r", encoding="utf-8", newline="") as handle:
         reader = csv.DictReader(handle)
         self.assertIsNotNone(reader.fieldnames)
         for field_name in phase_a.REQUIRED_TRADE_FIELDS:
            self.assertIn(field_name, reader.fieldnames)
         rows = list(reader)

      holdout_rows = [row for row in rows if row["run_id"] == "holdout"]
      self.assertEqual(len(holdout_rows), 107)
      self.assertAlmostEqual(sum(float(row["realized_pnl"]) for row in holdout_rows), 78.61, places=2)
      self.assertEqual({row["symbol"] for row in holdout_rows}, {"XAUUSD"})

   def test_outputs_and_rankings_are_phase_a_only(self) -> None:
      summary_path = self.outputs["research_attribution_summary"]
      rankings_path = self.outputs["research_change_rankings"]

      summary_payload = json.loads(summary_path.read_text(encoding="utf-8"))
      rankings_text = rankings_path.read_text(encoding="utf-8")

      self.assertEqual(summary_payload["phase_source"], "Phase A")
      self.assertFalse(summary_payload["baseline"]["phase_b_required"])
      self.assertIn("Phase source: Phase A artifact analysis only.", rankings_text)


if __name__ == "__main__":
   unittest.main()
