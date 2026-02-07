---
description: 
alwaysApply: true
---

# Repository Guidelines

## Project Structure & Module Organization
- `MQL5/Experts/FundingPips/RPEA.mq5` is the Expert Advisor entry point; its includes mirror modules under `MQL5/Include/RPEA`.
- Core subsystems live in `MQL5/Include/RPEA/*.mqh` (order engine, risk, synthetic manager, news, telemetry). Keep functions scoped to their modules and guard headers.
- Tests reside in `Tests/RPEA`, with CSV fixtures in `Tests/RPEA/fixtures/news`. Production news fallback data is at `Files/RPEA/news/calendar_high_impact.csv`.

## Codebase State (Living Document)

> **Rule**: After implementing any task, update **Last Updated**, the module table
> that changed, and the **Recent Changes** list at the bottom of this section.
> This keeps future agents current without a full codebase scan.

**Last Updated**: M7 Task 07 complete (2026-02-07). Execution mode enabled; Task 08 pending.

### Module Inventory

Each row shows responsibility, current line count, and which layer it belongs to.
Agents should check this table before editing a module to understand its scope and
avoid unintended coupling.

| Module | Lines | Layer | Responsibility |
|--------|------:|-------|----------------|
| `order_engine.mqh` | ~5550 | Execution | OCO, market fallback, retries, trailing, two-leg atomic ops, partial fills. **Largest module; edit with care.** |
| `persistence.mqh` | ~2020 | Support | File-backed state recovery, intent queue, challenge state persistence. |
| `equity_guardian.mqh` | ~1350 | Risk | Baseline tracking, daily/overall floors, kill-switch, MicroMode activation (+10% target), giveback protection. |
| `queue.mqh` | ~1250 | Execution | Action queueing during news windows, TTL expiry, post-news revalidation. |
| `config.mqh` | ~1070 | Support | EA inputs, validation, clamping. Many `#ifdef RPEA_TEST_RUNNER` branches. |
| `news.mqh` | ~875 | Support | Calendar API + CSV fallback, T +/-300s window, `News_IsEntryBlocked`, `News_GetWindowStateDetailed`. |
| `synthetic.mqh` | ~650 | Execution | XAUEUR proxy/replication manager (XAUUSD-only or two-leg XAUUSD+EURUSD). |
| `allocator.mqh` | ~572 | Risk | Builds `OrderPlan` for **BWISC + MR**, strategy-specific risk sizing, budget gate, and strategy-tagged comments. |
| `sessions.mqh` | ~445 | Support | Session windows (LO, NY), OR snapshot. |
| `logging.mqh` | ~415 | Support | CSV audit rows (`LogAuditRow`), structured `LogDecision`. |
| `indicators.mqh` | ~403 | Support | Indicator snapshots (ATR, MA, Bollinger, etc.). |
| `emrt.mqh` | ~377 | M7 Ensemble | EMRT formation (rank, P50, beta). Used by MR signals. |
| `breakeven.mqh` | ~312 | Execution | Breakeven at +0.5R. |
| `trailing.mqh` | ~288 | Execution | Trailing stop logic (ATR-based, activates at +1R). |
| `rl_pretrain_inputs.mqh` | ~277 | M7 Ensemble | Pre-training parameter defaults (MR_RiskPct_Default, TimeStopMin/Max, etc.). |
| `meta_policy.mqh` | ~306 | Signal | Strategy chooser (BWISC vs MR vs Skip). Deterministic rules + optional bandit. **`M7_DECISION_ONLY` is 0 (execution enabled).** |
| `state.mqh` | ~237 | Support | `ChallengeState` struct, `State_Get()`/`State_Set()` accessors. |
| `signals_bwisc.mqh` | ~230 | Signal | BWISC signals (BC/MSC). Populates `g_last_bwisc_context` (`BWISC_Context`). |
| `rl_agent.mqh` | ~220 | M7 Ensemble | Q-learning table, `RL_StateFromSpread`, `RL_GetQAdvantage`. |
| `signals_mr.mqh` | ~282 | Signal | MR signals (mean reversion, EMRT + RL). Populates `g_last_mr_context` with execution-symbol entry price and direction. |
| `liquidity.mqh` | ~204 | Support | Rolling spread/slippage stats, quantile getters, `Liquidity_SpreadOK`. |
| `risk.mqh` | ~192 | Risk | `Risk_SizingByATRDistanceForSymbol`, `Risk_GetEffectiveRiskPct` (handles MicroMode). |
| `m7_helpers.mqh` | ~185 | M7 Ensemble | Wrapper functions (ATR, spread, session helpers) to avoid circular includes. |
| `scheduler.mqh` | ~123 | Orchestration | Main tick handler. Calls signals -> meta-policy -> allocator -> logs. |
| `symbol_bridge.mqh` | ~85 | Support | XAUEUR -> XAUUSD mapping. `SymbolBridge_GetExecutionSymbol()`. |
| `regime.mqh` | ~81 | M7 Ensemble | Regime detection (trending/ranging/volatile). ADX + ATR percentile. |
| `telemetry.mqh` | ~64 | Support | `LogMetaPolicyDecision` (structured meta-policy telemetry). |
| `slo_monitor.mqh` | ~60 | M7 Ensemble | SLO metrics stub + threshold check (`SLO_InitMetrics`, `SLO_CheckAndThrottle`). |
| `app_context.mqh` | ~27 | Support | `AppContext` struct definition. |
| `mr_context.mqh` | ~17 | Signal | Lightweight `MR_Context` struct + `g_last_mr_context` (allocator-safe include). |
| `bandit.mqh` | ~12 | M7 Ensemble | Contextual bandit stub (optional meta-policy enhancement). |

