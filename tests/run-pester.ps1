<#
.SYNOPSIS
  Runs the multi-cli session-continuation Pester suite (Pester 3.4 compatible).

.DESCRIPTION
  One documented command:
      powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-pester.ps1

  Discovers the Pester *.Tests.ps1 files in this directory and runs them. Exits
  non-zero if any test fails, so it doubles as a CI gate. Works with the built-in
  Windows PowerShell 5.1 Pester 3.4 and (if present) Pester 5+.
#>

param([switch]$CI)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition

Import-Module Pester -ErrorAction Stop
$pesterVersion = (Get-Module Pester).Version
Write-Host "Using Pester $pesterVersion"

$testFiles = Get-ChildItem -Path $here -Filter '*.Tests.ps1' | ForEach-Object { $_.FullName }

if ($pesterVersion.Major -ge 5) {
    $config = New-PesterConfiguration
    $config.Run.Path = $testFiles
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $result = Invoke-Pester -Configuration $config
    $failed = $result.FailedCount
} else {
    # Pester 3.4 path.
    $result = Invoke-Pester -Path $testFiles -PassThru
    $failed = $result.FailedCount
}

if ($failed -gt 0) { exit 1 }

# Sweep temp def files this run dot-sourced (one per child PowerShell that imported
# the launcher). Best-effort; never fail the run on cleanup.
Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter 'mcli_defs_*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

exit 0
