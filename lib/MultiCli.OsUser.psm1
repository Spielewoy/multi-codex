Set-StrictMode -Version Latest

# osUserCredentialStore account mechanism for multi-cli (Windows).
#
# Each profile gets a multi-cli-owned local OS user whose per-user Windows
# Credential Manager namespace is the account boundary the adapter requires
# (antigravity, agy-cli, kiro, zed, windsurf, copilot-vscode). Declared
# shared/session state is junctioned from the sandbox user's home tree into
# the operator's native shared root, exactly like the file-overlay runtime.
#
# Launch mechanism: Start-Process -Credential starts a generated PowerShell
# wrapper as the sandbox user. The password is retrieved from the operator's
# Credential Manager and bound through PSCredential, never placed in native
# process arguments. Foreground wrappers report the child exit code through
# <profile>\.osuser-launch.exitcode; detached GUI processes start directly.
#
# Hard rules:
#   - elevation is checked BEFORE any provisioning attempt; the error names
#     the remedy ("Run as Administrator");
#   - only users recorded as multi-cli-owned in <profile>\.osuser.json (and
#     matching the derived identity) are ever adopted, launched, or deleted;
#   - macOS/Linux fail closed with a precise message; no sudo half-path.
#
# Exported surface (orchestrator wiring): Get-OsUserName, Get-OsUserTaskName,
# Get-OsUserCredentialTarget, Get-OsUserOwnership, Initialize-OsUserIsolation
# (profile creation), Get-OsUserLaunchPlan, Invoke-OsUserLaunch (launch),
# Remove-OsUserIsolation (profile delete). Everything else is internal.

# Null-safe property walk (adapters arrive as ConvertFrom-Json objects).
function Get-OsUserProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

# --- Identity derivation ---------------------------------------------------

