import os
import tempfile
import time
import unittest
from pathlib import Path

from tools import fundingpips_mt5_runner as runner


class FundingPipsMt5RunnerTests(unittest.TestCase):
   def test_build_spec_parses_staged_files(self) -> None:
      spec = runner.build_spec(
         {
            "name": "staged_probe",
            "staged_files": [
               {
                  "source_path": "artifacts/qtable.bin",
                  "terminal_relative_path": "RPEA/qtable/mr_qtable.bin",
                  "artifact_id": "qtable_a",
                  "sha256": "deadbeef",
               }
            ],
         }
      )

      self.assertEqual(len(spec.staged_files), 1)
      self.assertEqual(spec.staged_files[0].source_path, Path("artifacts/qtable.bin"))
      self.assertEqual(spec.staged_files[0].terminal_relative_path, "RPEA/qtable/mr_qtable.bin")
      self.assertEqual(spec.staged_files[0].artifact_id, "qtable_a")
      self.assertEqual(spec.staged_files[0].sha256, "deadbeef")

   def test_build_runner_paths_resolves_relative_output_root(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo_root = Path(tmp_dir) / "repo"
         terminal_data = Path(tmp_dir) / "terminal_data"
         terminal_exe = Path(tmp_dir) / "terminal64.exe"
         metaeditor_exe = Path(tmp_dir) / "metaeditor64.exe"
         repo_root.mkdir(parents=True)
         terminal_data.mkdir(parents=True)
         terminal_exe.write_text("terminal", encoding="ascii")
         metaeditor_exe.write_text("metaeditor", encoding="ascii")

         original_repo_root = runner.repo_root
         original_resolve_terminal_data_path = runner.resolve_terminal_data_path
         original_resolve_terminal_exe = runner.resolve_terminal_exe
         original_resolve_metaeditor_exe = runner.resolve_metaeditor_exe
         try:
            runner.repo_root = lambda: repo_root
            runner.resolve_terminal_data_path = lambda preferred: terminal_data
            runner.resolve_terminal_exe = lambda mt5_install_path, terminal_data_path: terminal_exe
            runner.resolve_metaeditor_exe = lambda mt5_install_path, terminal_data_path: metaeditor_exe

            paths = runner.build_runner_paths(output_root="relative_output")
         finally:
            runner.repo_root = original_repo_root
            runner.resolve_terminal_data_path = original_resolve_terminal_data_path
            runner.resolve_terminal_exe = original_resolve_terminal_exe
            runner.resolve_metaeditor_exe = original_resolve_metaeditor_exe

      self.assertEqual(paths.repo_root, repo_root)
      self.assertEqual(paths.output_root, (repo_root / "relative_output").resolve())

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

   def test_compute_cache_key_changes_when_staged_file_hash_changes(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo = Path(tmp_dir)
         artifact_path = repo / "artifacts" / "qtable.bin"
         artifact_path.parent.mkdir(parents=True)
         artifact_path.write_text("alpha", encoding="ascii")
         spec = runner.build_spec(
            {
               "name": "staged_cache_probe",
               "staged_files": [
                  {
                     "source_path": "artifacts/qtable.bin",
                     "terminal_relative_path": "RPEA/qtable/mr_qtable.bin",
                  }
               ],
            }
         )
         base_text = "RiskPct=1.5\nEnableMR=1\n"
         terminal = {"path": "C:/MT5/terminal64.exe", "size": 1, "mtime_ns": 2}
         dependency_hash = "dep_hash_v1"

         fingerprint_a = runner.fingerprint_staged_files(spec.staged_files, repo)
         artifact_path.write_text("beta", encoding="ascii")
         fingerprint_b = runner.fingerprint_staged_files(spec.staged_files, repo)

      key_a = runner.compute_cache_key(
         spec,
         base_text,
         terminal,
         dependency_hash,
         staged_files_fingerprint=fingerprint_a,
      )
      key_b = runner.compute_cache_key(
         spec,
         base_text,
         terminal,
         dependency_hash,
         staged_files_fingerprint=fingerprint_b,
      )

      self.assertNotEqual(key_a, key_b)

   def test_compute_cache_key_changes_when_agent_modes_change(self) -> None:
      spec_a = runner.build_spec({"name": "local_only", "use_local": 1, "use_remote": 0, "use_cloud": 0})
      spec_b = runner.build_spec({"name": "remote_enabled", "use_local": 0, "use_remote": 1, "use_cloud": 0})
      base_text = "RiskPct=1.5\nEnableMR=1\n"
      terminal = {"path": "C:/MT5/terminal64.exe", "size": 1, "mtime_ns": 2}
      dependency_hash = "dep_hash_v1"

      key_a = runner.compute_cache_key(spec_a, base_text, terminal, dependency_hash)
      key_b = runner.compute_cache_key(spec_b, base_text, terminal, dependency_hash)

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

   def test_stage_runtime_files_copies_into_terminal_tree(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         repo = Path(tmp_dir) / "repo"
         terminal_data = Path(tmp_dir) / "terminal_data"
         tester_root = Path(tmp_dir) / "tester_root"
         artifact_path = repo / "artifacts" / "thresholds.json"
         agent_files = (
            tester_root
            / "D0E8209F77C8CF37AD8BF550E51FF075"
            / "Agent-127.0.0.1-3000"
            / "MQL5"
            / "Files"
         )
         artifact_path.parent.mkdir(parents=True)
         terminal_data.mkdir(parents=True)
         agent_files.mkdir(parents=True)
         artifact_path.write_text("{\"k_thresholds\":[0.0]}", encoding="ascii")

         staged_rows = runner.stage_runtime_files(
            (
               runner.StagedFileSpec(
                  source_path=Path("artifacts/thresholds.json"),
                  terminal_relative_path="RPEA/rl/thresholds.json",
               ),
            ),
            repo=repo,
            terminal_data_path=terminal_data,
            tester_root=tester_root,
         )
         self.assertEqual(len(staged_rows), 1)
         destination = Path(staged_rows[0]["terminal_destination_path"])
         common_destination = Path(staged_rows[0]["common_destination_path"])
         agent_destination = Path(staged_rows[0]["tester_agent_destination_paths"][0])
         self.assertTrue(destination.exists())
         self.assertTrue(common_destination.exists())
         self.assertTrue(agent_destination.exists())
         self.assertEqual(destination.read_text(encoding="ascii"), "{\"k_thresholds\":[0.0]}")
         self.assertEqual(common_destination.read_text(encoding="ascii"), "{\"k_thresholds\":[0.0]}")
         self.assertEqual(agent_destination.read_text(encoding="ascii"), "{\"k_thresholds\":[0.0]}")

   def test_run_single_backtest_returns_cache_hit_before_preflight(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         root = Path(tmp_dir)
         repo_root = root / "repo"
         output_root = root / "output"
         tester_profiles_dir = root / "tester_profiles"
         config_dir = root / "config"
         terminal_data_path = root / "terminal_data"
         terminal_exe = root / "terminal64.exe"
         metaeditor_exe = root / "metaeditor64.exe"
         base_set_path = repo_root / "Tests" / "RPEA" / "RPEA_10k_default.set"
         expert_dir = repo_root / "MQL5" / "Experts" / "FundingPips"
         include_dir = repo_root / "MQL5" / "Include" / "RPEA"

         base_set_path.parent.mkdir(parents=True)
         expert_dir.mkdir(parents=True)
         include_dir.mkdir(parents=True)
         output_root.mkdir(parents=True)
         tester_profiles_dir.mkdir(parents=True)
         config_dir.mkdir(parents=True)
         terminal_data_path.mkdir(parents=True)
         terminal_exe.write_text("terminal", encoding="ascii")
         metaeditor_exe.write_text("metaeditor", encoding="ascii")
         base_set_path.write_text("RiskPct=1.5\n", encoding="ascii")
         (expert_dir / "RPEA.mq5").write_text("#property strict\n", encoding="ascii")
         (include_dir / "dummy.mqh").write_text("#property strict\n", encoding="ascii")

         paths = runner.RunnerPaths(
            repo_root=repo_root,
            terminal_exe=terminal_exe,
            metaeditor_exe=metaeditor_exe,
            terminal_data_path=terminal_data_path,
            tester_root=root / "tester_root",
            tester_profiles_dir=tester_profiles_dir,
            config_dir=config_dir,
            output_root=output_root,
         )
         spec = runner.build_spec({"name": "cache_hit_probe"})
         terminal_info = {"path": str(terminal_exe), "size": 1, "mtime_ns": 2}
         dependency_hash = "dep_hash_v1"
         base_set_text = base_set_path.read_text(encoding="ascii")
         cache_key = runner.compute_cache_key(spec, base_set_text, terminal_info, dependency_hash)
         run_dir = output_root / f"cache_hit_probe__{cache_key}"
         collected_dir = run_dir / "collected"
         collected_dir.mkdir(parents=True)
         (run_dir / "run_manifest.json").write_text("{}", encoding="ascii")
         (collected_dir / runner.SUMMARY_FILENAME).write_text("summary", encoding="ascii")
         (collected_dir / runner.DAILY_FILENAME).write_text("daily", encoding="ascii")
         cached_report = collected_dir / f"{spec.report_stem}_{cache_key}.xml.htm"
         cached_report.write_text("report", encoding="ascii")

         original_terminal_fingerprint = runner.terminal_fingerprint
         original_dependency_hash = runner.compute_ea_dependency_hash
         original_sync_repo = runner.sync_repo
         original_compile_ea = runner.compile_ea
         original_stop_existing_mt5 = runner.stop_existing_mt5
         original_assert_no_running_mt5 = runner.assert_no_running_mt5

         def fail(*args, **kwargs):
            raise AssertionError("preflight should not run on cache hit")

         try:
            runner.terminal_fingerprint = lambda _: terminal_info
            runner.compute_ea_dependency_hash = lambda _: dependency_hash
            runner.sync_repo = fail
            runner.compile_ea = fail
            runner.stop_existing_mt5 = fail
            runner.assert_no_running_mt5 = fail

            result = runner.run_single_backtest(
               spec,
               paths,
               dry_run=False,
               sync_before_run=True,
               compile_before_run=True,
               force=False,
               stop_existing=False,
            )
         finally:
            runner.terminal_fingerprint = original_terminal_fingerprint
            runner.compute_ea_dependency_hash = original_dependency_hash
            runner.sync_repo = original_sync_repo
            runner.compile_ea = original_compile_ea
            runner.stop_existing_mt5 = original_stop_existing_mt5
            runner.assert_no_running_mt5 = original_assert_no_running_mt5

      self.assertEqual(result["status"], "cache_hit")
      self.assertEqual(result["report_path"], str(cached_report))

   def test_run_single_backtest_does_not_cache_hit_when_report_missing(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         root = Path(tmp_dir)
         repo_root = root / "repo"
         output_root = root / "output"
         tester_profiles_dir = root / "tester_profiles"
         config_dir = root / "config"
         terminal_data_path = root / "terminal_data"
         terminal_exe = root / "terminal64.exe"
         metaeditor_exe = root / "metaeditor64.exe"
         tests_dir = repo_root / "Tests" / "RPEA"
         base_set_path = tests_dir / "RPEA_10k_default.set"
         template_ini_path = tests_dir / "RPEA_10k_single.ini"
         expert_dir = repo_root / "MQL5" / "Experts" / "FundingPips"
         include_dir = repo_root / "MQL5" / "Include" / "RPEA"

         tests_dir.mkdir(parents=True)
         expert_dir.mkdir(parents=True)
         include_dir.mkdir(parents=True)
         output_root.mkdir(parents=True)
         tester_profiles_dir.mkdir(parents=True)
         config_dir.mkdir(parents=True)
         terminal_data_path.mkdir(parents=True)
         terminal_exe.write_text("terminal", encoding="ascii")
         metaeditor_exe.write_text("metaeditor", encoding="ascii")
         base_set_path.write_text("RiskPct=1.5\n", encoding="ascii")
         template_ini_path.write_text("[Tester]\nExpert=FundingPips\\RPEA\n", encoding="ascii")
         (expert_dir / "RPEA.mq5").write_text("#property strict\n", encoding="ascii")
         (include_dir / "dummy.mqh").write_text("#property strict\n", encoding="ascii")

         paths = runner.RunnerPaths(
            repo_root=repo_root,
            terminal_exe=terminal_exe,
            metaeditor_exe=metaeditor_exe,
            terminal_data_path=terminal_data_path,
            tester_root=root / "tester_root",
            tester_profiles_dir=tester_profiles_dir,
            config_dir=config_dir,
            output_root=output_root,
         )
         spec = runner.build_spec({"name": "cache_miss_probe"})
         terminal_info = {"path": str(terminal_exe), "size": 1, "mtime_ns": 2}
         dependency_hash = "dep_hash_v1"
         base_set_text = base_set_path.read_text(encoding="ascii")
         cache_key = runner.compute_cache_key(spec, base_set_text, terminal_info, dependency_hash)
         run_dir = output_root / f"cache_miss_probe__{cache_key}"
         collected_dir = run_dir / "collected"
         collected_dir.mkdir(parents=True)
         (run_dir / "run_manifest.json").write_text("{}", encoding="ascii")
         (collected_dir / runner.SUMMARY_FILENAME).write_text("summary", encoding="ascii")
         (collected_dir / runner.DAILY_FILENAME).write_text("daily", encoding="ascii")

         original_terminal_fingerprint = runner.terminal_fingerprint
         original_dependency_hash = runner.compute_ea_dependency_hash
         original_sync_repo = runner.sync_repo
         original_assert_no_running_mt5 = runner.assert_no_running_mt5
         sync_calls: list[str] = []

         try:
            runner.terminal_fingerprint = lambda _: terminal_info
            runner.compute_ea_dependency_hash = lambda _: dependency_hash
            runner.sync_repo = lambda repo: sync_calls.append(str(repo))
            runner.assert_no_running_mt5 = lambda: None

            result = runner.run_single_backtest(
               spec,
               paths,
               dry_run=True,
               sync_before_run=True,
               compile_before_run=False,
               force=False,
               stop_existing=False,
            )
         finally:
            runner.terminal_fingerprint = original_terminal_fingerprint
            runner.compute_ea_dependency_hash = original_dependency_hash
            runner.sync_repo = original_sync_repo
            runner.assert_no_running_mt5 = original_assert_no_running_mt5

      self.assertEqual(result["status"], "dry_run")
      self.assertEqual(len(sync_calls), 1)

   def test_run_batch_syncs_first_uncached_run_after_cache_hit(self) -> None:
      with tempfile.TemporaryDirectory() as tmp_dir:
         batch_path = Path(tmp_dir) / "batch.json"
         batch_path.write_text(
            runner.stable_json(
               {
                  "defaults": {"symbol": "EURUSD"},
                  "runs": [
                     {"name": "cached_run"},
                     {"name": "uncached_run"},
                     {"name": "later_run"},
                  ],
               }
            ),
            encoding="ascii",
         )

         fake_paths = runner.RunnerPaths(
            repo_root=Path(tmp_dir),
            terminal_exe=Path(tmp_dir) / "terminal64.exe",
            metaeditor_exe=Path(tmp_dir) / "metaeditor64.exe",
            terminal_data_path=Path(tmp_dir) / "terminal_data",
            tester_root=Path(tmp_dir) / "tester_root",
            tester_profiles_dir=Path(tmp_dir) / "tester_profiles",
            config_dir=Path(tmp_dir) / "config",
            output_root=Path(tmp_dir) / "output",
         )
         call_sync_flags: list[bool] = []
         statuses = iter(("cache_hit", "completed", "completed"))
         original_run_single_backtest = runner.run_single_backtest

         def fake_run_single_backtest(spec, paths, **kwargs):
            self.assertEqual(paths, fake_paths)
            call_sync_flags.append(kwargs["sync_before_run"])
            return {"status": next(statuses), "name": spec.name}

         try:
            runner.run_single_backtest = fake_run_single_backtest
            result = runner.run_batch(
               batch_path,
               fake_paths,
               dry_run=False,
               sync_before_run=True,
               compile_before_run=True,
               force=False,
               stop_existing=False,
            )
         finally:
            runner.run_single_backtest = original_run_single_backtest

      self.assertEqual(call_sync_flags, [True, True, False])
      self.assertEqual(len(result["results"]), 3)

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

   def test_compact_slug_shortens_overlong_names_with_hash_suffix(self) -> None:
      raw = "phase5_anchor_pipeline__stage3__wf001_202508__report__baseline_artifacts__ql_enabled__baseline"

      compact = runner.compact_slug(raw, max_length=64)

      self.assertLessEqual(len(compact), 64)
      self.assertRegex(compact, r"_[0-9a-f]{12}$")
      self.assertNotEqual(compact, runner.safe_name(raw))

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

   def test_load_ini_text_with_encoding_round_trips_non_ascii(self) -> None:
      ini_text = "[Common]\nServer=München-Broker\nAccountName=Jörg\n"

      with tempfile.TemporaryDirectory() as tmp_dir:
         ini_path = Path(tmp_dir) / "common.ini"
         output_path = Path(tmp_dir) / "generated.ini"
         ini_path.write_text(ini_text, encoding="utf-16")

         loaded_text, encoding = runner.load_ini_text_with_encoding(ini_path)
         output_path.write_text(loaded_text + "\n[Tester]\nExpert=FundingPips\\RPEA\n", encoding=encoding)
         round_trip = output_path.read_text(encoding="utf-16")

      self.assertEqual(encoding, "utf-16")
      self.assertIn("München", round_trip)
      self.assertIn("Jörg", round_trip)

   def test_wait_for_artifacts_uses_xml_htm_fallback_when_xml_is_stale(self) -> None:
      class FakeProcess:
         def poll(self):
            return None

      with tempfile.TemporaryDirectory() as tmp_dir:
         root = Path(tmp_dir)
         tester_root = root / "tester_root"
         report_root = root / "terminal_data" / "Tester" / "reports"
         tester_root.mkdir(parents=True)
         report_root.mkdir(parents=True)
         summary_path = tester_root / runner.SUMMARY_FILENAME
         daily_path = tester_root / runner.DAILY_FILENAME
         expected_report_path = report_root / "probe.xml"
         alt_report_path = expected_report_path.with_suffix(expected_report_path.suffix + ".htm")
         started_at = time.time() - 5.0

         summary_path.write_text("summary", encoding="ascii")
         daily_path.write_text("daily", encoding="ascii")
         expected_report_path.write_text("stale xml", encoding="ascii")
         alt_report_path.write_text("fresh html", encoding="ascii")

         os.utime(summary_path, (started_at + 1.0, started_at + 1.0))
         os.utime(daily_path, (started_at + 1.0, started_at + 1.0))
         os.utime(expected_report_path, (started_at - 1.0, started_at - 1.0))
         os.utime(alt_report_path, (started_at + 2.0, started_at + 2.0))

         artifacts = runner.wait_for_artifacts(
            process=FakeProcess(),
            tester_root=tester_root,
            expected_report_path=expected_report_path,
            timeout_seconds=1,
            started_at=started_at,
         )

      self.assertEqual(artifacts["report"], alt_report_path)

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
