[CmdletBinding()]
param(
    [switch]$Check,
    [string]$OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) 'multi-cli-release'),
    [string]$ExpectedVersion
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'release\VERSION') -Raw).Trim()

if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw 'release/VERSION must contain X.Y.Z.'
}
if ($ExpectedVersion -and $version -ne $ExpectedVersion) {
    throw "Expected version $ExpectedVersion, found $version."
}

$bashSource = Get-Content -LiteralPath (Join-Path $root 'multi-cli') -Raw
$powershellSource = Get-Content -LiteralPath (Join-Path $root 'multi-cli.ps1') -Raw
if ($bashSource -notmatch "(?m)^VERSION=`"$([regex]::Escape($version))`"$") {
    throw "multi-cli does not embed version $version."
}
if ($powershellSource -notmatch "(?m)^\`$VERSION = '$([regex]::Escape($version))'$") {
    throw "multi-cli.ps1 does not embed version $version."
}

Write-Host "Version metadata is synchronized at $version."
if ($Check) { return }

$output = [System.IO.Path]::GetFullPath($OutputDirectory)
$archiveRoot = "multi-cli-v$version"
$stage = Join-Path $output $archiveRoot
$archive = Join-Path $output "$archiveRoot-windows.zip"
$prefix = $output.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$pathRoot = [System.IO.Path]::GetPathRoot($output)
$userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)

if (
    $output.TrimEnd('\', '/') -eq $pathRoot.TrimEnd('\', '/') -or
    $output.TrimEnd('\', '/') -eq $userHome.TrimEnd('\', '/') -or
    $stage -eq $output -or
    -not $stage.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
) {
    throw "Refusing unsafe staging path: $stage"
}

New-Item -ItemType Directory -Force -Path $output | Out-Null
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$paths = @(
    'LICENSE', 'README.md', 'docs', 'lib', 'schema',
    'agy-cli', 'antigravity', 'claude-cli', 'codex', 'codex-gui', 'commandcode',
    'copilot-cli', 'copilot-vscode', 'cursor', 'cursor-cli', 'gemini-cli', 'grok-cli',
    'kimi-cli', 'kiro', 'opencode', 'windsurf', 'zed',
    'multi-cli.ps1', 'scripts\install.ps1', 'scripts\uninstall.ps1'
)

foreach ($relative in $paths) {
    $source = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing release path: $relative"
    }
    $destination = Join-Path $stage $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
}

Compress-Archive -LiteralPath $stage -DestinationPath $archive -CompressionLevel Optimal
Remove-Item -LiteralPath $stage -Recurse -Force

Write-Host "Created $archive"
