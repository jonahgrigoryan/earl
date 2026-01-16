param(
    [Parameter(Mandatory = $true)]
    [string]$ReportPath,
    [double]$StartingBalance = 10000,
    [double]$TargetProfit = 1000,
    [int]$MinTradeDays = 3,
    [double]$MaxDailyLossPct = 4.0,
    [double]$MaxOverallLossPct = 6.0,
    [switch]$DebugReport
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path $ScriptRoot -Parent
$script:DebugReport = $DebugReport

function Resolve-RepoPath {
    param([string]$Path, [string]$RepoRoot)
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $RepoRoot $Path)
}

function Read-TextFile {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2) {
        if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            return [System.Text.Encoding]::Unicode.GetString($bytes)
        }
        if ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
            return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes)
        }
    }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($text.IndexOf([char]0) -ge 0) {
        $text = [System.Text.Encoding]::Unicode.GetString($bytes)
    }
    return $text
}

function Convert-ToDouble {
    param([string]$Value, [double]$Default = 0)
    $parsed = 0.0
    if ([double]::TryParse($Value, [ref]$parsed)) { return $parsed }
    return $Default
}

function Get-FirstNumber {
    param([string]$Content, [string]$Label)
    $pattern = [regex]::Escape($Label) + "[^0-9-]*([+-]?\d[\d.,]*)"
    $match = [regex]::Match($Content, $pattern, "IgnoreCase")
    if ($match.Success) {
        return ($match.Groups[1].Value -replace ",", "")
    }
    return $null
}

