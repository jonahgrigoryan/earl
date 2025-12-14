# Repository Guidelines

## Project Structure & Module Organization
- `MQL5/Experts/FundingPips/RPEA.mq5` is the Expert Advisor entry point; its includes mirror modules under `MQL5/Include/RPEA`.
- Core subsystems live in `MQL5/Include/RPEA/*.mqh` (order engine, risk, synthetic manager, news, telemetry). Keep functions scoped to their modules and guard headers.
- Tests reside in `Tests/RPEA`, with CSV fixtures in `Tests/RPEA/fixtures/news`. Production news fallback data is at `Files/RPEA/news/calendar_high_impact.csv`.

## Current Baseline & Workflow
- Milestone: M3 complete (Phases 1–5). Tasks 21–24 are part of baseline (confidence-based sizing, ATR spread filter, breakeven at +0.5R, 45m pending expiry). Current tip: `feat/m3-order-engine` (merged via `feat/m3-phase5-optimization` and task branches).
- Task execution: each `taskXX.md` (e.g., `task21.md`–`task24.md`) provides atomic steps—implement logic, add/extend tests, wire into `Tests/RPEA/run_automated_tests_ea.mq5`, update docs/fixtures. Use `m3_structure.md` and `.kiro/specs/rpea-m3/{tasks.md, design.md, requirements.md}` for context.
- Branching: work on per-task branches (`feat/m3-task23`, `feat/m3-task24`, etc.), merge into the phase aggregator, then into `feat/m3-order-engine`. Avoid outdated branch examples.
- Upcoming milestone: M4 (compliance polish per `finalspec.md` / `prd.md`—calendar integration, CEST day tracking, min trade days, kill-switch floors, disable flags, persistence hardening). Use the M4 naming pattern below when starting new work.

## Build, Test, and Development Commands
- `MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log` — compile the EA and produce a compile log.
- `powershell -ExecutionPolicy Bypass -File run_tests.ps1` — launch MetaTrader Strategy Tester, execute `Tests/RPEA/run_automated_tests_ea.mq5`, and write results to `MQL5/Files/RPEA/test_results/test_results.json`.
- Strategy Tester manual reruns: attach `Tests/RPEA/run_automated_tests_ea.mq5` to the tester to exercise suites such as `Task10_News_CSV_Fallback`.

## Coding Style & Naming Conventions
- Use strict MQL5 mode, three-space indentation, and braces on new lines to match existing `.mq5/.mqh` files.
- Types use `PascalCase`; functions follow `Module_Action` (e.g., `News_ForceReload`); constants/macros are ALL_CAPS.
- Avoid wildcard includes. Reference modules explicitly via `<RPEA/...>` and keep helpers in `MQL5/Include/RPEA`.
- No `static` variables; prefer `CArrayObj` over STL; favor early returns and explicit types.

## Testing Guidelines
- Add new unit suites under `Tests/RPEA/test_*.mqh`, following `Scenario_Action_Expectation` naming.
- Mirror fixture changes between `Tests/RPEA/fixtures/news` and `Files/RPEA/news/calendar_high_impact.csv`.
- Always rerun `powershell -ExecutionPolicy Bypass -File run_tests.ps1` before submitting; include the updated JSON or key log excerpts when relevant. The runner includes Phase 5 suites (breakeven, pending expiry) by default.

## Commit & Pull Request Guidelines
- Preferred messages mirror `M3: Task <id> — summary` or concise imperatives aligned with the workstream.
- Develop on task/phase branches (e.g., `feat/m3-task24` → `feat/m3-phase5-optimization` → `feat/m3-order-engine`). For M4 compliance polish, use `feat/m4-taskXX` → optional `feat/m4-phaseY` → base `feat/m4-compliance-polish` (or the current M4 base branch).
- Pull requests should summarize scope, link supporting docs (e.g., `task10.md`), and attach the latest automated test outcome or relevant compile logs.

## Agent-Specific Notes
- Respect existing worktree changes; never revert user edits unless asked.
- Use `rg` for search and keep edits ASCII unless the file already uses other encodings.
- Validate queueing, synthetic pricing, and risk behaviors against `.kiro/specs/rpea-m3/{tasks.md, design.md, requirements.md}` whenever updating those systems.
