# Claude Code Instructions - RPEA M7

This repo is an MQL5 EA. Scope is M7 only, production development and end-to-end testing.
Use `docs/m7-final-workflow.md` as the source of truth for tasks, sequencing, and phase branches.

## Must Read
- Always open and follow `AGENTS.md`. If it conflicts with this file, follow `AGENTS.md`.
- Keep changes within the phase requested by the user. Do not start later phases.

## Branching (M7)
- Base branch: `feat/m7-ensemble-integration`
- Create phase branches from base (Phase 0 uses `feat/m7-phase0-scaffold`; follow `docs/m7-final-workflow.md` for phase naming).

## Build/Test
- Compile EA: `MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log`
- Run tests: `powershell -ExecutionPolicy Bypass -File run_tests.ps1`

## MQL5 Style
- Strict mode, 3-space indent, braces on new lines.
- Types PascalCase, functions Module_Action, constants ALL_CAPS.
- No static variables; avoid wildcard includes; use `<RPEA/...>` includes.
- Prefer early returns, explicit types.

## Files and Safety
- Do not create new root files unless explicitly requested.
- Do not revert user changes; avoid destructive git.
- Keep ASCII unless the file already uses non-ASCII.

## Parallel Agents
- Use parallel agents only when asked. Otherwise work sequentially.