function Get-PercentAfterLabel {
    param([string]$Content, [string]$Label)
    $pattern = [regex]::Escape($Label) + ".{0,200}?([+-]?\d[\d.,]*)\s*%"
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor `
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    $match = [regex]::Match($Content, $pattern, $options)
    if ($match.Success) {
        return ($match.Groups[1].Value -replace ",", "")
    }
    $index = $Content.IndexOf($Label, [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -ge 0) {
        $sliceLen = [Math]::Min(2000, $Content.Length - $index)
        $slice = $Content.Substring($index, $sliceLen)
        $fallback = [regex]::Match($slice, "([+-]?\d[\d.,]*)\s*%", $options)
        if ($fallback.Success) {
            return ($fallback.Groups[1].Value -replace ",", "")
        }
    }
    return $null
}

function Extract-DailyPnlFromXml {
    param([xml]$Xml)
    $daily = @{}
    $nodes = $Xml.SelectNodes("//Deal|//Trade")
    foreach ($node in $nodes) {
        $dateText = $null
        $profitText = $null
        foreach ($child in $node.ChildNodes) {
            if ($child.NodeType -ne "Element") { continue }
            if (-not $dateText -and $child.Name -match "(time|date)") {
                $dateText = $child.InnerText
            }
            if (-not $profitText -and $child.Name -match "profit") {
                $profitText = $child.InnerText
            }
        }
        if ($dateText -and $profitText) {
            if ($dateText -match '(\d{4}\.\d{2}\.\d{2})') {
                $date = $matches[1]
                $profitVal = [double]$profitText
                if (-not $daily.ContainsKey($date)) { $daily[$date] = 0.0 }
                $daily[$date] += $profitVal
            }
        }
    }
    return $daily
}

function Extract-DailyPnlFromHtml {
    param([string]$Content)
    $daily = @{}
    $rows = [regex]::Matches($Content, "<tr[^>]*>.*?</tr>", "Singleline")
    foreach ($row in $rows) {
        $rowText = $row.Value
        if ($rowText -notmatch '(\d{4}\.\d{2}\.\d{2})') { continue }
        $date = $matches[1]
        $numbers = [regex]::Matches($rowText, '[-+]?[0-9]+(?:\.[0-9]+)?')
        if ($numbers.Count -eq 0) { continue }
        $profitText = $numbers[$numbers.Count - 1].Value
        $profitVal = [double]$profitText
        if (-not $daily.ContainsKey($date)) { $daily[$date] = 0.0 }
        $daily[$date] += $profitVal
    }
    return $daily
}

function Parse-TestReport {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Report not found: $Path"
    }

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $content = Read-TextFile -Path $Path
    if ($content.IndexOf([char]0) -ge 0) {
        $content = $content -replace [string][char]0, ""
    }
    $content = $content -replace "&#37;", "%"
    $content = $content -replace "&nbsp;", " "

    $netProfit = Get-FirstNumber -Content $content -Label "Total Net Profit"
    if (-not $netProfit) { $netProfit = Get-FirstNumber -Content $content -Label "Net Profit" }
    $profitFactor = Get-FirstNumber -Content $content -Label "Profit Factor"
    $totalTrades = Get-FirstNumber -Content $content -Label "Total Trades"
    $winRate = Get-PercentAfterLabel -Content $content -Label "Profit Trades"
    if (-not $winRate) { $winRate = Get-PercentAfterLabel -Content $content -Label "Win Rate" }
    $maxDdPct = Get-PercentAfterLabel -Content $content -Label "Maximal Drawdown"
    if (-not $maxDdPct) { $maxDdPct = Get-PercentAfterLabel -Content $content -Label "Max Drawdown" }
    if (-not $maxDdPct) { $maxDdPct = Get-PercentAfterLabel -Content $content -Label "Equity Drawdown Maximal" }
    if (-not $maxDdPct) { $maxDdPct = Get-PercentAfterLabel -Content $content -Label "Balance Drawdown Maximal" }
    if (-not $maxDdPct) { $maxDdPct = Get-PercentAfterLabel -Content $content -Label "Equity Drawdown Relative" }
    if (-not $maxDdPct) { $maxDdPct = Get-PercentAfterLabel -Content $content -Label "Balance Drawdown Relative" }
    if (-not $maxDdPct) { $maxDdPct = Get-FirstNumber -Content $content -Label "Maximal Drawdown %" }
    if (-not $maxDdPct) { $maxDdPct = Get-FirstNumber -Content $content -Label "Max Drawdown %" }
    if (-not $maxDdPct) { $maxDdPct = Get-FirstNumber -Content $content -Label "Maximal Drawdown" }
    if (-not $maxDdPct) {
        $ddMatch = [regex]::Match($content, "(?i)Drawdown[^0-9%]{0,400}([0-9][0-9.,]*)\s*%", "Singleline")
        if ($ddMatch.Success) {
            $maxDdPct = $ddMatch.Groups[1].Value
        }
    }

    if ($script:DebugReport) {
        Write-Host ("Debug: Content contains label -> {0}" -f ($content -match "Equity Drawdown Maximal"))
        Write-Host ("Debug: MaxDD candidates -> MaximalDrawdown={0}" -f (Get-PercentAfterLabel -Content $content -Label "Maximal Drawdown"))
        Write-Host ("Debug: EquityDrawdownMaximal={0}" -f (Get-PercentAfterLabel -Content $content -Label "Equity Drawdown Maximal"))
        Write-Host ("Debug: EquityDrawdownRelative={0}" -f (Get-PercentAfterLabel -Content $content -Label "Equity Drawdown Relative"))
    }

    if (-not $netProfit) { throw "Net profit not found in report: $Path" }
    if (-not $profitFactor) { throw "Profit factor not found in report: $Path" }
    if (-not $maxDdPct) { throw "Max drawdown percent not found in report: $Path" }

    $dailyPnl = @{}
    if ($ext -eq ".xml") {
        try {
            [xml]$xml = $content
            $dailyPnl = Extract-DailyPnlFromXml -Xml $xml
        } catch {
            $dailyPnl = @{}
        }
    }
    if ($dailyPnl.Count -eq 0) {
        $dailyPnl = Extract-DailyPnlFromHtml -Content $content
    }

    $tradeDays = $dailyPnl.Keys.Count

    return [pscustomobject]@{
        NetProfit = Convert-ToDouble -Value $netProfit -Default 0
        ProfitFactor = Convert-ToDouble -Value $profitFactor -Default 0
        TotalTrades = if ($totalTrades) { [int](Convert-ToDouble -Value $totalTrades -Default 0) } else { 0 }
        WinRate = if ($winRate) { Convert-ToDouble -Value $winRate -Default 0 } else { 0 }
        MaxDrawdownPct = Convert-ToDouble -Value ($maxDdPct -replace '%', '') -Default 0
        DailyPnl = $dailyPnl
        TradeDays = $tradeDays
    }
}

$resolvedReport = Resolve-RepoPath -Path $ReportPath -RepoRoot $RepoRoot
$metrics = Parse-TestReport -Path $resolvedReport

$dailyViolations = 0
$baseline = $StartingBalance
$sortedDates = $metrics.DailyPnl.Keys | Sort-Object
foreach ($date in $sortedDates) {
    $value = $metrics.DailyPnl[$date]
    if ($value -lt 0) {
        $lossPct = [Math]::Abs($value / $baseline * 100.0)
        if ($lossPct -ge $MaxDailyLossPct) {
            $dailyViolations += 1
        }
    }
    $baseline += $value
}

$overallViolation = $metrics.MaxDrawdownPct -ge $MaxOverallLossPct
$profitOk = $metrics.NetProfit -ge $TargetProfit
$tradeDaysOk = $metrics.TradeDays -ge $MinTradeDays
$dailyOk = $dailyViolations -eq 0
$overallOk = -not $overallViolation

$pass = $profitOk -and $tradeDaysOk -and $dailyOk -and $overallOk
$reasons = @()
if (-not $profitOk) { $reasons += "profit_target" }
if (-not $tradeDaysOk) { $reasons += "trade_days" }
if (-not $dailyOk) { $reasons += "daily_cap" }
if (-not $overallOk) { $reasons += "overall_cap" }

Write-Host "Report: $resolvedReport"
Write-Host ("Net Profit: {0}" -f $metrics.NetProfit)
Write-Host ("Profit Factor: {0}" -f $metrics.ProfitFactor)
Write-Host ("Total Trades: {0}" -f $metrics.TotalTrades)
Write-Host ("Win Rate: {0}%" -f $metrics.WinRate)
Write-Host ("Max Drawdown %: {0}" -f $metrics.MaxDrawdownPct)
Write-Host ("Trade Days: {0}" -f $metrics.TradeDays)
Write-Host ("Daily Cap Violations: {0}" -f $dailyViolations)
Write-Host ("Overall Cap Violation: {0}" -f $overallViolation)

if ($pass) {
    Write-Host "PASS" -ForegroundColor Green
    exit 0
}

Write-Host ("FAIL: {0}" -f ($reasons -join ", ")) -ForegroundColor Red
exit 1
