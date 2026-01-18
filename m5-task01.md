# M5-Task01: Strategy Tester presets and tester configs

## Objective

Create MT5 Strategy Tester presets (.set) and tester configs (.ini) for the RPEA $10k challenge. The presets must list every EA input from RPEA.mq5 and encode optimization ranges from finalspec.md.

## Deliverables

- Tests/RPEA/RPEA_10k_default.set
- Tests/RPEA/RPEA_10k_optimize.set
- Tests/RPEA/RPEA_10k_tester.ini
- Tests/RPEA/RPEA_10k_metals.ini
- Tests/RPEA/RPEA_10k_single.ini
- Tests/RPEA/RPEA_10k_quick.ini

## Requirements

- Include every input parameter from MQL5/Experts/FundingPips/RPEA.mq5.
- Booleans must be 0 or 1 (MT5 format).
- Optimization preset must include explicit ||Y or ||N for every parameter.
- Optimization ranges per finalspec.md:
  - RiskPct 0.8..2.0 step 0.1
  - MicroRiskPct 0.05..0.20 step 0.05
  - SLmult 0.7..1.3 step 0.1
  - RtargetBC 1.8..2.6 step 0.1
  - RtargetMSC 1.6..2.4 step 0.1
  - TrailMult 0.6..1.2 step 0.1
  - ORMinutes 30..75 step 15 (30,45,60,75)
  - UseLondonOnly 0..1 step 1
- Governance/compliance inputs must be fixed (||N).
- .ini files must include ForwardMode=0.
- Use OptimizationCriterion=1 (Profit Factor) for consistency.
- Use Model=4 for accurate runs and Model=1 for quick sweeps (explicit per .ini below).

## Required .set formatting

- RPEA_10k_default.set uses plain MT5 format: Param=value (no optimization fields).
- RPEA_10k_optimize.set uses optimization fields for every parameter with explicit ||Y or ||N. For fixed numeric values use Param=value||value||0||value||N. For string inputs, follow the MT5-exported format if required.

## Required .ini values

| File | Symbol | Period | Deposit | Currency | Leverage | Model | ExecutionMode | Optimization | OptimizationCriterion | FromDate | ToDate | ForwardMode | ShutdownTerminal |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Tests/RPEA/RPEA_10k_tester.ini | EURUSD | M1 | 10000 | USD | 50 | 4 | 0 | 2 | 1 | 2024.07.01 | 2024.12.31 | 0 | 1 |
| Tests/RPEA/RPEA_10k_metals.ini | XAUUSD | M1 | 10000 | USD | 20 | 4 | 0 | 2 | 1 | 2024.07.01 | 2024.12.31 | 0 | 1 |
| Tests/RPEA/RPEA_10k_single.ini | EURUSD | M1 | 10000 | USD | 50 | 4 | 0 | 0 | 1 | 2024.07.01 | 2024.12.31 | 0 | 1 |
| Tests/RPEA/RPEA_10k_quick.ini | EURUSD | M1 | 10000 | USD | 50 | 1 | 0 | 2 | 1 | 2024.07.01 | 2024.12.31 | 0 | 1 |

## Files to Modify/Create

- Tests/RPEA/RPEA_10k_default.set
- Tests/RPEA/RPEA_10k_optimize.set
- Tests/RPEA/RPEA_10k_tester.ini
- Tests/RPEA/RPEA_10k_metals.ini
- Tests/RPEA/RPEA_10k_single.ini
- Tests/RPEA/RPEA_10k_quick.ini

## Steps

1. Extract all input parameters and defaults from MQL5/Experts/FundingPips/RPEA.mq5.
2. Create RPEA_10k_default.set with static defaults for every input.
3. Create RPEA_10k_optimize.set with optimization ranges for the required parameters and ||N for all others.
4. Create RPEA_10k_tester.ini (FX optimization, leverage 1:50, Model=4).
5. Create RPEA_10k_metals.ini (XAUUSD optimization, leverage 1:20, Model=4).
6. Create RPEA_10k_single.ini (single test, Optimization=0, Model=4).
7. Create RPEA_10k_quick.ini (fast sweep, Model=1, Optimization=2).
8. Copy .set files to MT5 Profiles/Tester and copy the news CSV into the MT5 Files/RPEA/news folder (paths below).

## Validation

- Compile EA: MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
- Optional: use scripts/verify_set_coverage.ps1 (if added in M5 Task03) to diff inputs vs .set.
- Run MT5 with /config:<ini> and confirm a report is produced.

## MT5 profile copy steps

- Portable mode:
  - Copy Tests/RPEA/*.set to C:\Program Files\MetaTrader 5\Profiles\Tester\
  - Copy Files/RPEA/news/calendar_high_impact.csv to C:\Program Files\MetaTrader 5\MQL5\Files\RPEA\news\
- Default mode:
  - Copy Tests/RPEA/*.set to %APPDATA%\MetaQuotes\Terminal\<HASH>\MQL5\Profiles\Tester\
  - Copy Files/RPEA/news/calendar_high_impact.csv to %APPDATA%\MetaQuotes\Terminal\<HASH>\MQL5\Files\RPEA\news\

## Notes

- If MT5 rejects string inputs in the optimize .set, export a .set from MT5 and match the string format.
- Keep all files ASCII-only.
