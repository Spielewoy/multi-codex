<#
.SYNOPSIS
  Uninstall multi-cli from Windows.
#>

$ErrorActionPreference = 'Stop'

$script:UninstallRoot = Split-Path -Parent $PSScriptRoot
$script:InstallRoot = $null

function Assert-SafeRemovalPath {
    param([string]$Path, [string]$Purpose)
    $resolved = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $root = [IO.Path]::GetPathRoot($resolved).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $userHome = [IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (-not $resolved -or $resolved -eq $root -or $resolved -eq $userHome) {
        throw "Refusing to remove unsafe $Purpose path: $Path"
    }
}

function Assert-MultiCliInstall {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath (Join-Path $Path 'multi-cli.ps1') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $Path 'lib') -PathType Container)) {
        throw "Refusing to remove $Path because it is not a recognizable multi-cli installation."
    }
}

function Test-UserPathEntry {
    param([string]$Path, [string]$Entry)
    if (-not $Path) { return $false }
    return @($Path -split ';' | Where-Object { $_ }) -contains $Entry
}

function Resolve-UninstallModule {
    param([string]$Name)
    $candidates = @(
        (Join-Path $script:UninstallRoot "lib\$Name"),
        (Join-Path $script:InstallRoot "lib\$Name")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw "Cannot clean profile resources: module '$Name' is missing. Reinstall multi-cli, then retry uninstall."
}

function Read-UninstallAdapter {
    param([string]$Tool)
    $candidates = @(
        (Join-Path $script:UninstallRoot "$Tool\adapter.json"),
        (Join-Path $script:InstallRoot "$Tool\adapter.json")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json
        }
    }
    return $null
}

function Remove-UninstallProfileResources {
    param([string]$ProfilesRoot)
    $metadataFiles = Get-ChildItem -LiteralPath $ProfilesRoot -Filter '.profile.json' -File -Recurse -Force -ErrorAction SilentlyContinue
    $ownedShortcuts = @()
    foreach ($metadataFile in $metadataFiles) {
        $profileDir = Split-Path -Parent $metadataFile.FullName
        if (Test-Path -LiteralPath (Join-Path $profileDir '.osuser.json')) {
            Import-Module (Resolve-UninstallModule 'MultiCli.OsUser.psm1') -Force
            Remove-OsUserIsolation -ProfileDir $profileDir
        }
        $tool = Split-Path -Leaf (Split-Path -Parent $profileDir)
        $adapter = Read-UninstallAdapter -Tool $tool
        if ($null -eq $adapter) {
            throw "Cannot determine whether '$tool' owns stored credentials because its adapter is missing. Reinstall multi-cli, then retry uninstall."
        }
        $profileName = Split-Path -Leaf $profileDir
        $ownedShortcuts += Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\multi-cli $tool $profileName.lnk"
        if ($adapter.account.mechanism -ne 'processSecret') { continue }
        $metadata = Get-Content -LiteralPath $metadataFile.FullName -Raw | ConvertFrom-Json
        $environmentVariable = $adapter.account.secret.environmentVariable
        if (-not $metadata.profileId -or -not $environmentVariable) { continue }
        Import-Module (Resolve-UninstallModule 'MultiCli.CredentialStore.psm1') -Force
        [void](Remove-MultiCliCredential -Target "multi-cli/$($adapter.id)/$($metadata.profileId)/$environmentVariable")
    }
    foreach ($shortcutPath in $ownedShortcuts) {
        if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
            Remove-Item -LiteralPath $shortcutPath -Force
            Write-Host "Removed shortcut: $(Split-Path -Leaf $shortcutPath)"
        }
    }
}

$InstallDir = if ($env:MULTICLI_INSTALL_DIR) { $env:MULTICLI_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'multi-cli' }
$script:InstallRoot = $InstallDir
$BinDir     = if ($env:MULTICLI_BIN_DIR)     { $env:MULTICLI_BIN_DIR }     else { Join-Path $env:LOCALAPPDATA 'multi-cli\bin' }
$ProfileDir = if ($env:MULTICLI_HOME)        { $env:MULTICLI_HOME }        else { Join-Path $env:USERPROFILE 'MultiCliProfiles' }

Write-Host "multi-cli uninstaller (Windows)"
Write-Host ""

foreach ($cmd in @('multi-cli.cmd')) {
    $p = Join-Path $BinDir $cmd
    if (Test-Path $p) { Remove-Item -Force $p; Write-Host "Removed $p" }
}

$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if (Test-UserPathEntry -Path $userPath -Entry $BinDir) {
    $newPath = ($userPath -split ';' | Where-Object { $_ -ne $BinDir }) -join ';'
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
    Write-Host "Removed $BinDir from user PATH"
}

# install.ps1 also registers the profile alias dir on the user PATH.
$profilesBinDir = Join-Path $ProfileDir 'bin'
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if (Test-UserPathEntry -Path $userPath -Entry $profilesBinDir) {
    $newPath = ($userPath -split ';' | Where-Object { $_ -ne $profilesBinDir }) -join ';'
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
    Write-Host "Removed $profilesBinDir from user PATH"
}

$shouldRemoveInstall = $false
if ((Test-Path $InstallDir) -and ($InstallDir -ne (Split-Path -Parent $MyInvocation.MyCommand.Definition))) {
    if ([Console]::IsInputRedirected) {
        Write-Host "Remove install directory ${InstallDir}? [y/N]"
        $confirm = [Console]::In.ReadLine()
    } else {
        $confirm = Read-Host "Remove install directory ${InstallDir}? [y/N]"
    }
    if ($confirm -match '^[Yy]$') {
        Assert-SafeRemovalPath -Path $InstallDir -Purpose 'install'
        Assert-MultiCliInstall -Path $InstallDir
        $shouldRemoveInstall = $true
    }
}

if (Test-Path $ProfileDir) {
    if ([Console]::IsInputRedirected) {
        Write-Host "Remove all profiles at ${ProfileDir}? [y/N]"
        $confirm = [Console]::In.ReadLine()
    } else {
        $confirm = Read-Host "Remove all profiles at ${ProfileDir}? [y/N]"
    }
    if ($confirm -match '^[Yy]$') {
        Assert-SafeRemovalPath -Path $ProfileDir -Purpose 'profile'
        Remove-UninstallProfileResources -ProfilesRoot $ProfileDir
        Remove-Item -Recurse -Force $ProfileDir
        Write-Host "Removed $ProfileDir"
    } else {
        Write-Host "Profiles kept at $ProfileDir"
    }
}

if ($shouldRemoveInstall) {
    Remove-Item -Recurse -Force $InstallDir
    Write-Host "Removed $InstallDir"
}

Write-Host ""
Write-Host "multi-cli uninstalled."
