import os
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
      dependency_hash = "dep_hash_v1"

      key_a = runner.compute_cache_key(spec_a, base_text, terminal, dependency_hash)
      key_b = runner.compute_cache_key(spec_b, base_text, terminal, dependency_hash)

      self.assertEqual(key_a, key_b)

   def test_compute_cache_key_changes_when_dependency_hash_changes(self) -> None:
      spec = runner.build_spec({"name": "cache_probe"})
      base_text = "RiskPct=1.5\nEnableMR=1\n"
      terminal = {"path": "C:/MT5/terminal64.exe", "size": 1, "mtime_ns": 2}

      key_a = runner.compute_cache_key(spec, base_text, terminal, "dep_hash_v1")
      key_b = runner.compute_cache_key(spec, base_text, terminal, "dep_hash_v2")

      self.assertNotEqual(key_a, key_b)

   def test_compute_ea_dependency_hash_changes_when_include_file_changes(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo_root = Path(tmp_dir)
         expert_dir = repo_root / "MQL5" / "Experts" / "FundingPips"
         include_dir = repo_root / "MQL5" / "Include" / "RPEA"
         expert_dir.mkdir(parents=True)
         include_dir.mkdir(parents=True)
         (expert_dir / "RPEA.mq5").write_text('#include <RPEA/test_module.mqh>\n', encoding="ascii")
         module_path = include_dir / "test_module.mqh"
         module_path.write_text("int TestValue() { return 1; }\n", encoding="ascii")

         hash_a = runner.compute_ea_dependency_hash(repo_root)
         module_path.write_text("int TestValue() { return 2; }\n", encoding="ascii")
         hash_b = runner.compute_ea_dependency_hash(repo_root)

      self.assertNotEqual(hash_a, hash_b)

   def test_build_spec_merges_default_and_run_set_overrides(self) -> None:
      spec = runner.build_spec(
         {
            "name": "batch_probe",
            "set_overrides": {
               "RiskPct": "0.9",
               "EnableMR": "1",
            },
         },
         defaults={
            "symbol": "XAUUSD",
            "set_overrides": {
               "RiskPct": "1.2",
               "EnableQL": "0",
            },
         },
      )

      self.assertEqual(spec.symbol, "XAUUSD")
      self.assertEqual(
         spec.set_overrides,
         {
            "RiskPct": "0.9",
            "EnableQL": "0",
            "EnableMR": "1",
         },
      )

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

   def test_locate_recent_file_ignores_stale_artifacts_before_run_start(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         root = Path(tmp_dir)
         stale = root / runner.SUMMARY_FILENAME
         stale.write_text("old", encoding="ascii")

         not_before = stale.stat().st_mtime + 0.5
         found = runner.locate_recent_file(root, runner.SUMMARY_FILENAME, not_before)

      self.assertIsNone(found)

   def test_locate_recent_file_accepts_new_artifacts_after_run_start(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         root = Path(tmp_dir)
         fresh = root / runner.SUMMARY_FILENAME
         fresh.write_text("new", encoding="ascii")
         start = fresh.stat().st_mtime - 0.001
         os.utime(fresh, (start + 1.0, start + 1.0))

         found = runner.locate_recent_file(root, runner.SUMMARY_FILENAME, start)

      self.assertEqual(found, fresh)


if __name__ == "__main__":
   unittest.main()
