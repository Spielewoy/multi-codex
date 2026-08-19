<#
.SYNOPSIS
  Real-world end-to-end harness for multi-cli on Windows.

.DESCRIPTION
  Drives the REAL installed CLI binaries through the REAL multi-cli.ps1 with a
  fully sandboxed home: a dedicated USERPROFILE root under %TEMP% (never the
  operator's real home) and a sandboxed MULTICLI_HOME. No mocks, no fixture
  adapters, no fixture binaries.

  Per schema-v2 accountOverlay adapter, dispatched by the adapter's REAL
  account mechanism (read from adapter.json at runtime):

    fileOverlay  (claude-cli, codex, gemini-cli, commandcode)
      - seed the real shared normal-state root (under the test home) before
        profile creation
      - create profiles account-a/account-b via real `multi-cli new`
      - launch the real binary with the adapter's safe version command via
        real `multi-cli launch`; assert exit code and that the version output
        matches the direct binary's output
      - assert profile auth credential files are profile-local and EMPTY while
        seeded shared state content is visible through both profiles
      - assert .runtime holds junctions/hardlinks into the shared root
      - assert a session line written via profile A's runtime is visible via
        profile B's runtime and in the shared root
      - assert `doctor --deep` is clean after a launch (per-tool allowlist for
        known vendor transients), flags a planted rogue file, and is clean
        again after its removal

    processSecret (cursor-cli, copilot-cli, kimi-cli, grok-cli)
      - store per-profile dummy tokens (`dummy-token-account-a/-b`) through
        the same real credential-store module and target derivation as auth set
      - assert real `auth status` reports present
      - launch via a .cmd shim (MULTICLI_OVERRIDE_BINARY) that captures the
        secret env var to a file and then execs the REAL binary; assert the
        two profiles receive DIFFERENT token values and the version output
        matches the direct binary
      - real `auth clear`, then assert launch fails with the auth-set hint

  Safety: every child process gets USERPROFILE/HOME/APPDATA/LOCALAPPDATA/TEMP
  redirected under the sandbox, MULTICLI_HOME points into the sandbox, and the
  child PATH is pre-seeded with the sandbox alias dir so `multi-cli new` never
  touches the registry User PATH. A snapshot of the real-home tool roots and
  the registry User PATH is taken before/after and compared. All Credential
  Manager entries written (multi-cli/<tool>/<profileId>/<var> targets) are
  removed and verified gone. The sandbox is removed at the end.

  Never opens browsers or logins, never sends prompts that consume quota:
  only the adapters' versionCommand is ever passed to the real binaries.

  Exit code: 0 when every executed tool passed (skips allowed), 1 otherwise.

.PARAMETER Tool
  Tools to exercise. copilot-cli and grok-cli record an explicit SKIP when
  their binary is absent.

.PARAMETER EvidenceDir
  Directory for the sanitized evidence JSON (realworld-evidence.json).

.PARAMETER SandboxRoot
  Sandbox root (deleted before and after the run).

.PARAMETER KeepSandbox
  Keep the sandbox on disk after the run (debugging).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tests/e2e/windows/Invoke-RealWorldE2E.ps1
#>
[CmdletBinding()]
param(
    [string[]]$Tool = @('kimi-cli', 'claude-cli', 'codex', 'gemini-cli', 'commandcode', 'copilot-cli', 'grok-cli'),
    [string]$EvidenceDir = (Join-Path ([System.IO.Path]::GetTempPath()) 'multi-cli-realworld-evidence'),
    [string]$SandboxRoot = (Join-Path ([System.IO.Path]::GetTempPath()) 'mcli_realworld'),
    [switch]$KeepSandbox
)

$ErrorActionPreference = 'Stop'

# powershell.exe -File binds one command-line token per parameter, so accept
# both `-Tool a,b` (single token) and proper arrays from in-process callers.
$Tool = @($Tool | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$script:LauncherPath = Join-Path $script:RepoRoot 'multi-cli.ps1'
$script:PowerShellExe = (Get-Command powershell.exe).Source
$script:SandboxRoot = [System.IO.Path]::GetFullPath($SandboxRoot)
$script:SandboxHome = Join-Path $script:SandboxRoot 'home'
$script:SandboxProfiles = Join-Path $script:SandboxRoot 'profiles'
$script:SandboxTemp = Join-Path $script:SandboxRoot 'tmp'
$script:SandboxShims = Join-Path $script:SandboxRoot 'shims'
$script:SandboxCaptures = Join-Path $script:SandboxRoot 'captures'
$script:FailureCount = 0
$script:RunNotes = @()
$script:CredentialTargets = New-Object 'System.Collections.Generic.List[string]'
$script:SafetyAssertions = @()

# Roots under the REAL user profile that the harness must never mutate.
# .claude / .claude.json are intentionally excluded: this harness may run from
# inside a Claude Code session which legitimately writes its own state there.
$script:RealHomeMarkerRoots = @('.kimi-code', '.codex', '.gemini', '.commandcode', '.copilot', '.grok', 'MultiCliProfiles')

# Per-tool allowlist of known vendor-transient runtime files that `doctor
# --deep` flags although the adapter cannot declare them (guid/random names).
# Applied as a union because every tool's doctor run scans the whole shared
# MULTICLI_HOME, including earlier tools' profiles.
$script:DoctorTransientAllowlist = @{
    'gemini-cli' = @('^\.gemini/projects\.json\.[0-9a-fA-F-]+\.tmp$')
    'codex'      = @('^tmp/arg0/codex-arg0[^/]+/(\.lock|applypatch\.bat|apply_patch\.bat)$')
}

# =============================================================================
# Generic helpers
# =============================================================================

function Get-PropSafe {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Add-Note {
    param([string]$Text)
    $script:RunNotes += $Text
    Write-Host "  [note] $Text"
}

function Add-Assertion {
    param([System.Collections.IDictionary]$ToolEntry, [string]$Name, [bool]$Passed, [string]$Detail = '')
    $ToolEntry.assertions += [ordered]@{ name = $Name; passed = $Passed; detail = $Detail }
    if ($Passed) { Write-Host "  [ok]   $Name$(if ($Detail) { " -- $Detail" })" }
    else {
        $script:FailureCount++
        Write-Host "  [FAIL] $Name$(if ($Detail) { " -- $Detail" })" -ForegroundColor Red
    }
}

function Add-SafetyAssertion {
    param([string]$Name, [bool]$Passed, [string]$Detail = '')
    $script:SafetyAssertions += [ordered]@{ name = $Name; passed = $Passed; detail = $Detail }
    if ($Passed) { Write-Host "  [ok]   safety/$Name$(if ($Detail) { " -- $Detail" })" }
    else {
        $script:FailureCount++
        Write-Host "  [FAIL] safety/$Name$(if ($Detail) { " -- $Detail" })" -ForegroundColor Red
    }
}

# Runs a child process with full env control, stdin support, and a hard
# timeout that kills the child. Both streams are drained concurrently via
# ReadToEndAsync (deadlock-safe); after the process exits the reads get a
# grace window so output is not lost to a slow pipe flush.
function Invoke-ChildProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [hashtable]$EnvMap = @{},
        [string]$StdinText,
        [int]$TimeoutSeconds = 120
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $argLine = ($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $startInfo.Arguments = $argLine
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    if ($null -ne $StdinText) { $startInfo.RedirectStandardInput = $true }
    foreach ($key in $EnvMap.Keys) { $startInfo.EnvironmentVariables[$key] = [string]$EnvMap[$key] }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if ($null -ne $StdinText) {
        $process.StandardInput.WriteLine($StdinText)
        $process.StandardInput.Close()
    }
    $timedOut = $false
    $exited = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $exited) {
        $timedOut = $true
        try { $process.Kill() } catch { Write-Warning "Could not kill timed-out child ${FilePath}: $($_.Exception.Message)" }
        $process.WaitForExit()
    }
    $stdout = ''
    $stderr = ''
    if ($stdoutTask.Wait(10000)) { $stdout = $stdoutTask.Result }
    if ($stderrTask.Wait(10000)) { $stderr = $stderrTask.Result }
    return [pscustomobject]@{
        ExitCode = $(if ($timedOut) { -1 } else { $process.ExitCode })
        Stdout   = $stdout
        Stderr   = $stderr
        TimedOut = $timedOut
    }
}

# Sandbox environment for EVERY child process. USERPROFILE is always the test
# root; the alias dir is pre-seeded into PATH so `multi-cli new` never writes
# the registry User PATH.
function Get-SandboxEnv {
    $envMap = @{
        USERPROFILE   = $script:SandboxHome
        HOME          = $script:SandboxHome
        HOMEDRIVE     = $script:SandboxHome.Substring(0, 2)
        HOMEPATH      = $script:SandboxHome.Substring(2)
        APPDATA       = Join-Path $script:SandboxHome 'AppData\Roaming'
        LOCALAPPDATA  = Join-Path $script:SandboxHome 'AppData\Local'
        TEMP          = $script:SandboxTemp
        TMP           = $script:SandboxTemp
        MULTICLI_HOME = $script:SandboxProfiles
        PATH          = (Join-Path $script:SandboxProfiles 'bin') + ';' + $env:PATH
    }
    return $envMap
}

# Invokes the REAL multi-cli.ps1 in a child powershell.exe under the sandbox.
function Invoke-MultiCli {
    param(
        [string[]]$MultiCliArgs,
        [hashtable]$ExtraEnv = @{},
        [string]$StdinText,
        [int]$TimeoutSeconds = 120
    )
    $envMap = Get-SandboxEnv
    foreach ($key in $ExtraEnv.Keys) { $envMap[$key] = $ExtraEnv[$key] }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:LauncherPath) + $MultiCliArgs
    return Invoke-ChildProcess -FilePath $script:PowerShellExe -Arguments $arguments -EnvMap $envMap -StdinText $StdinText -TimeoutSeconds $TimeoutSeconds
}

function Get-ToolAdapter {
    param([string]$ToolId)
    $manifestPath = Join-Path (Join-Path (Join-Path $script:RepoRoot 'ai-tools') $ToolId) 'adapter.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Adapter manifest not found for '$ToolId'." }
    return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

# Resolves the tool's binary the way multi-cli does, but against the REAL
# environment (children run with a redirected APPDATA), preferring
# process-startable shims (.cmd/.exe) over npm's .ps1/extensionless stubs,
# and never accepting a Windows system binary (guards commandcode's 'cmd').
function Resolve-RealBinary {
    param($Adapter)
    $candidates = @((Get-PropSafe $Adapter.binary 'windows'))
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        $expanded = $candidate.Replace('$HOME', $env:USERPROFILE)
        $expanded = [Environment]::ExpandEnvironmentVariables($expanded)
        if (Test-Path -LiteralPath $expanded -PathType Leaf) {
            $resolved = (Get-Item -LiteralPath $expanded).FullName
        } else {
            $command = Get-Command $expanded -ErrorAction SilentlyContinue
            if (-not $command) { continue }
            $resolved = $command.Source
            foreach ($extension in @('.cmd', '.exe', '.bat')) {
                $sibling = [System.IO.Path]::ChangeExtension($resolved, $extension)
                if ([System.IO.Path]::GetExtension($resolved) -ne $extension -and (Test-Path -LiteralPath $sibling -PathType Leaf)) {
                    $resolved = $sibling
                    break
                }
            }
        }
        if ($resolved.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $extension = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
        if (@('.cmd', '.exe', '.bat') -notcontains $extension) { continue }
        return $resolved
    }
    return $null
}

# The tool's shared normal-state root, resolved against the SANDBOX home.
function Get-SandboxSharedRoot {
    param($Adapter)
    $root = (Get-PropSafe (Get-PropSafe (Get-PropSafe $Adapter 'normalState') 'root') 'windows')
    if (-not $root) { return $null }
    $expanded = $root.Replace('$HOME', $script:SandboxHome).Replace('%USERPROFILE%', $script:SandboxHome)
    return [System.IO.Path]::GetFullPath($expanded)
}

function Get-VersionArguments {
    param($Adapter)
    $versionCommand = @(Get-PropSafe $Adapter 'versionCommand')
    if ($versionCommand.Count -eq 0 -or -not $versionCommand[0]) { return @('--version') }
    return $versionCommand
}

# Runs the real binary directly (no multi-cli) and returns its version output.
# This is the control the launch output must match. The adapter's isolation
# env vars are pointed at a sandbox scratch dir: codex/gemini locate the home
# directory via the Windows Known Folder API (not env vars), so an unadorned
# direct run would write helper/state files into the operator's REAL home.
function Get-DirectBinaryVersion {
    param($Adapter, [string]$Binary, [string[]]$VersionArgs)
    $scratch = Join-Path $script:SandboxRoot "direct\$($Adapter.id)"
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $envMap = Get-SandboxEnv
    $isolationEnv = Get-PropSafe $Adapter.isolation 'env'
    if ($isolationEnv) {
        foreach ($property in $isolationEnv.PSObject.Properties) {
            $value = [string]$property.Value
            foreach ($token in @('{sharedStateRoot}', '{runtimeRoot}', '{profileDir}', '{authDir}')) {
                $value = $value.Replace($token, $scratch)
            }
            $value = $value.Replace('{profileId}', 'direct').Replace('{realHome}', $script:SandboxHome)
            $envMap[$property.Name] = $value
        }
    }
    $result = Invoke-ChildProcess -FilePath $Binary -Arguments $VersionArgs -EnvMap $envMap -TimeoutSeconds 90
    $combined = ($result.Stdout + $result.Stderr).Trim()
    $firstLine = ($combined -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    return [pscustomobject]@{ Full = $combined; FirstLine = $firstLine; ExitCode = $result.ExitCode }
}

function Get-ProfileMetadata {
    param([string]$ToolId, [string]$ProfileName)
    $metadataPath = Join-Path (Join-Path (Join-Path $script:SandboxProfiles $ToolId) $ProfileName) '.profile.json'
    return Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
}

function Get-CredentialTarget {
    param($Adapter, [string]$ProfileName)
    $metadata = Get-ProfileMetadata -ToolId $Adapter.id -ProfileName $ProfileName
    $environmentVariable = (Get-PropSafe (Get-PropSafe $Adapter.account 'secret') 'environmentVariable')
    return "multi-cli/$($Adapter.id)/$($metadata.profileId)/$environmentVariable"
}

function Remove-TrackedCredential {
    param([string]$Target)
    try { [void](Remove-MultiCliCredential -Target $Target) }
    catch { Write-Warning "Credential cleanup failed for a multi-cli target: $($_.Exception.Message)" }
}

# Deletes a directory tree that may contain junctions/hardlinks without ever
# traversing a reparse point (PS 5.1 Remove-Item -Recurse follows junctions).
function Remove-TreeSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $reparsePoints = New-Object 'System.Collections.Generic.List[System.IO.FileSystemInfo]'
    $stack = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $stack.Push((Get-Item -LiteralPath $Path -Force))
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue) {
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { $reparsePoints.Add($item); continue }
            if ($item.PSIsContainer) { $stack.Push($item) }
        }
    }
    foreach ($reparsePoint in $reparsePoints) {
        if ($reparsePoint.PSIsContainer) { [System.IO.Directory]::Delete($reparsePoint.FullName) }
        else { [System.IO.File]::Delete($reparsePoint.FullName) }
    }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path) {
        Start-Sleep -Milliseconds 500
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Safety snapshots
# =============================================================================

function Get-RealHomeSnapshot {
    $snapshot = @{}
    foreach ($rootName in $script:RealHomeMarkerRoots) {
        $rootPath = Join-Path $env:USERPROFILE $rootName
        if (-not (Test-Path -LiteralPath $rootPath)) { $snapshot[$rootName] = 'ABSENT'; continue }
        $lines = Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { "{0}|{1}|{2}" -f $_.FullName.Substring($rootPath.Length), $_.Length, $_.LastWriteTimeUtc.Ticks } |
            Sort-Object
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
        $snapshot[$rootName] = [System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    return $snapshot
}

function Test-SnapshotsEqual {
    param($Before, $After)
    $differing = @()
    foreach ($key in $Before.Keys) {
        if (-not $After.Contains($key) -or $Before[$key] -ne $After[$key]) { $differing += $key }
    }
    return $differing
}

# =============================================================================
# Evidence
# =============================================================================

function ConvertTo-SanitizedText {
    param([string]$Text)
    $sanitized = $Text
    foreach ($pair in @(
        @($script:SandboxRoot, '%SANDBOX%'),
        @($env:TEMP, '%TEMP%'),
        @([System.IO.Path]::GetTempPath().TrimEnd('\'), '%TEMP%'),
        @($env:USERPROFILE, '%USERPROFILE%'),
        @($env:USERNAME, '<user>')
    )) {
        if ($pair[0]) { $sanitized = $sanitized -replace [regex]::Escape($pair[0]), $pair[1] }
    }
    return $sanitized
}

function Write-Evidence {
    param([string]$OverallStatus, $Tools)
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
    $evidence = [ordered]@{
        schemaVersion = 1
        harness       = 'Invoke-RealWorldE2E'
        runAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
        overallStatus = $OverallStatus
        host          = [ordered]@{
            osVersion        = [Environment]::OSVersion.Version.ToString()
            powershellVersion = $PSVersionTable.PSVersion.ToString()
        }
        safety        = [ordered]@{
            excludedRealHomeRoots = @('.claude', '.claude.json')
            exclusionReason       = 'Harness may run inside a Claude Code session which legitimately writes its own state.'
            assertions            = $null
        }
        notes         = $script:RunNotes
        tools         = $Tools
    }
    $secretPattern = '(?i)(access_token|refresh_token|id_token|api[_-]?key|bearer\s+[A-Za-z0-9]|sk-[A-Za-z0-9]|dummy-token)'
    $evidence.safety.assertions = @($script:SafetyAssertions)
    $json = ConvertTo-SanitizedText ($evidence | ConvertTo-Json -Depth 8)
    $scanPassed = $true
    if ($json -match $secretPattern) { $scanPassed = $false }
    Add-SafetyAssertion -Name 'evidence-secret-scan' -Passed $scanPassed `
        $(if ($scanPassed) { 'No tokens, env dumps, or user paths in evidence.' } else { 'Secret-like content detected; evidence redacted to minimal form.' })
    $evidence.safety.assertions = @($script:SafetyAssertions)
    $json = ConvertTo-SanitizedText ($evidence | ConvertTo-Json -Depth 8)
    if (-not $scanPassed) {
        $json = (@{ schemaVersion = 1; overallStatus = 'fail'; reason = 'evidence-secret-scan' } | ConvertTo-Json)
    }
    $outputPath = Join-Path $EvidenceDir 'realworld-evidence.json'
    $temporaryPath = "$outputPath.tmp"
    [System.IO.File]::WriteAllText($temporaryPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
    Write-Host "Evidence written to $outputPath"
}

# =============================================================================
# Tool flows
# =============================================================================

function New-BothProfiles {
    param($Adapter, [System.Collections.IDictionary]$ToolEntry)
    foreach ($name in @('account-a', 'account-b')) {
        $result = Invoke-MultiCli -MultiCliArgs @('new', "$($Adapter.id)/$name", '--no-seed') -TimeoutSeconds 120
        if ($result.ExitCode -ne 0) {
            Add-Assertion $ToolEntry 'profiles-created' $false "new $($Adapter.id)/$name exited $($result.ExitCode): $($result.Stdout.Trim())"
            return $false
        }
    }
    foreach ($name in @('account-a', 'account-b')) {
        $profileDir = Join-Path (Join-Path $script:SandboxProfiles $Adapter.id) $name
        $metadata = Get-ProfileMetadata -ToolId $Adapter.id -ProfileName $name
        if (-not (Test-Path -LiteralPath (Join-Path $profileDir 'auth') -PathType Container)) {
            Add-Assertion $ToolEntry 'profiles-created' $false "auth dir missing for $name"
            return $false
        }
        if ([guid]::Parse($metadata.profileId) -isnot [guid]) {
            Add-Assertion $ToolEntry 'profiles-created' $false "profileId not a guid for $name"
            return $false
        }
    }
    Add-Assertion $ToolEntry 'profiles-created' $true 'account-a and account-b created via real multi-cli new.'
    return $true
}

function Test-VersionMatch {
    param($Adapter, [System.Collections.IDictionary]$ToolEntry, [string]$ProfileName, [string]$Binary, [string]$ExpectedFirstLine, [hashtable]$ExtraEnv = @{})
    $versionArgs = Get-VersionArguments $Adapter
    # Children run with a sandboxed APPDATA, so adapter candidates like
    # %APPDATA%\npm\<tool>.cmd do not resolve there and Get-Command would pick
    # npm's .ps1 stub (not process-startable). Pin the harness-resolved real
    # binary; a caller-provided shim in $ExtraEnv wins when present.
    $launchEnv = @{ MULTICLI_OVERRIDE_BINARY = $Binary }
    foreach ($key in $ExtraEnv.Keys) { $launchEnv[$key] = $ExtraEnv[$key] }
    $result = Invoke-MultiCli -MultiCliArgs (@('launch', "$($Adapter.id)/$ProfileName") + $versionArgs) -ExtraEnv $launchEnv -TimeoutSeconds 180
    Add-Assertion $ToolEntry "launch-exit-zero-$ProfileName" ($result.ExitCode -eq 0 -and -not $result.TimedOut) `
        "exit=$($result.ExitCode) timedOut=$($result.TimedOut) stderr=$($result.Stderr.Trim().Substring(0, [Math]::Min(200, $result.Stderr.Trim().Length)))"
    $matched = $ExpectedFirstLine -and $result.Stdout.Contains($ExpectedFirstLine)
    Add-Assertion $ToolEntry "version-matches-direct-binary-$ProfileName" ([bool]$matched) `
        "expected launch output to contain '$ExpectedFirstLine'"
    return $result
}

function Test-FileOverlayTool {
    param($Adapter, [System.Collections.IDictionary]$ToolEntry, [string]$Binary, $DirectVersion)

    $sharedRoot = Get-SandboxSharedRoot $Adapter
    $normalState = $Adapter.normalState
    $sharedPaths = @((Get-PropSafe $normalState 'sharedPaths'))
    $sessionPaths = @((Get-PropSafe $normalState 'sessionPaths'))
    $filePaths = @((Get-PropSafe $normalState 'filePaths'))
    $credentialFiles = @((Get-PropSafe $Adapter.account 'credentialFiles'))

    # --- seed the REAL shared normal-state root BEFORE building profiles ---
    $seedTag = "mcli-e2e-seed-$([guid]::NewGuid().ToString('N'))"
    $sharedSeedRel = @($sharedPaths | Where-Object { $filePaths -contains $_ } | Select-Object -First 1)[0]
    $sessionSeedRel = @($sessionPaths | Where-Object { $filePaths -contains $_ } | Select-Object -First 1)[0]
    $sessionSeedIsDir = $false
    if (-not $sessionSeedRel -and $sessionPaths.Count -gt 0) {
        $sessionSeedRel = "$($sessionPaths[0])/seed-marker.txt" -replace '/', '\'
        $sessionSeedIsDir = $true
    }
    New-Item -ItemType Directory -Force -Path $sharedRoot | Out-Null
    if ($sharedSeedRel) {
        $sharedSeedPath = Join-Path $sharedRoot ($sharedSeedRel -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sharedSeedPath) | Out-Null
        Set-Content -LiteralPath $sharedSeedPath -Value "$seedTag-shared" -Encoding ASCII
    }
    if ($sessionSeedRel) {
        $sessionSeedPath = Join-Path $sharedRoot $sessionSeedRel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sessionSeedPath) | Out-Null
        Set-Content -LiteralPath $sessionSeedPath -Value "$seedTag-session" -Encoding ASCII
    }

    if (-not (New-BothProfiles $Adapter $ToolEntry)) { return }

    # --- launch both profiles through the real binary ---
    Test-VersionMatch $Adapter $ToolEntry 'account-a' $Binary $DirectVersion.FirstLine | Out-Null
    Test-VersionMatch $Adapter $ToolEntry 'account-b' $Binary $DirectVersion.FirstLine | Out-Null

    $profileADir = Join-Path (Join-Path $script:SandboxProfiles $Adapter.id) 'account-a'
    $profileBDir = Join-Path (Join-Path $script:SandboxProfiles $Adapter.id) 'account-b'
    $runtimeRootA = Join-Path $profileADir '.runtime'
    $runtimeRootB = Join-Path $profileBDir '.runtime'
    $runtimeLinkRootA = $runtimeRootA
    $runtimeLinkRootB = $runtimeRootB
    $runtimeSubdir = Get-PropSafe $normalState 'runtimeSubdir'
    if ($runtimeSubdir) {
        $runtimeLinkRootA = Join-Path $runtimeRootA ($runtimeSubdir -replace '/', '\')
        $runtimeLinkRootB = Join-Path $runtimeRootB ($runtimeSubdir -replace '/', '\')
    }

    # (a) credential files are profile-local and EMPTY in both profiles
    $credentialsOk = $true
    $credentialDetail = @()
    foreach ($profileDir in @($profileADir, $profileBDir)) {
        foreach ($credRel in $credentialFiles) {
            $credPath = Join-Path (Join-Path $profileDir 'auth') ($credRel -replace '/', '\')
            $item = Get-Item -LiteralPath $credPath -Force -ErrorAction SilentlyContinue
            if (-not $item) { $credentialsOk = $false; $credentialDetail += "missing $credRel"; continue }
            if ($item.Length -ne 0) { $credentialsOk = $false; $credentialDetail += "$credRel not empty" }
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { $credentialsOk = $false; $credentialDetail += "$credRel is a link" }
        }
    }
    Add-Assertion $ToolEntry 'credential-files-profile-local-empty' $credentialsOk ($credentialDetail -join '; ')

    # runtime credential entries are hardlinks back into the profile's own auth dir
    $credLinkOk = $true
    foreach ($credRel in $credentialFiles) {
        $runtimeCred = Get-Item -LiteralPath (Join-Path $runtimeLinkRootA ($credRel -replace '/', '\')) -Force -ErrorAction SilentlyContinue
        $profileCredFull = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $profileADir 'auth') ($credRel -replace '/', '\')))
        $targets = @($runtimeCred.Target)
        if (-not $runtimeCred -or $runtimeCred.LinkType -ne 'HardLink' -or
            $targets.Count -eq 0 -or -not $targets[0].Equals($profileCredFull, [StringComparison]::OrdinalIgnoreCase)) {
            $credLinkOk = $false
        }
    }
    Add-Assertion $ToolEntry 'credential-hardlinks-point-to-profile-auth' $credLinkOk `
        'runtime credential files must be hardlinks into profile auth/, not the shared root.'

    # (a2) seeded shared content visible through both profiles and intact at the root
    $seedOk = $true
    if ($sharedSeedRel) {
        $expected = "$seedTag-shared"
        foreach ($probe in @(
            (Join-Path $sharedRoot ($sharedSeedRel -replace '/', '\')),
            (Join-Path $runtimeLinkRootA ($sharedSeedRel -replace '/', '\')),
            (Join-Path $runtimeLinkRootB ($sharedSeedRel -replace '/', '\'))
        )) {
            if ((Get-Content -LiteralPath $probe -Raw -ErrorAction SilentlyContinue).Trim() -ne $expected) { $seedOk = $false }
        }
    }
    if ($sessionSeedRel) {
        $expected = "$seedTag-session"
        foreach ($probe in @(
            (Join-Path $sharedRoot $sessionSeedRel),
            (Join-Path $runtimeLinkRootA $sessionSeedRel),
            (Join-Path $runtimeLinkRootB $sessionSeedRel)
        )) {
            if ((Get-Content -LiteralPath $probe -Raw -ErrorAction SilentlyContinue).Trim() -ne $expected) { $seedOk = $false }
        }
    }
    Add-Assertion $ToolEntry 'shared-state-seed-visible-in-both-profiles' $seedOk `
        "shared seed '$sharedSeedRel', session seed '$($sessionSeedRel -replace '\\', '/')'."

    # (b) .runtime contains links into the shared root
    $junctions = @(Get-ChildItem -LiteralPath $runtimeLinkRootA -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer -and ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) })
    $junctionTargetsOk = $junctions.Count -gt 0
    foreach ($junction in $junctions) {
        foreach ($target in @($junction.Target)) {
            if (-not $target.StartsWith($sharedRoot, [StringComparison]::OrdinalIgnoreCase)) { $junctionTargetsOk = $false }
        }
    }
    $hardlinks = @(Get-ChildItem -LiteralPath $runtimeLinkRootA -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LinkType -eq 'HardLink' })
    $hardlinkTargetsOk = $hardlinks.Count -gt 0
    foreach ($hardlink in $hardlinks) {
        $targets = @($hardlink.Target)
        $pointsToShared = $false
        foreach ($target in $targets) {
            if ($target.StartsWith($sharedRoot, [StringComparison]::OrdinalIgnoreCase)) { $pointsToShared = $true }
        }
        $pointsToProfile = $false
        foreach ($target in $targets) {
            if ($target.StartsWith($profileADir, [StringComparison]::OrdinalIgnoreCase)) { $pointsToProfile = $true }
        }
        if (-not ($pointsToShared -or $pointsToProfile)) { $hardlinkTargetsOk = $false }
    }
    Add-Assertion $ToolEntry 'runtime-links-into-shared-root' ($junctionTargetsOk -and $hardlinkTargetsOk) `
        "$($junctions.Count) junction(s), $($hardlinks.Count) hardlink(s) in account-a .runtime."

    # (c) session write via profile A is visible via profile B and at the shared root
    $crossTag = "mcli-e2e-xprofile-$([guid]::NewGuid().ToString('N'))"
    $crossOk = $true
    if ($sessionSeedRel -and -not $sessionSeedIsDir) {
        Add-Content -LiteralPath (Join-Path $runtimeLinkRootA $sessionSeedRel) -Value $crossTag -Encoding ASCII
        $viaB = Get-Content -LiteralPath (Join-Path $runtimeLinkRootB $sessionSeedRel) -Raw -ErrorAction SilentlyContinue
        $viaRoot = Get-Content -LiteralPath (Join-Path $sharedRoot $sessionSeedRel) -Raw -ErrorAction SilentlyContinue
        if (-not ($viaB -and $viaB.Contains($crossTag))) { $crossOk = $false }
        if (-not ($viaRoot -and $viaRoot.Contains($crossTag))) { $crossOk = $false }
    } elseif ($sessionSeedRel) {
        $crossFile = "xprofile-$([guid]::NewGuid().ToString('N')).txt"
        $sessionDirRel = Split-Path -Parent $sessionSeedRel
        Set-Content -LiteralPath (Join-Path $runtimeLinkRootA "$sessionDirRel\$crossFile") -Value $crossTag -Encoding ASCII
        if (-not (Test-Path -LiteralPath (Join-Path $runtimeLinkRootB "$sessionDirRel\$crossFile") -PathType Leaf)) { $crossOk = $false }
        if (-not (Test-Path -LiteralPath (Join-Path $sharedRoot "$sessionDirRel\$crossFile") -PathType Leaf)) { $crossOk = $false }
    }
    Add-Assertion $ToolEntry 'shared-session-visible-across-profiles' $crossOk `
        'write through account-a runtime observed through account-b runtime and the shared root.'

    # (d) doctor --deep after clean launches
    $doctorClean = Invoke-MultiCli -MultiCliArgs @('doctor', '--deep') -TimeoutSeconds 90
    $unexpectedLines = @($doctorClean.Stdout -split "`r?`n" | Where-Object { $_ -match 'unexpected runtime file' })
    $allowlist = @($script:DoctorTransientAllowlist.Values | ForEach-Object { $_ } | Where-Object { $_ })
    $flagged = @()
    $ignored = 0
    foreach ($line in $unexpectedLines) {
        $relative = $line
        if ($line -match 'unexpected runtime file (.+?) in ') { $relative = $Matches[1] }
        $allowed = $false
        foreach ($pattern in $allowlist) { if ($relative -match $pattern) { $allowed = $true; break } }
        if ($allowed) { $ignored++ } else { $flagged += $relative }
    }
    if ($ignored -gt 0) {
        Add-Note "$($Adapter.id): doctor --deep flagged $ignored known vendor-transient runtime file(s) matching the vendor-transient allowlist (gemini-cli '.gemini/projects.json.<guid>.tmp'; codex 'tmp/arg0/codex-arg0*' apply-patch helpers); recorded, not counted as failure."
    }
    $doctorExpectedExit = $(if ($ignored -gt 0) { 1 } else { 0 })
    Add-Assertion $ToolEntry 'doctor-deep-clean-after-launch' ($flagged.Count -eq 0 -and $doctorClean.ExitCode -eq $doctorExpectedExit) `
        "unexpected=$($flagged.Count) ignoredTransients=$ignored exit=$($doctorClean.ExitCode) expectedExit=$doctorExpectedExit"

    # (e) rogue file is flagged, then clean again after removal
    $roguePath = Join-Path $runtimeRootA 'rogue-e2e.txt'
    Set-Content -LiteralPath $roguePath -Value 'rogue' -Encoding ASCII
    $doctorRogue = Invoke-MultiCli -MultiCliArgs @('doctor', '--deep') -TimeoutSeconds 90
    $rogueFlagged = $doctorRogue.Stdout -match 'unexpected runtime file rogue-e2e\.txt'
    Add-Assertion $ToolEntry 'doctor-deep-flags-rogue-file' ([bool]$rogueFlagged) 'planted .runtime\rogue-e2e.txt must be flagged.'
    Remove-Item -LiteralPath $roguePath -Force
    $doctorAfter = Invoke-MultiCli -MultiCliArgs @('doctor', '--deep') -TimeoutSeconds 90
    $rogueStillThere = $doctorAfter.Stdout -match 'unexpected runtime file rogue-e2e\.txt'
    Add-Assertion $ToolEntry 'doctor-deep-clean-after-rogue-removal' (-not $rogueStillThere) 'rogue file gone from doctor output after removal.'
}

function Set-ProfileSecret {
    param($Adapter, [System.Collections.IDictionary]$ToolEntry, [string]$ProfileName, [string]$Token)
    $target = Get-CredentialTarget -Adapter $Adapter -ProfileName $ProfileName
    $script:CredentialTargets.Add($target)
    Set-MultiCliCredential -Target $target -Secret $Token
    $stored = Get-MultiCliCredential -Target $target
    $ok = $stored -eq $Token
    Add-Assertion $ToolEntry "auth-set-$ProfileName" $ok `
        'real Credential Manager round-trip using the same target and module as multi-cli auth set.'
    return $ok
}

function New-TokenCaptureShim {
    param($Adapter, [string]$Binary)
    $environmentVariable = (Get-PropSafe (Get-PropSafe $Adapter.account 'secret') 'environmentVariable')
    $shimPath = Join-Path $script:SandboxShims "$($Adapter.id)-capture.cmd"
    $shimContent = @"
@echo off
>"%MCLI_CAPTURE_FILE%" echo %$environmentVariable%
"$Binary" %*
exit /b %ERRORLEVEL%
"@
    Set-Content -LiteralPath $shimPath -Value $shimContent -Encoding ASCII
    return $shimPath
}

function Test-ProcessSecretPreconditions {
    param($Adapter, [System.Collections.IDictionary]$ToolEntry, [string]$SharedRoot)
    if ($Adapter.id -ne 'grok-cli') { return $true }
    $configPath = Join-Path $SharedRoot 'config.toml'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Add-Assertion $ToolEntry 'process-secret-preconditions-clear' $true 'no shared Grok config exists.'
        return $true
    }
    $config = Get-Content -LiteralPath $configPath -Raw
    $hasStrongerCredential = $config -match '(?m)^\s*(api_key|env_key)\s*='
    Add-Assertion $ToolEntry 'process-secret-preconditions-clear' (-not $hasStrongerCredential) `
        'shared Grok config must not define model.api_key or model.env_key before XAI_API_KEY isolation is claimed.'
    return -not $hasStrongerCredential
}

function Set-ProcessSecretSharedSeed {
    param($Adapter, [string]$SharedSeedPath, [string]$SeedTag)
    if ($Adapter.id -ne 'cursor-cli') {
        Set-Content -LiteralPath $SharedSeedPath -Value "$SeedTag-shared" -Encoding ASCII
        return
    }
    $cursorSeed = [ordered]@{
        version = 1
        editor  = [ordered]@{ vimMode = $true }
        hints   = $false
    }
    $cursorJson = $cursorSeed | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText(
        $SharedSeedPath,
        $cursorJson,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Test-ProcessSecretSharedSeed {
    param($Adapter, [string]$SharedSeedPath, [string]$SeedTag)
    if ($Adapter.id -ne 'cursor-cli') {
        $seedAfter = (Get-Content -LiteralPath $SharedSeedPath -Raw -ErrorAction SilentlyContinue).Trim()
        return $seedAfter -eq "$SeedTag-shared"
    }
    $cursorState = $null
    try { $cursorState = Get-Content -LiteralPath $SharedSeedPath -Raw -ErrorAction Stop | ConvertFrom-Json }
    catch { $cursorState = $null }
    return $null -ne $cursorState -and
        $cursorState.version -eq 1 -and
        $cursorState.editor.vimMode -eq $true -and
        $cursorState.hints -eq $false
}

function Test-ProcessSecretTool {
    param($Adapter, [System.Collections.IDictionary]$ToolEntry, [string]$Binary, $DirectVersion)

    $sharedRoot = Get-SandboxSharedRoot $Adapter
    $normalState = $Adapter.normalState
    $sharedPaths = @((Get-PropSafe $normalState 'sharedPaths'))
    $filePaths = @((Get-PropSafe $normalState 'filePaths'))

    if (-not (Test-ProcessSecretPreconditions -Adapter $Adapter -ToolEntry $ToolEntry -SharedRoot $sharedRoot)) { return }

    # Seed a shared config file in the REAL shared root before profile creation.
    $seedTag = "mcli-e2e-seed-$([guid]::NewGuid().ToString('N'))"
    $sharedSeedRel = @($sharedPaths | Where-Object { $filePaths -contains $_ } | Select-Object -First 1)[0]
    if ($sharedSeedRel) {
        $sharedSeedPath = Join-Path $sharedRoot ($sharedSeedRel -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sharedSeedPath) | Out-Null
        Set-ProcessSecretSharedSeed -Adapter $Adapter -SharedSeedPath $sharedSeedPath -SeedTag $seedTag
    }

    if (-not (New-BothProfiles $Adapter $ToolEntry)) { return }

    $shim = New-TokenCaptureShim -Adapter $Adapter -Binary $Binary
    $tokens = @{ 'account-a' = 'dummy-token-account-a'; 'account-b' = 'dummy-token-account-b' }
    $captured = @{}

    foreach ($name in @('account-a', 'account-b')) {
        if (-not (Set-ProfileSecret $Adapter $ToolEntry $name $tokens[$name])) { return }

        $status = Invoke-MultiCli -MultiCliArgs @('auth', 'status', "$($Adapter.id)/$name") -TimeoutSeconds 120
        Add-Assertion $ToolEntry "auth-status-present-$name" `
            ($status.ExitCode -eq 0 -and $status.Stdout -match 'Credential present') `
            "real auth status exit=$($status.ExitCode)."

        $captureFile = Join-Path $script:SandboxCaptures "$($Adapter.id)-$name.txt"
        $launch = Test-VersionMatch $Adapter $ToolEntry $name $Binary $DirectVersion.FirstLine `
            -ExtraEnv @{ MULTICLI_OVERRIDE_BINARY = $shim; MCLI_CAPTURE_FILE = $captureFile }
        if (-not (Test-Path -LiteralPath $captureFile -PathType Leaf)) {
            Add-Assertion $ToolEntry "profile-token-captured-$name" $false 'shim capture file missing after launch.'
            return
        }
        $captured[$name] = (Get-Content -LiteralPath $captureFile -Raw).Trim()
        Add-Assertion $ToolEntry "profile-token-captured-$name" ($captured[$name] -eq $tokens[$name]) `
            'env secret observed by the launched process equals the configured per-profile dummy token.'
    }

    Add-Assertion $ToolEntry 'profile-tokens-differ' ($captured['account-a'] -ne $captured['account-b']) `
        'account-a and account-b launched with different secret env values.'

    if ($sharedSeedRel) {
        $sharedSeedPath = Join-Path $sharedRoot ($sharedSeedRel -replace '/', '\')
        $seedIntact = Test-ProcessSecretSharedSeed -Adapter $Adapter -SharedSeedPath $sharedSeedPath -SeedTag $seedTag
        $detail = if ($Adapter.id -eq 'cursor-cli') {
            "shared Cursor settings in '$sharedSeedRel' remained version=1, editor.vimMode=true, hints=false after both launches."
        } else {
            "shared seed '$sharedSeedRel' intact after both launches."
        }
        Add-Assertion $ToolEntry 'shared-state-seed-intact' $seedIntact $detail
    }

    foreach ($name in @('account-a', 'account-b')) {
        $clear = Invoke-MultiCli -MultiCliArgs @('auth', 'clear', "$($Adapter.id)/$name") -TimeoutSeconds 120
        $gone = -not (Test-MultiCliCredential -Target (Get-CredentialTarget -Adapter $Adapter -ProfileName $name))
        Add-Assertion $ToolEntry "auth-clear-$name" ($clear.ExitCode -eq 0 -and $gone) `
            "real auth clear exit=$($clear.ExitCode), credential verified gone."
    }

    $postClear = Invoke-MultiCli -MultiCliArgs (@('launch', "$($Adapter.id)/account-a") + (Get-VersionArguments $Adapter)) -TimeoutSeconds 120
    $hintShown = $postClear.Stdout -match 'no stored credential' -and $postClear.Stdout -match 'auth set'
    Add-Assertion $ToolEntry 'launch-fails-after-auth-clear' ($postClear.ExitCode -ne 0 -and $hintShown) `
        "exit=$($postClear.ExitCode), auth-set hint shown."

    $profileADir = Join-Path (Join-Path $script:SandboxProfiles $Adapter.id) 'account-a'
    Add-Assertion $ToolEntry 'no-runtime-overlay-built' `
        (-not (Test-Path -LiteralPath (Join-Path $profileADir '.runtime'))) `
        'processSecret profiles run directly against the shared root; no .runtime overlay expected.'
}

# =============================================================================
# Cleanup
# =============================================================================

function Clear-SandboxCredentials {
    foreach ($target in $script:CredentialTargets) { Remove-TrackedCredential $target }
    $script:CredentialTargets.Clear()
    # Belt-and-braces sweep: any credential derivable from sandbox profile
    # metadata (covers a crashed previous run and anything missed above).
    $profilesRoot = $script:SandboxProfiles
    if (-not (Test-Path -LiteralPath $profilesRoot)) { return }
    $metadataFiles = Get-ChildItem -LiteralPath $profilesRoot -Recurse -Force -Filter '.profile.json' -ErrorAction SilentlyContinue
    foreach ($metadataFile in $metadataFiles) {
        $metadata = Get-Content -LiteralPath $metadataFile.FullName -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if (-not $metadata) { continue }
        $adapter = $null
        try { $adapter = Get-ToolAdapter -ToolId $metadata.adapterId } catch { continue }
        $environmentVariable = (Get-PropSafe (Get-PropSafe $adapter.account 'secret') 'environmentVariable')
        if (-not $environmentVariable) { continue }
        Remove-TrackedCredential "multi-cli/$($metadata.adapterId)/$($metadata.profileId)/$environmentVariable"
    }
}

# =============================================================================
# Main
# =============================================================================

Write-Host "multi-cli real-world E2E harness"
Write-Host "  sandbox: $script:SandboxRoot"
Write-Host "  evidence: $EvidenceDir"
Write-Host ""

Import-Module (Join-Path $script:RepoRoot 'lib\MultiCli.CredentialStore.psm1') -Force

$toolsEvidence = [ordered]@{}

# --- safety preflight: snapshot real-home marker roots and registry PATH ---
$registryPathBefore = [Environment]::GetEnvironmentVariable('PATH', 'User')
$homeSnapshotBefore = Get-RealHomeSnapshot

# --- reset any stale sandbox from a previous/crashed run ---
Clear-SandboxCredentials
Remove-TreeSafe $script:SandboxRoot
New-Item -ItemType Directory -Force -Path $script:SandboxHome, $script:SandboxProfiles, $script:SandboxTemp, $script:SandboxShims, $script:SandboxCaptures | Out-Null

try {
    # --- prove the child-process environment is sandboxed ---
    $probe = Invoke-ChildProcess -FilePath $script:PowerShellExe `
        -Arguments @('-NoProfile', '-Command', 'Write-Output $env:USERPROFILE; Write-Output $env:APPDATA; Write-Output $env:MULTICLI_HOME') `
        -EnvMap (Get-SandboxEnv) -TimeoutSeconds 120
    $probeLines = @($probe.Stdout -split "`r?`n" | Where-Object { $_.Trim() })
    $envSandboxed = $probeLines.Count -eq 3 -and
        $probeLines[0].Trim() -eq $script:SandboxHome -and
        $probeLines[1].Trim() -eq (Join-Path $script:SandboxHome 'AppData\Roaming') -and
        $probeLines[2].Trim() -eq $script:SandboxProfiles
    Add-SafetyAssertion 'child-env-sandboxed' $envSandboxed 'child USERPROFILE/APPDATA/MULTICLI_HOME all under the sandbox.'

    foreach ($toolId in $Tool) {
        Write-Host ""
        Write-Host "[$toolId]" -ForegroundColor Cyan
        $toolEntry = [ordered]@{
            status        = 'running'
            skipReason    = $null
            mechanism     = $null
            binaryVersion = $null
            assertions    = @()
        }
        $toolsEvidence[$toolId] = $toolEntry
        try {
            $adapter = Get-ToolAdapter -ToolId $toolId
            $isSchemaV2Overlay = ((Get-PropSafe $adapter 'schemaVersion') -eq 2) -and
                ((Get-PropSafe $adapter.isolation 'strategy') -eq 'accountOverlay')
            if (-not $isSchemaV2Overlay) {
                Add-Assertion $toolEntry 'adapter-contract' $false 'adapter is not schema-v2 accountOverlay.'
                $toolEntry.status = 'fail'
                continue
            }
            $mechanism = Get-PropSafe $adapter.account 'mechanism'
            $toolEntry.mechanism = $mechanism

            $binary = Resolve-RealBinary $adapter
            if (-not $binary) {
                $toolEntry.status = 'skip'
                $toolEntry.skipReason = "$toolId binary not found on this host (adapter candidates exhausted, system binaries rejected)."
                Write-Host "  SKIP: $($toolEntry.skipReason)" -ForegroundColor Yellow
                continue
            }
            Add-Assertion $toolEntry 'binary-resolved' $true 'real installed binary resolved via adapter candidates.'

            $directVersion = Get-DirectBinaryVersion -Adapter $adapter -Binary $binary -VersionArgs (Get-VersionArguments $adapter)
            if ($directVersion.ExitCode -ne 0 -or -not $directVersion.FirstLine) {
                Add-Assertion $toolEntry 'direct-version-captured' $false "exit=$($directVersion.ExitCode)."
                $toolEntry.status = 'fail'
                continue
            }
            $toolEntry.binaryVersion = $directVersion.FirstLine
            Add-Assertion $toolEntry 'direct-version-captured' $true $directVersion.FirstLine

            switch ($mechanism) {
                'fileOverlay'   { Test-FileOverlayTool   -Adapter $adapter -ToolEntry $toolEntry -Binary $binary -DirectVersion $directVersion }
                'processSecret' { Test-ProcessSecretTool -Adapter $adapter -ToolEntry $toolEntry -Binary $binary -DirectVersion $directVersion }
                default         { Add-Assertion $toolEntry 'adapter-contract' $false "unsupported account mechanism '$mechanism'." }
            }
            $failed = @($toolEntry.assertions | Where-Object { -not $_.passed })
            $toolEntry.status = $(if ($failed.Count -gt 0) { 'fail' } else { 'pass' })
        } catch {
            Add-Assertion $toolEntry 'flow-completed' $false $_.Exception.Message
            $toolEntry.status = 'fail'
        }
        Write-Host "  => $($toolEntry.status)$(
            if ($toolEntry.status -eq 'pass') {
                " ($(@($toolEntry.assertions).Count) assertions)"
            } elseif ($toolEntry.skipReason) { " -- $($toolEntry.skipReason)" } else { '' })"
    }
} finally {
    Write-Host ""
    Write-Host '[cleanup]' -ForegroundColor Cyan

    Clear-SandboxCredentials
    $credentialsClean = $true
    $profilesRoot = $script:SandboxProfiles
    if (Test-Path -LiteralPath $profilesRoot) {
        foreach ($metadataFile in Get-ChildItem -LiteralPath $profilesRoot -Recurse -Force -Filter '.profile.json' -ErrorAction SilentlyContinue) {
            $metadata = Get-Content -LiteralPath $metadataFile.FullName -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
            if (-not $metadata) { continue }
            try { $adapter = Get-ToolAdapter -ToolId $metadata.adapterId } catch { continue }
            $environmentVariable = (Get-PropSafe (Get-PropSafe $adapter.account 'secret') 'environmentVariable')
            if (-not $environmentVariable) { continue }
            if (Test-MultiCliCredential -Target "multi-cli/$($metadata.adapterId)/$($metadata.profileId)/$environmentVariable") { $credentialsClean = $false }
        }
    }
    Add-SafetyAssertion 'credential-manager-clean' $credentialsClean 'all multi-cli/* test targets removed and verified absent.'

    if ($KeepSandbox) { Write-Host "  keeping sandbox at $script:SandboxRoot" }
    else { Remove-TreeSafe $script:SandboxRoot }

    $registryPathAfter = [Environment]::GetEnvironmentVariable('PATH', 'User')
    # The guard's purpose: THIS harness must not mutate the registry User PATH
    # (multi-cli new appends the alias dir unless it is pre-seeded into the
    # child PATH, which Get-SandboxEnv does). Other processes on a live
    # workstation may legitimately change the same value mid-run; such churn
    # is recorded as a note, not attributed to this harness -- unless an added
    # entry references our sandbox, which is a hard failure.
    $registryClean = $true
    $registryDetail = 'registry User PATH identical before/after (alias dir was pre-seeded into child PATH).'
    if ($registryPathAfter -ne $registryPathBefore) {
        $beforeEntries = @($registryPathBefore -split ';' | Where-Object { $_ })
        $afterEntries = @($registryPathAfter -split ';' | Where-Object { $_ })
        $added = @($afterEntries | Where-Object { $beforeEntries -notcontains $_ })
        $sandboxLeaks = @($added | Where-Object { $_.IndexOf($script:SandboxRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
        if ($sandboxLeaks.Count -gt 0) {
            $registryClean = $false
            $registryDetail = "registry User PATH gained $($sandboxLeaks.Count) entr(ies) referencing the sandbox."
        } else {
            Add-Note "Registry User PATH changed during the run due to external churn ($($added.Count) added entr(ies), none referencing the sandbox); this workstation runs concurrent multi-cli test sessions whose fixture profiles append to the User PATH."
            $registryDetail = "external churn only ($($added.Count) added entr(ies), none referencing the sandbox)."
        }
    }
    Add-SafetyAssertion 'registry-user-path-unchanged' $registryClean $registryDetail

    $homeSnapshotAfter = Get-RealHomeSnapshot
    $differingRoots = @(Test-SnapshotsEqual $homeSnapshotBefore $homeSnapshotAfter)
    Add-SafetyAssertion 'real-home-unchanged' ($differingRoots.Count -eq 0) `
        $(if ($differingRoots.Count -eq 0) {
            "marker roots under the real user profile unchanged: $($script:RealHomeMarkerRoots -join ', ') (.claude excluded, see safety.exclusionReason)."
        } else {
            "CHANGED real-home marker root(s): $($differingRoots -join ', ') -- another process (or a sandbox escape) wrote there during the run."
        })

    $executedTools = @($toolsEvidence.Values | Where-Object { $_.status -ne 'skip' })
    if ($executedTools.Count -eq 0) {
        $script:FailureCount++
        Add-SafetyAssertion 'at-least-one-tool-executed' $false 'No requested vendor binary was available; an all-skipped run is not evidence.'
    } else {
        Add-SafetyAssertion 'at-least-one-tool-executed' $true "$($executedTools.Count) requested tool(s) executed."
    }
    $overallStatus = $(if ($script:FailureCount -gt 0) { 'fail' } else { 'pass' })
    try { Write-Evidence -OverallStatus $overallStatus -Tools $toolsEvidence }
    catch { Write-Warning "Evidence write failed: $_"; $script:FailureCount++ }

    Write-Host ""
    Write-Host "Overall: $(if ($script:FailureCount -gt 0) { "FAIL ($script:FailureCount failed assertion(s))" } else { 'PASS' })"
    if ($script:FailureCount -gt 0) { exit 1 }
    exit 0
}