**Files planned for Task 08**:
- No new required headers from Task 07 remain pending.

### Key Design Decisions (Locked)

1. **Context Separation**: `BWISC_Context` lives in `signals_bwisc.mqh`. Task 07 creates `MR_Context` in a dedicated lightweight `mr_context.mqh`. Allocator includes only context headers, NOT full signal modules (avoids circular includes: `signals_mr` -> `m7_helpers` -> `order_engine`).

2. **Strategy-Specific Risk**: MR will use `Config_GetMRRiskPctDefault()` (0.90%) in normal mode, `Config_GetMicroRiskPct()` in MicroMode. BWISC uses `Risk_GetEffectiveRiskPct()` (already handles MicroMode). Both respect MicroMode for challenge compliance.

3. **Entry Price Source**: MR entry price must come from the **execution symbol** (`SymbolBridge_GetExecutionSymbol(signal_symbol)`), not signal symbol. Using XAUEUR quotes directly produces invalid prices.

4. **Execution Mode Gate**: `M7_DECISION_ONLY` flag in `meta_policy.mqh` is now **0** (execution enabled).

5. **Order Comment Format**: `"{prefix}{strategy}-{setup_type} b={bias} conf={confidence} {timestamp}"`. MR uses `setup_type = "MR"` (forced in allocator, not derived from entry vs bid/ask like BC/MSC).

6. **Risk Units**: `Risk_SizingByATRDistanceForSymbol()` expects percentage directly (e.g., 0.90 for 0.90%). Do **not** divide by 100.

### Integration Flow (Current State)

```
scheduler.mqh tick loop:
  1. Gate checks (floors, news, spread, session)
  2. SignalsBWISC_Propose() -> populates g_last_bwisc_context
  3. SignalsMR_Propose()    -> populates output params + g_last_mr_context
  4. MetaPolicy_Choose()    -> returns "BWISC" | "MR" | "Skip"
  5. Allocator_BuildOrderPlan(strategy, symbol, sl, tp, conf) -> OrderPlan
  6. If plan.valid -> OrderEngine places order (execution enabled)
```

**MicroMode Integration**:
- Activated by `Equity_IsMicroModeActive()` (reads `state.micro_mode` flag).
- All strategies respect it. To test: `State_Get()` / `State_Set(st)` with `st.micro_mode = true`.
- Restore original state after test: `State_Set(orig_st)`.

### Patterns for Agents

