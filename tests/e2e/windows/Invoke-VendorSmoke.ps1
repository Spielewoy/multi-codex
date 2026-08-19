param(
    [Parameter(Mandatory = $true)]
    [string]$Tool,

    [string]$EvidenceDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) 'multi-cli-evidence')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))
$adapterPath = Join-Path (Join-Path (Join-Path $repoRoot 'ai-tools') $Tool) 'adapter.json'
if (-not (Test-Path -LiteralPath $adapterPath)) { throw "Unknown adapter '$Tool'." }
$adapter = Get-Content -LiteralPath $adapterPath -Raw | ConvertFrom-Json
$support = $adapter.support.windows
if ($support.level -ne 'supported') {
    throw "Adapter '$Tool' does not claim Windows support: $($support.reason)"
}
if (@($adapter.versionCommand).Count -eq 0 -or -not @($adapter.versionCommand)[0]) {
    throw "Adapter '$Tool' has no non-interactive versionCommand for offline verification."
}

$candidates = @($adapter.binary.windows)
$binary = $null
foreach ($candidate in $candidates) {
    $expanded = [Environment]::ExpandEnvironmentVariables(($candidate -replace '\$HOME', $env:USERPROFILE))
    if (Test-Path -LiteralPath $expanded -PathType Leaf) { $binary = (Get-Item -LiteralPath $expanded).FullName; break }
    $command = Get-Command $expanded -ErrorAction SilentlyContinue
    if ($command) {
        $resolvedCommand = if ($command.Source) { $command.Source } else { $command.Definition }
        if ($resolvedCommand -and (Test-Path -LiteralPath $resolvedCommand -PathType Leaf)) {
            $binary = (Get-Item -LiteralPath $resolvedCommand).FullName
            break
        }
    }
}
if (-not $binary) {
    Write-Host "SKIP: $Tool is not installed on this Windows host."
    exit 3
}

$versionArguments = @($adapter.versionCommand)
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
if ([System.IO.Path]::GetExtension($binary) -eq '.ps1') {
    $startInfo.FileName = (Get-Command powershell.exe).Source
    $quotedArguments = ($versionArguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$binary`" $quotedArguments"
} elseif ([System.IO.Path]::GetExtension($binary) -eq '.cmd') {
    $startInfo.FileName = $env:ComSpec
    $quotedArguments = ($versionArguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $startInfo.Arguments = "/d /s /c `"`"$binary`" $quotedArguments`""
} else {
    $startInfo.FileName = $binary
    $startInfo.Arguments = ($versionArguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
}
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.CreateNoWindow = $true
$process = [System.Diagnostics.Process]::Start($startInfo)
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw "$Tool version command exited $($process.ExitCode)." }

$version = ($stdout + $stderr).Trim()
if (-not $version) { throw "$Tool version command returned no product identity." }
New-Item -ItemType Directory -Force -Path $EvidenceDirectory | Out-Null
$evidence = [ordered]@{
    schemaVersion = 1
    mode = 'real-binary-offline'
    tool = $Tool
    binarySha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
    adapterSha256 = (Get-FileHash -LiteralPath $adapterPath -Algorithm SHA256).Hash.ToLowerInvariant()
    version = ($version -replace '[\r\n]+', ' ')
    windowsVersion = [Environment]::OSVersion.Version.ToString()
    passed = $true
}
$json = $evidence | ConvertTo-Json -Depth 5
if ($json -match '(?i)(access_token|refresh_token|id_token|api[_-]?key|bearer\s+|sk-[A-Za-z0-9])') {
    throw 'Evidence secret scan failed.'
}
$outputPath = Join-Path $EvidenceDirectory "$Tool-offline.json"
$temporaryPath = "$outputPath.tmp"
[System.IO.File]::WriteAllText($temporaryPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
Write-Host "PASS: $Tool real binary $version"
