<#
.SYNOPSIS
  Runs the opt-in real Windows AppX isolation test for codex-gui.

.DESCRIPTION
  This test creates a local Windows user and launches the installed Codex GUI.
  It never stops an existing or test-created Codex process. When the test app
  remains open, the profile and owned user are left for explicit cleanup after
  the user closes that app.
#>

$ErrorActionPreference = 'Stop'

if ($env:MULTICLI_REAL_APPX_E2E -ne '1') {
    Write-Host 'Codex GUI AppX E2E not enabled. Set MULTICLI_REAL_APPX_E2E=1 to run it.'
    exit 0
}
if ($env:OS -ne 'Windows_NT') { throw 'The Codex GUI AppX E2E requires Windows.' }

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'The Codex GUI AppX E2E must run from an elevated PowerShell terminal.'
}
$sessionId = (Get-Process -Id $PID).SessionId
if ($sessionId -le 0) { throw 'The Codex GUI AppX E2E requires an interactive Windows session.' }

$package = Get-AppxPackage -Name OpenAI.Codex -PackageTypeFilter Main -ErrorAction Stop |
    Sort-Object Version -Descending |
    Select-Object -First 1
if (-not $package) { throw 'OpenAI.Codex is not installed for the test operator.' }
if ("$($package.SignatureKind)" -ne 'Store') { throw 'OpenAI.Codex is not signed by the Microsoft Store.' }
$manifest = Get-AppxPackageManifest -Package $package
if (@($manifest.Package.Applications.Application.Id) -notcontains 'App') {
    throw "OpenAI.Codex package '$($package.PackageFullName)' does not declare application id 'App'."
}

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$repoRoot = Split-Path $repoRoot -Parent
$launcher = Join-Path $repoRoot 'multi-cli.ps1'
$runId = [guid]::NewGuid().ToString('N')
$profileName = "e2e-$runId"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "multi-cli-codex-gui-e2e-$runId"
$previousMultiCliHome = $env:MULTICLI_HOME
$env:MULTICLI_HOME = $testRoot

function Invoke-TestLauncher {
    param([string[]]$Arguments)
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output.Trim() }
}

try {
    $beforeProcesses = @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like 'ChatGPT*' -or $_.ProcessName -like 'codex*' } |
        ForEach-Object {
            [pscustomobject]@{
                Id = $_.Id
                ProcessName = $_.ProcessName
                StartTimeUtc = $_.StartTime.ToUniversalTime().ToString('o')
            }
        })

    $created = Invoke-TestLauncher -Arguments @('new', "codex-gui/$profileName", '--no-seed')
    if ($created.ExitCode -ne 0) { throw "Profile creation failed:`n$($created.Output)" }

    $launched = Invoke-TestLauncher -Arguments @('launch', "codex-gui/$profileName")
    if ($launched.ExitCode -ne 0) { throw "Codex GUI launch failed:`n$($launched.Output)" }

    $profileDir = Join-Path $testRoot "codex-gui\$profileName"
    $record = Get-Content -LiteralPath (Join-Path $profileDir '.osuser.json') -Raw | ConvertFrom-Json
    $result = Get-Content -LiteralPath (Join-Path $profileDir '.osuser-appx-bootstrap.json') -Raw | ConvertFrom-Json
    if ($result.status -ne 'verified') { throw "Expected verified AppX evidence, got '$($result.status)'." }
    $expectedAumid = "$($package.PackageFamilyName)!App"
    if ($result.package -ne $package.Name -or
        $result.packageFamilyName -ne $package.PackageFamilyName -or
        $result.aumid -ne $expectedAumid) {
        throw "Verified AppX evidence does not match '$expectedAumid'."
    }
    if ([int64]$result.mainWindowHandle -eq 0) { throw 'Verified AppX evidence did not include a visible GUI window.' }

    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $($result.processId)" -ErrorAction Stop
    $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop
    $expectedSid = (New-Object Security.Principal.NTAccount($record.username)).Translate([Security.Principal.SecurityIdentifier]).Value
    if ($owner.ReturnValue -ne 0 -or $owner.Sid -ne $expectedSid) {
        throw "Process $($result.processId) owner SID '$($owner.Sid)' does not match '$expectedSid'."
    }
    if ([int]$process.SessionId -ne $sessionId) {
        throw "Process $($result.processId) used session $($process.SessionId), expected $sessionId."
    }

    foreach ($beforeProcess in $beforeProcesses) {
        $currentProcess = Get-Process -Id $beforeProcess.Id -ErrorAction SilentlyContinue
        if (-not $currentProcess -or
            $currentProcess.ProcessName -ne $beforeProcess.ProcessName -or
            $currentProcess.StartTime.ToUniversalTime().ToString('o') -ne $beforeProcess.StartTimeUtc) {
            throw "Existing Codex process $($beforeProcess.Id) exited or changed during the E2E run."
        }
    }

    $shortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\multi-cli codex-gui $profileName.lnk"
    if (-not (Test-Path -LiteralPath $shortcut -PathType Leaf)) {
        throw "The verified launcher did not create '$shortcut'."
    }
    $shortcutObject = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
    if ($shortcutObject.TargetPath -notmatch 'powershell\.exe$' -or
        $shortcutObject.Arguments -notmatch [regex]::Escape($launcher) -or
        $shortcutObject.Arguments -notmatch [regex]::Escape($testRoot) -or
        $shortcutObject.Arguments -notmatch [regex]::Escape("launch 'codex-gui/$profileName'")) {
        throw 'The verified shortcut does not route this profile through multi-cli with its profile root.'
    }

    $evidenceDir = Join-Path ([System.IO.Path]::GetTempPath()) 'multi-cli-codex-gui-e2e'
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
    $evidencePath = Join-Path $evidenceDir "$runId.json"
    [ordered]@{
        windowsBuild = [Environment]::OSVersion.Version.ToString()
        packageVersion = [string]$package.Version
        packageFamilyName = [string]$package.PackageFamilyName
        aumid = [string]$result.aumid
        processId = [int]$result.processId
        ownerSid = [string]$owner.Sid
        sessionId = [int]$process.SessionId
        profilePath = $profileDir
        verifiedUtc = [string]$result.verifiedUtc
    } | ConvertTo-Json | Set-Content -LiteralPath $evidencePath -Encoding UTF8

    Write-Host "Codex GUI AppX E2E passed. Evidence: $evidencePath"
    Write-Host "The test did not stop Codex. Close the test GUI yourself, then delete: codex-gui/$profileName"
} finally {
    $env:MULTICLI_HOME = $previousMultiCliHome
}
