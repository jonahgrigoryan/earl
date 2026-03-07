import tempfile
import unittest
from pathlib import Path

from tools import fundingpips_mt5_runner as runner


class FundingPipsMt5RunnerTests(unittest.TestCase):
   def test_compute_cache_key_is_order_independent_for_overrides(self) -> None:
      spec_a = runner.build_spec(
         {
            "name": "order_a",
            "set_overrides": {
               "RiskPct": "1.2",
               "EnableMR": "0",
            },
         }
      )
      spec_b = runner.build_spec(
         {
            "name": "order_b",
            "set_overrides": {
               "EnableMR": "0",
               "RiskPct": "1.2",
            },
         }
      )
      base_text = "RiskPct=1.5\nEnableMR=1\n"
      terminal = {"path": "C:/MT5/terminal64.exe", "size": 1, "mtime_ns": 2}

      key_a = runner.compute_cache_key(spec_a, base_text, terminal)
      key_b = runner.compute_cache_key(spec_b, base_text, terminal)

      self.assertEqual(key_a, key_b)

   def test_write_single_run_set_sanitizes_optimize_syntax(self) -> None:
      base_text = "\n".join(
         [
            "; header",
            "RiskPct=1.5||0.8||0.1||2.0||Y",
            "EnableMR=1||0||1||1||N",
            "SymbolName=EURUSD",
            "",
         ]
      )

      with tempfile.TemporaryDirectory() as tmp_dir:
         output = Path(tmp_dir) / "generated.set"
         runner.write_single_run_set(
            base_text,
            {"RiskPct": 0.9, "EnableMR": False, "NewParam": "abc"},
            output,
         )
         written = output.read_text(encoding="ascii").splitlines()

      self.assertIn("RiskPct=0.9", written)
      self.assertIn("EnableMR=0", written)
      self.assertIn("SymbolName=EURUSD", written)
      self.assertIn("NewParam=abc", written)
      self.assertNotIn("RiskPct=1.5||0.8||0.1||2.0||Y", written)

   def test_build_tester_ini_contains_generated_set_and_report(self) -> None:
      spec = runner.build_spec(
         {
            "name": "eurusd_probe",
            "template_ini": "Tests/RPEA/RPEA_10k_single.ini",
         }
      )
      ini_text = runner.build_tester_ini(
         spec,
         "generated_probe.set",
         r"Tester\reports\eurusd_probe.xml",
      )

      self.assertIn("ExpertParameters=generated_probe.set", ini_text)
      self.assertIn(r"Report=Tester\reports\eurusd_probe.xml", ini_text)
      self.assertIn("Optimization=0", ini_text)
      self.assertIn("Expert=FundingPips\\RPEA", ini_text)

   def test_prepend_common_section_adds_only_common_block(self) -> None:
      common_ini = "\n".join(
         [
            "[Common]",
            "Login=123456",
            "Server=MetaQuotes-Demo",
            "[Charts]",
            "ProfileLast=Default",
         ]
      )
      tester_ini = "\n".join(
         [
            "[Tester]",
            "Expert=FundingPips\\RPEA",
         ]
      )

      merged = runner.prepend_common_section(tester_ini, common_ini)

      self.assertTrue(merged.startswith("[Common]"))
      self.assertIn("Login=123456", merged)
      self.assertIn("[Tester]", merged)
      self.assertNotIn("[Charts]", merged)


if __name__ == "__main__":
   unittest.main()
