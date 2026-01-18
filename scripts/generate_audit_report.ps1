param(
    [string]$ReportPath = "",
    [string]$OutputPath = "Files\\RPEA\\reports\\audit_report.csv",
    [string]$TemplatePath = "Files\\RPEA\\reports\\audit_report_template.csv",
    [string]$AuditLogRoot = "Files\\RPEA\\logs",
    [string]$ProfileBase = "",
    [string]$MT5Path = "",
    [bool]$CopyAgentLogs = $true,
    [string]$FromDate = "",
    [string]$ToDate = "",
    [double]$StartingBalance = 10000,
    [double]$TargetProfit = 1000,
    [int]$MinTradeDays = 3,
    [double]$MaxDailyLossPct = 4.0,
    [double]$MaxOverallLossPct = 6.0,
    [switch]$Append
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path $ScriptRoot -Parent

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

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
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

function Parse-ReportMetadata {
    param([string]$Content)
    $title = $null
    if ($Content -match "<Title>([^<]+)</Title>") {
        $title = $matches[1]
    } elseif ($Content -match "<title>([^<]+)</title>") {
        $title = $matches[1]
    }

    $symbol = ""
    $period = ""
    $fromDate = ""
    $toDate = ""
    if ($title -and $title -match '([A-Z0-9]+),\\s*(M\\d+)\\s+(\\d{4}\\.\\d{2}\\.\\d{2})-(\\d{4}\\.\\d{2}\\.\\d{2})') {
        $symbol = $matches[1]
        $period = $matches[2]
        $fromDate = $matches[3]
        $toDate = $matches[4]
    } elseif ($title -and $title -match '([A-Z0-9]+),\\s*(M\\d+)') {
        $symbol = $matches[1]
        $period = $matches[2]
    }

    return [pscustomobject]@{
        Title = $title
        Symbol = $symbol
        Period = $period
        FromDate = $fromDate
        ToDate = $toDate
    }
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
    $metadata = Parse-ReportMetadata -Content $content

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
        Metadata = $metadata
        NetProfit = Convert-ToDouble -Value $netProfit -Default 0
        ProfitFactor = Convert-ToDouble -Value $profitFactor -Default 0
        TotalTrades = if ($totalTrades) { [int](Convert-ToDouble -Value $totalTrades -Default 0) } else { 0 }
        WinRate = if ($winRate) { Convert-ToDouble -Value $winRate -Default 0 } else { 0 }
        MaxDrawdownPct = Convert-ToDouble -Value ($maxDdPct -replace '%', '') -Default 0
        DailyPnl = $dailyPnl
        TradeDays = $tradeDays
        ReportFormat = $ext.TrimStart('.')
        Content = $content
    }
}

function Split-CsvLoose {
    param([string]$Line)
    $values = New-Object System.Collections.Generic.List[string]
    $current = ""
    $inQuotes = $false
    $chars = $Line.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $ch = $chars[$i]
        if ($ch -eq '"') {
            if ($inQuotes -and $i + 1 -lt $chars.Length -and $chars[$i + 1] -eq '"') {
                $current += '"'
                $i++
            } else {
                $inQuotes = -not $inQuotes
            }
            continue
        }
        if ($ch -eq ',' -and -not $inQuotes) {
            $values.Add($current)
            $current = ""
            continue
        }
        $current += $ch
    }
    $values.Add($current)
    return $values
}

function Normalize-AuditFields {
    param([System.Collections.Generic.List[string]]$Values, [int]$ExpectedCount)
    if ($Values.Count -gt $ExpectedCount) {
        $prefixCount = $ExpectedCount - 2
        $prefix = @()
        for ($i = 0; $i -lt $prefixCount; $i++) { $prefix += $Values[$i] }
        $newsState = $Values[$Values.Count - 1]
        $gating = ($Values[$prefixCount..($Values.Count - 2)] -join ",")
        return @($prefix + $gating + $newsState)
    }
    if ($Values.Count -lt $ExpectedCount) {
        $pad = $ExpectedCount - $Values.Count
        for ($i = 0; $i -lt $pad; $i++) { $Values.Add("") }
    }
    return @($Values)
}

