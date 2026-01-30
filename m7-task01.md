# M7 Task 01 -- EMRT Formation Job

Branch name: `feat/m7-task01-emrt-formation` (cut from `feat/m7-phase1-foundation`)

Source of truth: `docs/m7-final-workflow.md` (Phase 1, Task 1, Steps 1.1-1.5)

## Objective
Implement the EMRT (Empirical Mean Reversion Time) module for synthetic XAUEUR spread calculation. This module computes reversion time percentiles and rank metrics, and computes beta **only when** `MR_UseLogRatio=false` (log-ratio mode skips grid search and uses beta=1.0).

## Prerequisites
- Phase 0 inputs must already exist in `RPEA.mq5`, including `MR_UseLogRatio` (default `true`).
- Prefer file path macros from `MQL5/Include/RPEA/config.mqh` (e.g., `FILE_EMRT_CACHE` and `RPEA_EMRT_DIR`).

## Workflow
1. **Get implementation details** from `docs/m7-final-workflow.md` (Phase 1, Task 1)
2. **Implement code locally** in repository workspace (`c:\Users\AWCS\earl-1`)
3. **Sync code to MT5 data folder** using `SyncRepoToTerminal.ps1`
   - Note: the sync script only mirrors `MQL5/Include/RPEA` and `MQL5/Experts/FundingPips`
   - `MQL5/Files/RPEA/emrt/` is auto-created by `Persistence_EnsureFolders()` on EA init. For isolated file I/O testing before running the EA, create manually or extend the sync script.
4. **Compile from MT5 data folder** to verify implementation

## File to Modify
- `MQL5/Include/RPEA/emrt.mqh`

## Implementation Steps

### Step 1.1: Data Structures & File I/O

**Reference:** `docs/m7-final-workflow.md` -> Phase 1 -> Task 1 -> Step 1.1

**Implementation:**
1. Add `EMRT_Cache` struct with fields: `beta_star`, `rank`, `p50_minutes`, `last_refresh`, `symbol`
2. Add global variables: `g_emrt_cache`, `g_emrt_loaded = false`
3. Implement `EMRT_LoadCache(string path)`:
   - Read JSON from `FILE_EMRT_CACHE` (`RPEA/emrt/emrt_cache.json`)
   - Parse and populate `g_emrt_cache`
   - Set `g_emrt_loaded = true` on success
   - Return `false` if file doesn't exist or parse fails
4. Implement `EMRT_SaveCache(string path)`:
   - Ensure directory exists (`RPEA_EMRT_DIR` under `MQL5/Files`)
   - Write `g_emrt_cache` to JSON file
   - Handle file I/O errors gracefully
5. Update existing accessor functions (`EMRT_GetRank`, `EMRT_GetP50`, `EMRT_GetBeta`) to check `g_emrt_loaded` and return safe defaults if false

**Verification:**
```powershell
# 1. Sync code to MT5 data folder
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1

# 2. Compile from MT5 data folder
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log

# 3. Check compile log (log is created in MT5 data folder's MQL5 path)
Get-Content "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\FundingPips\compile_rpea.log"
```

**Expected:** ✅ Compiles successfully, accessors return safe defaults (0.5, 75.0, 1.0 for log-ratio / 0.0 otherwise) when cache not loaded

---

### Step 1.2: Synthetic Spread Generation

**Reference:** `docs/m7-final-workflow.md` -> Phase 1 -> Task 1 -> Step 1.2

**Implementation:**
1. Implement `EMRT_BuildSyntheticSpread()` function:
   - Parameters: `xauusd_close[]`, `eurusd_close[]`, `beta`, output `spread[]`
   - If `MR_UseLogRatio=true`:
     - Calculate: `spread[i] = MathLog(xauusd_close[i]) - MathLog(eurusd_close[i])`
     - Validate positive prices before `MathLog`
     - Ignore `beta` in this mode
   - If `MR_UseLogRatio=false`:
     - Calculate: `spread[i] = xauusd_close[i] - beta * eurusd_close[i]`
   - Handle array size mismatches using `MathMin()`
   - Resize output array to match input length

**Verification:**
```powershell
# Sync and compile
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log

# Check compile log (created in MT5 data folder's MQL5 path)
$logPath = "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\FundingPips\compile_rpea.log"
Get-Content $logPath
```

**Expected:** ✅ Function compiles (not yet called, so no runtime test needed)

---

### Step 1.3: Extrema Detection & Crossing Times

**Reference:** `docs/m7-final-workflow.md` -> Phase 1 -> Task 1 -> Step 1.3

**Implementation:**
1. Implement `EMRT_FindCrossingTimes()` function:
   - Calculate rolling mean and sigma (standard deviation) of spread array
   - Find extrema where `|spread[i] - mean| > threshold_mult * sigma`
   - Track time (in minutes/M1 bars) for each extrema to cross back to rolling mean
   - Store crossing times in output array
   - Handle edge cases (insufficient data, no extrema found)

**Verification:**
```powershell
# Sync and compile
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log

# Check compile log (created in MT5 data folder's MQL5 path)
$logPath = "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\FundingPips\compile_rpea.log"
Get-Content $logPath
```

