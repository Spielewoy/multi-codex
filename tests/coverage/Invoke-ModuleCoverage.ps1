<#
.SYNOPSIS
  Runs the in-process Pester coverage gate for the lib/*.psm1 modules.

.DESCRIPTION
  Pester 3.4's -CodeCoverage only counts commands executed in its own
  runspace, so the suite is built around tests/ModuleFunctions.Tests.ps1,
  which imports the three modules and drives their functions in-process.
  tests/OverlayState.Tests.ps1 runs alongside as the end-to-end check that
  the launcher still wires the same modules correctly from child processes
  (its child-process execution contributes no coverage by itself).

  Prints per-module and total command coverage, writes JSON and Cobertura
  reports under the system temporary directory by default, and enforces executable-line coverage for
  production lines added since -Baseline. It exits 1 when tests are unexecuted
  or fail, any module or changed-line result is below -MinimumPercent, or any
  command outside the documented host exceptions is missed.

  Documented exceptions: commands listed in $script:DocumentedExceptions are
  provably uncoverable on this host (no file-symlink privilege) and have a
  privilege-gated test that exercises them on capable hosts. They are exempt
  from the miss check and recorded in the JSON summary's documentedExceptions
  field. The gate fails when ANY other command is missed, and also when a listed
  exception no longer exists in the analyzed commands (stale exception - remove it).

  USAGE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests/coverage/Invoke-ModuleCoverage.ps1 [-MinimumPercent 95]
#>

param(
    [double]$MinimumPercent = 95,
    [string]$OutputPath,
    [string]$Baseline = $env:COVERAGE_BASELINE
)

$ErrorActionPreference = 'Stop'
$coverageRoot = $PSScriptRoot
$testsRoot = Split-Path -Parent $coverageRoot
$repoRoot = Split-Path -Parent $testsRoot
if (-not $OutputPath) {
    $OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) 'multi-cli-coverage\powershell-coverage.json'
}
if (-not $Baseline) {
    & git -C $repoRoot rev-parse --verify --quiet 'HEAD^^{commit}' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $Baseline = 'HEAD^'
    }
    else {
        & git -C $repoRoot rev-parse --verify --quiet 'origin/main^{commit}' 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Cannot resolve a coverage baseline. Set COVERAGE_BASELINE explicitly.'
        }
        $Baseline = 'origin/main'
    }
}

# Same Pester pinning as tests/run-pester.ps1: the suite is 3.x syntax only.
Get-Module Pester | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion 3.4.0 -MaximumVersion 3.99.99 -Force -ErrorAction Stop
$pesterVersion = (Get-Module Pester).Version
if (-not $pesterVersion -or $pesterVersion.Major -ne 3) {
    throw "Pester 3.x is required but none was loaded (got '$pesterVersion')."
}
Write-Host "Using Pester $pesterVersion"

$testFiles = @(
    (Join-Path $testsRoot 'ModuleFunctions.Tests.ps1'),
    (Join-Path $testsRoot 'Migration.Tests.ps1'),
    (Join-Path $testsRoot 'TransferSafety.Tests.ps1'),
    (Join-Path $testsRoot 'OsUser.Tests.ps1'),
    (Join-Path $testsRoot 'OverlayState.Tests.ps1')
)

# Commands that cannot execute on this host, matched against Pester's missed
# commands by module file name and normalized command text (not line numbers,
# so module edits do not stale them by position alone).
$script:DocumentedExceptions = @(
    [ordered]@{
        file = 'MultiCli.OsUser.psm1'
        command = 'throw "OS-user isolation for $Tool/$ProfileName requires an elevated terminal (Run as Administrator)."'
        reason = 'GitHub windows-latest is elevated, so the non-admin refusal cannot execute there. The end-to-end assertion in tests/OsUser.Tests.ps1 executes on non-elevated Windows hosts; elevated CI covers Test-OsUserElevated and all provisioning paths.'
    },
    [ordered]@{
        file = 'MultiCli.OsUser.psm1'
        command = '$ErrorActionPreference = ''Continue'''
        reason = 'These native command helpers are exercised by the non-admin elevation test only when the runner is not elevated. Elevated CI covers every caller through deterministic shims; standard Windows hosts cover the real net.exe probe.'
    },
    [ordered]@{
        file = 'MultiCli.OsUser.psm1'
        command = 'return (& $FilePath @NativeArgs 2>&1 | Out-String).Trim()'
        reason = 'These native command helpers are exercised by the non-admin elevation test only when the runner is not elevated. Elevated CI covers every caller through deterministic shims; standard Windows hosts cover the real net.exe probe.'
    },
    [ordered]@{
        file = 'MultiCli.OsUser.psm1'
        command = '& $FilePath @NativeArgs 2>&1'
        reason = 'These native command helpers are exercised by the non-admin elevation test only when the runner is not elevated. Elevated CI covers every caller through deterministic shims; standard Windows hosts cover the real net.exe probe.'
    },
    [ordered]@{
        file = 'MultiCli.OsUser.psm1'
        command = 'Out-String'
        reason = 'These native command helpers are exercised by the non-admin elevation test only when the runner is not elevated. Elevated CI covers every caller through deterministic shims; standard Windows hosts cover the real net.exe probe.'
    },
    [ordered]@{
        file = 'MultiCli.OsUser.psm1'
        command = '$null = Invoke-OsUserNative -FilePath net.exe -NativeArgs @(''user'', $Username)'
        reason = 'These native command helpers are exercised by the non-admin elevation test only when the runner is not elevated. Elevated CI covers every caller through deterministic shims; standard Windows hosts cover the real net.exe probe.'
    },
    [ordered]@{
        file = 'MultiCli.OsUser.psm1'
        command = '''user'', $Username'
        reason = 'These native command helpers are exercised by the non-admin elevation test only when the runner is not elevated. Elevated CI covers every caller through deterministic shims; standard Windows hosts cover the real net.exe probe.'
    },
    [ordered]@{
        file = 'MultiCli.OsUser.psm1'
        command = 'return ($LASTEXITCODE -eq 0)'
        reason = 'These native command helpers are exercised by the non-admin elevation test only when the runner is not elevated. Elevated CI covers every caller through deterministic shims; standard Windows hosts cover the real net.exe probe.'
    },
    [ordered]@{
        file = 'MultiCli.OsUser.psm1'
        command = '$LASTEXITCODE -eq 0'
        reason = 'These native command helpers are exercised by the non-admin elevation test only when the runner is not elevated. Elevated CI covers every caller through deterministic shims; standard Windows hosts cover the real net.exe probe.'
    },
    [ordered]@{
        file = 'MultiCli.Runtime.psm1'
        command = '[System.IO.File]::Delete($reparsePoint.FullName)'
        reason = 'Deleting a file reparse point can execute only when the host permits creation of file symlinks. The covering test exercises this command on Developer Mode, elevated, and other symlink-capable Windows hosts.'
    },
    [ordered]@{
        file = 'MultiCli.Runtime.psm1'
        command = '$hasLock = $true'
        reason = 'This assignment runs only when Mutex.WaitOne throws AbandonedMutexException. Windows releases a mutex owned by an exited test process without reporting abandonment on this host. The covering test ''New-RuntimeOverlay survives a real abandoned mutex'' proves the real cross-process recovery path and exercises the assignment on runtimes that surface the exception.'
    }
)

function Get-NormalizedCommandText {
    param([string]$Text)
    return ($Text -replace '\s+', ' ').Trim()
}

function Write-PesterCobertura {
    param($Coverage, [string]$Path, [string]$RepositoryRoot)
    $hitLines = @{}
    foreach ($command in @($Coverage.HitCommands)) {
        $hitLines["$($command.File)|$($command.Line)"] = $true
    }
    $commandsByFile = @($Coverage.HitCommands) + @($Coverage.MissedCommands) | Group-Object File
    $settings = New-Object Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.Encoding = New-Object Text.UTF8Encoding($false)
    $writer = [Xml.XmlWriter]::Create($Path, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement('coverage')
        $writer.WriteStartElement('packages')
        $writer.WriteStartElement('package')
        $writer.WriteStartElement('classes')
        foreach ($fileGroup in $commandsByFile) {
            $relativePath = $fileGroup.Name.Substring($RepositoryRoot.Length).TrimStart('\', '/') -replace '\\', '/'
            $writer.WriteStartElement('class')
            $writer.WriteAttributeString('filename', $relativePath)
            $writer.WriteStartElement('lines')
            foreach ($lineGroup in @($fileGroup.Group | Group-Object Line | Sort-Object { [int]$_.Name })) {
                $writer.WriteStartElement('line')
                $writer.WriteAttributeString('number', $lineGroup.Name)
                $hits = if ($hitLines.ContainsKey("$($fileGroup.Name)|$($lineGroup.Name)")) { '1' } else { '0' }
                $writer.WriteAttributeString('hits', $hits)
                $writer.WriteEndElement()
            }
            $writer.WriteEndElement()
            $writer.WriteEndElement()
        }
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    } finally {
        $writer.Dispose()
    }
}

foreach ($testFile in $testFiles) {
    if (-not (Test-Path -LiteralPath $testFile)) { throw "Missing test file: $testFile" }
}
$moduleFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'lib') -Filter '*.psm1' | ForEach-Object { $_.FullName })
if ($moduleFiles.Count -eq 0) { throw "No lib/*.psm1 modules found under $repoRoot." }

$result = Invoke-Pester -Script $testFiles -CodeCoverage $moduleFiles -PassThru -Quiet

Write-Host ""
$unexecutedCount = $result.SkippedCount + $result.PendingCount + $result.InconclusiveCount
Write-Host "Tests: $($result.PassedCount) passed, $($result.FailedCount) failed, $unexecutedCount unexecuted, $($result.TotalCount) total"
if ($result.FailedCount -gt 0) {
    foreach ($failed in @($result.TestResult | Where-Object { $_.Result -eq 'Failed' })) {
        Write-Host "  FAILED: $($failed.Name)"
        Write-Host "    $($failed.FailureMessage)"
    }
}

$coverage = $result.CodeCoverage
if (-not $coverage -or $coverage.NumberOfCommandsAnalyzed -eq 0) {
    throw 'Pester returned no code-coverage data; the modules were not analyzed.'
}

$perModule = @{}
foreach ($command in @($coverage.HitCommands) + @($coverage.MissedCommands)) {
    $name = Split-Path -Leaf $command.File
    if (-not $perModule.ContainsKey($name)) {
        $perModule[$name] = [pscustomobject]@{ Name = $name; Analyzed = 0; Executed = 0 }
    }
    $perModule[$name].Analyzed++
}
foreach ($command in @($coverage.HitCommands)) {
    $perModule[(Split-Path -Leaf $command.File)].Executed++
}

$moduleSummaries = @()
$underCoveredModules = @()
Write-Host ""
Write-Host 'Module coverage:'
foreach ($moduleFile in $moduleFiles) {
    $name = Split-Path -Leaf $moduleFile
    if (-not $perModule.ContainsKey($name)) { throw "Coverage data missing for $name." }
    $entry = $perModule[$name]
    $percent = [math]::Round(100.0 * $entry.Executed / $entry.Analyzed, 2)
    $moduleSummaries += [ordered]@{
        name = $name
        analyzed = $entry.Analyzed
        executed = $entry.Executed
        missed = ($entry.Analyzed - $entry.Executed)
        percent = $percent
    }
    if ($percent -lt $MinimumPercent) { $underCoveredModules += $name }
    Write-Host ("  {0,-36} {1,6}%  ({2}/{3})" -f $name, $percent, $entry.Executed, $entry.Analyzed)
}

$totalAnalyzed = $coverage.NumberOfCommandsAnalyzed
$totalExecuted = $coverage.NumberOfCommandsExecuted
$totalMissed = $coverage.NumberOfCommandsMissed
$totalPercent = [math]::Round(100.0 * $totalExecuted / $totalAnalyzed, 2)
Write-Host ("  {0,-36} {1,6}%  ({2}/{3})" -f 'TOTAL', $totalPercent, $totalExecuted, $totalAnalyzed)

if ($totalMissed -gt 0) {
    Write-Host ""
    Write-Host "Missed commands ($totalMissed):"
    $shown = 0
    foreach ($missed in @($coverage.MissedCommands)) {
        if ($shown -ge 30) { Write-Host "  ... and $($totalMissed - $shown) more"; break }
        Write-Host ("  {0}:{1} [{2}] {3}" -f (Split-Path -Leaf $missed.File), $missed.Line, $missed.Function, $missed.Command)
        $shown++
    }
}

# Partition missed commands into documented exceptions and unexpected misses.
$missedCommands = @($coverage.MissedCommands)
$analyzedCommands = @($coverage.HitCommands) + $missedCommands
$exemptedCommands = @()
$exceptionReports = @()
foreach ($exception in $script:DocumentedExceptions) {
    $matches = @($missedCommands | Where-Object {
        (Split-Path -Leaf $_.File) -eq $exception.file -and
        (Get-NormalizedCommandText $_.Command) -eq (Get-NormalizedCommandText $exception.command)
    })
    $knownMatches = @($analyzedCommands | Where-Object {
        (Split-Path -Leaf $_.File) -eq $exception.file -and
        (Get-NormalizedCommandText $_.Command) -eq (Get-NormalizedCommandText $exception.command)
    })
    $exceptionReports += [ordered]@{
        file = $exception.file
        command = $exception.command
        reason = $exception.reason
        active = ($matches.Count -gt 0)
        exists = ($knownMatches.Count -gt 0)
    }
    if ($matches.Count -gt 0) { $exemptedCommands += $matches[0] }
}
$unexpectedMisses = @($missedCommands | Where-Object { $exemptedCommands -notcontains $_ })
$staleExceptions = @($exceptionReports | Where-Object { -not $_.exists })

Write-Host ""
Write-Host "Documented exceptions: $($exceptionReports.Count) listed, $(@($exceptionReports | Where-Object { $_.active }).Count) active, $($staleExceptions.Count) stale"
foreach ($report in $exceptionReports) {
    $state = if ($report.active) {
        'active (missed on this host)'
    } elseif ($report.exists) {
        'covered on this host'
    } else {
        'STALE (command no longer analyzed; remove it)'
    }
    Write-Host "  $($report.file): $($report.command) - $state"
}
Write-Host "Unexpected missed commands: $($unexpectedMisses.Count)"
foreach ($missed in $unexpectedMisses) {
    Write-Host ("  {0}:{1} [{2}] {3}" -f (Split-Path -Leaf $missed.File), $missed.Line, $missed.Function, $missed.Command)
}

$summary = [ordered]@{
    generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    pesterVersion = $pesterVersion.ToString()
    minimumPercent = $MinimumPercent
    total = [ordered]@{
        analyzed = $totalAnalyzed
        executed = $totalExecuted
        missed = $totalMissed
        percent = $totalPercent
    }
    modules = $moduleSummaries
    underCoveredModules = @($underCoveredModules)
    documentedExceptions = @($exceptionReports)
    unexpectedMissed = $unexpectedMisses.Count
    tests = [ordered]@{
        total = [int]$result.TotalCount
        passed = [int]$result.PassedCount
        failed = [int]$result.FailedCount
        unexecuted = [int]$unexecutedCount
    }
    passed = ($result.FailedCount -eq 0 -and $unexecutedCount -eq 0 -and $underCoveredModules.Count -eq 0 -and $totalPercent -ge $MinimumPercent -and $unexpectedMisses.Count -eq 0 -and $staleExceptions.Count -eq 0)
}
$summaryDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $summaryDirectory)) {
    New-Item -ItemType Directory -Force -Path $summaryDirectory | Out-Null
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host ""
Write-Host "Coverage summary written to $OutputPath"

$outputDirectory = Split-Path -Parent $OutputPath
$coberturaPath = Join-Path $outputDirectory 'powershell-cobertura.xml'
Write-PesterCobertura -Coverage $coverage -Path $coberturaPath -RepositoryRoot $repoRoot
$changedReportPath = Join-Path $outputDirectory 'powershell-changed-lines.json'
$changedArguments = @(
    (Join-Path $coverageRoot 'check_changed_coverage.py'),
    '--repo', $repoRoot,
    '--baseline', $Baseline,
    '--coverage-root', $coberturaPath,
    '--minimum', $MinimumPercent,
    '--output', $changedReportPath,
    '--pathspec', 'lib/*.psm1'
)
& python @changedArguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($result.FailedCount -gt 0) { exit 1 }
if ($unexecutedCount -gt 0) {
    Write-Host "Coverage gate FAILED: $unexecutedCount test(s) skipped, pending, or inconclusive."
    exit 1
}
if ($underCoveredModules.Count -gt 0) {
    Write-Host "Coverage gate FAILED: module(s) below $MinimumPercent%: $($underCoveredModules -join ', ')."
    exit 1
}
if ($unexpectedMisses.Count -gt 0) {
    Write-Host "Coverage gate FAILED: $($unexpectedMisses.Count) missed command(s) outside the documented exceptions."
    exit 1
}
if ($staleExceptions.Count -gt 0) {
    Write-Host "Coverage gate FAILED: $($staleExceptions.Count) documented exception(s) no longer match an analyzed command; remove them from `$script:DocumentedExceptions."
    exit 1
}
if ($totalPercent -lt $MinimumPercent) {
    Write-Host "Coverage gate FAILED: $totalPercent% is below $MinimumPercent%."
    exit 1
}
Write-Host "Coverage gate passed: $totalPercent% >= $MinimumPercent%."
exit 0