function Normalize-LegacyFields {
    param([System.Collections.Generic.List[string]]$Values, [int]$ExpectedCount)
    if ($Values.Count -gt $ExpectedCount) {
        $prefix = @()
        for ($i = 0; $i -lt ($ExpectedCount - 1); $i++) { $prefix += $Values[$i] }
        $tail = ($Values[($ExpectedCount - 1)..($Values.Count - 1)] -join ",")
        return @($prefix + $tail)
    }
    if ($Values.Count -lt $ExpectedCount) {
        $pad = $ExpectedCount - $Values.Count
        for ($i = 0; $i -lt $pad; $i++) { $Values.Add("") }
    }
    return @($Values)
}

function Parse-AuditLogLine {
    param([string]$Line, [string[]]$Header)
    $values = Split-CsvLoose -Line $Line
    $values = Normalize-AuditFields -Values $values -ExpectedCount $Header.Count
    $row = @{}
    for ($i = 0; $i -lt $Header.Count; $i++) {
        $row[$Header[$i]] = $values[$i]
    }
    return $row
}

function Parse-LegacyLogLine {
    param([string]$Line, [string[]]$Header)
    $values = Split-CsvLoose -Line $Line
    $values = Normalize-LegacyFields -Values $values -ExpectedCount $Header.Count
    $row = @{}
    for ($i = 0; $i -lt $Header.Count; $i++) {
        $row[$Header[$i]] = $values[$i]
    }
    return $row
}

function Try-ParseDate {
    param([string]$Value)
    try {
        return [datetime]::Parse($Value)
    } catch {
        return $null
    }
}

function Get-TerminalProfile {
    param([string]$ProfileBase)
    if ([string]::IsNullOrEmpty($ProfileBase)) {
        $terminalRoot = Join-Path $env:APPDATA "MetaQuotes\\Terminal"
        $profile = Get-ChildItem -Path $terminalRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $profile) {
            throw "MT5 data folder not found at $terminalRoot"
        }
        $profileRoot = $profile.FullName
    } else {
        $profileRoot = $ProfileBase
    }
    return $profileRoot
}

function Find-LatestReport {
    param([string]$ProfileRoot)
    $reportsDir = Join-Path $ProfileRoot "Tester\\reports"
    if (-not (Test-Path $reportsDir)) { return $null }
    $files = Get-ChildItem -Path $reportsDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match "\\.(xml|htm|html)$" } |
        Sort-Object LastWriteTime -Descending
    if ($files.Count -gt 0) { return $files[0].FullName }
    return $null
}

function Resolve-MT5Path {
    param([string]$ConfiguredPath, [string]$RepoRoot)
    if (-not [string]::IsNullOrEmpty($ConfiguredPath)) { return $ConfiguredPath }
    $wfConfig = Join-Path $RepoRoot "scripts\\wf_config.json"
    if (Test-Path $wfConfig) {
        try {
            $cfg = Get-Content $wfConfig -Raw | ConvertFrom-Json
            if ($cfg.mt5_path) { return $cfg.mt5_path }
        } catch { }
    }
    return ""
}

