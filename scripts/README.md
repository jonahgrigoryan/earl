# RPEA Test Automation Scripts

## 🚀 Quick Start

```powershell
# Run all tests (compile + execute)
.\compile-and-test.ps1

# Or just run tests (if already compiled)
.\run-mt5-tests.ps1
```

## 📁 Files Overview

| File | Purpose | When to Use |
|------|---------|-------------|
| `compile-and-test.ps1` | **Main workflow script** | Every development cycle |
| `run-mt5-tests.ps1` | Test runner only | When tests are pre-compiled |
| `run-mt5-tests.cmd` | Batch wrapper | If PowerShell is restricted |

## 🎯 Common Workflows

### Development Cycle

```powershell
# 1. Make code changes
# 2. Quick compile + test
.\compile-and-test.ps1

# 3. If tests pass, commit
git add .
git commit -m "M3 Task X: Description"
```

### Fast Iteration

```powershell
# Skip test recompilation (tests already compiled)
.\compile-and-test.ps1 -Fast

# Only compile, don't run tests (check syntax only)
.\compile-and-test.ps1 -SkipTests
```

### Custom MT5 Location

```powershell
# If MT5 is not in default location
.\compile-and-test.ps1 -MT5Path "D:\MetaTrader 5"
```

## 📊 Understanding Test Output

### Success Output
```
==> Compiling RPEA.mq5...
✓ RPEA.mq5 compiled successfully

==> Compiling test EA...
✓ Test EA compiled successfully

==> Running unit tests...
[TEST SUITE START] Task1_OrderEngine_Scaffolding
[PASS] TestOrderEngine_RunAll: All tests passed
...
Total Tests: 42
Passed: 42
Failed: 0

╔════════════════════════════════════════╗
║   ✓ BUILD & TEST SUCCESSFUL            ║
╚════════════════════════════════════════╝
```

### Failure Output
```
==> Running unit tests...
[TEST SUITE START] Task3_Volume_Price_Normalization
[FAIL] TestNormalization_RoundsStep: Expected 0.01, got 0.015
...
Total Tests: 42
Passed: 41
Failed: 1

✗ SOME TESTS FAILED
```

## 🔧 Configuration

### MT5 Path Detection

Scripts auto-detect MT5 at: `C:\Program Files\MetaTrader 5`

To override:
```powershell
$MT5Path = "D:\Your\MT5\Path"
.\run-mt5-tests.ps1 -MT5Path $MT5Path
```

### Test Timeout

Default: 120 seconds

To increase:
```powershell
.\run-mt5-tests.ps1 -TimeoutSeconds 300
```

### Keep Terminal Open (Debug Mode)

```powershell
.\run-mt5-tests.ps1 -KeepOpen
```

## 📋 Test Results Location

JSON results file:
```
C:\Program Files\MetaTrader 5\MQL5\Files\RPEA\test_results\test_results.json
```

View results:
```powershell
Get-Content "C:\Program Files\MetaTrader 5\MQL5\Files\RPEA\test_results\test_results.json" | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

## 🐛 Troubleshooting

### "Terminal not found"
```powershell
# Check if MT5 is installed
Test-Path "C:\Program Files\MetaTrader 5\terminal64.exe"

# If not found, specify correct path
.\run-mt5-tests.ps1 -MT5Path "YOUR_PATH"
```

### "Compilation failed"
```powershell
# Check compilation logs
Get-Content ".\MQL5\Experts\FundingPips\compile_rpea.log"
Get-Content ".\Tests\RPEA\compile_automated_tests.log"
```

### "Tests hang/timeout"
```powershell
# Manually kill MT5 terminal
Get-Process | Where-Object {$_.Name -like "*terminal*"} | Stop-Process -Force

# Run with debugging
.\run-mt5-tests.ps1 -KeepOpen
```

### "No test results generated"
**Check:**
1. MT5 Experts tab for errors
2. File permissions on `MQL5/Files/RPEA/` directory
3. Test EA actually runs (check terminal logs)

**Manual test:**
1. Open MT5 terminal
2. Drag `run_automated_tests_ea.ex5` to chart
3. Check Experts tab output

## 🔄 CI/CD Integration

### Exit Codes

- `0` = Success ✅
- `1` = Failure ❌

### Script Example

```powershell
# Run tests and capture result
.\compile-and-test.ps1

