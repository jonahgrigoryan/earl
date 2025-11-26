# Warp Agent Guidelines for Earl-1

## Project Overview
This is an MQL5 Expert Advisor (EA) project (RPEA M3).
It follows a SPARC-like methodology with specific phases for implementation.

## Project Structure
- `MQL5/Experts/FundingPips/RPEA.mq5`: Main EA entry point.
- `MQL5/Include/RPEA/*.mqh`: Core subsystems (order engine, risk, etc).
- `Tests/RPEA`: Unit tests.
- `Files/RPEA`: Runtime files (logs, state, news).
- Strategy Tester builds live under `%APPDATA%\MetaQuotes\Tester\D0E8209F77C8CF37AD8BF550E51FF075\Agent-*/MQL5`.

## Development Commands
### Build
```powershell
MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
```

### Test
```powershell
powershell -ExecutionPolicy Bypass -File run_tests.ps1
```
This runs `Tests/RPEA/run_automated_tests_ea.mq5` in the Strategy Tester.
If Strategy Tester automation stalls, open the tester terminal (`%APPDATA%\MetaQuotes\Tester\...`) and run the EA manually with the preset in `Tests/RPEA/run_automated_tests.set`.

## Code Style & Conventions
- **Language**: MQL5 (strict mode).
- **Indentation**: 3 spaces.
- **Naming**: `PascalCase` for types, `Module_Action` for functions.
- **Constraints**:
  - No `static` variables.
  - Use `CArrayObj` instead of `std::vector`.
  - Explicit types (avoid `auto`).
  - Early returns preferred.
  - Header guards required.

## Workflow
Follow the 5-Phase implementation plan defined in `zen_prompts_m3.md`.
Refer to `AGENTS.md` for detailed agent-specific instructions.

## Important Notes
- **XAUEUR**: Used as signal source only (Task 11). Execution maps to XAUUSD (Task 15).
- **Atomic Operations**: Removed/Simplified.
- **Replication**: Removed.
- **Master Accounts**: SL enforcement within 30s required.

## Current Milestone Status
- Milestone: **M3 Phase 5** (Tasks 21-24). Tasks 1-20 complete; Task 21 (dynamic risk by confidence) implemented and under test.
- Active branch: `feat/m3-task21`.
- Read `task21.md`, `tasks.md`, and `m3_structure.md` before coding.

## Testing & Verification
1. Recompile from the main terminal (`C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075`).
2. Copy or recompile the EA in the Strategy Tester installation (`%APPDATA%\MetaQuotes\Tester\...`) before running tester suites; each agent folder (`Agent-127.0.0.1-xxxx`) needs the updated files.
3. Run `Tests/RPEA/run_automated_tests_ea.mq5` (either via `run_tests.ps1` or manual Strategy Tester) and ensure all 18 suites pass.

## Hand-off Checklist for New Agents
- Review: `AGENTS.md`, `zen_prompts_m3.md`, `.kiro/specs/rpea-m3/*.md`, and the active `taskXX.md`.
- Confirm the tester data folder contains the latest includes/experts (copy from the repo or recompile inside the tester’s MetaEditor).
- Respect coding conventions (3-space indent, no `static`, `CArrayObj` instead of STL).
- Log changes in `MQL5/Files/RPEA/logs` and keep `test_results.json` up to date after test runs.
