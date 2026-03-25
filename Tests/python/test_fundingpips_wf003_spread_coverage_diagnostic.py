import csv
import json
import tempfile
import unittest
from pathlib import Path

from tools import fundingpips_wf003_spread_coverage_diagnostic as diagnostic


def write_decision_log(path: Path, rows: list[dict[str, object]]) -> None:
   path.parent.mkdir(parents=True, exist_ok=True)
   with path.open("w", encoding="utf-8", newline="") as handle:
      handle.write("date,time,event,component,level,message,fields_json\n")
      for row in rows:
         handle.write(
            ",".join(
               (
                  str(row["date"]),
                  str(row["time"]),
                  "DECISION",
                  str(row["component"]),
                  "1",
                  str(row["message"]),
                  json.dumps(row["fields"], separators=(",", ":"), sort_keys=True),
               )
            )
            + "\n"
         )


def write_run_bundle(
   root: Path,
   run_name: str,
   decision_rows: list[dict[str, object]],
   summary_metrics: dict[str, object],
) -> Path:
   run_dir = root / run_name
   collected = run_dir / "collected"
   logs_dir = collected / "logs"
   decision_path = logs_dir / "decisions_20251001.csv"
   write_decision_log(decision_path, decision_rows)

   summary_path = collected / "fundingpips_eval_summary.json"
   summary_path.write_text(json.dumps(summary_metrics, indent=2, sort_keys=True), encoding="utf-8")
   daily_path = collected / "fundingpips_eval_daily.csv"
   daily_path.write_text("server_date,max_daily_dd_pct\n2025-10-01,0.0\n", encoding="utf-8")
   report_path = collected / f"{run_name}.xml.htm"
   report_path.write_text("<html></html>\n", encoding="utf-8")

   manifest = {
      "run_dir": str(run_dir),
      "collected_summary": str(summary_path),
      "collected_daily": str(daily_path),
      "collected_report": str(report_path),
      "collected_decision_logs": [str(decision_path)],
      "collected_event_logs": [],
   }
   manifest_path = run_dir / "run_manifest.json"
   manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
   return manifest_path