**Expected:** ✅ Function compiles successfully

---

### Step 1.4: Beta Grid Search

**Reference:** `docs/m7-final-workflow.md` -> Phase 1 -> Task 1 -> Step 1.4

**Implementation:**
1. Implement `EMRT_RefreshWeekly()` function:
   - Check `UseXAUEURProxy` input (from `RPEA.mq5`) - if false, print warning and return
   - Get 60-90 day lookback of XAUUSD and EURUSD M1 data using `CopyClose()`
   - If `MR_UseLogRatio=true`:
     - Set `beta_star = 1.0` (skip grid search)
     - Build spread using log-ratio mode
   - If `MR_UseLogRatio=false`:
     - Grid search beta values from `EMRT_BetaGridMin` to `EMRT_BetaGridMax` (step size: 0.1)
     - For each beta:
       - Build synthetic spread using `EMRT_BuildSyntheticSpread()`
       - Find crossing times using `EMRT_FindCrossingTimes()`
       - Calculate EMRT (median crossing time)
       - Check variance cap (use `EMRT_VarCapMult` * variance threshold)
     - Select beta* that minimizes EMRT (subject to variance cap)
   - Compute rank percentile (compare current EMRT to historical distribution)
   - Save results to cache using `EMRT_SaveCache()`
   - Set `g_emrt_loaded = true`

**Verification:**
```powershell
# Sync and compile
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log

# Check compile log (created in MT5 data folder's MQL5 path)
$logPath = "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\FundingPips\compile_rpea.log"
Get-Content $logPath
```

**Expected:** ✅ Full EMRT module compiles, function can be called (won't run until EA attached to chart)

---

### Step 1.5: Accessor Functions (Verify)

**Reference:** `docs/m7-final-workflow.md` -> Phase 1 -> Task 1 -> Step 1.5

**Implementation:**
1. Verify accessor functions (`EMRT_GetRank`, `EMRT_GetP50`, `EMRT_GetBeta`) are updated from Step 1.1
2. Ensure they:
   - Check `g_emrt_loaded` flag
   - Return safe defaults if cache not loaded:
     - `EMRT_GetRank`: return 0.5 (neutral)
     - `EMRT_GetP50`: return 75.0 (midpoint of MR_TimeStopMin/Max)
     - `EMRT_GetBeta`: return `1.0` when `MR_UseLogRatio=true` (beta implicit), otherwise return `0.0`
   - Return cache values if loaded

**Verification:**
```powershell
# Sync and compile
cd c:\Users\AWCS\earl-1
powershell -ExecutionPolicy Bypass -File SyncRepoToTerminal.ps1
cd "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log

# Check compile log (created in MT5 data folder's MQL5 path)
$logPath = "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\FundingPips\compile_rpea.log"
Get-Content $logPath
```

**Expected:** ✅ Accessors work with or without cache, safe defaults returned when cache not loaded

---

## Critical Paths

**Repository workspace:** `c:\Users\AWCS\earl-1`

**MT5 Data Folder:** `C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075`
> Confirm this path using MT5: **File -> Open Data Folder** (path is user/terminal specific).

**Sync Script:** `SyncRepoToTerminal.ps1` (run from repo root)
> Note: script does **not** sync `MQL5/Files/`. Create `MQL5/Files/RPEA/emrt/` manually in the terminal folder or extend the script.

**Compile Command:** Run from MT5 data folder:
```powershell
MetaEditor64.exe /compile:MQL5\Experts\FundingPips\RPEA.mq5 /log:MQL5\Experts\FundingPips\compile_rpea.log
```

## Implementation Notes

- Include `<RPEA/config.mqh>` at the top of `emrt.mqh` for file path macros (`FILE_EMRT_CACHE`, `RPEA_EMRT_DIR`)
- Use JSON format for cache file (MQL5 has `FileReadString`/`FileWriteString` for text files)
- Cache file path: `FILE_EMRT_CACHE` (resolved to `RPEA/emrt/emrt_cache.json`)
- Ensure directory exists before saving (use `FileIsExist()` checks or create directory)
- Handle array bounds and empty data gracefully
- Use existing MQL5 functions: `CopyClose()`, `ArraySize()`, `MathMin()`, `MathMax()`, `MathStdDev()`
- Follow MQL5 style: 3-space indent, braces on new lines, PascalCase types
- No `static` variables (per repo rules)
- Header guards present (`#ifndef RPEA_EMRT_MQH`)

## Deliverables

- Complete `emrt.mqh` implementation with all 5 steps
- File I/O functions handle errors gracefully
- Accessors return safe defaults when cache not loaded
- Code compiles successfully after each step

## Acceptance Checklist

- [ ] All 5 steps implemented
- [ ] Code compiles successfully after each step
- [ ] Accessors return safe defaults when cache not loaded
- [ ] `EMRT_RefreshWeekly()` can be called (will populate cache when EA runs)
- [ ] Code follows MQL5 style guidelines
- [ ] No compilation errors or warnings

## Hold Point

After all steps complete and compile successfully, stop and report results before proceeding to Task 2.