function Copy-AgentLogs {
    param([string]$RepoRoot, [string]$AuditLogRoot, [string]$Mt5Path)
    $sources = @()
    $defaultTester = Join-Path $env:APPDATA "MetaQuotes\\Tester"
    if (Test-Path $defaultTester) {
        $sources += Get-ChildItem -Path $defaultTester -Directory -ErrorAction SilentlyContinue
    }
    if (-not [string]::IsNullOrEmpty($Mt5Path)) {
        $portableTester = Join-Path $Mt5Path "Tester"
        if (Test-Path $portableTester) {
            $sources += Get-Item -Path $portableTester -ErrorAction SilentlyContinue
        }
    }

    $copied = @()
    foreach ($source in $sources) {
        $agentRoots = Get-ChildItem -Path $source.FullName -Directory -Filter "Agent-*" -ErrorAction SilentlyContinue
        foreach ($agentRoot in $agentRoots) {
            $logRoot = Join-Path $agentRoot.FullName "MQL5\\Files\\RPEA\\logs"
            if (-not (Test-Path $logRoot)) { continue }
            $agentTag = Split-Path $agentRoot.FullName -Leaf
            $logFiles = Get-ChildItem -Path $logRoot -File -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match "^(audit|events|decisions)_.*\\.csv$"
            }
            foreach ($file in $logFiles) {
                $destName = "agent_${agentTag}_$($file.Name)"
                $destPath = Join-Path $AuditLogRoot $destName
                if (Test-Path $destPath) {
                    if ((Get-Item $destPath).Length -eq $file.Length) {
                        continue
                    }
                }
                Copy-Item -Path $file.FullName -Destination $destPath -Force
                $copied += $destPath
            }
        }
    }
    return $copied
}

function Escape-CsvValue {
    param($Value)
    $text = if ($null -eq $Value) { "" } else { $Value.ToString() }
    if ($text -match '[,"]') {
        $text = $text -replace '"', '""'
        return '"' + $text + '"'
    }
    return $text
}

$resolvedOutput = Resolve-RepoPath -Path $OutputPath -RepoRoot $RepoRoot
$resolvedTemplate = Resolve-RepoPath -Path $TemplatePath -RepoRoot $RepoRoot
$resolvedAuditRoot = Resolve-RepoPath -Path $AuditLogRoot -RepoRoot $RepoRoot

Ensure-Directory -Path (Split-Path $resolvedOutput -Parent)
Ensure-Directory -Path $resolvedAuditRoot

$mt5Resolved = Resolve-MT5Path -ConfiguredPath $MT5Path -RepoRoot $RepoRoot

if ($CopyAgentLogs) {
    Copy-AgentLogs -RepoRoot $RepoRoot -AuditLogRoot $resolvedAuditRoot -Mt5Path $mt5Resolved | Out-Null
}

$resolvedReport = $ReportPath
if ([string]::IsNullOrEmpty($resolvedReport)) {
    $profileRoot = Get-TerminalProfile -ProfileBase $ProfileBase
    $resolvedReport = Find-LatestReport -ProfileRoot $profileRoot
}
if ([string]::IsNullOrEmpty($resolvedReport)) {
    throw "ReportPath not provided and no MT5 report found."
}
$resolvedReport = Resolve-RepoPath -Path $resolvedReport -RepoRoot $RepoRoot

$metrics = Parse-TestReport -Path $resolvedReport
$hadTradeTable = $metrics.DailyPnl.Count -gt 0
$notes = @()
$fromFilter = if ($FromDate) { [datetime]::ParseExact($FromDate, "yyyy-MM-dd", $null) } else { $null }
$toFilter = if ($ToDate) { [datetime]::ParseExact($ToDate, "yyyy-MM-dd", $null) } else { $null }

$auditHeader = "timestamp,intent_id,action_id,symbol,mode,requested_price,executed_price,requested_vol,filled_vol,remaining_vol,tickets[],retry_count,gate_open_risk,gate_pending_risk,gate_next_risk,room_today,room_overall,gate_pass,decision,confidence,efficiency,rho_est,est_value,hold_time,gating_reason,news_window_state".Split(",")
$legacyHeader = "date,time,event,component,level,message,fields_json".Split(",")

$newsBlocks = 0
$budgetRejects = 0
$floorBreaches = 0
$auditRows = 0
$decisionRows = 0
$eventRows = 0
$auditFiles = New-Object System.Collections.Generic.HashSet[string]
$decisionFiles = New-Object System.Collections.Generic.HashSet[string]
$eventFiles = New-Object System.Collections.Generic.HashSet[string]
$auditTradeDays = New-Object System.Collections.Generic.HashSet[string]

