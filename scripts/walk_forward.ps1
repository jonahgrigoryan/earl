param(
    [string]$ConfigPath = "$PSScriptRoot\wf_config.json",
    [switch]$DryRun,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
    param(
        [string]$Path,
        [string]$RepoRoot
    )
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return (Join-Path $RepoRoot $Path)
}

function Get-ConfigValue {
    param(
        [pscustomobject]$Config,
        [string]$Name,
        $Default
    )
    $prop = $Config.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($prop) {
        return $prop.Value
    }
    return $Default
}

function Get-OverrideObject {
    param(
        [pscustomobject]$Overrides,
        [string]$Key
    )
    if (-not $Overrides) { return $null }
    $prop = $Overrides.PSObject.Properties | Where-Object { $_.Name -eq $Key } | Select-Object -First 1
    if ($prop) {
        return $prop.Value
    }
    return $null
}

function Find-MT5Terminal {
    param([string]$ConfiguredPath)

    if (-not [string]::IsNullOrEmpty($ConfiguredPath)) {
        $candidate = Join-Path $ConfiguredPath "terminal64.exe"
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    if ($env:MT5_PATH) {
        $envCandidate = Join-Path $env:MT5_PATH "terminal64.exe"
        if (Test-Path $envCandidate) {
            return $envCandidate
        }
    }

    $commonRoots = @(
        "C:\\Program Files\\MetaTrader 5",
        "C:\\Program Files (x86)\\MetaTrader 5",
        "C:\\MetaTrader 5",
        "C:\\MT5"
    )
    foreach ($root in $commonRoots) {
        $candidate = Join-Path $root "terminal64.exe"
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $searchRoots = @("C:\\Program Files", "C:\\Program Files (x86)")
    foreach ($root in $searchRoots) {
        $found = Get-ChildItem -Path $root -Filter "terminal64.exe" -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    throw "MT5 terminal64.exe not found. Set mt5_path in wf_config.json or MT5_PATH env var."
}

function Read-IniValue {
    param(
        [string]$Path,
        [string]$Key,
        $Default = $null
    )
    if (-not (Test-Path $Path)) {
        return $Default
    }
    $lines = Get-Content $Path
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if (-not $trim -or $trim.StartsWith(";")) { continue }
        if ($trim -match "^\s*$Key\s*=\s*(.+)$") {
            return $matches[1].Trim()
        }
    }
    return $Default
}

function Get-OptimizationCriterion {
    param([string]$IniPath)
    $value = Read-IniValue -Path $IniPath -Key "OptimizationCriterion" -Default "1"
    $parsed = 1
    if ([int]::TryParse($value, [ref]$parsed)) {
        return $parsed
    }
    return 1
}

function Get-SymbolConfig {
    param(
        [pscustomobject]$Config,
        [string]$Symbol
    )
    $override = Get-OverrideObject -Overrides $Config.symbol_overrides -Key $Symbol
    return [pscustomobject]@{
        OptimizeIni = if ($override -and $override.optimize_ini) { $override.optimize_ini } else { $Config.optimize_ini }
        SingleIni = if ($override -and $override.single_ini) { $override.single_ini } else { $Config.single_ini }
        QuickIni = if ($override -and $override.quick_ini) { $override.quick_ini } else { $Config.quick_ini }
        OptimizeLeverage = if ($override -and $override.optimize_leverage) { $override.optimize_leverage } else { $null }
        SingleLeverage = if ($override -and $override.single_leverage) { $override.single_leverage } else { $null }
        Leverage = if ($override -and $override.leverage) { $override.leverage } else { $null }
        OptimizationMetric = if ($override -and $override.optimization_metric) { $override.optimization_metric } else { $null }
        OptimizationMetricOrder = if ($override -and $override.optimization_metric_order) { $override.optimization_metric_order } else { $null }
    }
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-TerminalProfile {
    param([string]$ProfileBase)

    if ([string]::IsNullOrEmpty($ProfileBase)) {
        $terminalRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
        $profile = Get-ChildItem -Path $terminalRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $profile) {
            throw "MT5 data folder not found at $terminalRoot"
        }
        $profileRoot = $profile.FullName
        $isPortable = $false
    } else {
        $profileRoot = $ProfileBase
        $isPortable = $true
    }

    # Both portable and default MT5 use MQL5\Profiles\Tester for .set files
    $testerProfiles = Join-Path $profileRoot "MQL5\Profiles\Tester"

    $reportsDir = Join-Path $profileRoot "Tester\reports"
    $filesDir = Join-Path $profileRoot "MQL5\Files"
    $configDir = Join-Path $profileRoot "config"

    return @{
        ProfileRoot = $profileRoot
        TesterProfiles = $testerProfiles
        ReportsDir = $reportsDir
        FilesDir = $filesDir
        ConfigDir = $configDir
        IsPortable = $isPortable
    }
}

function Read-BoolInputs {
    param([string]$Mq5Path)
    $bools = New-Object System.Collections.Generic.HashSet[string]
    $lines = Get-Content $Mq5Path
    foreach ($line in $lines) {
        if ($line -match '^\s*input\s+bool\s+(\w+)') {
            [void]$bools.Add($matches[1])
        }
    }
    return $bools
}

function Read-SetFile {
    param([string]$Path)
    $order = New-Object System.Collections.Generic.List[string]
    $values = @{}
    $lines = Get-Content $Path
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if (-not $trim) { continue }
        if ($trim.StartsWith(";")) { continue }
        if ($trim -notmatch "=") { continue }
        $parts = $trim.Split("=", 2)
        $key = $parts[0].Trim()
        $val = $parts[1].Trim()
        if (-not $values.ContainsKey($key)) {
            $order.Add($key)
        }
        $values[$key] = $val
    }
    return @{ Order = $order; Values = $values }
}

function Write-SetFile {
    param(
        [string]$Path,
        [System.Collections.Generic.List[string]]$Order,
        [hashtable]$Values
    )
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Order) {
        $lines.Add("$key=$($Values[$key])")
    }
    Set-Content -Path $Path -Value $lines -Encoding ASCII
}

