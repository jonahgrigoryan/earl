import unittest

from tools import fundingpips_xauusd_mr_floor_sensitivity_diagnostic as diag


class FundingPipsXauusdMrFloorSensitivityDiagnosticTests(unittest.TestCase):
   def test_normalize_candidate_row_classifies_floor_buckets(self) -> None:
      dataset = diag.DatasetConfig(
         id="holdout",
         label="Holdout",
         source_kind="research_candidates",
      )

      safe_row = diag.normalize_candidate_row(
         dataset,
         {
            "decision_ts": "2025-11-03T02:16:59",
            "symbol": "XAUUSD",
            "strategy": "MR",
            "plan_valid": "true",
            "place_ok": "true",
            "rejection_reason": "",
            "risk_raw_volume": "0.0212",
            "volume": "0.0200",
            "requested_entry_price": "3965.46000",
            "sl": "3936.75000",
            "meta_regime": "VOLATILE",
         },
      )
      floor_row = diag.normalize_candidate_row(
         dataset,
         {
            "decision_ts": "2025-11-04T08:00:29",
            "symbol": "XAUUSD",
            "strategy": "MR",
            "plan_valid": "true",
            "place_ok": "true",
            "rejection_reason": "",
            "risk_raw_volume": "0.0160",
            "volume": "0.0100",
            "requested_entry_price": "3971.61000",
            "sl": "3942.90000",
            "meta_regime": "VOLATILE",
         },
      )
      zero_row = diag.normalize_candidate_row(
         dataset,
         {
            "decision_ts": "2025-10-30T02:56:59",
            "symbol": "XAUUSD",
            "strategy": "MR",
            "plan_valid": "false",
            "place_ok": "",
            "rejection_reason": "volume_zero",
            "risk_raw_volume": "0.0099",
            "volume": "0.0000",
            "requested_entry_price": "3950.42000",
            "sl": "3889.41000",
            "meta_regime": "VOLATILE",
         },
      )

      self.assertEqual(safe_row["bucket"], "safe_above_floor")
      self.assertEqual(floor_row["bucket"], "near_floor_0.01")
      self.assertEqual(floor_row["quantization_kind"], "quantized_to_min_lot")
      self.assertEqual(zero_row["bucket"], "rounded_to_0.00")
      self.assertEqual(zero_row["quantization_kind"], "quantized_to_zero")
      self.assertAlmostEqual(zero_row["overshoot_to_min_lot_pct"], (0.01 / 0.0099 - 1.0) * 100.0)

   def test_build_wf003_zero_tolerance_rows_groups_by_overshoot_band(self) -> None:
      rows = [
         {"bucket": "rounded_to_0.00", "raw_volume": 0.0099, "overshoot_to_min_lot_pct": 1.010101},
         {"bucket": "rounded_to_0.00", "raw_volume": 0.0096, "overshoot_to_min_lot_pct": 4.166667},
         {"bucket": "rounded_to_0.00", "raw_volume": 0.0090, "overshoot_to_min_lot_pct": 11.111111},
         {"bucket": "rounded_to_0.00", "raw_volume": 0.0078, "overshoot_to_min_lot_pct": 28.205128},
      ]

      result = diag.build_wf003_zero_tolerance_rows(rows)
      by_label = {row["threshold_label"]: row for row in result}

      self.assertEqual(by_label["<=2pct_overshoot"]["count"], 1)
      self.assertEqual(by_label["<=5pct_overshoot"]["count"], 2)
      self.assertEqual(by_label["<=10pct_overshoot"]["count"], 2)
      self.assertEqual(by_label["<=30pct_overshoot"]["count"], 4)

   def test_build_recommendation_prefers_precision_telemetry_branch(self) -> None:
      dataset_summaries = {
         "holdout": {"executed_min_lot_share": 0.560748},
         "wf003_202510": {
            "executed_min_lot_share": 1.0,
            "zero_share_of_candidates": 0.874255,
         },
      }
      tolerance_rows = [
         {
            "threshold_label": "<=5pct_overshoot",
            "share_of_wf003_zero_rows": 0.4485,
         },
         {
            "threshold_label": "<=10pct_overshoot",
            "share_of_wf003_zero_rows": 0.5208,
         },
      ]

      result = diag.build_recommendation(dataset_summaries, tolerance_rows)

      self.assertFalse(result["behavior_change_branch_justified"])
      self.assertTrue(result["follow_up_branch_justified"])
      self.assertEqual(result["exact_next_branch"], "codex/xauusd-mr-floor-precision-telemetry")
      self.assertIn("Do not open a rounding/size-behavior branch yet", result["key_call"])


if __name__ == "__main__":
   unittest.main()