# Check exit code
if ($LASTEXITCODE -eq 0) {
    Write-Host "Tests passed, deploying..."
} else {
    Write-Host "Tests failed, blocking deployment"
    exit 1
}
```

### Batch File Example

```cmd
@echo off
call scripts\run-mt5-tests.cmd
if %ERRORLEVEL% neq 0 (
    echo Tests failed!
    exit /b 1
)
echo Tests passed!
```

## 📚 Related Documentation

- [TESTING.md](../docs/TESTING.md) - Comprehensive testing guide
- [session-checkpoint.md](../.claude/session-checkpoint.md) - Project status
- [zen_prompts_m3.md](../.zencoder/zen_prompts_m3.md) - M3 implementation guide

## 🎓 Examples

### Example 1: Fix failing test
```powershell
# Run tests, see failure
.\compile-and-test.ps1

# Fix code in order_engine.mqh
# Re-test quickly
.\compile-and-test.ps1 -Fast

# Verify fix
# Commit
git commit -am "fix: Task 3 normalization rounding issue"
```

### Example 2: Add new test suite
```powershell
# 1. Create test file: test_order_engine_oco.mqh
# 2. Edit run_automated_tests_ea.mq5
# 3. Add new suite in RunAllTests()
# 4. Compile and test
.\compile-and-test.ps1

# Should show new suite in results
```

### Example 3: Pre-commit hook
```powershell
# .git/hooks/pre-commit (PowerShell version)
#!/usr/bin/env pwsh
Push-Location scripts
$result = .\compile-and-test.ps1
Pop-Location

if ($LASTEXITCODE -ne 0) {
    Write-Host "Tests failed! Fix before committing." -ForegroundColor Red
    exit 1
}

exit 0
```

## ⚙️ Advanced Options

### Parallel Execution (Future)

```powershell
# Run multiple test suites in parallel
# (Not yet implemented, but architecture supports it)
.\run-mt5-tests.ps1 -Parallel -MaxJobs 4
```

### Custom Test Selection

```powershell
# Run only specific test suites (future feature)
.\run-mt5-tests.ps1 -Suites "Task1,Task3,Task5"
```

### Performance Profiling

```powershell
# Measure test execution time
Measure-Command { .\compile-and-test.ps1 }
```

## 🧭 Walk-Forward Automation (M5 Task02)

```powershell
# Run walk-forward automation
.\walk_forward.ps1

# Validate config and paths only
.\walk_forward.ps1 -ValidateOnly

# Generate configs without launching MT5
.\walk_forward.ps1 -DryRun

# CMD wrapper (double-click friendly)
.\walk_forward.cmd
```

### Config Highlights (scripts/wf_config.json)

- mt5_path: MT5 install root containing terminal64.exe
- profile_base: blank for default AppData profile; set for portable installs
- symbols + symbol_overrides: per-symbol ini/leverage overrides (XAUUSD uses RPEA_10k_metals.ini)
- use_quick_model: switch to quick .ini (Model=1) for fast sweeps
- max_candidates / max_passing_candidates / stop_when_passes: candidate control
- optimization_metric / optimization_metric_order: override OptimizationCriterion mapping
- allow_profile_write / copy_sets / copy_news: control external writes

### Outputs

- Summary CSV: `Files/RPEA/reports/wf_results.csv`
- MT5 reports: `%APPDATA%\MetaQuotes\Terminal\<HASH>\Tester\reports\` or `<profile_base>\Tester\reports\`

### Common Failure Modes

- terminal64.exe not found (set mt5_path or MT5_PATH env var)
- no optimization report generated (check MT5 Experts/Journal tabs)
- no candidates after min_trades filter (reduce min_trades or shorten window)
- missing .set in profile when copy_sets=false

## 📞 Support

**Issues?** Check:
1. MT5 terminal logs: `%APPDATA%\MetaQuotes\Terminal\{ID}\Logs`
2. Compilation logs in project directories
3. Test result JSON for detailed failure info
4. Session checkpoint for project status

**Need help?** Review:
- Full testing guide: `docs/TESTING.md`
- M3 specifications: `.kiro/specs/rpea-m3/`
- Implementation prompts: `.zencoder/zen_prompts_m3.md`

---

**Version:** 1.0.0
**Last Updated:** 2025-10-20
**Status:** ✅ Production Ready
