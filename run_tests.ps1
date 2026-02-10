param(
   [string]$RepoRoot = "C:\Users\AWCS\earl-1",
   [string]$MT5InstallPath = "C:\Program Files\MetaTrader 5",
   [string]$TerminalDataPath = "C:\Users\AWCS\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
   [int]$TimeoutSec = 600,
   [string]$RequiredSuite = "",
   [switch]$SkipSync,
   [switch]$SkipCompile
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$Message)
{
   Write-Host "[run_tests] $Message"
}

function Resolve-TerminalDataPath([string]$Preferred)
{
   if($Preferred -and (Test-Path $Preferred))
   {
      return (Resolve-Path $Preferred).Path
   }

   $terminalRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
   $profile = Get-ChildItem -Path $terminalRoot -Directory -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
   if($profile)
   {
      return $profile.FullName
   }

   throw "MT5 data folder not found under $terminalRoot"
}

function Resolve-ToolPath([string[]]$Candidates, [string]$ToolName)
{
   foreach($candidate in $Candidates)
   {
      if(Test-Path $candidate)
      {
         return $candidate
      }
   }
   throw "$ToolName not found. Tried: $($Candidates -join ', ')"
}

function Get-TesterResultFiles([datetime]$NotBefore)
{
   $testerRoot = Join-Path $env:APPDATA "MetaQuotes\Tester"
   if(-not (Test-Path $testerRoot))
   {
      return @()
   }

   $files = Get-ChildItem -Path $testerRoot -Recurse -Filter "test_results.json" -File -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -like "*\MQL5\Files\RPEA\test_results\test_results.json" }

   if($NotBefore -gt [datetime]::MinValue)
   {
      $lowerBound = $NotBefore.AddSeconds(-2)
      $files = $files | Where-Object { $_.LastWriteTime -ge $lowerBound }
   }

   return @($files)
}

function Parse-CompileErrors([string]$CompileLogPath)
{
   if(-not (Test-Path $CompileLogPath))
   {
      return -1
   }

   $resultLine = Get-Content -Path $CompileLogPath | Select-String -Pattern "^Result:" | Select-Object -Last 1
   if(-not $resultLine)
   {
      return -1
   }

   if($resultLine.Line -match "Result:\s*(\d+)\s+errors?")
   {
      return [int]$matches[1]
   }

   return -1
}

function Assert-CompileZeroErrors([string]$CompileLogPath, [string]$Label)
{
   $errors = Parse-CompileErrors -CompileLogPath $CompileLogPath
   if($errors -ne 0)
   {
      throw "$Label compile failed. Expected 0 errors, got $errors. Log: $CompileLogPath"
   }
   Write-Info "$Label compile passed (0 errors): $CompileLogPath"
}

function Stop-MT5Processes()
{
   $names = @("terminal64", "metatester64", "metatester", "metaeditor64", "metaeditor")
   $procs = Get-Process -Name $names -ErrorAction SilentlyContinue
   if($procs)
   {
      Write-Info "Stopping existing MT5 processes..."
      $procs | Stop-Process -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 2
   }
}

function Remove-FileIfExists([string]$PathToRemove)
{
   if(Test-Path $PathToRemove)
   {
      Remove-Item -Path $PathToRemove -Force -ErrorAction SilentlyContinue
   }
}

function Wait-ForResults([datetime]$RunStart,
                         [string]$PrimaryResultPath,
                         [System.Diagnostics.Process]$Process,
                         [int]$TimeoutSeconds)
{
   $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
   $waited = 0

   while((Get-Date) -lt $deadline)
   {
      Start-Sleep -Seconds 1
      $waited++

      $candidates = @()
      if(Test-Path $PrimaryResultPath)
      {
         $primaryItem = Get-Item $PrimaryResultPath
         if($primaryItem.LastWriteTime -ge $RunStart.AddSeconds(-2))
         {
            $candidates += $primaryItem
         }
      }

      $candidates += Get-TesterResultFiles -NotBefore $RunStart
      $latest = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
      if($latest)
      {
         return $latest.FullName
      }

      if($Process.HasExited -and $waited -gt 3)
      {
         # Process exited; allow short grace period for file flush.
         Start-Sleep -Seconds 2
      }

      if($waited % 10 -eq 0)
      {
         Write-Info "Waiting for test results... ($waited/$TimeoutSeconds)"
      }
   }

   return $null
}

function New-TesterConfig([string]$ConfigPath)
{
   $content = @"
[Tester]
Expert=Tests\RPEA\run_automated_tests_ea
ExpertParameters=Tests\RPEA\run_automated_tests.set
Symbol=EURUSD
Period=M1
Model=0
ExecutionMode=0
Optimization=0
FromDate=2024.01.02
ToDate=2024.01.05
Deposit=10000
Currency=USD
Leverage=100
UseLocal=1
UseRemote=0
UseCloud=0
Visual=0
ShutdownTerminal=1
ReplaceReport=1
"@
   Set-Content -Path $ConfigPath -Value $content -Encoding ASCII
}