$auditFilesFound = Get-ChildItem -Path $resolvedAuditRoot -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^audit_.*\\.csv$" }
foreach ($file in $auditFilesFound) {
    $lines = Get-Content $file.FullName
    foreach ($line in $lines) {
        if (-not $line) { continue }
        if ($line.StartsWith("timestamp,")) { continue }
        $row = Parse-AuditLogLine -Line $line -Header $auditHeader
        $ts = Try-ParseDate -Value $row["timestamp"]
        if ($fromFilter -and $ts -and $ts -lt $fromFilter) { continue }
        if ($toFilter -and $ts -and $ts -gt $toFilter.AddDays(1)) { continue }
        if ($ts) { $auditTradeDays.Add($ts.ToString("yyyy-MM-dd")) | Out-Null }

        $auditRows += 1
        $auditFiles.Add($file.Name) | Out-Null

        $gating = $row["gating_reason"]
        $decision = $row["decision"]
        $newsState = $row["news_window_state"]

        if (($gating -match "(?i)news_.*block|news_gate_block|news_window_block|news_block") -or
            ($newsState -match "(?i)block") -or
            ($decision -match "(?i)news_.*block|news_gate_block|news_window_block")) {
            $newsBlocks += 1
        }

        if ($gating -match "(?i)budget|insufficient_room|lock_timeout|calc_error|budget_gate|budget_calc") {
            $budgetRejects += 1
        }

        if ($gating -match "(?i)floor|killswitch") {
            $floorBreaches += 1
        }
    }
}

$eventFilesFound = Get-ChildItem -Path $resolvedAuditRoot -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^events_.*\\.csv$" }
foreach ($file in $eventFilesFound) {
    $lines = Get-Content $file.FullName
    foreach ($line in $lines) {
        if (-not $line) { continue }
        if ($line.StartsWith("date,time,")) { continue }
        $row = Parse-LegacyLogLine -Line $line -Header $legacyHeader
        $ts = Try-ParseDate -Value ("$($row["date"]) $($row["time"])")
        if ($fromFilter -and $ts -and $ts -lt $fromFilter) { continue }
        if ($toFilter -and $ts -and $ts -gt $toFilter.AddDays(1)) { continue }
        if ($ts) { $auditTradeDays.Add($ts.ToString("yyyy-MM-dd")) | Out-Null }

        $eventRows += 1
        $eventFiles.Add($file.Name) | Out-Null

        $event = $row["event"]
        $message = $row["message"]
        if ($event -match "(?i)NEWS_BLOCK_START|NEWS_GATE_BLOCK|NEWS_WINDOW_BLOCK") {
            $newsBlocks += 1
        }
        if ($event -match "(?i)KILLSWITCH|FLOOR") {
            $floorBreaches += 1
        }
        if ($message -match "(?i)BUDGET_GATE" -and $row["fields_json"] -match '(?i)gate_pass":false|gate_pass":0') {
            $budgetRejects += 1
        }
    }
}

$decisionFilesFound = Get-ChildItem -Path $resolvedAuditRoot -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^decisions_.*\\.csv$" }
foreach ($file in $decisionFilesFound) {
    $lines = Get-Content $file.FullName
    foreach ($line in $lines) {
        if (-not $line) { continue }
        if ($line.StartsWith("date,time,")) { continue }
        $row = Parse-LegacyLogLine -Line $line -Header $legacyHeader
        $ts = Try-ParseDate -Value ("$($row["date"]) $($row["time"])")
        if ($fromFilter -and $ts -and $ts -lt $fromFilter) { continue }
        if ($toFilter -and $ts -and $ts -gt $toFilter.AddDays(1)) { continue }
        if ($ts) { $auditTradeDays.Add($ts.ToString("yyyy-MM-dd")) | Out-Null }

        $decisionRows += 1
        $decisionFiles.Add($file.Name) | Out-Null

        $message = $row["message"]
        if ($message -match "(?i)BUDGET_GATE") {
            if ($row["fields_json"] -match '(?i)gate_pass":false|gate_pass":0|insufficient_room|lock_timeout|calc_error') {
                $budgetRejects += 1
            }
        }
        if ($message -match "(?i)KILLSWITCH_DAILY|KILLSWITCH_OVERALL") {
            $floorBreaches += 1
        }
    }
}

