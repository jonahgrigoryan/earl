# Run RPEA automated tests
$mt5Path = 'C:\Program Files\MetaTrader 5'
$terminal = Join-Path $mt5Path 'terminal64.exe'
$terminalDataRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
$terminalProfile = Get-ChildItem -Path $terminalDataRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $terminalProfile) {
    Write-Host "ERROR: MT5 data folder not found at $terminalDataRoot"
    exit 1
}
$primaryResults = Join-Path $terminalProfile.FullName 'MQL5\Files\RPEA\test_results\test_results.json'
$testerResultsPatterns = @(
    (Join-Path $env:APPDATA 'MetaQuotes\Tester\Agent-*\MQL5\Files\RPEA\test_results\test_results.json'),
    (Join-Path $env:APPDATA 'MetaQuotes\Tester\*\Agent-*\MQL5\Files\RPEA\test_results\test_results.json')
)

function Get-TestrunResult {
    foreach ($pattern in $testerResultsPatterns) {
        $match = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($match) {
            return $match
        }
    }
    return $null
}

# Remove previous results
if (Test-Path $primaryResults) {
    Remove-Item $primaryResults -Force
    Write-Host 'Previous primary results cleared'
}
$existingTester = Get-TestrunResult
if ($existingTester) {
    $existingTester | ForEach-Object { Remove-Item $_.FullName -Force }
    Write-Host 'Previous tester results cleared'
}

# Kill all MT5/MetaTester/MetaEditor processes
Write-Host 'Killing all MT5, MetaTester, and MetaEditor processes...'
Get-Process -Name 'terminal64.exe', 'MetaTester.exe', 'MetaEditor.exe' | Stop-Process -Force
Start-Sleep -Seconds 2 # Give processes a moment to terminate

# Ensure MQL5/Files/RPEA/test_results directory
$testResultsDir = Join-Path $terminalProfile.FullName 'MQL5\Files\RPEA\test_results'
if (-not (Test-Path $testResultsDir)) {
    New-Item -ItemType Directory -Path $testResultsDir -Force
    Write-Host "Created directory: $testResultsDir"
}

# Start MT5 terminal minimized
Write-Host 'Starting MT5 terminal with test EA (minimized)...'
$proc = Start-Process -FilePath $terminal -ArgumentList '-minimized' -PassThru

# Wait for results with timeout
$timeout = 600 # 10 minutes timeout
$waited = 0
while ($waited -lt $timeout) {
    Start-Sleep -Seconds 1 # Poll every 1 second
    $waited += 1

    $hasPrimary = Test-Path $primaryResults
    $fallback = Get-TestrunResult
    if ($hasPrimary -or $fallback) {
        Write-Host 'Test results file created!'
        break
    }

    if ($proc.HasExited) {
        Write-Host 'Terminal process exited'
        Start-Sleep -Seconds 3
        $hasPrimary = Test-Path $primaryResults
        $fallback = Get-TestrunResult
        if ($hasPrimary -or $fallback) {
            Write-Host 'Test results found after terminal exit'
            break
        }
    }

    if ($waited % 10 -eq 0) {
        Write-Host "Waiting... ($waited/$timeout seconds)"
    }
}

# Stop terminal if still running
if (!$proc.HasExited) {
    Write-Host 'Stopping MT5 terminal...'
    Stop-Process -Id $proc.Id -Force
    Start-Sleep -Seconds 2
}

# Determine which results file exists
$resultsPathUsed = $null
if (Test-Path $primaryResults) {
    $resultsPathUsed = $primaryResults
} else {
    $fallback = Get-TestrunResult
    if ($fallback) {
        $resultsPathUsed = $fallback.FullName
    }
}

# Check if results file exists
if ($resultsPathUsed) {
    Write-Host "Results file found! ($resultsPathUsed)"
    $results = Get-Content $resultsPathUsed | ConvertFrom-Json
    Write-Host "`n=== TEST RESULTS ==="
    Write-Host "Total Tests: $($results.total_tests)"
    Write-Host "Passed: $($results.total_passed)"
    Write-Host "Failed: $($results.total_failed)"
    Write-Host "Success: $($results.success)`n"

    foreach ($suite in $results.suites) {
        $status = if ($suite.failed -eq 0) { 'PASS' } else { 'FAIL' }
        Write-Host "[$status] $($suite.name)"
        Write-Host "  Tests: $($suite.passed)/$($suite.total_tests) passed"
    }
    exit 0
} else {
    Write-Host "ERROR: Results file not generated at $primaryResults or under tester agents"
    Write-Host "Please follow these steps to run the automated tests:"
    Write-Host "1. Open MetaTrader 5."
    Write-Host "2. Go to 'File' -> 'Open Data Folder' (or 'Open Terminal Data Folder' for older versions)."
    Write-Host "3. In Strategy Tester, run the EA compiled from 'Tests\\RPEA\\run_automated_tests_ea.mq5'."
    Write-Host "4. Set the symbol to 'EURUSD' and timeframe to 'M1'."
    Write-Host "5. Click 'Start' and wait for completion."
    Write-Host "6. Confirm 'test_results.json' is created under 'MQL5\\Files\\RPEA\\test_results'."
    exit 1
}
