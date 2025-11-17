param(
    [string]$repoPath = "C:\Users\AWCS\earl-1",
    [string]$terminalPath = "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
)

$srcInclude = Join-Path $repoPath "MQL5\Include\RPEA"
$dstInclude = Join-Path $terminalPath "MQL5\Include\RPEA"
$srcExpert = Join-Path $repoPath "MQL5\Experts\FundingPips"
$dstExpert = Join-Path $terminalPath "MQL5\Experts\FundingPips"

function Sync-Path {
    param([string]$src,[string]$dst)
    if(!(Test-Path $src)) {
        Write-Warning "Source path $src missing"
        return
    }
    Write-Host "Syncing $src -> $dst"
    robocopy $src $dst /MIR | Out-Null
}

Sync-Path $srcInclude $dstInclude
Sync-Path $srcExpert $dstExpert
