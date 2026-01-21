# Quick script to check test results
$profiles = Get-ChildItem -Path "$env:APPDATA\MetaQuotes\Terminal" -Directory | Where-Object { $_.Name -ne 'Help' } | Sort-Object LastWriteTime -Descending

Write-Host "MT5 Profiles found:" -ForegroundColor Cyan
$profiles | ForEach-Object { 
    Write-Host "  $($_.Name) - Last Write: $($_.LastWriteTime)" 
}

if ($profiles) {
    $active = $profiles | Select-Object -First 1
    Write-Host "`nActive profile: $($active.Name)" -ForegroundColor Green
    $resultsPath = Join-Path $active.FullName 'MQL5\Files\RPEA\test_results\test_results.json'
    Write-Host "Results path: $resultsPath"
    
    if (Test-Path $resultsPath) {
        Write-Host "`n[RESULTS FOUND]" -ForegroundColor Green
        $results = Get-Content $resultsPath | ConvertFrom-Json
        Write-Host "Total Tests: $($results.total_tests)"
        Write-Host "Passed: $($results.total_passed)" -ForegroundColor Green
        Write-Host "Failed: $($results.total_failed)" -ForegroundColor $(if ($results.total_failed -gt 0) { 'Red' } else { 'Green' })
        Write-Host "Success: $($results.success)"
        
        Write-Host "`nSuites:" -ForegroundColor Cyan
        foreach ($suite in $results.suites) {
            $status = if ($suite.failed -eq 0) { 'PASS' } else { 'FAIL' }
            $color = if ($suite.failed -eq 0) { 'Green' } else { 'Red' }
            Write-Host "  [$status] $($suite.name) - $($suite.passed)/$($suite.total_tests) passed" -ForegroundColor $color
        }
    } else {
        Write-Host "`n[NO RESULTS FOUND]" -ForegroundColor Yellow
        Write-Host "Run tests in Strategy Tester first!"
    }
}