# Full lowercase SHA-256 hex of the UTF-8 identity string. Single hash path
# so PowerShell and lib/multicli-osuser.sh derive identical names.
function Get-OsUserIdentityHash {
    param([string]$Tool, [string]$ProfileId)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes("$Tool`:$ProfileId")
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

# Sandbox username: mcli_ + first 12 hex of SHA256("<tool>:<profileId>").
# 17 chars, within the 20-char Windows SAM account limit; deterministic, and
# collision-safe across tools because the tool id is part of the hash input.
function Get-OsUserName {
    param([string]$Tool, [string]$ProfileId)
    if ([string]::IsNullOrEmpty($Tool)) { throw 'OS-user name derivation requires a tool id.' }
    if ([string]::IsNullOrEmpty($ProfileId)) { throw 'OS-user name derivation requires a profileId.' }
    $hex = Get-OsUserIdentityHash -Tool $Tool.ToLowerInvariant() -ProfileId $ProfileId
    return 'mcli_' + $hex.Substring(0, 12)
}

# Scheduled-task name for the sandbox user (multi-cli-<hash suffix>).
function Get-OsUserTaskName {
    param([string]$Username)
    if ([string]::IsNullOrEmpty($Username)) { throw 'OS-user task name requires a username.' }
    return 'multi-cli-' + $Username.Substring(5)
}

# Credential Manager target holding the sandbox user's password.
function Get-OsUserCredentialTarget {
    param([string]$Username)
    if ([string]::IsNullOrEmpty($Username)) { throw 'OS-user credential target requires a username.' }
    return "multi-cli/osuser/$Username"
}

# --- Platform and elevation gates ------------------------------------------

function Test-OsUserRuntimePlatform {
    param([Runtime.InteropServices.OSPlatform]$Platform)
    return [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform($Platform)
}

function Get-OsUserPlatform {
    if ($env:OS -eq 'Windows_NT') { return 'windows' }
    if (Test-OsUserRuntimePlatform -Platform ([Runtime.InteropServices.OSPlatform]::OSX)) { return 'macos' }
    return 'linux'
}

# Explicit parameter so the non-Windows contract is testable on Windows.
function Assert-OsUserWindows {
    param([string]$Platform)
    if ($Platform -ne 'windows') {
        throw "OS-user isolation on $Platform is not implemented (needs sudo-backed user provisioning); use a process-secret or file-overlay profile"
    }
}

function Test-OsUserElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-OsUserElevated {
    param([string]$Tool, [string]$ProfileName)
    if (-not (Test-OsUserElevated)) {
        throw "OS-user isolation for $Tool/$ProfileName requires an elevated terminal (Run as Administrator)."
    }
}

# --- Ownership record (<profile>\.osuser.json) -------------------------------

# The ownership record, or $null when the profile has none.
function Get-OsUserOwnership {
    param([string]$ProfileDir)
    $path = Join-Path $ProfileDir '.osuser.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

# Write the record atomically (temp + move).
function Write-OsUserOwnership {
    param([string]$ProfileDir, [string]$Tool, [string]$ProfileId, [string]$Username)
    $record = [ordered]@{
        schemaVersion = 1
        tool = $Tool
        profileId = $ProfileId
        username = $Username
        taskName = Get-OsUserTaskName -Username $Username
        credentialTarget = Get-OsUserCredentialTarget -Username $Username
        createdUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    $temporaryPath = Join-Path $ProfileDir '.osuser.json.tmp'
    $record | ConvertTo-Json | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination (Join-Path $ProfileDir '.osuser.json') -Force
}

# The record after proving it matches the derived identity; $null when there
# is no record. Foreign records are refused, never touched. Runs before the
# elevation gate on purpose: a fabricated record is rejected on any host.
function Assert-OsUserOwnership {
    param([string]$ProfileDir)
    $record = Get-OsUserOwnership -ProfileDir $ProfileDir
    if ($null -eq $record) { return $null }
    $metadataPath = Join-Path $ProfileDir '.profile.json'
    if (-not (Test-Path -LiteralPath $metadataPath)) {
        throw "Refusing to touch OS user '$($record.username)': '$ProfileDir' is missing schema-v2 profile metadata."
    }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ($record.tool -ne $metadata.adapterId -or $record.profileId -ne $metadata.profileId) {
        throw "Refusing to touch OS user '$($record.username)': the ownership record in '$ProfileDir' belongs to another profile."
    }
    $expected = Get-OsUserName -Tool $metadata.adapterId -ProfileId $metadata.profileId
    $expectedTask = Get-OsUserTaskName -Username $expected
    $expectedCredential = Get-OsUserCredentialTarget -Username $expected
    if ($record.username -ne $expected -or $record.taskName -ne $expectedTask -or $record.credentialTarget -ne $expectedCredential) {
        throw "Refusing to touch OS user '$($record.username)': the ownership record in '$ProfileDir' does not match the derived identity '$expected'; the user is not multi-cli-owned."
    }
    return $record
}

# --- Provisioning (admin-gated) ----------------------------------------------

# The schema-v2 metadata every osUser profile carries.
function Get-OsUserProfileMetadata {
    param($Adapter, [string]$ProfileDir)
    $path = Join-Path $ProfileDir '.profile.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Profile '$($Adapter.id)/$(Split-Path $ProfileDir -Leaf)' is missing schema-v2 metadata."
    }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Get-OsUserModuleRoot {
    return $PSScriptRoot
}

function Import-OsUserCredentialStore {
    $moduleRoot = Get-OsUserModuleRoot
    if (-not $moduleRoot) { throw 'Cannot locate MultiCli.CredentialStore.psm1: module directory unknown.' }
    Import-Module (Join-Path $moduleRoot 'MultiCli.CredentialStore.psm1') -Force
}

# Run a native command with merged output. Preference variables are
# dynamically scoped, so pinning Continue here keeps a caller's
# $ErrorActionPreference=Stop from turning the native command's stderr lines
# into terminating ErrorRecords; the exit code stays in $LASTEXITCODE.
function Invoke-OsUserNative {
    param([string]$FilePath, [string[]]$NativeArgs)
    $ErrorActionPreference = 'Continue'
    return (& $FilePath @NativeArgs 2>&1 | Out-String).Trim()
}

function Test-OsUserExists {
    param([string]$Username)
    $null = Invoke-OsUserNative -FilePath net.exe -NativeArgs @('user', $Username)
    return ($LASTEXITCODE -eq 0)
}

# 24 chars with one guaranteed character per complexity class (Windows
# default policy), rejection-sampled to avoid modulo bias. The charset
# excludes quotes and backslashes so the password survives verbatim as a
# process argument.
function New-OsUserPassword {
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghjkmnpqrstuvwxyz', '23456789', '!#$%&*+-=?@^_.')
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $next = {
            param([int]$Max)
            $bytes = New-Object byte[] 1
            do { $rng.GetBytes($bytes) } while ($bytes[0] -ge (256 - (256 % $Max)))
            return $bytes[0] % $Max
        }
        $chars = New-Object 'System.Collections.Generic.List[char]'
        foreach ($set in $sets) { $chars.Add($set[(& $next $set.Length)]) }
        $all = -join $sets
        while ($chars.Count -lt 24) { $chars.Add($all[(& $next $all.Length)]) }
        for ($index = $chars.Count - 1; $index -gt 0; $index--) {
            $swap = & $next ($index + 1)
            $held = $chars[$index]; $chars[$index] = $chars[$swap]; $chars[$swap] = $held
        }
        return -join $chars
    } finally {
        $rng.Dispose()
    }
}

function New-OsUserAccount {
    param([string]$Username, [string]$Password, [string]$Tool)
    $output = Invoke-OsUserNative -FilePath net.exe -NativeArgs @('user', $Username, $Password, '/add', '/expires:never', '/passwordchg:no')
    if ($LASTEXITCODE -ne 0) { throw "Failed to create OS user '$Username': $output" }
    # net user /add assigns the default local Users membership. Avoid passing
    # the localized group name to net localgroup on non-English Windows.
    $output = Invoke-OsUserNative -FilePath net.exe -NativeArgs @('user', $Username, "/comment:multi-cli owned sandbox user for $Tool")
    if ($LASTEXITCODE -ne 0) { throw "Failed to mark OS user '$Username' as multi-cli-owned: $output" }
}

# Grant the sandbox user Modify on a state tree it must read/write through
# junctions (the profile dir, and the operator's shared root).
function Grant-OsUserAccess {
    param([string]$Path, [string]$Username)
    $output = Invoke-OsUserNative -FilePath icacls.exe -NativeArgs @($Path, '/grant', "${Username}:(OI)(CI)M", '/T')
    if ($LASTEXITCODE -ne 0) { throw "Failed to grant OS user '$Username' access to '$Path': $output" }
}

# Provision the sandbox user for a profile. Idempotent: an existing user is
# adopted only when the profile's ownership record proves multi-cli created
# it. Elevation is checked BEFORE any creation attempt. Returns the username.
function Initialize-OsUserIsolation {
    param($Adapter, [string]$ProfileDir)
    Assert-OsUserWindows -Platform (Get-OsUserPlatform)
    $metadata = Get-OsUserProfileMetadata -Adapter $Adapter -ProfileDir $ProfileDir
    $username = Get-OsUserName -Tool $Adapter.id -ProfileId $metadata.profileId
    if (Test-OsUserExists -Username $username) {
        $record = Assert-OsUserOwnership -ProfileDir $ProfileDir
        if ($null -eq $record) {
            throw "OS user '$username' already exists but is not recorded as multi-cli-owned in '$ProfileDir'; refusing to touch it."
        }
        return $username
    }
    Assert-OsUserElevated -Tool $Adapter.id -ProfileName (Split-Path $ProfileDir -Leaf)
    Import-OsUserCredentialStore
    $password = New-OsUserPassword
    $credentialTarget = Get-OsUserCredentialTarget -Username $username
    New-OsUserAccount -Username $username -Password $password -Tool $Adapter.id
    $hasCredential = $false
    try {
        Set-MultiCliCredential -Target $credentialTarget -Secret $password
        $hasCredential = $true
        Write-OsUserOwnership -ProfileDir $ProfileDir -Tool $Adapter.id -ProfileId $metadata.profileId -Username $username
        Grant-OsUserAccess -Path $ProfileDir -Username $username
        return $username
    } catch {
        if ($hasCredential) { Remove-MultiCliCredential -Target $credentialTarget | Out-Null }
        Remove-Item -LiteralPath (Join-Path $ProfileDir '.osuser.json'), (Join-Path $ProfileDir '.osuser.json.tmp') -Force -ErrorAction SilentlyContinue
        $null = Invoke-OsUserNative -FilePath net.exe -NativeArgs @('user', $username, '/delete')
        throw
    } finally {
        $password = $null
    }
}

# --- Shared-state wiring -------------------------------------------------------

# Operator-side shared root: the adapter's native windows root, tokens
# expanded via the launcher's Resolve-PathToken contract.
function Get-OsUserSharedRoot {
    param($Adapter)
    $normalState = Get-OsUserProperty -Object $Adapter -Name 'normalState'
    $roots = Get-OsUserProperty -Object $normalState -Name 'root'
    $root = Get-OsUserProperty -Object $roots -Name 'windows'
    if (-not $root) { throw "Adapter '$($Adapter.id)' has no normal-state root for windows." }
    return [System.IO.Path]::GetFullPath((Resolve-PathToken $root))
}

# The same root as seen from the sandbox user's home tree: home tokens are
# mapped onto the sandbox home instead of the operator's environment.
function Get-OsUserSandboxRoot {
    param($Adapter, [string]$SandboxHome)
    $normalState = Get-OsUserProperty -Object $Adapter -Name 'normalState'
    $roots = Get-OsUserProperty -Object $normalState -Name 'root'
    $root = Get-OsUserProperty -Object $roots -Name 'windows'
    if (-not $root) { throw "Adapter '$($Adapter.id)' has no normal-state root for windows." }
    $mapped = $root -replace '(?i)%APPDATA%', (Join-Path $SandboxHome 'AppData\Roaming')
    $mapped = $mapped -replace '(?i)%LOCALAPPDATA%', (Join-Path $SandboxHome 'AppData\Local')
    $mapped = $mapped -replace '(?i)%USERPROFILE%', $SandboxHome
    $mapped = $mapped -replace '\$HOME', $SandboxHome
    return [System.IO.Path]::GetFullPath($mapped)
}

# Junction (directories) or hardlink (files) one path, mirroring the
# file-overlay runtime's no-copy-fallback rule.
function New-OsUserLink {
    param([string]$Source, [string]$Destination, [string]$Label)
    $parent = Split-Path -Parent $Destination
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $itemType = if (Test-Path -LiteralPath $Source -PathType Container) { 'Junction' } else { 'HardLink' }
    try {
        New-Item -ItemType $itemType -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
    } catch {
        throw "Cannot link $Label '$Destination' to '$Source': $($_.Exception.Message)"
    }
}

# Link every declared shared/session path from the sandbox user's state root
# into the operator's shared root, creating missing sources first. An
# existing destination (already wired, or real data written by the sandbox
# user) is left untouched: clobbering real state is worse than skipping.
function Add-OsUserStateLinks {
    param($Adapter, [string]$SharedRoot, [string]$SandboxRoot)
    $normalState = Get-OsUserProperty -Object $Adapter -Name 'normalState'
    $filePaths = @(Get-OsUserProperty -Object $normalState -Name 'filePaths')
    $declared = @(Get-OsUserProperty -Object $normalState -Name 'sharedPaths') + @(Get-OsUserProperty -Object $normalState -Name 'sessionPaths')
    foreach ($relativePath in $declared) {
        if (-not $relativePath) { continue }
        $windowsRelative = $relativePath -replace '/', '\'
        $source = Join-Path $SharedRoot $windowsRelative
        $sourceParent = Split-Path -Parent $source
        if ($sourceParent) { New-Item -ItemType Directory -Force -Path $sourceParent | Out-Null }
        if (-not (Test-Path -LiteralPath $source)) {
            if ($filePaths -contains $relativePath) {
                New-Item -ItemType File -Force -Path $source | Out-Null
            } else {
                New-Item -ItemType Directory -Force -Path $source | Out-Null
            }
        }
        $destination = Join-Path $SandboxRoot $windowsRelative
        if (Test-Path -LiteralPath $destination) { continue }
        New-OsUserLink -Source $source -Destination $destination -Label 'shared state'
    }
}

# The sandbox user's home from the ProfileList registry, or $null when the
# profile has not materialized yet (fresh user, never logged on).
function Get-OsUserSandboxHome {
    param([string]$Username)
    try {
        $sid = (New-Object Security.Principal.NTAccount($Username)).Translate([Security.Principal.SecurityIdentifier]).Value
        $item = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -Name ProfileImagePath -ErrorAction Stop
        if ($item.ProfileImagePath) { return $item.ProfileImagePath }
    } catch {
        # Unknown user or no ProfileList entry: both mean "no home yet".
    }
    return $null
}

function New-OsUserAppxError {
    param([string]$Target, [string]$Username, [string]$Phase, [string]$Detail)
    $message = "Code: unsupported_appx_secondary_user`nCodex GUI AppX launch failed.`nPackage: $Target`nUser: $Username`nPhase: $Phase`nError: $Detail`nNormal user state modified: false"
    return New-Object InvalidOperationException($message)
}

# Register and activate the Store package inside the owned user's profile.
# The parent accepts success only when the returned PID has the expected SID
# and remains in the initiating interactive session.
function Invoke-OsUserAppxLaunch {
    param(
        [string]$Username,
        [string]$CredentialTarget,
        [string]$ProfileDir,
        [string]$Target,
        [int]$TimeoutSeconds = 120
    )
    if ($Target -notmatch '^appx:([^!]+)!(.+)$') {
        throw (New-OsUserAppxError -Target $Target -Username $Username -Phase 'resolve' -Detail 'The AppX target must contain a package family and application id.')
    }
    $packageFamilyName = $Matches[1]
    $aumid = "$packageFamilyName!$($Matches[2])"
    $expectedSessionId = (Get-Process -Id $PID -ErrorAction Stop).SessionId
    if ($expectedSessionId -le 0) {
        throw (New-OsUserAppxError -Target $aumid -Username $Username -Phase 'session-check' -Detail 'The launcher is not in an interactive Windows session.')
    }

    $scriptPath = Join-Path $ProfileDir '.osuser-appx.ps1'
    $resultPath = Join-Path $ProfileDir '.osuser-appx.json'
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    $familyLiteral = $packageFamilyName.Replace("'", "''")
    $aumidLiteral = $aumid.Replace("'", "''")
    $resultLiteral = $resultPath.Replace("'", "''")
    $script = @"
`$ErrorActionPreference = 'Stop'
`$phase = 'register'
try {
    `$package = Get-AppxPackage -PackageTypeFilter Main -ErrorAction SilentlyContinue |
        Where-Object { `$_.PackageFamilyName -eq '$familyLiteral' } | Select-Object -First 1
    if (-not `$package) {
        Add-AppxPackage -RegisterByFamilyName -MainPackage '$familyLiteral' -ErrorAction Stop
        `$package = Get-AppxPackage -PackageTypeFilter Main -ErrorAction Stop |
            Where-Object { `$_.PackageFamilyName -eq '$familyLiteral' } | Select-Object -First 1
    }
    if (-not `$package -or "`$(`$package.Status)" -ne 'Ok') { throw 'AppX registration is not healthy.' }

    `$phase = 'activate'
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("2E941141-7F97-4756-BA1D-9DECDE894A3D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IApplicationActivationManager {
    [PreserveSig]
    int ActivateApplication(
        [MarshalAs(UnmanagedType.LPWStr)] string aumid,
        [MarshalAs(UnmanagedType.LPWStr)] string arguments,
        int options,
        out uint processId);
}

public static class MultiCliAppxLauncher {
    [DllImport("ole32.dll", PreserveSig = true)]
    private static extern int CoCreateInstance(
        ref Guid classId, IntPtr outer, uint context, ref Guid interfaceId,
        [MarshalAs(UnmanagedType.Interface)] out IApplicationActivationManager manager);

    public static uint Activate(string aumid) {
        Guid classId = new Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C");
        Guid interfaceId = new Guid("2E941141-7F97-4756-BA1D-9DECDE894A3D");
        IApplicationActivationManager manager;
        Marshal.ThrowExceptionForHR(CoCreateInstance(ref classId, IntPtr.Zero, 4, ref interfaceId, out manager));
        uint processId;
        Marshal.ThrowExceptionForHR(manager.ActivateApplication(aumid, null, 0, out processId));
        return processId;
    }
}
'@
    [uint32]`$processId = [MultiCliAppxLauncher]::Activate('$aumidLiteral')
    @{ processId = `$processId } | ConvertTo-Json | Set-Content -LiteralPath '$resultLiteral' -Encoding UTF8
} catch {
    @{ phase = `$phase; error = `$_.Exception.Message; hresult = `$_.Exception.HResult } |
        ConvertTo-Json | Set-Content -LiteralPath '$resultLiteral' -Encoding UTF8
    exit 1
}
"@
    Set-Content -LiteralPath $scriptPath -Value $script -Encoding UTF8

    try {
        $helper = Start-OsUserWrapperProcess -Username $Username -CredentialTarget $CredentialTarget -WrapperPath $scriptPath
    } catch {
        throw (New-OsUserAppxError -Target $aumid -Username $Username -Phase 'register' -Detail $_.Exception.Message)
    }
    if (-not $helper) {
        throw (New-OsUserAppxError -Target $aumid -Username $Username -Phase 'register' -Detail 'The owned-user helper did not start.')
    }
    $waitMilliseconds = [Math]::Min([Math]::Max($TimeoutSeconds, 1), 120) * 1000
    if (-not $helper.WaitForExit($waitMilliseconds)) {
        throw (New-OsUserAppxError -Target $aumid -Username $Username -Phase 'activate' -Detail 'The owned-user helper timed out.')
    }
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw (New-OsUserAppxError -Target $aumid -Username $Username -Phase 'activate' -Detail 'The owned-user helper returned no result.')
    }
    try {
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    } catch {
        throw (New-OsUserAppxError -Target $aumid -Username $Username -Phase 'activate' -Detail 'The owned-user helper returned an invalid result.')
    }
    $errorText = [string](Get-OsUserProperty -Object $result -Name 'error')
    $processId = Get-OsUserProperty -Object $result -Name 'processId'
    if ($errorText -or -not $processId) {
        $phase = [string](Get-OsUserProperty -Object $result -Name 'phase')
        if (-not $phase) { $phase = 'activate' }
        if (-not $errorText) { $errorText = 'The owned-user helper returned no process ID.' }
        throw (New-OsUserAppxError -Target $aumid -Username $Username -Phase $phase -Detail $errorText)
    }

    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Min([Math]::Max($TimeoutSeconds, 1), 15))
    do {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
        if ($process) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    $owner = if ($process) { Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction SilentlyContinue } else { $null }
    $expectedSid = (New-Object Security.Principal.NTAccount($Username)).Translate([Security.Principal.SecurityIdentifier]).Value
    if (-not $owner -or $owner.ReturnValue -ne 0 -or $owner.Sid -ne $expectedSid) {
        throw (New-OsUserAppxError -Target $aumid -Username $Username -Phase 'owner-check' -Detail 'The activated process does not belong to the owned user.')
    }
    if ([int]$process.SessionId -ne $expectedSessionId) {
        throw (New-OsUserAppxError -Target $aumid -Username $Username -Phase 'session-check' -Detail "The activated process used session $($process.SessionId), expected $expectedSessionId.")
    }

    do {
        $guiProcess = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($guiProcess -and -not $guiProcess.HasExited -and $guiProcess.MainWindowHandle -ne 0) { break }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $guiProcess -or $guiProcess.HasExited -or $guiProcess.MainWindowHandle -eq 0) {
        throw (New-OsUserAppxError -Target $aumid -Username $Username -Phase 'activate' -Detail 'The activated process did not produce a visible GUI window.')
    }
    Start-Sleep -Milliseconds 1000
    $guiProcess = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $guiProcess -or $guiProcess.HasExited -or $guiProcess.MainWindowHandle -eq 0) {
        throw (New-OsUserAppxError -Target $aumid -Username $Username -Phase 'activate' -Detail 'The activated GUI process exited before launch verification completed.')
    }
    return 0
}

# --- Launch --------------------------------------------------------------------

# The wrapper runs inside the sandbox user's PowerShell process. Its base64
# payloads preserve arbitrary Unicode, spaces, percent signs, and exclamation
# marks without cmd.exe expansion or command-line interpolation.
function Get-OsUserWrapperContent {
    param(
        [string]$Binary,
        [string[]]$Arguments,
        $Environment,
        [string[]]$ClearEnvironment,
        [string]$LogPath,
        [string]$ExitCodePath
    )
    $utf8 = [Text.Encoding]::UTF8
    $binaryPayload = [Convert]::ToBase64String($utf8.GetBytes($Binary))
    $argumentPayloads = @($Arguments) | Where-Object { $null -ne $_ } | ForEach-Object {
        [Convert]::ToBase64String($utf8.GetBytes([string]$_))
    }
    $environmentPayloads = @()
    if ($null -ne $Environment) {
        $environmentPayloads = @($Environment.GetEnumerator() | ForEach-Object {
            [pscustomobject]@{
                Name = [Convert]::ToBase64String($utf8.GetBytes([string]$_.Key))
                Value = [Convert]::ToBase64String($utf8.GetBytes([string]$_.Value))
            }
        })
    }
    $clearPayloads = @($ClearEnvironment) | Where-Object { $_ } | ForEach-Object {
        [Convert]::ToBase64String($utf8.GetBytes([string]$_))
    }
    $payload = [ordered]@{
        binary = $binaryPayload
        arguments = $argumentPayloads
        environment = $environmentPayloads
        clearEnvironment = $clearPayloads
        logPath = [Convert]::ToBase64String($utf8.GetBytes($LogPath))
        exitCodePath = [Convert]::ToBase64String($utf8.GetBytes($ExitCodePath))
    } | ConvertTo-Json -Compress
    $payloadLiteral = $payload.Replace("'", "''")
    return @"
`$ErrorActionPreference = 'Stop'
`$utf8 = [Text.Encoding]::UTF8
function Decode { param([string]`$Value) return `$utf8.GetString([Convert]::FromBase64String(`$Value)) }
`$payload = '$payloadLiteral' | ConvertFrom-Json
foreach (`$name in @(`$payload.clearEnvironment)) {
    if (`$null -eq `$name) { continue }
    `$decodedName = Decode -Value ([string]`$name)
    if (`$decodedName.Length -gt 0) { [Environment]::SetEnvironmentVariable(`$decodedName, `$null, 'Process') }
}
foreach (`$entry in @(`$payload.environment)) {
    if (`$null -eq `$entry -or `$null -eq `$entry.Name) { continue }
    `$decodedName = Decode -Value ([string]`$entry.Name)
    if (`$decodedName.Length -gt 0) { [Environment]::SetEnvironmentVariable(`$decodedName, (Decode -Value ([string]`$entry.Value)), 'Process') }
}
`$arguments = @(`$payload.arguments | Where-Object { `$null -ne `$_ } | ForEach-Object { Decode -Value ([string]`$_) })
& (Decode -Value `$payload.binary) @arguments *> (Decode -Value `$payload.logPath)
`$exitCode = if (`$null -eq `$LASTEXITCODE) { 0 } else { `$LASTEXITCODE }
Set-Content -LiteralPath (Decode -Value `$payload.exitCodePath) -Value `$exitCode -Encoding ASCII
exit `$exitCode
"@
}

# Expand the six adapter placeholders against the launch-time paths; the
# runtime view for osUser profiles is the sandbox user's state root.
function Expand-OsUserValue {
    param(
        [string]$Value,
        [string]$ProfileDir,
        [string]$ProfileId,
        [string]$AuthDir,
        [string]$RuntimeRoot,
        [string]$SharedRoot
    )
    return $Value.Replace('{profileDir}', $ProfileDir).
        Replace('{profileId}', $ProfileId).
        Replace('{authDir}', $AuthDir).
        Replace('{runtimeRoot}', $RuntimeRoot).
        Replace('{sharedStateRoot}', $SharedRoot).
        Replace('{realHome}', $env:USERPROFILE)
}

# Plan one osUser launch. Pure: derives the identity and builds the wrapper
# content and task coordinates without provisioning or touching the system,
# so the exact task/wrapper contract is testable on a non-elevated host.
# Invoke-OsUserLaunch is the executing counterpart.
function Get-OsUserLaunchPlan {
    param($Adapter, [string]$ProfileDir, [string]$Binary, [string[]]$BinaryArgs, [string]$SandboxHome)
    Assert-OsUserWindows -Platform (Get-OsUserPlatform)
    $metadata = Get-OsUserProfileMetadata -Adapter $Adapter -ProfileDir $ProfileDir
    $username = Get-OsUserName -Tool $Adapter.id -ProfileId $metadata.profileId
    if (-not $SandboxHome) {
        $SandboxHome = Get-OsUserSandboxHome -Username $username
        if (-not $SandboxHome) { $SandboxHome = Join-Path $env:SystemDrive "Users\$username" }
    }
    $sharedRoot = Get-OsUserSharedRoot -Adapter $Adapter
    $sandboxRoot = Get-OsUserSandboxRoot -Adapter $Adapter -SandboxHome $SandboxHome
    $environment = [ordered]@{}
    $isolation = Get-OsUserProperty -Object $Adapter -Name 'isolation'
    $envBlock = Get-OsUserProperty -Object $isolation -Name 'env'
    if ($null -ne $envBlock) {
        foreach ($property in $envBlock.PSObject.Properties) {
            $environment[$property.Name] = Expand-OsUserValue -Value $property.Value -ProfileDir $ProfileDir -ProfileId $metadata.profileId -AuthDir (Join-Path $ProfileDir 'auth') -RuntimeRoot $sandboxRoot -SharedRoot $sharedRoot
        }
    }
    $environment['MULTICLI_PROFILE_ID'] = $metadata.profileId
    $logPath = Join-Path $ProfileDir '.osuser-launch.log'
    $exitCodePath = Join-Path $ProfileDir '.osuser-launch.exitcode'
    $wrapperPath = Join-Path $ProfileDir '.osuser-task.ps1'
    $clearEnvironment = @(Get-OsUserProperty -Object $isolation -Name 'clearEnv')
    $wrapperContent = Get-OsUserWrapperContent -Binary $Binary -Arguments $BinaryArgs -Environment $environment -ClearEnvironment $clearEnvironment -LogPath $logPath -ExitCodePath $exitCodePath
    return [pscustomobject]@{
        Binary = $Binary
        Arguments = @($BinaryArgs)
        Environment = $environment
        ClearEnvironment = $clearEnvironment
        Mode = Get-OsUserProperty -Object $isolation -Name 'mode'
        Username = $username
        CredentialTarget = Get-OsUserCredentialTarget -Username $username
        SandboxHome = $SandboxHome
        SharedRoot = $sharedRoot
        SandboxRoot = $sandboxRoot
        WrapperPath = $wrapperPath
        WrapperContent = $wrapperContent
        LogPath = $logPath
        ExitCodePath = $exitCodePath
    }
}

function New-OsUserCredential {
    param([string]$Username, [string]$CredentialTarget)
    Import-OsUserCredentialStore
    $password = Get-MultiCliCredential -Target $CredentialTarget
    if ([string]::IsNullOrEmpty($password)) {
        throw "OS-user credential for '$Username' is missing from Credential Manager at '$CredentialTarget'. Recreate the profile."
    }
    try {
        $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
        return New-Object Management.Automation.PSCredential(".\$Username", $securePassword)
    } finally {
        $password = $null
    }
}

function Start-OsUserWrapperProcess {
    param([string]$Username, [string]$CredentialTarget, [string]$WrapperPath)
    $credential = New-OsUserCredential -Username $Username -CredentialTarget $CredentialTarget
    $powershellPath = Join-Path $PSHOME 'powershell.exe'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$WrapperPath`""
    return Start-Process -FilePath $powershellPath -ArgumentList $arguments -Credential $credential -LoadUserProfile -PassThru -WindowStyle Hidden
}

# Materialize the user's Windows profile through a credential-bound no-op.
# Start-Process receives the password via PSCredential rather than native argv.
function Initialize-OsUserSandboxHome {
    param([string]$Username, [string]$CredentialTarget, [int]$TimeoutSeconds = 120)
    $process = Start-OsUserInteractiveProcess -Username $Username -CredentialTarget $CredentialTarget -Binary $env:ComSpec -BinaryArgs @('/d', '/c', 'exit 0')
    if (-not $process) { throw "Could not start the profile bootstrap process for OS user '$Username'." }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not (Get-OsUserSandboxHome -Username $Username)) {
        if ((Get-Date) -gt $deadline) {
            throw "The profile directory for OS user '$Username' did not materialize within $TimeoutSeconds seconds. Check 'net user $Username' and the Windows user profile event log."
        }
        Start-Sleep -Milliseconds 500
    }
}

# Launch $Binary as the profile's sandbox user. Foreground mode uses the
# generated wrapper to report the child exit code; detached mode returns once
# the credential-bound process starts.
function Start-OsUserInteractiveProcess {
    param(
        [string]$Username,
        [string]$CredentialTarget,
        [string]$Binary,
        [string[]]$BinaryArgs
    )
    $credential = New-OsUserCredential -Username $Username -CredentialTarget $CredentialTarget
    $parameters = @{
        FilePath = $Binary
        Credential = $credential
        LoadUserProfile = $true
        PassThru = $true
    }
    if (@($BinaryArgs).Count -gt 0) { $parameters.ArgumentList = @($BinaryArgs) }
    $process = Start-Process @parameters
    return [bool]$process
}

function Invoke-OsUserLaunch {
    param(
        $Adapter,
        [string]$ProfileDir,
        [string]$Binary,
        [string[]]$BinaryArgs,
        [string]$SandboxHome,
        [int]$TimeoutSeconds = 7200
    )
    $username = Initialize-OsUserIsolation -Adapter $Adapter -ProfileDir $ProfileDir
    if ($Binary -like 'appx:*') {
        return Invoke-OsUserAppxLaunch -Username $username -CredentialTarget (Get-OsUserCredentialTarget -Username $username) -ProfileDir $ProfileDir -Target $Binary -TimeoutSeconds ([Math]::Min($TimeoutSeconds, 120))
    }
    if (-not $SandboxHome) {
        $SandboxHome = Get-OsUserSandboxHome -Username $username
        if (-not $SandboxHome) {
            $record = Get-OsUserOwnership -ProfileDir $ProfileDir
            Initialize-OsUserSandboxHome -Username $username -CredentialTarget $record.credentialTarget
            $SandboxHome = Get-OsUserSandboxHome -Username $username
        }
    }
    $plan = Get-OsUserLaunchPlan -Adapter $Adapter -ProfileDir $ProfileDir -Binary $Binary -BinaryArgs $BinaryArgs -SandboxHome $SandboxHome
    if ($plan.Mode -eq 'detached') {
        if (-not (Start-OsUserInteractiveProcess -Username $username -CredentialTarget $plan.CredentialTarget -Binary $Binary -BinaryArgs $BinaryArgs)) {
            throw "OS-user launch of '$Binary' did not start."
        }
        return 0
    }
    $normalState = Get-OsUserProperty -Object $Adapter -Name 'normalState'
    $declared = @(Get-OsUserProperty -Object $normalState -Name 'sharedPaths') + @(Get-OsUserProperty -Object $normalState -Name 'sessionPaths') | Where-Object { $_ }
    if (@($declared).Count -gt 0) {
        Assert-OsUserElevated -Tool $Adapter.id -ProfileName (Split-Path $ProfileDir -Leaf)
        New-Item -ItemType Directory -Force -Path $plan.SharedRoot | Out-Null
        Add-OsUserStateLinks -Adapter $Adapter -SharedRoot $plan.SharedRoot -SandboxRoot $plan.SandboxRoot
        Grant-OsUserAccess -Path $plan.SharedRoot -Username $username
    }
    Set-Content -LiteralPath $plan.WrapperPath -Value $plan.WrapperContent -Encoding UTF8
    Remove-Item -LiteralPath $plan.LogPath, $plan.ExitCodePath -Force -ErrorAction SilentlyContinue
    $process = Start-OsUserWrapperProcess -Username $username -CredentialTarget $plan.CredentialTarget -WrapperPath $plan.WrapperPath
    if (-not $process) { throw "OS-user launch of '$Binary' did not start." }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not (Test-Path -LiteralPath $plan.ExitCodePath)) {
        if ((Get-Date) -gt $deadline) {
            if (-not $process.HasExited) { $process.Kill() }
            throw "OS-user launch of '$Binary' did not finish within $TimeoutSeconds seconds; the process was stopped. See '$($plan.LogPath)'."
        }
        Start-Sleep -Milliseconds 500
    }
    $exitCodeText = (Get-Content -LiteralPath $plan.ExitCodePath -Raw).Trim()
    if ($exitCodeText -notmatch '^\d+$') {
        throw "OS-user launch of '$Binary' wrote a malformed exit-code file '$($plan.ExitCodePath)'. See '$($plan.LogPath)'."
    }
    return [int]$exitCodeText
}

# --- Deletion (profile delete integration) --------------------------------------

# Remove everything multi-cli owns for this profile: any legacy scheduled task,
# the sandbox user, the Credential Manager password, and the ownership record.
# No record = nothing owned = a safe no-op (any profile delete can call it).
# Foreign records are refused before the elevation gate. Returns $true when
# an owned user was removed.
function Remove-OsUserIsolation {
    param([string]$ProfileDir)
    $record = Get-OsUserOwnership -ProfileDir $ProfileDir
    if ($null -eq $record) { return $false }
    $record = Assert-OsUserOwnership -ProfileDir $ProfileDir
    Assert-OsUserWindows -Platform (Get-OsUserPlatform)
    Assert-OsUserElevated -Tool $record.tool -ProfileName (Split-Path $ProfileDir -Leaf)
    Import-OsUserCredentialStore
    $null = Invoke-OsUserNative -FilePath schtasks.exe -NativeArgs @('/query', '/tn', $record.taskName)
    if ($LASTEXITCODE -eq 0) {
        $output = Invoke-OsUserNative -FilePath schtasks.exe -NativeArgs @('/delete', '/tn', $record.taskName, '/f')
        if ($LASTEXITCODE -ne 0) { throw "Failed to delete scheduled task '$($record.taskName)': $output" }
    }
    if (Test-OsUserExists -Username $record.username) {
        $output = Invoke-OsUserNative -FilePath net.exe -NativeArgs @('user', $record.username, '/delete')
        if ($LASTEXITCODE -ne 0) { throw "Failed to delete OS user '$($record.username)': $output" }
    }
    Remove-MultiCliCredential -Target $record.credentialTarget | Out-Null
    Remove-Item -LiteralPath (Join-Path $ProfileDir '.osuser.json') -Force
    return $true
}

Export-ModuleMember -Function Get-OsUserName, Get-OsUserTaskName, Get-OsUserCredentialTarget, Get-OsUserOwnership, Initialize-OsUserIsolation, Get-OsUserLaunchPlan, Invoke-OsUserLaunch, Remove-OsUserIsolation
