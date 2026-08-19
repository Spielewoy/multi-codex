<#
.SYNOPSIS
  Install multi-cli on Windows.
.PARAMETER Local
  Install from the current directory instead of cloning.
#>
param(
    [switch]$Local
)

$ErrorActionPreference = 'Stop'

$RepoUrl    = if ($env:MULTICLI_REPO)        { $env:MULTICLI_REPO }        else { 'https://github.com/Spielewoy/multi-cli.git' }
$InstallDir = if ($env:MULTICLI_INSTALL_DIR)  { $env:MULTICLI_INSTALL_DIR }  else { Join-Path $env:LOCALAPPDATA 'multi-cli' }
$BinDir     = if ($env:MULTICLI_BIN_DIR)      { $env:MULTICLI_BIN_DIR }      else { Join-Path $env:LOCALAPPDATA 'multi-cli\bin' }
$JqVersion  = if ($env:MULTICLI_JQ_VERSION)   { $env:MULTICLI_JQ_VERSION }   else { '1.7.1' }

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Assert-NativeSuccess {
    param([string]$Action)
    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE."
    }
}

function Test-UserPathEntry {
    param([string]$Path, [string]$Entry)
    if (-not $Path) { return $false }
    return @($Path -split ';' | Where-Object { $_ }) -contains $Entry
}

# jq is a hard dependency: multi-cli is entirely jq-driven. Resolve it or fail.
function Install-Jq {
    param([string]$BinDir)

    if (Test-Command 'jq') {
        Write-Host "jq found: $((Get-Command jq).Source)"
        return
    }

    Write-Host "jq is required but not installed. Attempting to install it ..."

    if (Test-Command 'winget') {
        try {
            winget install --id jqlang.jq -e --source winget `
                --accept-package-agreements --accept-source-agreements
        } catch { Write-Host "winget install failed: $_" -ForegroundColor Yellow }
    } elseif (Test-Command 'choco') {
        try { choco install jq -y } catch { Write-Host "choco install failed: $_" -ForegroundColor Yellow }
    }

    # Refresh PATH so a freshly installed jq is discoverable in this session.
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('PATH', 'User')

    if (Test-Command 'jq') {
        Write-Host "Installed jq: $((Get-Command jq).Source)"
        return
    }

    # No package manager succeeded - fall back to the official static binary.
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { 'i386' }
    $asset = "jq-windows-$arch.exe"
    $url = "https://github.com/jqlang/jq/releases/download/jq-$JqVersion/$asset"
    $dest = Join-Path $BinDir 'jq.exe'
    try {
        New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
        Write-Host "Downloading jq $JqVersion from $url"
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        $env:PATH = "$BinDir;$env:PATH"
        if (Test-Command 'jq') {
            Write-Host "Installed jq to $BinDir"
            return
        }
    } catch { Write-Host "jq download failed: $_" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "Error: jq is required but could not be installed automatically." -ForegroundColor Red
    Write-Host "multi-cli is entirely jq-driven and will not run without it." -ForegroundColor Red
    Write-Host "Install jq manually, then re-run this installer:"
    Write-Host "  winget install jqlang.jq"
    Write-Host "  choco install jq"
    Write-Host "  Manual: https://jqlang.github.io/jq/download/"
    exit 1
}

Write-Host "multi-cli installer (Windows)"
Write-Host ""

if ($Local) {
    $InstallDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
    Write-Host "Installing from local directory: $InstallDir"
} else {
    if ($RepoUrl -match '<owner>|<repo>') {
        throw 'MULTICLI_REPO contains a placeholder. Set it to the multi-cli Git clone URL.'
    }
    if (-not (Test-Command 'git')) { throw 'git is required to install multi-cli from GitHub.' }
    Write-Host "Cloning from $RepoUrl ..."
    if (Test-Path (Join-Path $InstallDir '.git')) {
        Write-Host "Updating existing installation at $InstallDir"
        git -C $InstallDir pull --ff-only
        Assert-NativeSuccess -Action 'git pull'
    } else {
        if (Test-Path $InstallDir) {
            throw "$InstallDir exists but is not a Git checkout. Move it, choose MULTICLI_INSTALL_DIR, or use -Local from a multi-cli checkout."
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $InstallDir) | Out-Null
        git clone $RepoUrl $InstallDir
        Assert-NativeSuccess -Action 'git clone'
    }
}

$scriptPath = Join-Path $InstallDir 'multi-cli.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "$InstallDir does not contain the multi-cli PowerShell entrypoint."
}

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

Install-Jq -BinDir $BinDir

$wrapperPath = Join-Path $BinDir 'multi-cli.cmd'
@"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "$scriptPath" %*
"@ | Set-Content -Path $wrapperPath -Encoding ASCII

Write-Host ""
Write-Host "Installed multi-cli to $InstallDir"
Write-Host "Command wrapper at $wrapperPath"

$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if (-not (Test-UserPathEntry -Path $userPath -Entry $BinDir)) {
    Write-Host ""
    Write-Host "Adding $BinDir to user PATH ..."
    [Environment]::SetEnvironmentVariable('PATH', "$BinDir;$userPath", 'User')
    $env:PATH = "$BinDir;$env:PATH"
    Write-Host "Done. Restart your terminal for PATH changes to take effect."
} else {
    Write-Host "$BinDir is already in PATH."
}

$ProfilesBinDir = if ($env:MULTICLI_HOME) { Join-Path $env:MULTICLI_HOME 'bin' } else { Join-Path $env:USERPROFILE 'MultiCliProfiles\bin' }
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if (-not (Test-UserPathEntry -Path $userPath -Entry $ProfilesBinDir)) {
    Write-Host ""
    Write-Host "Adding $ProfilesBinDir to user PATH ..."
    [Environment]::SetEnvironmentVariable('PATH', "$ProfilesBinDir;$userPath", 'User')
    $env:PATH = "$ProfilesBinDir;$env:PATH"
    Write-Host "Done. Profile aliases will be available after terminal restart."
} else {
    Write-Host "$ProfilesBinDir is already in PATH."
}

Write-Host ""
Write-Host "Run 'multi-cli doctor' to verify your setup."