function Normalize-BoolValue {
    param([string]$Value)
    $lower = $Value.Trim().ToLowerInvariant()
    if ($lower -eq "true") { return "1" }
    if ($lower -eq "false") { return "0" }
    return $Value.Trim()
}

function Parse-ParametersString {
    param(
        [string]$ParamString,
        [System.Collections.Generic.HashSet[string]]$BoolInputs
    )
    $values = @{}
    if (-not $ParamString) { return $values }

    # Parse key=value pairs, handling semicolons in values (e.g., InpSymbols=EURUSD;XAUUSD)
    # MT5 format: "key1=value1;key2=value2;key3=value_with;semicolons"
    # Split on semicolons that are followed by a parameter name (word char + =)
    # This preserves semicolons inside values like InpSymbols=EURUSD;XAUUSD
    $parts = $ParamString -split ';(?=\s*\w+\s*=)'
    
    foreach ($part in $parts) {
        $trim = $part.Trim()
        if (-not $trim) { continue }
        if ($trim -notmatch '^(\w+)\s*=\s*(.+)$') { continue }
        $key = $matches[1]
        $val = $matches[2].Trim()
        if ($BoolInputs.Contains($key)) {
            $val = Normalize-BoolValue -Value $val
        }
        $values[$key] = $val
    }
    
    return $values
}

function Update-IniContent {
    param(
        [string[]]$Lines,
        [hashtable]$Updates
    )

    $out = New-Object System.Collections.Generic.List[string]
    $inTester = $false
    $testerBuffer = New-Object System.Collections.Generic.List[string]
    $found = @{}

    function Flush-TesterBuffer {
        if ($testerBuffer.Count -eq 0) { return }
        foreach ($line in $testerBuffer) {
            $trim = $line.Trim()
            if ($trim -match '^([^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                if ($Updates.ContainsKey($key)) {
                    $out.Add("$key=$($Updates[$key])")
                    $found[$key] = $true
                } else {
                    $out.Add($line)
                }
            } else {
                $out.Add($line)
            }
        }
        foreach ($key in $Updates.Keys) {
            if (-not $found.ContainsKey($key)) {
                $out.Add("$key=$($Updates[$key])")
                $found[$key] = $true
            }
        }
        $testerBuffer.Clear()
    }

    foreach ($line in $Lines) {
        $trim = $line.Trim()
        if ($trim -match '^\[(.+)\]$') {
            if ($inTester) {
                Flush-TesterBuffer
                $inTester = $false
            }
            $out.Add($line)
            if ($matches[1] -eq "Tester") {
                $inTester = $true
            }
            continue
        }

        if ($inTester) {
            $testerBuffer.Add($line)
        } else {
            $out.Add($line)
        }
    }

    if ($inTester) {
        Flush-TesterBuffer
    }

    return $out.ToArray()
}

function Write-IniFile {
    param(
        [string]$BasePath,
        [hashtable]$Updates,
        [string]$OutPath
    )
    $lines = Get-Content $BasePath
    $updated = Update-IniContent -Lines $lines -Updates $Updates
    Set-Content -Path $OutPath -Value $updated -Encoding ASCII
}

function Ensure-CommonSection {
    param(
        [string]$IniPath,
        [string]$CommonIniPath
    )
    if (-not (Test-Path $IniPath)) {
        return
    }
    $lines = Get-Content $IniPath
    if ($lines | Where-Object { $_ -match '^\s*\[Common\]\s*$' }) {
        return
    }
    if (-not (Test-Path $CommonIniPath)) {
        return
    }

    $commonLines = Get-Content $CommonIniPath
    $section = New-Object System.Collections.Generic.List[string]
    $inCommon = $false
    foreach ($line in $commonLines) {
        if ($line -match '^\s*\[Common\]\s*$') {
            $inCommon = $true
            $section.Add($line)
            continue
        }
        if ($inCommon) {
            if ($line -match '^\s*\[.+\]\s*$') {
                break
            }
            $section.Add($line)
        }
    }
    if ($section.Count -eq 0) {
        return
    }
    $merged = $section + "" + $lines
    Set-Content -Path $IniPath -Value $merged -Encoding ASCII
}

function Convert-ToDouble {
    param(
        [string]$Value,
        [double]$Default = 0
    )
    $parsed = 0.0
    if ([double]::TryParse($Value, [ref]$parsed)) {
        return $parsed
    }
    return $Default
}

