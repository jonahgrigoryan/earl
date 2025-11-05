# Repository Guidelines

## Project Structure & Module Organization
- `MQL5/Experts/FundingPips/RPEA.mq5` is the Expert Advisor entry point; its includes mirror modules under `MQL5/Include/RPEA`.
- Core subsystems live in `MQL5/Include/RPEA/*.mqh` (order engine, risk, synthetic manager, news, telemetry). Keep functions scoped to their modules and guard headers.
- Tests reside in `Tests/RPEA`, with CSV fixtures in `Tests/RPEA/fixtures/news`. Production news fallback data is at `Files/RPEA/news/calendar_high_impact.csv`.

## Build, Test, and Development Commands
- `MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log` — compile the EA and produce a compile log.
- `powershell -ExecutionPolicy Bypass -File run_tests.ps1` — launch MetaTrader Strategy Tester, execute `Tests/RPEA/run_automated_tests_ea.mq5`, and write results to `MQL5/Files/RPEA/test_results/test_results.json`.
- Strategy Tester manual reruns: attach `Tests/RPEA/run_automated_tests_ea.mq5` to the tester to exercise suites such as `Task10_News_CSV_Fallback`.

## Coding Style & Naming Conventions
- Use strict MQL5 mode, three-space indentation, and braces on new lines to match existing `.mq5/.mqh` files.
- Types use `PascalCase`; functions follow `Module_Action` (e.g., `News_ForceReload`); constants/macros are ALL_CAPS.
- Avoid wildcard includes. Reference modules explicitly via `<RPEA/...>` and keep helpers in `MQL5/Include/RPEA`.

## Testing Guidelines
- Add new unit suites under `Tests/RPEA/test_*.mqh`, following `Scenario_Action_Expectation` naming.
- Mirror fixture changes between `Tests/RPEA/fixtures/news` and `Files/RPEA/news/calendar_high_impact.csv`.
- Always rerun `powershell -ExecutionPolicy Bypass -File run_tests.ps1` before submitting; include the updated JSON or key log excerpts when relevant.

## Commit & Pull Request Guidelines
- Preferred messages mirror `M3: Task <id> — summary` or concise imperatives aligned with the workstream.
- Develop on feature branches like `cursor/complete-project-implementation-from-task-10-76ee` targeting `feat/m3-phase3-risk-trailing`.
- Pull requests should summarize scope, link supporting docs (e.g., `task10.md`), and attach the latest automated test outcome or relevant compile logs.

## Agent-Specific Notes
- Respect existing worktree changes; never revert user edits unless asked.
- Use `rg` for search and keep edits ASCII unless the file already uses other encodings.
- Validate queueing, synthetic pricing, and risk behaviors against `.kiro/specs/rpea-m3/{tasks.md, design.md, requirements.md}` whenever updating those systems.
