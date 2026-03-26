import unittest

from tools import fundingpips_rl_emrt_sizing_diagnostic as diag


class FundingPipsRLEMRTSizingDiagnosticTests(unittest.TestCase):
   def test_classify_divergence_detects_candidate_volume_zero_cliff(self) -> None:
      baseline_meta = {"choice": "MR", "mr_conf": 0.58}
      candidate_meta = {"choice": "MR", "mr_conf": 0.56}
      baseline_lineage = {
         "place_ok": True,
         "plan_valid": True,
         "final_volume": 0.01,
         "risk_raw_volume": 0.0106,
         "rejection_reason": "",
      }
      candidate_lineage = {
         "place_ok": False,
         "plan_valid": False,
         "final_volume": None,
         "risk_raw_volume": 0.0098,
         "rejection_reason": "volume_zero",
      }

      result = diag.classify_divergence(
         baseline_meta,
         candidate_meta,
         baseline_lineage,
         candidate_lineage,
      )

      self.assertEqual(result["stage"], "allocator")
      self.assertEqual(result["reason"], "candidate_volume_zero")
      self.assertTrue(result["lost_baseline_trade"])
      self.assertTrue(result["zero_cliff"])
      self.assertTrue(result["baseline_at_min_lot"])

   def test_summarize_contributions_reports_negative_delta_share(self) -> None:
      meta_rows = [
         {
            "inferred_q_advantage": 0.60,
            "emrt_fastness": 0.50,
            "delta_conf": -0.02,
            "candidate_rl_component": 0.48,
            "candidate_emrt_component": 0.10,
            "baseline_mr_conf": 0.60,
            "candidate_mr_conf": 0.58,
         },
         {
            "inferred_q_advantage": 0.40,
            "emrt_fastness": 0.55,
            "delta_conf": 0.03,
            "candidate_rl_component": 0.32,
            "candidate_emrt_component": 0.11,
            "baseline_mr_conf": 0.40,
            "candidate_mr_conf": 0.43,
         },
      ]

      result = diag.summarize_contributions(meta_rows)

      self.assertEqual(result["shared_eval_count"], 2)
      self.assertEqual(result["negative_delta_share"], 0.5)
      self.assertEqual(result["positive_delta_share"], 0.5)
      self.assertEqual(result["q_advantage"]["median"], 0.5)
      self.assertEqual(result["emrt_fastness"]["median"], 0.525)

   def test_build_next_recommendation_closes_single_knob_path(self) -> None:
      summary = {
         "root_cause": {"classification": "xauusd_min_lot_quantization"},
         "windows": {"holdout": {"delta_vs_baseline": {"trades_total": 0}}},
      }

      result = diag.build_next_recommendation(summary)

      self.assertEqual(result["result"], "close_single_knob_path")
      self.assertIn("single-knob", result["recommended_next_step"])


if __name__ == "__main__":
   unittest.main()