if (-not $hadTradeTable -and $auditTradeDays.Count -gt 0) {
    $metrics.DailyPnl = @{}
    foreach ($day in $auditTradeDays) { $metrics.DailyPnl[$day] = 0.0 }
    $metrics.TradeDays = $auditTradeDays.Count
    $notes += "trade_days_from_audit"
}
if ($metrics.DailyPnl.Count -eq 0) {
    $notes += "no_trade_table_parsed"
}

$dailyViolations = 0
$baseline = $StartingBalance
$sortedDates = $metrics.DailyPnl.Keys | Sort-Object
foreach ($date in $sortedDates) {
    $value = $metrics.DailyPnl[$date]
    if ($value -lt 0) {
        $lossPct = [Math]::Abs($value / $baseline * 100.0)
        if ($lossPct -ge $MaxDailyLossPct) { $dailyViolations += 1 }
    }
    $baseline += $value
}
$overallViolation = $metrics.MaxDrawdownPct -ge $MaxOverallLossPct
if ($auditFilesFound.Count -eq 0 -and $eventFilesFound.Count -eq 0 -and $decisionFilesFound.Count -eq 0) {
    $notes += "no_audit_logs_found"
}

$templateHeaders = @()
if (Test-Path $resolvedTemplate) {
    $templateHeaders = (Get-Content $resolvedTemplate -Raw).Trim().Split(",")
}
if ($templateHeaders.Count -eq 0) {
    $templateHeaders = "report_id,generated_at,report_path,report_format,symbol,period,from_date,to_date,net_profit,profit_factor,total_trades,win_rate,max_drawdown_pct,trade_days,daily_cap_violations,overall_cap_violation,target_profit,min_trade_days,max_daily_loss_pct,max_overall_loss_pct,starting_balance,news_blocks,budget_gate_rejects,floor_breaches,audit_rows,audit_files,decision_rows,decision_files,event_rows,event_files,notes".Split(",")
}

$reportId = [System.IO.Path]::GetFileNameWithoutExtension($resolvedReport)
$generatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

$rowMap = @{
    report_id = $reportId
    generated_at = $generatedAt
    report_path = $resolvedReport
    report_format = $metrics.ReportFormat
    symbol = $metrics.Metadata.Symbol
    period = $metrics.Metadata.Period
    from_date = $metrics.Metadata.FromDate
    to_date = $metrics.Metadata.ToDate
    net_profit = $metrics.NetProfit
    profit_factor = $metrics.ProfitFactor
    total_trades = $metrics.TotalTrades
    win_rate = $metrics.WinRate
    max_drawdown_pct = $metrics.MaxDrawdownPct
    trade_days = $metrics.TradeDays
    daily_cap_violations = $dailyViolations
    overall_cap_violation = $overallViolation
    target_profit = $TargetProfit
    min_trade_days = $MinTradeDays
    max_daily_loss_pct = $MaxDailyLossPct
    max_overall_loss_pct = $MaxOverallLossPct
    starting_balance = $StartingBalance
    news_blocks = $newsBlocks
    budget_gate_rejects = $budgetRejects
    floor_breaches = $floorBreaches
    audit_rows = $auditRows
    audit_files = ($auditFiles | Sort-Object) -join ";"
    decision_rows = $decisionRows
    decision_files = ($decisionFiles | Sort-Object) -join ";"
    event_rows = $eventRows
    event_files = ($eventFiles | Sort-Object) -join ";"
    notes = ($notes -join ";")
}

$headerLine = ($templateHeaders -join ",")
$valueLine = ($templateHeaders | ForEach-Object { Escape-CsvValue -Value $rowMap[$_] }) -join ","

if ($Append -and (Test-Path $resolvedOutput)) {
    Add-Content -Path $resolvedOutput -Value $valueLine -Encoding ASCII
} else {
    Set-Content -Path $resolvedOutput -Value @($headerLine, $valueLine) -Encoding ASCII
}

Write-Host "Audit report written to $resolvedOutput"
