# M7 Task 08 Done Checklist

Use this checklist immediately after Task 08 code implementation is complete.

## 1) Sync Repo To MT5

- [ ] Sync repo files to MT5 terminal data folder.

```powershell
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
```

## 2) Compile Production EA

- [ ] Compile production EA from MT5 data folder.

```powershell
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
```

## 3) Compile Test Runner

- [ ] Compile test runner (guard against silent `run_tests.ps1` failures).

```powershell
& "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:MQL5\Experts\Tests\RPEA\run_automated_tests_ea.mq5 /log:MQL5\Experts\Tests\RPEA\compile_automated_tests.log
```

## 4) Run Automated Tests

- [ ] Run automated tests from repo root.

```powershell
powershell -ExecutionPolicy Bypass -File run_tests.ps1
```

## 5) Verify Artifacts

- [ ] `compile_rpea.log` has 0 errors.
- [ ] `test_results.json` has updated timestamp.
- [ ] `M7Task08_EndToEnd` suite is present.
- [ ] Expected suite total passes (35/35).

## 6) Manual Strategy Tester Validation

- [ ] Run `Experts\FundingPips\RPEA.ex5` in Strategy Tester.
- [ ] Use EURUSD chart symbol, `InpSymbols="EURUSD;XAUUSD"`, 5 trading days.

## 7) Capture Evidence

- [ ] Capture tester journal lines for:
- [ ] `EVAL`
- [ ] `PLAN_REJECT`
- [ ] `PLACE_OK` / `PLACE_FAIL`
- [ ] `MR_TIMESTOP` (if triggered)
- [ ] `[SLO] Metrics initialized` startup line

## 8) Fill Task Results

- [ ] Fill `m7-task08.md` Results section with compile/test/tester outcomes.

## 9) Update AGENTS.md

- [ ] Update `Last Updated`.
- [ ] Update changed module line counts.
- [ ] Add Task 08 item to `Recent Changes`.
- [ ] Set M7 progress to Tasks 01-08 complete.

## 10) Commit And Push Task Branch

- [ ] Commit and push Task 08 branch.

```powershell
git status --short
git add <task08 files>
git commit -m "M7: Task 08 - end-to-end testing and validation"
git push -u origin feat/m7-phase5-task08-end-to-end-testing
```

## 11) Merge To Milestone Branch

- [ ] Merge task branch into `feat/m7-ensemble-integration` and push.

```powershell
git checkout feat/m7-ensemble-integration
git pull
git merge --no-ff feat/m7-phase5-task08-end-to-end-testing
git push
```

## 12) Final Sync To MT5

- [ ] Sync again so MT5 files match merged branch.

```powershell
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
```
