# FundingPips Profitability Run Summary (2026-03-03)

## Scope
Branch: `feat/fundingpips-challenge-profitability`

This run focused on:
1. Fixing runtime input behavior that blocked tuning effectiveness.
2. Running a 3-window robustness comparison for Candidate B vs Candidate E.
3. Running one longer validation window on the selected candidate.

## Code Changes Applied

### Runtime Fix
File: `MQL5/Include/RPEA/config.mqh`

Issue:
- Non-test getters were using preprocessor checks in a way that caused EA runtime input values to be ignored in tester/live paths.
- This affected controls like `EnableMRBypassOnRLUnloaded`, anomaly toggles, and adaptive-risk toggles during tuning runs.

Fix:
- Restored non-test getter behavior to read EA input variables directly.
- Kept script compile compatibility via defaults in `rl_pretrain_inputs.mqh`.

Related living-doc update:
- `AGENTS.md`

Commit:
- `0ad2dbd` (`M7: restore runtime input getters for challenge tuning`)

## Validation Gates (Post-fix)

- EA compile: `0 errors, 2 warnings`
  - `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\FundingPips\compile_rpea.log`
- Script compile (`emrt_refresh.mq5`): `0 errors, 0 warnings`
  - `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Scripts\compile_emrt_refresh.log`
- Automated suite: `41/41` pass
  - `MQL5/Files/RPEA/test_results/test_results.json`

## Robustness Matrix (B vs E)

Artifacts:
- `.tmp/challenge_matrix_results.csv`
- `.tmp/challenge_matrix_summary.csv`
- `.tmp/challenge_matrix_summary.json`

Windows:
- W1: `2025-06-03` to `2025-07-03`
- W2: `2025-07-03` to `2025-08-03`
- W3: `2025-08-03` to `2025-09-03`

### Candidate B Results
- W1: net `+23.70`, PF `3.09`, trades `2`, balance DD `0.11%`, equity DD `0.51%`
- W2: net `-118.60`, PF `0.07`, trades `2`, balance DD `1.27%`, equity DD `1.75%`
- W3: net `-28.26`, PF `0.31`, trades `2`, balance DD `0.41%`, equity DD `0.79%`

True median net profit (sorted):
- Values: `-118.60, -28.26, +23.70`
- Median: `-28.26`

### Candidate E Results
- W1: net `+27.65`, PF `3.09`, trades `2`, balance DD `0.13%`, equity DD `0.60%`
- W2: net `-130.46`, PF `0.07`, trades `2`, balance DD `1.40%`, equity DD `1.92%`
- W3: net `-31.40`, PF `0.31`, trades `2`, balance DD `0.45%`, equity DD `0.87%`

True median net profit (sorted):
- Values: `-130.46, -31.40, +27.65`
- Median: `-31.40`

### Note on `.tmp/challenge_matrix_summary.*`
The auto summary exported incorrect median values due to index rounding behavior in the helper script.
Use the raw results in `.tmp/challenge_matrix_results.csv` and the corrected medians above.

## Candidate Selection
Selected candidate: **B**

Reason:
- Better true median net (`-28.26` vs `-31.40`).
- Lower worst drawdown across robustness windows.

## Selected Candidate Settings (B)
Relative to `Tests/RPEA/RPEA_10k_default.set`, Candidate B tuning used:

- `UseLondonOnly=0`
- `StartHourLO=1`
- `StartHourNY=1`
- `ORMinutes=30`
- `CutoffHour=23`
- `NewsBufferS=0`
- `SpreadMultATR=1.0`
- `MaxSpreadPoints=0`
- `BWISC_ConfCut=0.00`
- `MR_ConfCut=0.00`
- `MR_EMRTWeight=0.0`
- `EMRT_FastThresholdPct=100`
- `EnableMR=1`
- `EnableMRBypassOnRLUnloaded=1`
- `MR_LongOnly=1`
- `EnableAnomalyDetector=0`
- `AnomalyShadowMode=0`
- `UseBanditMetaPolicy=0`
- `BanditShadowMode=0`

Candidate E additionally changed:
- `RiskPct=2.5`
- `MR_RiskPct_Default=1.50`

## Longer Validation (Selected Candidate B)
Window:
- `2025-06-03` to `2025-11-21`

Report:
- `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\RPEA_long_candidateB_20250603_20251121.htm`

Result:
- Net: `+23.70`
- PF: `3.09`
- Trades: `2`
- Balance DD max: `0.11%`
- Equity DD max: `0.51%`

Decision-log check (same run horizon):
- `place_ok=2`
- `place_fail=0`
- Placement dates observed: `20250603` only

Interpretation:
- The setup is now capable of placing and closing trades profitably in probe conditions.
- Trade frequency remains too low for challenge-style target progression.
- This is not yet challenge-pass ready.

## Next Tuning Focus
1. Increase valid setup frequency without loosening risk governance.
2. Separate MR vs BWISC throughput diagnostics by month (which side is starved).
3. Improve consistency across windows (W2/W3 losses are the primary issue).
4. Keep hard constraints: daily/overall DD caps and deterministic compile/test gates.