**Include Guard**: All `.mqh` files use `#ifndef RPEA_MODULE_MQH` / `#define` / `#endif`.

**Context Population** (signal modules):
```cpp
// Clear at function start, populate before hasSetup=true
g_last_bwisc_context.entry_price = 0.0;
// ... signal logic ...
g_last_bwisc_context.entry_price = ask; // or bid based on direction
```

**Test Pattern**: Unit tests in `Tests/RPEA/test_*.mqh`. Register in `run_automated_tests_ea.mq5`. Use deterministic values (manually set globals, don't rely on live broker prices). Use EURUSD for stable tester execution.

**AppContext in Tests**: Always `ZeroMemory(ctx); ArrayResize(ctx.symbols, N);` before assigning `ctx.symbols[i]`.

### Recent Changes (Newest First)

Update this list when completing a task. Helps agents understand what just changed.

- **M7 Task 07** (complete): Added `mr_context.mqh`, populated MR context in `signals_mr.mqh`, integrated MR strategy path in `allocator.mqh` (context selection, strategy-specific risk, MR setup type/comment format), enabled execution mode in `meta_policy.mqh` (`M7_DECISION_ONLY=0`), added `slo_monitor.mqh` stub, added `test_allocator_mr.mqh`, and wired `M7Task07_AllocatorMR` in `run_automated_tests_ea.mq5`. Validation: compile clean, tests `34/34` passed including `M7Task07_AllocatorMR`.
- **Ops Note (2026-02-07)**: During M7 Task 07 preflight, `run_tests.ps1` appeared stalled because the test runner had a compile blocker (`Tests/RPEA/run_automated_tests_ea.mq5` contained stray token at line 597). Added troubleshooting guidance in Build/Test commands: compile the test runner first, then use explicit `/config:` Strategy Tester invocation and verify latest tester-agent `test_results.json` when needed.
- **M7 Task 06** (complete): Added `Regime_Detect()` in `regime.mqh`, `LogMetaPolicyDecision()` in `telemetry.mqh`, rolling liquidity stats in `liquidity.mqh`, efficiency stubs in `meta_policy.mqh`, wired quantiles/regime into meta-policy, `Liquidity_UpdateStats` fed from scheduler + order engine. Tests: `test_regime_telemetry.mqh`.
- **M7 Task 05** (complete): Full `MetaPolicy_Choose()` with deterministic rules (Rules 0-6), `MetaPolicyContext` struct, bandit integration stub, `M7_DECISION_ONLY=1`. Tests: `test_meta_policy.mqh`.
- **M7 Task 04** (complete): `SignalsMR_Propose()` with EMRT+RL confidence, entry conditions, SL/TP calculation. Tests: `test_signals_mr.mqh`.
- **M7 Task 03** (complete): Pre-training script (`MQL5/Scripts/rl_pretrain.mq5`), Q-table file generation.
- **M7 Task 02** (complete): `rl_agent.mqh` - Q-learning table, state discretization, action policy. Tests: `test_rl_agent.mqh`.
- **M7 Task 01** (complete): `emrt.mqh` - EMRT formation, rank, P50, beta functions.
- **M7 Phase 0** (complete): Stubs, helpers (`m7_helpers.mqh`), ensemble inputs in `RPEA.mq5`.

### When Adding New Features

1. **Check the module table above** for file sizes and layer. Large modules need more care.
2. **Avoid circular includes**: Use lightweight context headers if module A needs types from module B but B already includes A's dependencies.
3. **Respect MicroMode**: All risk-sizing paths must check `Equity_IsMicroModeActive()`.
4. **After implementation**: Update this section -- bump "Last Updated", update changed module line counts, add entry to "Recent Changes".
5. **Test integration**: Verify signal -> allocator -> order engine flow. Set g_last contexts manually in tests.

## Current Baseline & Workflow
- Milestones M3-M6 complete (order engine, compliance, strategy tester, hardening).
- **Active milestone**: M7 ensemble integration (BWISC + MR). Source of truth: `docs/m7-final-workflow.md`. Base branch: `feat/m7-ensemble-integration`.
- **M7 progress**: Tasks 01-07 complete. Task 08 (end-to-end testing) is the final task.
- Task execution: each `m7-taskXX.md` provides atomic steps: implement logic, add/extend tests, wire into `Tests/RPEA/run_automated_tests_ea.mq5`, compile checkpoint after each step. Follow `docs/m7-final-workflow.md` step-by-step.
- Branching: work on per-task branches and merge into the milestone base. For M7, follow phase branches (e.g., `feat/m7-phase5-task07-allocator-integration` -> `feat/m7-ensemble-integration`).

## Build, Test, and Development Commands

**Important**: Code is edited in the repo (`C:\Users\AWCS\earl-1`). Compiling must happen from the **MT5 data folder** because `/compile:` paths are relative to the working directory.

- **Sync repo to MT5**: `powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1` (run from repo root).
- **Compile EA** (from MT5 data folder):
  ```
  cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075" && "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
  ```
- **Run tests** (from repo root): `powershell -ExecutionPolicy Bypass -File run_tests.ps1` - launches Strategy Tester, writes results to `MQL5/Files/RPEA/test_results/test_results.json`.
- Strategy Tester manual reruns: attach `Tests/RPEA/run_automated_tests_ea.mq5` to the tester to exercise suites such as `Task10_News_CSV_Fallback`.
- Troubleshooting `run_tests.ps1` stalls: first compile test runner separately (from MT5 data folder): `"C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\Tests\RPEA\run_automated_tests_ea.mq5 /log:MQL5\Experts\Tests\RPEA\compile_automated_tests.log`; if compile fails, fix runner before retrying tests.
- Fallback when script still stalls: run terminal with explicit config (`terminal64.exe /config:<ini>`) using `Expert=Tests\RPEA\run_automated_tests_ea`, `ExpertParameters=Tests\RPEA\run_automated_tests.set`, `ShutdownTerminal=1`; then verify latest tester-agent result at `%APPDATA%\MetaQuotes\Tester\...\Agent-*\MQL5\Files\RPEA\test_results\test_results.json`.

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
- Preferred messages mirror `M3: Task <id> - summary`, `M4: Task <id> - summary`, `M5: Task <id> - summary`, `M6: Task <id> - summary`, or `M7: Task <id> - summary`, or use concise imperatives aligned with the workstream.
- Develop on task/phase branches (e.g., `feat/m3-task24` -> `feat/m3-phase5-optimization` -> `feat/m3-order-engine`). For M4 compliance polish, use `feat/m4-taskXX` -> optional `feat/m4-phaseY` -> base `feat/m4-compliance-polish` (or the current M4 base branch). For M5 Strategy Tester artifacts, use `feat/m5-taskXX` -> base `feat/m5-strategy-tester`. For M6 hardening, use `feat/m6-taskXX` -> base `feat/m6-hardening`. For M7, follow `docs/m7-final-workflow.md` phase branches (e.g., `feat/m7-phase0-scaffold` -> `feat/m7-phase1-foundation` -> `feat/m7-ensemble-integration`).
- Pull requests should summarize scope, link supporting docs (e.g., `task10.md`), and attach the latest automated test outcome or relevant compile logs.

## Agent-Specific Notes
- Respect existing worktree changes; never revert user edits unless asked.
- Use `rg` for search and keep edits ASCII unless the file already uses other encodings.
- Validate queueing, synthetic pricing, and risk behaviors against `.kiro/specs/rpea-m3/{tasks.md, design.md, requirements.md}` whenever updating those systems.
- Git Status Commands: When checking git status for task work, use PowerShell in the repo root (not WSL) and run `git status --short` (without filtering) to see all changes including both untracked (`??`) and modified (`M`) files. This ensures you see both new untracked task files (e.g., `m6-task01.md`) and any files modified during the current work session (e.g., `AGENTS.md`). When reporting or focusing, prioritize untracked milestone task markdown files (`m[0-9]-task*.md`), but do not filter out modified files entirely as they may include important changes made during the task. To see only untracked task files, use `git status --short | Select-String \"^\\?\\?.*m[0-9]-task\"`.
