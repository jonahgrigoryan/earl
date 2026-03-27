import unittest

from tools import fundingpips_xauusd_mr_floor_precision_telemetry_diagnostic as diag


class FundingPipsXauusdMrFloorPrecisionTelemetryDiagnosticTests(unittest.TestCase):
   def test_build_failure_slice_rows_filters_lost_baseline_trades_with_floor_zero(self) -> None:
      rows = [
         {
            "lost_baseline_trade": True,
            "candidate_volume_zero_subcause": "below_min_after_step",
            "candidate_volume_zero_gap_pct": 1.2,
         },
         {
            "lost_baseline_trade": True,
            "candidate_volume_zero_subcause": "",
            "candidate_volume_zero_gap_pct": None,
         },
         {
            "lost_baseline_trade": False,
            "candidate_volume_zero_subcause": "below_min_after_budget",
            "candidate_volume_zero_gap_pct": 2.4,
         },
      ]

      result = diag.build_failure_slice_rows(rows)

      self.assertEqual(len(result), 1)
      self.assertEqual(result[0]["candidate_volume_zero_subcause"], "below_min_after_step")

   def test_summarize_failure_slice_builds_zero_cause_counts_and_gap_bands(self) -> None:
      rows = [
         {
            "candidate_volume_zero_subcause": "below_min_after_step",
            "candidate_volume_zero_gap_pct": 0.8,
            "candidate_volume_zero_reference_volume": 0.00992,
         },
         {
            "candidate_volume_zero_subcause": "below_min_after_step",
            "candidate_volume_zero_gap_pct": 1.8,
            "candidate_volume_zero_reference_volume": 0.00982,
         },
         {
            "candidate_volume_zero_subcause": "below_min_after_budget",
            "candidate_volume_zero_gap_pct": 4.9,
            "candidate_volume_zero_reference_volume": 0.00951,
         },
      ]

      result = diag.summarize_failure_slice(rows)
      bands = {row["threshold_label"]: row for row in result["tolerance_bands"]}

      self.assertEqual(result["count"], 3)
      self.assertEqual(result["zero_cause_counts"]["below_min_after_step"], 2)
      self.assertEqual(result["zero_cause_counts"]["below_min_after_budget"], 1)
      self.assertEqual(bands["<= 1pct below min lot"]["count"], 1)
      self.assertEqual(bands["<= 2pct below min lot"]["count"], 2)
      self.assertEqual(bands["<= 5pct below min lot"]["count"], 3)

   def test_build_intervention_call_closes_broad_slice(self) -> None:
      failure_slice = {
         "count": 25,
         "tolerance_bands": [
            {"threshold_label": "<= 1pct below min lot", "share_of_slice": 0.08},
            {"threshold_label": "<= 2pct below min lot", "share_of_slice": 0.16},
            {"threshold_label": "<= 5pct below min lot", "share_of_slice": 0.44},
            {"threshold_label": "<= 10pct below min lot", "share_of_slice": 0.60},
         ],
      }

      result = diag.build_intervention_call(failure_slice, {"lost_trade_reason_counts": {"candidate_volume_zero": 25}})

      self.assertFalse(result["later_intervention_branch_justified"])
      self.assertTrue(result["close_path"])
      self.assertEqual(result["exact_next_branch"], "")


if __name__ == "__main__":
   unittest.main()