function Canonicalize-FieldName {
    param([string]$Name)
    if (-not $Name) { return "" }
    return ($Name -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
}

function Build-CanonicalFieldMap {
    param([hashtable]$Fields)
    $map = @{}
    foreach ($key in $Fields.Keys) {
        $canon = Canonicalize-FieldName -Name $key
        if (-not $canon) { continue }
        $map[$canon] = $Fields[$key]
    }
    return $map
}

function Parse-FieldNumber {
    param([string]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [double] -or $Value -is [int]) { return [double]$Value }
    $text = $Value.ToString().Replace(",", "")
    $match = [regex]::Match($text, '[-+]?\d+(?:\.\d+)?')
    if ($match.Success) {
        return [double]$match.Value
    }
    return $null
}

function Get-CanonicalValue {
    param(
        [hashtable]$Canonical,
        [string[]]$Keys
    )
    foreach ($key in $Keys) {
        $canon = Canonicalize-FieldName -Name $key
        if ($Canonical.ContainsKey($canon)) {
            return $Canonical[$canon]
        }
    }
    return $null
}

function Get-CanonicalNumber {
    param(
        [hashtable]$Canonical,
        [string[]]$Keys
    )
    $value = Get-CanonicalValue -Canonical $Canonical -Keys $Keys
    return Parse-FieldNumber -Value $value
}

function Resolve-OptimizationMetric {
    param(
        [int]$Criterion,
        [string]$OverrideMetric,
        [string]$OverrideOrder
    )
    $metric = $null
    $sortDescending = $true

    if (-not [string]::IsNullOrEmpty($OverrideMetric)) {
        $metric = $OverrideMetric.ToLowerInvariant()
    } else {
        switch ($Criterion) {
            1 { $metric = "profit_factor" }
            2 { $metric = "expected_payoff" }
            3 { $metric = "drawdown"; $sortDescending = $false }
            4 { $metric = "custom" }
            default { $metric = "net_profit" }
        }
    }

    if (-not [string]::IsNullOrEmpty($OverrideOrder)) {
        $sortDescending = $OverrideOrder.ToLowerInvariant() -ne "asc"
    }

    return [pscustomobject]@{
        Metric = $metric
        SortDescending = $sortDescending
    }
}

function Get-RowMetricValue {
    param(
        [pscustomobject]$Row,
        [string]$Metric
    )
    switch ($Metric) {
        "profit_factor" { return $Row.ProfitFactor }
        "expected_payoff" { return $Row.ExpectedPayoff }
        "drawdown" { return $Row.Drawdown }
        "custom" { return Get-CanonicalNumber -Canonical $Row.Canonical -Keys @("custom", "customcriterion") }
        default { return $Row.NetProfit }
    }
}

function Build-OptimizationRow {
    param([hashtable]$Fields)
    if (-not $Fields -or $Fields.Count -eq 0) {
        return $null
    }

    $canonical = Build-CanonicalFieldMap -Fields $Fields
    $paramsRaw = Get-CanonicalValue -Canonical $canonical -Keys @("parameters", "inputs")
    $trades = Get-CanonicalNumber -Canonical $canonical -Keys @("trades", "totaltrades", "tradescount")
    $netProfit = Get-CanonicalNumber -Canonical $canonical -Keys @("netprofit", "profit", "result", "balance", "totalnetprofit")
    $profitFactor = Get-CanonicalNumber -Canonical $canonical -Keys @("profitfactor", "pf", "profit_factor")
    $expectedPayoff = Get-CanonicalNumber -Canonical $canonical -Keys @("expectedpayoff", "expectedpayoffpoints", "expectedpayoffpertrade")
    $drawdown = Get-CanonicalNumber -Canonical $canonical -Keys @("drawdown", "maxdrawdown", "maximaldrawdown", "maxdd", "drawdownpercent", "maxdrawdownpercent", "equitydd", "equityddpercent")

    return [pscustomobject]@{
        Trades = if ($trades) { [int]$trades } else { 0 }
        NetProfit = $netProfit
        ProfitFactor = $profitFactor
        ExpectedPayoff = $expectedPayoff
        Drawdown = $drawdown
        ParamsRaw = if ($paramsRaw) { $paramsRaw } else { "" }
        Fields = $Fields
        Canonical = $canonical
    }
}

function Get-SpreadsheetRowValues {
    param(
        [System.Xml.XmlNode]$Row,
        [System.Xml.XmlNamespaceManager]$Ns
    )
    $values = @()
    $colIndex = 1
    $cells = $Row.SelectNodes("ss:Cell", $Ns)
    foreach ($cell in $cells) {
        $indexNode = $cell.SelectSingleNode("@ss:Index", $Ns)
        if ($indexNode) {
            $colIndex = [int]$indexNode.Value
        }
        $dataNode = $cell.SelectSingleNode("ss:Data", $Ns)
        if ($dataNode) {
            while ($values.Count -lt $colIndex) {
                $values += $null
            }
            $values[$colIndex - 1] = $dataNode.InnerText
        }
        $colIndex += 1
    }
    return ,$values
}

function Parse-OptimizationReportSpreadsheet {
    param([xml]$Xml)
    $ns = New-Object System.Xml.XmlNamespaceManager($Xml.NameTable)
    $ns.AddNamespace("ss", "urn:schemas-microsoft-com:office:spreadsheet")

    $rowNodes = $Xml.SelectNodes("//ss:Worksheet[@ss:Name='Tester Optimizator Results']//ss:Row", $ns)
    if (-not $rowNodes -or $rowNodes.Count -eq 0) {
        $rowNodes = $Xml.SelectNodes("//ss:Worksheet//ss:Row", $ns)
    }
    if (-not $rowNodes -or $rowNodes.Count -eq 0) {
        return @()
    }

    $headers = @()
    $results = @()
    $rowIndex = 0
    foreach ($row in $rowNodes) {
        $values = Get-SpreadsheetRowValues -Row $row -Ns $ns
        if ($rowIndex -eq 0) {
            $headers = $values
            $rowIndex += 1
            continue
        }
        if (-not $headers -or $headers.Count -eq 0) {
            continue
        }
        $fields = @{}
        for ($i = 0; $i -lt $headers.Count -and $i -lt $values.Count; $i++) {
            $header = $headers[$i]
            if ([string]::IsNullOrWhiteSpace($header)) { continue }
            $fields[$header] = $values[$i]
        }
        $rowObj = Build-OptimizationRow -Fields $fields
        if ($rowObj) {
            $results += $rowObj
        }
    }

    return $results
}

function Get-NewReportFile {
    param(
        [string[]]$SearchDirs,
        [string[]]$Patterns,
        [datetime]$Since
    )
    $candidates = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($dir in $SearchDirs) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($pattern in $Patterns) {
            $items = Get-ChildItem -Path $dir -Filter $pattern -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($item.LastWriteTime -ge $Since) {
                    $candidates.Add($item)
                }
            }
        }
    }
    # If no pattern-matched files found, get most recent report file of any name
    if ($candidates.Count -eq 0) {
        $allReports = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        foreach ($dir in $SearchDirs) {
            if (-not (Test-Path $dir)) { continue }
            $items = Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | 
                Where-Object { $_.LastWriteTime -ge $Since -and ($_.Extension -eq ".xml" -or $_.Extension -eq ".htm" -or $_.Extension -eq ".html") }
            foreach ($item in $items) {
                $allReports.Add($item)
            }
        }
        if ($allReports.Count -gt 0) {
            return $allReports | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        return $null
    }
    return $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Invoke-MT5Run {
    param(
        [string]$TerminalPath,
        [string]$IniPath,
        [string[]]$ReportSearchDirs,
        [string[]]$ReportPatterns,
        [int]$TimeoutSeconds
    )
    $start = Get-Date
    $iniPathArg = "/config:$IniPath"
    $proc = Start-Process -FilePath $TerminalPath -ArgumentList @("/tester", $iniPathArg) -PassThru
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $report = Get-NewReportFile -SearchDirs $ReportSearchDirs -Patterns $ReportPatterns -Since $start
        if ($report) {
            return $report.FullName
        }
        if ($proc.HasExited) {
            Start-Sleep -Seconds 2
            $report = Get-NewReportFile -SearchDirs $ReportSearchDirs -Patterns $ReportPatterns -Since $start
            if ($report) {
                return $report.FullName
            }
        }
    }

    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
    throw "MT5 run timed out without report: $IniPath"
}