try
{
   $repoRootResolved = (Resolve-Path $RepoRoot).Path
   $terminalDataResolved = Resolve-TerminalDataPath -Preferred $TerminalDataPath

   $terminalExe = Resolve-ToolPath -ToolName "terminal64.exe" -Candidates @(
      (Join-Path $MT5InstallPath "terminal64.exe"),
      (Join-Path $terminalDataResolved "terminal64.exe")
   )
   $metaEditorExe = Resolve-ToolPath -ToolName "metaeditor64.exe" -Candidates @(
      (Join-Path $MT5InstallPath "metaeditor64.exe"),
      (Join-Path $terminalDataResolved "metaeditor64.exe")
   )

   if(-not $SkipSync)
   {
      $syncScript = Join-Path $repoRootResolved "SyncRepoToTerminal.ps1"
      if(Test-Path $syncScript)
      {
         Write-Info "Syncing repo to MT5 data folder..."
         & powershell -ExecutionPolicy Bypass -File $syncScript
         if($LASTEXITCODE -ne 0)
         {
            throw "SyncRepoToTerminal.ps1 failed with exit code $LASTEXITCODE"
         }
      }
      else
      {
         Write-Info "Sync script not found, continuing without sync: $syncScript"
      }
   }

   $primaryResults = Join-Path $terminalDataResolved "MQL5\Files\RPEA\test_results\test_results.json"
   $testResultsDir = Split-Path -Parent $primaryResults
   if(-not (Test-Path $testResultsDir))
   {
      New-Item -ItemType Directory -Path $testResultsDir -Force | Out-Null
   }

   $compileLogRel = "MQL5\Experts\Tests\RPEA\compile_automated_tests.log"
   $compileLogAbs = Join-Path $terminalDataResolved $compileLogRel

   if(-not $SkipCompile)
   {
      Write-Info "Compiling automated test runner..."
      $compileArgs = @(
         "/compile:MQL5\Experts\Tests\RPEA\run_automated_tests_ea.mq5",
         "/log:$compileLogRel"
      )
      $compileProc = Start-Process -FilePath $metaEditorExe -ArgumentList $compileArgs -WorkingDirectory $terminalDataResolved -PassThru -Wait
      if(-not (Test-Path $compileLogAbs))
      {
         throw "Compile log missing after MetaEditor run: $compileLogAbs"
      }
      if($compileProc.ExitCode -ne 0)
      {
         Write-Info "MetaEditor returned non-zero exit code ($($compileProc.ExitCode)); checking compile log for final result."
      }
      Assert-CompileZeroErrors -CompileLogPath $compileLogAbs -Label "Test runner"
   }

   Write-Info "Cleaning previous results..."
   Remove-FileIfExists -PathToRemove $primaryResults
   foreach($item in (Get-TesterResultFiles -NotBefore ([datetime]::MinValue)))
   {
      Remove-FileIfExists -PathToRemove $item.FullName
   }

   Stop-MT5Processes

   $tmpDir = Join-Path $repoRootResolved ".tmp"
   if(-not (Test-Path $tmpDir))
   {
      New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
   }
   $configPath = Join-Path $tmpDir "run_tests_auto.ini"
   New-TesterConfig -ConfigPath $configPath

   $runStart = Get-Date
   Write-Info "Starting MT5 Strategy Tester via explicit /config..."
   $proc = Start-Process -FilePath $terminalExe -ArgumentList "/config:$configPath" -PassThru

   $resultPathUsed = Wait-ForResults -RunStart $runStart -PrimaryResultPath $primaryResults -Process $proc -TimeoutSeconds $TimeoutSec

   if(-not $proc.HasExited)
   {
      Write-Info "Stopping MT5 process..."
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
   }

   if(-not $resultPathUsed)
   {
      throw "Results file not generated after $TimeoutSec seconds."
   }

   Write-Info "Results found: $resultPathUsed"
   $results = Get-Content -Path $resultPathUsed -Raw | ConvertFrom-Json

   $repoResultCopy = Join-Path $repoRootResolved "MQL5\Files\RPEA\test_results\test_results.json"
   $repoResultDir = Split-Path -Parent $repoResultCopy
   if(-not (Test-Path $repoResultDir))
   {
      New-Item -ItemType Directory -Path $repoResultDir -Force | Out-Null
   }
   Copy-Item -Path $resultPathUsed -Destination $repoResultCopy -Force
   Write-Info "Copied results to repo path: $repoResultCopy"

   Write-Host ""
   Write-Host "=== TEST RESULTS ==="
   Write-Host "Total Suites: $($results.total_suites)"
   Write-Host "Total Tests:  $($results.total_tests)"
   Write-Host "Passed:       $($results.total_passed)"
   Write-Host "Failed:       $($results.total_failed)"
   Write-Host "Success:      $($results.success)"
   Write-Host ""

   foreach($suite in $results.suites)
   {
      $status = if($suite.failed -eq 0) { "PASS" } else { "FAIL" }
      Write-Host "[$status] $($suite.name) - $($suite.passed)/$($suite.total_tests)"
   }

   if($RequiredSuite -ne "")
   {
      $targetSuite = $results.suites | Where-Object { $_.name -eq $RequiredSuite } | Select-Object -First 1
      if(-not $targetSuite)
      {
         throw "Required suite '$RequiredSuite' not found in results."
      }
      if($targetSuite.failed -ne 0)
      {
         throw "Required suite '$RequiredSuite' failed."
      }
      Write-Info "Required suite passed: $RequiredSuite"
   }

   if(-not $results.success -or [int]$results.total_failed -ne 0)
   {
      throw "Automated tests failed (success=$($results.success), failed=$($results.total_failed))."
   }

   exit 0
}
catch
{
   Write-Host "[run_tests] ERROR: $($_.Exception.Message)"
   exit 1
}