class FundingPipsWf003SpreadCoverageDiagnosticTests(unittest.TestCase):
   def test_build_diagnostic_summary_flags_volume_zero_on_baseline_execution_slice(self) -> None:
      with tempfile.TemporaryDirectory(prefix="wf003_diag_") as tmp_dir:
         root = Path(tmp_dir)
         common_summary = {
            "days_traded": 1,
            "final_return_pct": 0.0,
            "max_daily_dd_pct": 0.0,
            "max_overall_dd_pct": 0.0,
            "trades_total": 0,
         }

         baseline_rows = [
            {"date": "2025-10-01", "time": "01:09:59", "component": "Sessions", "message": "OR_TICK", "fields": {"symbol": "XAUUSD", "session": "LO"}},
            {"date": "2025-10-01", "time": "01:09:59", "component": "Sessions", "message": "OR_TICK", "fields": {"symbol": "XAUUSD", "session": "NY"}},
            {"date": "2025-10-01", "time": "01:09:59", "component": "MetaPolicy", "message": "EVAL", "fields": {"symbol": "XAUUSD", "choice": "MR", "regime": "VOLATILE", "confidence": 0.63}},
            {"date": "2025-10-01", "time": "01:09:59", "component": "Risk", "message": "SIZING", "fields": {"symbol": "XAUUSD", "sl_points": 4985.0, "raw_volume": 0.0108, "final_volume": 0.0100, "confidence": 0.63}},
            {"date": "2025-10-01", "time": "01:09:59", "component": "Allocator", "message": "ORDER_PLAN", "fields": {"exec_symbol": "XAUUSD", "signal_symbol": "XAUUSD", "strategy": "MR", "setup_type": "MR", "entry_price": 3860.2, "sl": 3810.35, "tp": 3934.97, "comment": "MR-MR b=0.63 conf=0.63 2025.10.", "valid": True}},
            {"date": "2025-10-01", "time": "01:09:59", "component": "Scheduler", "message": "PLACE_OK", "fields": {"symbol": "XAUUSD", "ticket": 2}},
         ]
         candidate_rows = [
            {"date": "2025-10-01", "time": "01:00:00", "component": "Sessions", "message": "OR_TICK", "fields": {"symbol": "XAUUSD", "session": "LO"}},
            {"date": "2025-10-01", "time": "01:00:00", "component": "Sessions", "message": "OR_TICK", "fields": {"symbol": "XAUUSD", "session": "NY"}},
            {"date": "2025-10-01", "time": "01:00:00", "component": "Liquidity", "message": "GATED", "fields": {"symbol": "XAUUSD", "spread": 1.20, "threshold": 0.60, "reason": "Spread too wide"}},
            {"date": "2025-10-01", "time": "01:00:00", "component": "Scheduler", "message": "ANOMALY_EVAL", "fields": {"symbol": "XAUUSD"}},
            {"date": "2025-10-01", "time": "01:00:00", "component": "Scheduler", "message": "GATED", "fields": {"spread_ok": False, "in_session": True, "in_or": True, "news": False, "anomaly_block": False, "anomaly_action": "none"}},
            {"date": "2025-10-01", "time": "01:09:59", "component": "Sessions", "message": "OR_TICK", "fields": {"symbol": "XAUUSD", "session": "LO"}},
            {"date": "2025-10-01", "time": "01:09:59", "component": "Sessions", "message": "OR_TICK", "fields": {"symbol": "XAUUSD", "session": "NY"}},
            {"date": "2025-10-01", "time": "01:09:59", "component": "MetaPolicy", "message": "EVAL", "fields": {"symbol": "XAUUSD", "choice": "MR", "regime": "VOLATILE", "confidence": 0.63}},
            {"date": "2025-10-01", "time": "01:09:59", "component": "Risk", "message": "SIZING", "fields": {"symbol": "XAUUSD", "sl_points": 6101.0, "raw_volume": 0.0089, "final_volume": 0.0, "confidence": 0.63}},
            {"date": "2025-10-01", "time": "01:09:59", "component": "Allocator", "message": "ORDER_PLAN", "fields": {"exec_symbol": "XAUUSD", "signal_symbol": "XAUUSD", "strategy": "MR", "setup_type": "MR", "entry_price": 3860.2, "sl": 3799.19, "tp": 3951.71, "comment": "MR-MR b=0.63 conf=0.63 2025.10.", "valid": False, "rejection_reason": "volume_zero"}},
            {"date": "2025-10-01", "time": "01:09:59", "component": "Scheduler", "message": "PLAN_REJECT", "fields": {"symbol": "XAUUSD", "reason": "volume_zero"}},
         ]

         baseline_manifest = write_run_bundle(root, "baseline", baseline_rows, {**common_summary, "trades_total": 1})
         sm45_manifest = write_run_bundle(root, "sm45", candidate_rows, common_summary)
         sm40_manifest = write_run_bundle(root, "sm40", candidate_rows, common_summary)
         validation_summary_path = root / "validation_summary.json"
         validation_summary_path.write_text(
            json.dumps(
               {
                  "reference": {
                     "report": {
                        "baseline": {
                           "rows": [
                              {"cycle_id": "wf001_202508", "zero_trade_flag": False},
                              {"cycle_id": "wf003_202510", "zero_trade_flag": False},
                           ],
                           "days_traded_mean": 20.7,
                           "trades_total_mean": 41.3,
                        }
                     }
                  },
                  "candidates": [
                     {
                        "id": "spread_mult_atr_0045",
                        "report": {"baseline": {"rows": [{"cycle_id": "wf003_202510", "zero_trade_flag": True}], "days_traded_mean": 10.3, "trades_total_mean": 20.3}},
                     },
                     {
                        "id": "spread_mult_atr_0040",
                        "report": {"baseline": {"rows": [{"cycle_id": "wf003_202510", "zero_trade_flag": True}], "days_traded_mean": 10.3, "trades_total_mean": 20.0}},
                     },
                  ],
               },
               indent=2,
               sort_keys=True,
            ),
            encoding="utf-8",
         )

         specs = [
            diagnostic.RunSpec("baseline", "baseline", baseline_manifest, 0.005, True),
            diagnostic.RunSpec("sm45", "sm45", sm45_manifest, 0.0045, False),
            diagnostic.RunSpec("sm40", "sm40", sm40_manifest, 0.0040, False),
         ]
         summary, csv_outputs = diagnostic.build_diagnostic_summary(root, specs, validation_summary_path)

         self.assertEqual(summary["baseline_place_ok"]["count"], 1)
         self.assertEqual(summary["baseline_place_ok"]["candidate_outcomes"]["sm45"], {"plan_reject_volume_zero": 1})
         self.assertEqual(summary["baseline_place_ok"]["session_counts"], {"LO+NY": 1})
         self.assertEqual(summary["baseline_place_ok"]["regime_counts"], {"VOLATILE": 1})
         self.assertAlmostEqual(summary["baseline_place_ok"]["geometry_delta"]["sm45"]["sl_points_ratio_median"], 6101.0 / 4985.0)
         self.assertEqual(csv_outputs["baseline_place_ok_outcomes"][0]["sm45_outcome"], "plan_reject_volume_zero")
         self.assertFalse(summary["recommendation"]["follow_up_spread_search_justified"])

   def test_liquidity_summary_captures_scheduler_state_and_ratio_bucket(self) -> None:
      rows = [
         diagnostic.DiagnosticRow("sm45", diagnostic.phase_a.parse_log_timestamp("2025-10-01", "01:00:00"), "2025-10-01T01:00:00", "Sessions", "OR_TICK", "XAUUSD", {"symbol": "XAUUSD", "session": "LO"}),
         diagnostic.DiagnosticRow("sm45", diagnostic.phase_a.parse_log_timestamp("2025-10-01", "01:00:00"), "2025-10-01T01:00:00", "Sessions", "OR_TICK", "XAUUSD", {"symbol": "XAUUSD", "session": "NY"}),
         diagnostic.DiagnosticRow("sm45", diagnostic.phase_a.parse_log_timestamp("2025-10-01", "01:00:00"), "2025-10-01T01:00:00", "Liquidity", "GATED", "XAUUSD", {"symbol": "XAUUSD", "spread": 1.20, "threshold": 0.60, "reason": "Spread too wide"}),
         diagnostic.DiagnosticRow("sm45", diagnostic.phase_a.parse_log_timestamp("2025-10-01", "01:00:00"), "2025-10-01T01:00:00", "Scheduler", "GATED", "XAUUSD", {"spread_ok": False, "in_session": True, "in_or": True}),
      ]
      row_lookup = diagnostic.build_row_lookup(rows)
      sessions = diagnostic.build_session_index(rows)

      summary = diagnostic.summarize_liquidity(rows, row_lookup, sessions, "XAUUSD")

      self.assertEqual(summary["count"], 1)
      self.assertEqual(summary["ratio_summary"]["median"], 2.0)
      self.assertEqual(summary["ratio_bucket_counts"], {"1.50-2.00x": 1})
      self.assertEqual(summary["session_counts"], {"LO+NY": 1})
      self.assertEqual(summary["scheduler_state_counts"], {"in_session=true|in_or=true|spread_ok=false": 1})


if __name__ == "__main__":
   unittest.main()