function Parse-OptimizationReport {
    param([string]$XmlPath)

    [xml]$xml = Get-Content $XmlPath -Raw
    $rows = Parse-OptimizationReportSpreadsheet -Xml $xml
    if ($rows.Count -gt 0) {
        return $rows
    }

    $rows = @()
    $nodes = $xml.SelectNodes("//Row")

    foreach ($node in $nodes) {
        $fields = @{}
        foreach ($child in $node.ChildNodes) {
            if ($child.NodeType -ne "Element") { continue }
            $fields[$child.Name] = $child.InnerText.Trim()
        }
        foreach ($attr in $node.Attributes) {
            $fields[$attr.Name] = $attr.Value
        }

        $rowObj = Build-OptimizationRow -Fields $fields
        if ($rowObj) {
            $rows += $rowObj
        }
    }

    return $rows
}

function Get-FirstNumber {
    param(
        [string]$Content,
        [string]$Label
    )
    $pattern = [regex]::Escape($Label) + "[^\d-]*([\-\d\.,]+)"
    $match = [regex]::Match($Content, $pattern, "IgnoreCase")
    if ($match.Success) {
        return ($match.Groups[1].Value -replace ",", "")
    }
    return $null
}

function Get-PercentAfterLabel {
    param(
        [string]$Content,
        [string]$Label
    )
    $pattern = [regex]::Escape($Label) + ".{0,200}?([\\-\\d\\.,]+)%"
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor `
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    $match = [regex]::Match($Content, $pattern, $options)
    if ($match.Success) {
        return ($match.Groups[1].Value -replace ",", "")
    }
    return $null
}

function Parse-TestReport {
    param([string]$Path)

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $netProfit = $null
    $profitFactor = $null
    $maxDdPct = $null
    $totalTrades = $null
    $dailyPnl = @{}

    if ($ext -eq ".xml") {
        [xml]$xml = Get-Content $Path -Raw
        $content = $xml.OuterXml
        $netProfit = Get-FirstNumber -Content $content -Label "Total Net Profit"
        if (-not $netProfit) { $netProfit = Get-FirstNumber -Content $content -Label "Net Profit" }
        $profitFactor = Get-FirstNumber -Content $content -Label "Profit Factor"
        # Prefer percent value when drawdown appears as "Maximal Drawdown 123.45 (1.23%)"
        $maxDdPct = Get-PercentAfterLabel -Content $content -Label "Maximal Drawdown"
        if (-not $maxDdPct) { $maxDdPct = Get-PercentAfterLabel -Content $content -Label "Max Drawdown" }
        if (-not $maxDdPct) { $maxDdPct = Get-FirstNumber -Content $content -Label "Maximal Drawdown %" }
        if (-not $maxDdPct) { $maxDdPct = Get-FirstNumber -Content $content -Label "Max Drawdown %" }
        if (-not $maxDdPct) { $maxDdPct = Get-FirstNumber -Content $content -Label "Maximal Drawdown" }
        $totalTrades = Get-FirstNumber -Content $content -Label "Total Trades"

        $nodes = $xml.SelectNodes("//Deal|//Trade|//Row")
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
                    if (-not $dailyPnl.ContainsKey($date)) { $dailyPnl[$date] = 0.0 }
                    $dailyPnl[$date] += $profitVal
                }
            }
        }
    } else {
        $content = Get-Content $Path -Raw
        $netProfit = Get-FirstNumber -Content $content -Label "Total Net Profit"
        if (-not $netProfit) { $netProfit = Get-FirstNumber -Content $content -Label "Net Profit" }
        $profitFactor = Get-FirstNumber -Content $content -Label "Profit Factor"
        # Prefer percent value when drawdown appears as "Maximal Drawdown 123.45 (1.23%)"
        $maxDdPct = Get-PercentAfterLabel -Content $content -Label "Maximal Drawdown"
        if (-not $maxDdPct) { $maxDdPct = Get-PercentAfterLabel -Content $content -Label "Max Drawdown" }
        if (-not $maxDdPct) { $maxDdPct = Get-FirstNumber -Content $content -Label "Maximal Drawdown %" }
        if (-not $maxDdPct) { $maxDdPct = Get-FirstNumber -Content $content -Label "Max Drawdown %" }
        if (-not $maxDdPct) { $maxDdPct = Get-FirstNumber -Content $content -Label "Maximal Drawdown" }
        $totalTrades = Get-FirstNumber -Content $content -Label "Total Trades"

        $rows = [regex]::Matches($content, "<tr[^>]*>.*?</tr>", "Singleline")
        foreach ($row in $rows) {
            $rowText = $row.Value
            if ($rowText -notmatch '(\d{4}\.\d{2}\.\d{2})') { continue }
            $date = $matches[1]
            $numbers = [regex]::Matches($rowText, '[-+]?[0-9]+(?:\.[0-9]+)?')
            if ($numbers.Count -eq 0) { continue }
            $profitText = $numbers[$numbers.Count - 1].Value
            $profitVal = [double]$profitText
            if (-not $dailyPnl.ContainsKey($date)) { $dailyPnl[$date] = 0.0 }
            $dailyPnl[$date] += $profitVal
        }
    }

    if (-not $netProfit) { throw "Net profit not found in report: $Path" }
    if (-not $profitFactor) { throw "Profit factor not found in report: $Path" }
    if (-not $maxDdPct) { throw "Max drawdown percent not found in report: $Path" }

    $tradeDays = $dailyPnl.Keys.Count

    return [pscustomobject]@{
        NetProfit = Convert-ToDouble -Value $netProfit -Default 0
        ProfitFactor = Convert-ToDouble -Value $profitFactor -Default 0
        MaxDrawdownPct = Convert-ToDouble -Value ($maxDdPct -replace '%','') -Default 0
        TotalTrades = if ($totalTrades) { [int](Convert-ToDouble -Value $totalTrades -Default 0) } else { 0 }
        DailyPnl = $dailyPnl
        TradeDays = $tradeDays
    }
}

function Compute-PassCriteria {
    param(
        [pscustomobject]$Metrics,
        [pscustomobject]$Config
    )
    $startingBalance = [double](Get-ConfigValue -Config $Config -Name "starting_balance" -Default 10000)
    $maxDailyLossPct = [double](Get-ConfigValue -Config $Config -Name "max_daily_loss_pct" -Default 4.0)
    $maxOverallLossPct = [double](Get-ConfigValue -Config $Config -Name "max_overall_loss_pct" -Default 6.0)
    $targetProfit = [double](Get-ConfigValue -Config $Config -Name "target_profit" -Default 1000.0)
    $minTradeDays = [int](Get-ConfigValue -Config $Config -Name "min_trade_days" -Default 3)

    $dailyViolations = 0
    $sortedDates = $Metrics.DailyPnl.Keys | Sort-Object
    $dayBaseline = $startingBalance
    foreach ($date in $sortedDates) {
        $value = $Metrics.DailyPnl[$date]
        if ($value -lt 0) {
            $lossPct = [Math]::Abs($value / $dayBaseline * 100.0)
            if ($lossPct -ge $maxDailyLossPct) {
                $dailyViolations += 1
            }
        }
        $dayBaseline += $value
    }

    $overallViolation = $Metrics.MaxDrawdownPct -ge $maxOverallLossPct

    $profitOk = $Metrics.NetProfit -ge $targetProfit
    $tradeDaysOk = $Metrics.TradeDays -ge $minTradeDays
    $dailyOk = $dailyViolations -eq 0
    $overallOk = -not $overallViolation

    $pass = $profitOk -and $tradeDaysOk -and $dailyOk -and $overallOk
    $reasons = @()
    if (-not $profitOk) { $reasons += "profit_target" }
    if (-not $tradeDaysOk) { $reasons += "trade_days" }
    if (-not $dailyOk) { $reasons += "daily_cap" }
    if (-not $overallOk) { $reasons += "overall_cap" }

    return [pscustomobject]@{
        Pass = $pass
        DailyCapViolations = $dailyViolations
        OverallCapViolation = $overallViolation
        Reasons = ($reasons -join ",")
    }
}

function Get-Windows {
    param(
        [datetime]$StartDate,
        [datetime]$EndDate,
        [int]$InSampleMonths,
        [int]$OutSampleWeeks
    )
    $windows = @()
    $cursor = $StartDate
    $index = 1
    while ($true) {
        $isStart = $cursor
        $isEnd = $isStart.AddMonths($InSampleMonths).AddDays(-1)
        $oosStart = $isEnd.AddDays(1)
        $oosEnd = $oosStart.AddDays(($OutSampleWeeks * 7) - 1)

        if ($oosEnd -gt $EndDate) {
            break
        }

        $windows += [pscustomobject]@{
            Index = $index
            ISStart = $isStart
            ISEnd = $isEnd
            OOSStart = $oosStart
            OOSEnd = $oosEnd
        }

        $cursor = $oosStart
        $index += 1
    }
    return $windows
}

# Main
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path $ScriptRoot -Parent

if (-not (Test-Path $ConfigPath)) {
    throw "Config not found: $ConfigPath"
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$mt5Path = Get-ConfigValue -Config $config -Name "mt5_path" -Default ""
$terminalPath = Find-MT5Terminal -ConfiguredPath $mt5Path
$profileBase = Get-ConfigValue -Config $config -Name "profile_base" -Default ""
$profileInfo = Get-TerminalProfile -ProfileBase $profileBase
$commonIniPath = Join-Path $profileInfo.ConfigDir "common.ini"

$runId = Get-ConfigValue -Config $config -Name "run_id" -Default ""
if ([string]::IsNullOrWhiteSpace($runId)) {
    $runId = Get-Date -Format "yyyyMMdd-HHmmss"
}
$allowProfileWrite = [bool](Get-ConfigValue -Config $config -Name "allow_profile_write" -Default $true)
$copySets = [bool](Get-ConfigValue -Config $config -Name "copy_sets" -Default $true)
$copyNews = [bool](Get-ConfigValue -Config $config -Name "copy_news" -Default $true)
$configOutputDir = Get-ConfigValue -Config $config -Name "config_output_dir" -Default ""

$defaultSetPath = Resolve-RepoPath -Path $config.default_set -RepoRoot $RepoRoot
$optimizeSetPath = Resolve-RepoPath -Path $config.optimize_set -RepoRoot $RepoRoot
$newsCsvPath = Resolve-RepoPath -Path $config.news_csv -RepoRoot $RepoRoot
$outputCsvPath = Resolve-RepoPath -Path $config.output_csv -RepoRoot $RepoRoot

$useQuickModel = [bool](Get-ConfigValue -Config $config -Name "use_quick_model" -Default $false)

$requiredFiles = @($defaultSetPath, $optimizeSetPath)
$symbolList = Get-ConfigValue -Config $config -Name "symbols" -Default @("EURUSD")
if ($symbolList -is [string]) {
    $symbolList = $symbolList -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
foreach ($symbol in $symbolList) {
    $symbolCfg = Get-SymbolConfig -Config $config -Symbol $symbol
    $optIni = Resolve-RepoPath -Path $symbolCfg.OptimizeIni -RepoRoot $RepoRoot
    $singleIni = Resolve-RepoPath -Path $symbolCfg.SingleIni -RepoRoot $RepoRoot
    $requiredFiles += @($optIni, $singleIni)
    if ($useQuickModel -and $symbolCfg.QuickIni) {
        $quickIni = Resolve-RepoPath -Path $symbolCfg.QuickIni -RepoRoot $RepoRoot
        $requiredFiles += $quickIni
    }
}
foreach ($path in $requiredFiles) {
    if (-not (Test-Path $path)) {
        throw "Required file missing: $path"
    }
}

if (-not $allowProfileWrite -and -not ($ValidateOnly -or $DryRun)) {
    throw "allow_profile_write=false prevents MT5 automation. Enable it or use -ValidateOnly/-DryRun."
}

if ([string]::IsNullOrEmpty($configOutputDir)) {
    $configOutputDir = $profileInfo.ConfigDir
} else {
    $configOutputDir = Resolve-RepoPath -Path $configOutputDir -RepoRoot $RepoRoot
}

$startDate = [datetime]::ParseExact($config.start_date, "yyyy-MM-dd", $null)
$endDate = [datetime]::ParseExact($config.end_date, "yyyy-MM-dd", $null)
$windows = Get-Windows -StartDate $startDate -EndDate $endDate -InSampleMonths $config.in_sample_months -OutSampleWeeks $config.out_sample_weeks
if ($windows.Count -eq 0) {
    throw "No walk-forward windows generated. Check start/end dates and window sizes."
}

$period = Get-ConfigValue -Config $config -Name "period" -Default "M1"
$minTrades = [int](Get-ConfigValue -Config $config -Name "min_trades" -Default 10)
$maxCandidates = [int](Get-ConfigValue -Config $config -Name "max_candidates" -Default 5)
$maxPassingCandidates = [int](Get-ConfigValue -Config $config -Name "max_passing_candidates" -Default 1)
$stopWhenPasses = [bool](Get-ConfigValue -Config $config -Name "stop_when_passes" -Default $true)
$terminalTimeoutSeconds = [int](Get-ConfigValue -Config $config -Name "terminal_timeout_seconds" -Default 3600)
$globalMetricOverride = Get-ConfigValue -Config $config -Name "optimization_metric" -Default ""
$globalMetricOrder = Get-ConfigValue -Config $config -Name "optimization_metric_order" -Default ""
$criteriaTargetProfit = [double](Get-ConfigValue -Config $config -Name "target_profit" -Default 1000.0)
$criteriaMinTradeDays = [int](Get-ConfigValue -Config $config -Name "min_trade_days" -Default 3)
$criteriaMaxDailyLossPct = [double](Get-ConfigValue -Config $config -Name "max_daily_loss_pct" -Default 4.0)
$criteriaMaxOverallLossPct = [double](Get-ConfigValue -Config $config -Name "max_overall_loss_pct" -Default 6.0)

if ($ValidateOnly) {
    Write-Host "Validation OK" -ForegroundColor Green
    Write-Host "MT5 terminal: $terminalPath"
    Write-Host "MT5 profile: $($profileInfo.ProfileRoot)"
    Write-Host "Windows: $(@($windows).Count)"
    Write-Host "Config output: $configOutputDir"
    Write-Host "Quick model: $useQuickModel"
    Write-Host "Run ID: $runId"
    exit 0
}

Ensure-Directory -Path (Split-Path $outputCsvPath -Parent)
Ensure-Directory -Path $configOutputDir

if ($allowProfileWrite) {
    Ensure-Directory -Path $profileInfo.TesterProfiles
    Ensure-Directory -Path $profileInfo.ReportsDir
    Ensure-Directory -Path $profileInfo.FilesDir
    Ensure-Directory -Path $profileInfo.ConfigDir
}

# Copy base .set files to Tester profiles
$defaultSetName = Split-Path $defaultSetPath -Leaf
$optimizeSetName = Split-Path $optimizeSetPath -Leaf
if ($copySets) {
    Copy-Item $defaultSetPath $profileInfo.TesterProfiles -Force
    Copy-Item $optimizeSetPath $profileInfo.TesterProfiles -Force
} else {
    $defaultInProfile = Join-Path $profileInfo.TesterProfiles $defaultSetName
    $optimizeInProfile = Join-Path $profileInfo.TesterProfiles $optimizeSetName
    if (-not (Test-Path $defaultInProfile)) {
        throw "Default .set not found in MT5 profiles: $defaultInProfile"
    }
    if (-not (Test-Path $optimizeInProfile)) {
        throw "Optimize .set not found in MT5 profiles: $optimizeInProfile"
    }
}

# Copy news CSV to MT5 Files folder (if available)
if ($copyNews -and (Test-Path $newsCsvPath)) {
    $newsDest = Join-Path $profileInfo.FilesDir "RPEA\news"
    Ensure-Directory -Path $newsDest
    Copy-Item $newsCsvPath $newsDest -Force
}

# Prepare parameter base
$boolInputs = Read-BoolInputs -Mq5Path (Join-Path $RepoRoot "MQL5\Experts\FundingPips\RPEA.mq5")
$defaultSet = Read-SetFile -Path $defaultSetPath

$tempDir = Join-Path $ScriptRoot "tmp\wf"
Ensure-Directory -Path $tempDir

$results = @()

foreach ($symbol in $symbolList) {
    $symbolCfg = Get-SymbolConfig -Config $config -Symbol $symbol
    $optimizeIniPath = Resolve-RepoPath -Path $symbolCfg.OptimizeIni -RepoRoot $RepoRoot
    $singleIniTemplatePath = Resolve-RepoPath -Path $symbolCfg.SingleIni -RepoRoot $RepoRoot
    $quickIniTemplatePath = $null
    if ($symbolCfg.QuickIni) {
        $quickIniTemplatePath = Resolve-RepoPath -Path $symbolCfg.QuickIni -RepoRoot $RepoRoot
    }

    $optIniTemplate = if ($useQuickModel -and $quickIniTemplatePath -and (Test-Path $quickIniTemplatePath)) { $quickIniTemplatePath } else { $optimizeIniPath }
    $criterion = Get-OptimizationCriterion -IniPath $optIniTemplate
    $metricOverride = if ($symbolCfg.OptimizationMetric) { $symbolCfg.OptimizationMetric } else { $globalMetricOverride }
    $metricOrderOverride = if ($symbolCfg.OptimizationMetricOrder) { $symbolCfg.OptimizationMetricOrder } else { $globalMetricOrder }
    $metricConfig = Resolve-OptimizationMetric -Criterion $criterion -OverrideMetric $metricOverride -OverrideOrder $metricOrderOverride

    $optLeverage = if ($symbolCfg.OptimizeLeverage) { $symbolCfg.OptimizeLeverage } elseif ($symbolCfg.Leverage) { $symbolCfg.Leverage } else { $null }
    $singleLeverage = if ($symbolCfg.SingleLeverage) { $symbolCfg.SingleLeverage } elseif ($symbolCfg.Leverage) { $symbolCfg.Leverage } else { $null }

    foreach ($window in $windows) {
        $isStart = $window.ISStart.ToString("yyyy.MM.dd")
        $isEnd = $window.ISEnd.ToString("yyyy.MM.dd")
        $oosStart = $window.OOSStart.ToString("yyyy.MM.dd")
        $oosEnd = $window.OOSEnd.ToString("yyyy.MM.dd")

        $optIniName = "wf_opt_$($symbol)_$($window.Index).ini"
        $optIniPath = Join-Path $configOutputDir $optIniName
        $optSetName = $optimizeSetName

        $optReportName = "wf_opt_${symbol}_$($window.Index).xml"
        $optUpdates = @{
            Symbol = $symbol
            Period = $period
            FromDate = $isStart
            ToDate = $isEnd
            ExpertParameters = $optSetName
            Report = (Join-Path "Tester\\reports" $optReportName)
        }
        if ($useQuickModel) {
            # Speed up optimization runs while keeping OOS tests on Model=4
            $optUpdates["Optimization"] = 1
            $optUpdates["Model"] = 1
        }
        if ($optLeverage) {
            $optUpdates["Leverage"] = $optLeverage
        }

        Write-IniFile -BasePath $optIniTemplate -Updates $optUpdates -OutPath $optIniPath
        Ensure-CommonSection -IniPath $optIniPath -CommonIniPath $commonIniPath

        if ($DryRun) {
            Write-Host "DryRun: Optimization $symbol $isStart-$isEnd" -ForegroundColor Cyan
            continue
        }

        # MT5 may generate reports with various names if Report= is not set in .ini
        # Check for common patterns: RPEA*.xml, report*.xml, optimization*.xml, or most recent XML
        $optReport = Invoke-MT5Run -TerminalPath $terminalPath -IniPath $optIniPath `
            -ReportSearchDirs @($profileInfo.ReportsDir, $profileInfo.ProfileRoot) `
            -ReportPatterns @("RPEA*.xml", "report*.xml", "optimization*.xml", "*.xml") `
            -TimeoutSeconds $terminalTimeoutSeconds

        $optRows = Parse-OptimizationReport -XmlPath $optReport
        foreach ($row in $optRows) {
            $metricValue = Get-RowMetricValue -Row $row -Metric $metricConfig.Metric
            $row | Add-Member -NotePropertyName "Metric" -NotePropertyValue $metricValue -Force
        }

        $filtered = $optRows | Where-Object { $_.Trades -ge $minTrades -and $null -ne $_.Metric }
        if ($metricConfig.SortDescending) {
            $filtered = $filtered | Sort-Object Metric -Descending
        } else {
            $filtered = $filtered | Sort-Object Metric
        }
        $candidates = $filtered | Select-Object -First $maxCandidates

        if (-not $candidates -or $candidates.Count -eq 0) {
            $results += [pscustomobject]@{
                run_id = $runId
                window_index = $window.Index
                symbol = $symbol
                is_start = $isStart
                is_end = $isEnd
                oos_start = $oosStart
                oos_end = $oosEnd
                candidate_rank = 0
                optimization_criterion = $criterion
                metric_name = $metricConfig.Metric
                metric_order = if ($metricConfig.SortDescending) { "desc" } else { "asc" }
                is_metric = 0
                is_trades = 0
                is_net_profit = 0
                is_profit_factor = 0
                is_expected_payoff = 0
                is_drawdown = 0
                is_params_raw = ""
                oos_net_profit = 0
                oos_profit_factor = 0
                oos_total_trades = 0
                oos_trade_days = 0
                oos_max_drawdown_pct = 0
                criteria_target_profit = $criteriaTargetProfit
                criteria_min_trade_days = $criteriaMinTradeDays
                criteria_max_daily_loss_pct = $criteriaMaxDailyLossPct
                criteria_max_overall_loss_pct = $criteriaMaxOverallLossPct
                oos_daily_cap_violations = 0
                oos_overall_cap_violation = $false
                pass = $false
                notes = if ($optRows.Count -eq 0) { "no_optimization_rows" } else { "no_candidates_after_filter" }
                is_report = $optReport
                oos_report = ""
                set_file = ""
            }
            continue
        }

        $passCount = 0
        $rank = 1
        foreach ($candidate in $candidates) {
            $paramOverrides = Parse-ParametersString -ParamString $candidate.ParamsRaw -BoolInputs $boolInputs
            foreach ($fieldKey in $candidate.Fields.Keys) {
                if ($defaultSet.Values.ContainsKey($fieldKey)) {
                    $value = $candidate.Fields[$fieldKey]
                    if ($boolInputs.Contains($fieldKey)) {
                        $value = Normalize-BoolValue -Value $value
                    }
                    $paramOverrides[$fieldKey] = $value
                }
            }
            $candidateValues = @{}
            foreach ($key in $defaultSet.Values.Keys) {
                $candidateValues[$key] = $defaultSet.Values[$key]
            }
            foreach ($key in $paramOverrides.Keys) {
                $candidateValues[$key] = $paramOverrides[$key]
            }

            $candidateSetName = "wf_${symbol}_$($window.Index)_$rank.set"
            $candidateSetPath = Join-Path $profileInfo.TesterProfiles $candidateSetName
            Write-SetFile -Path $candidateSetPath -Order $defaultSet.Order -Values $candidateValues

            $singleIniName = "wf_single_$($symbol)_$($window.Index)_$rank.ini"
            $singleIniPath = Join-Path $configOutputDir $singleIniName
            $singleReportName = "wf_single_${symbol}_$($window.Index)_$rank.xml"
            $singleUpdates = @{
                Symbol = $symbol
                Period = $period
                FromDate = $oosStart
                ToDate = $oosEnd
                ExpertParameters = $candidateSetName
                Report = (Join-Path "Tester\\reports" $singleReportName)
            }
            if ($singleLeverage) {
                $singleUpdates["Leverage"] = $singleLeverage
            }

            Write-IniFile -BasePath $singleIniTemplatePath -Updates $singleUpdates -OutPath $singleIniPath
            Ensure-CommonSection -IniPath $singleIniPath -CommonIniPath $commonIniPath

            # MT5 may generate reports with various names if Report= is not set in .ini
            # Check for common patterns: RPEA*.htm/html/xml, report*.htm/html/xml, or most recent report
            $testReport = Invoke-MT5Run -TerminalPath $terminalPath -IniPath $singleIniPath `
                -ReportSearchDirs @($profileInfo.ReportsDir, $profileInfo.ProfileRoot) `
                -ReportPatterns @("RPEA*.htm", "RPEA*.html", "RPEA*.xml", "report*.htm", "report*.html", "report*.xml", "*.htm", "*.html", "*.xml") `
                -TimeoutSeconds $terminalTimeoutSeconds

            $metrics = Parse-TestReport -Path $testReport
            $criteria = Compute-PassCriteria -Metrics $metrics -Config $config

            $results += [pscustomobject]@{
                run_id = $runId
                window_index = $window.Index
                symbol = $symbol
                is_start = $isStart
                is_end = $isEnd
                oos_start = $oosStart
                oos_end = $oosEnd
                candidate_rank = $rank
                optimization_criterion = $criterion
                metric_name = $metricConfig.Metric
                metric_order = if ($metricConfig.SortDescending) { "desc" } else { "asc" }
                is_metric = $candidate.Metric
                is_trades = $candidate.Trades
                is_net_profit = if ($candidate.NetProfit) { $candidate.NetProfit } else { 0 }
                is_profit_factor = if ($candidate.ProfitFactor) { $candidate.ProfitFactor } else { 0 }
                is_expected_payoff = if ($candidate.ExpectedPayoff) { $candidate.ExpectedPayoff } else { 0 }
                is_drawdown = if ($candidate.Drawdown) { $candidate.Drawdown } else { 0 }
                is_params_raw = $candidate.ParamsRaw
                oos_net_profit = $metrics.NetProfit
                oos_profit_factor = $metrics.ProfitFactor
                oos_total_trades = $metrics.TotalTrades
                oos_trade_days = $metrics.TradeDays
                oos_max_drawdown_pct = $metrics.MaxDrawdownPct
                criteria_target_profit = $criteriaTargetProfit
                criteria_min_trade_days = $criteriaMinTradeDays
                criteria_max_daily_loss_pct = $criteriaMaxDailyLossPct
                criteria_max_overall_loss_pct = $criteriaMaxOverallLossPct
                oos_daily_cap_violations = $criteria.DailyCapViolations
                oos_overall_cap_violation = $criteria.OverallCapViolation
                pass = $criteria.Pass
                notes = $criteria.Reasons
                is_report = $optReport
                oos_report = $testReport
                set_file = $candidateSetName
            }

            if ($criteria.Pass) {
                $passCount += 1
            }
            if ($stopWhenPasses -and $passCount -ge $maxPassingCandidates) {
                break
            }
            $rank += 1
        }
    }
}

if ($results.Count -gt 0) {
    if (-not (Test-Path $outputCsvPath)) {
        $results | Export-Csv -Path $outputCsvPath -NoTypeInformation
    } else {
        $results | Export-Csv -Path $outputCsvPath -NoTypeInformation -Append
    }
}

Write-Host "Walk-forward complete. Results: $outputCsvPath"
