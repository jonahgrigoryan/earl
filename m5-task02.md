# M5-Task02: Walk-forward automation scripts

## Objective

Automate walk-forward optimization and OOS validation for the RPEA $10k presets using MT5 Strategy Tester.

## Dependencies

- Requires M5-Task01 presets and .ini configs.

## Deliverables

- scripts/walk_forward.ps1
- scripts/walk_forward.cmd
- scripts/wf_config.json

## Requirements

- Support portable and default MT5 installations.
- Use the Task01 .ini files to run optimization and single tests.
- Parse optimization XML and select top results by OptimizationCriterion.
- Apply a minimum trades filter (reject parameter sets with < 10 trades).
- Apply FundingPips pass criteria on OOS results: target profit >= 10% ($1000 on $10k), trade days >= 3, daily cap violations = 0, overall cap violations = 0.
- Run OOS single test for each selected parameter set.
- Emit a CSV summary (IS + OOS metrics per window) including pass/fail and the criteria values.
- Avoid writing outside repo unless explicitly configured.

## Files to Modify/Create

- scripts/walk_forward.ps1
- scripts/walk_forward.cmd
- scripts/wf_config.json
- Files/RPEA/reports/ (output CSVs)

## Steps

1. Define wf_config.json with MT5 paths, profile_base, symbols, window sizes, and output paths.
2. Implement walk_forward.ps1:
   - Resolve repo root.
   - Detect portable vs default MT5 paths.
   - Copy .set files to MT5 Profiles/Tester if needed.
   - Run optimization via terminal64.exe /config:<ini> for each window.
   - Parse optimization XML, filter by min trades, select top N.
   - Run single-test OOS configs for selected params.
   - Parse OOS report and compute FundingPips pass criteria (profit target, trade days, daily/overall caps).
   - If a candidate fails pass criteria, try the next candidate until you have N passing or exhaust the list.
   - Append results to CSV in Files/RPEA/reports with pass/fail and criteria values.
3. Add walk_forward.cmd wrapper for double-click usage.
4. Document expected report locations and failure modes.

## Validation

- Run a short 1-2 window walk-forward with OHLC model to confirm:
  - XML optimization report is generated.
  - OOS report HTML/XML is generated.
  - Output CSV is created and populated.

## Notes

- Use ShutdownTerminal=1 in .ini to allow automation to proceed.
- If MT5 report formats differ by build, adjust parsing accordingly.
- Keep all files ASCII-only.
