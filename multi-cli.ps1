<#
.SYNOPSIS
  multi-cli.ps1 -- Run multiple sandboxed profiles of supported CLIs, IDEs, and GUI apps.

.DESCRIPTION
  Adapter-driven launcher: each supported tool ships an adapter.json describing
  how to find its binary and how to isolate its state. multi-cli reads the
  adapter and applies its isolation strategy: env, userDataDir, redirectHome,
  appdata, sandboxUser, or accountOverlay (schema-v2).

  USAGE
    multi-cli new <tool>/<name>      Create a new profile
    multi-cli launch <tool>/<name>   Launch the profile (binary args after `--`)
    multi-cli continue <tool> <src> <dest>   Copy a chat session between profiles
    multi-cli list                   List all profiles
    multi-cli tools                  List supported tools and detect installs
    multi-cli doctor                 Diagnose environment
    multi-cli help                   Full command reference
#>

param (
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$Cmd,

    [Parameter(Position = 1, Mandatory = $false)]
    [string]$Arg1,

    [Parameter(Position = 2, Mandatory = $false)]
    [string]$Arg2,

    [Alias('i')]
    [switch]$WholeRoot,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardArgs
)

$ErrorActionPreference = 'Stop'
$VERSION = '1.0.0'
$UTF8_BOM_BYTES = [byte[]](0xEF, 0xBB, 0xBF)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$MultiCliLauncherPath = $MyInvocation.MyCommand.Definition
$ToolsDir  = if ($env:MULTICLI_TOOLS_DIR) { $env:MULTICLI_TOOLS_DIR } else { Join-Path $ScriptDir 'ai-tools' }
$BASE = if ($env:MULTICLI_HOME) { $env:MULTICLI_HOME } else { Join-Path $env:USERPROFILE 'MultiCliProfiles' }

# Locate a lib module next to this launcher, falling back to the tools dir
# parent when MULTICLI_TOOLS_DIR points elsewhere (tests).
function Resolve-MultiCliModulePath {
    param([string]$ModuleName)
    $modulePath = Join-Path $ScriptDir "lib\$ModuleName"
    if (-not (Test-Path -LiteralPath $modulePath)) {
        $modulePath = Join-Path (Split-Path -Parent $ToolsDir) "lib\$ModuleName"
    }
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Module '$ModuleName' not found for $ToolsDir. Reinstall multi-cli."
    }
    return $modulePath
}

# Import the validation/runtime modules once per process; the Get-Command
# guard keeps repeated imports cheap.
function Import-AdapterValidationModule {
    if (Get-Command Test-AdapterManifest -ErrorAction SilentlyContinue) { return }
    Import-Module (Resolve-MultiCliModulePath 'MultiCli.AdapterValidation.psm1') -Force
}

function Import-RuntimeModule {
    if (Get-Command Get-AccountOverlayLaunchPlan -ErrorAction SilentlyContinue) { return }
    Import-Module (Resolve-MultiCliModulePath 'MultiCli.Runtime.psm1') -Force
}

# =============================================================================
# Adapter loading
# =============================================================================

# Parse every adapter under the tools dir, warning and skipping invalid ones.
function Get-Adapters {
    Import-AdapterValidationModule
    if (-not (Test-Path $ToolsDir)) { return @() }
    $adapters = @()
    foreach ($dir in Get-ChildItem -Directory -Path $ToolsDir) {
        $manifest = Join-Path $dir.FullName 'adapter.json'
        if (-not (Test-Path $manifest)) { continue }
        $validationErrors = @(Test-AdapterManifest -ManifestPath $manifest -ExpectedId $dir.Name)
        if ($validationErrors.Count -gt 0) {
            Write-Warning "Invalid adapter '$($dir.Name)': $($validationErrors -join '; ')"
            continue
        }
        $adapters += (Get-Content $manifest -Raw | ConvertFrom-Json)
    }
    return $adapters
}

# Parse one adapter by id; throws for unknown ids and invalid manifests.
# Every command that touches adapter data goes through this first.
function Get-Adapter {
    param([string]$ToolId)
    Test-ToolId $ToolId
    Import-AdapterValidationModule
    $manifest = Join-Path (Join-Path $ToolsDir $ToolId) 'adapter.json'
    if (-not (Test-Path $manifest)) { throw "Unknown tool '$ToolId'. Run: multi-cli tools" }
    $validationErrors = @(Test-AdapterManifest -ManifestPath $manifest -ExpectedId $ToolId)
    if ($validationErrors.Count -gt 0) {
        throw "Invalid adapter '$ToolId': $($validationErrors -join '; ')"
    }
    return Get-Content $manifest -Raw | ConvertFrom-Json
}

# Expand the path tokens adapters use for per-OS roots: $HOME and %VARS%.
function Resolve-PathToken {
    param([string]$Path)
    if (-not $Path) { return $Path }
    $expanded = $Path -replace '\$HOME', $env:USERPROFILE.Replace('\', '\\')
    return [Environment]::ExpandEnvironmentVariables($expanded)
}

# First binary candidate that exists (path or PATH lookup); $null when none
# resolve. MULTICLI_OVERRIDE_BINARY wins.
function Test-UriProtocol {
    param([string]$Scheme)
    $key = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey($Scheme)
    if ($null -eq $key) { return $false }
    try {
        if ($null -eq $key.GetValue('URL Protocol', $null)) { return $false }
        $command = $key.OpenSubKey('shell\open\command')
        if ($null -eq $command) { return $false }
        try { return -not [string]::IsNullOrWhiteSpace([string]$command.GetValue('')) } finally { $command.Dispose() }
    } finally { $key.Dispose() }
}

function Test-UriBinary {
    param([string]$Binary)
    return ($Binary -match '(?i)[\\/]explorer\.exe$')
}

function Get-AppxAdapterBinary {
    param([string]$PackageTarget)
    if ($PackageTarget -notmatch '^([^!]+)!(.+)$') { return $null }
    $packageName = $Matches[1]
    $applicationId = $Matches[2]
    $package = Get-AppxPackage -Name $packageName -PackageTypeFilter Main -ErrorAction SilentlyContinue |
        Where-Object { $_.SignatureKind -eq 'Store' } |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($null -eq $package) { return $null }
    $manifest = Get-AppxPackageManifest -Package $package
    $application = @($manifest.Package.Applications.Application) |
        Where-Object { $_.Id -eq $applicationId } | Select-Object -First 1
    if ($null -eq $application) { return $null }
    return "appx:$($package.PackageFamilyName)!$applicationId"
}

function Find-AdapterBinary {
    param($Adapter)
    if ($env:MULTICLI_OVERRIDE_BINARY) { return $env:MULTICLI_OVERRIDE_BINARY }
    $candidates = @()
    if ($Adapter.binary.windows) { $candidates += $Adapter.binary.windows }
    foreach ($candidate in $candidates) {
        if ($candidate -like 'appx:*') {
            $appxBinary = Get-AppxAdapterBinary -PackageTarget $candidate.Substring(5)
            if ($appxBinary) { return $appxBinary }
            continue
        }
        if ($candidate -like 'uri:*') {
            $scheme = $candidate.Substring(4)
            if (Test-UriProtocol -Scheme $scheme) { return (Get-Command explorer.exe).Source }
            continue
        }
        $resolved = Resolve-PathToken $candidate
        if (Test-Path $resolved -ErrorAction SilentlyContinue) { return $resolved }
        $command = Get-Command $resolved -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    return $null
}

# =============================================================================
# Session continuation
# =============================================================================

$SESSION_RESERVED_ENDPOINT = 'base'

# Skip automatic session seeding when the base state exceeds this size.
$SEED_MAX_BYTES = 500 * 1024 * 1024

# Null-safe PSObject property getter: adapters arrive from ConvertFrom-Json,
# so an absent section is a missing property rather than a null-valued one.
function Get-ObjectPropertySafe {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Test-AdapterNeedsOsUser {
    param($Adapter)
    $account = Get-ObjectPropertySafe -Object $Adapter -Name 'account'
    return (Get-ObjectPropertySafe -Object $account -Name 'mechanism') -eq 'osUserCredentialStore'
}

function Get-AdapterSystemHome {
    param($Adapter)
    if ((Get-ObjectPropertySafe -Object $Adapter -Name 'schemaVersion') -eq 2) {
        $normalState = Get-ObjectPropertySafe -Object $Adapter -Name 'normalState'
        $roots = Get-ObjectPropertySafe -Object $normalState -Name 'root'
        $root = Get-ObjectPropertySafe -Object $roots -Name 'windows'
        if (-not $root) { return $null }
        return [System.IO.Path]::GetFullPath((Resolve-PathToken $root))
    }
    if ($Adapter.share -and $Adapter.share.systemHome) {
        return [System.IO.Path]::GetFullPath((Resolve-PathToken $Adapter.share.systemHome))
    }
    return $null
}

function Resolve-SessionEndpoint {
    param($Adapter, [string]$Tool, [string]$Name)
    if ($Name -eq $SESSION_RESERVED_ENDPOINT) {
        $sysHome = Get-AdapterSystemHome $Adapter
        if (-not $sysHome) { throw "Tool '$Tool' has no system home; 'base' endpoint unavailable" }
        return $sysHome
    }
    Test-ProfileName $Name
    return Get-ProfileDir $Tool $Name
}

# Throw if an adapter-declared relative path is unsafe to join under a root:
# absolute, drive-qualified, or containing a '..' component.
function Assert-RelPathSafe {
    param([string]$Path, [string]$Kind, [string]$ToolId)
    if (-not $Path) { return }
    $norm = $Path -replace '\\', '/'
    if ($norm -match '^/' -or $norm -match '^[a-zA-Z]:') {
        throw "Adapter bug: $Kind '$Path' is absolute/drive-qualified for '$ToolId'."
    }
    if ("/$norm/" -match '/\.\./') {
        throw "Adapter bug: $Kind '$Path' contains '..' for '$ToolId'."
    }
}

function Test-SessionAdapterBug {
    param($Adapter)
    $paths = @($Adapter.session.paths)
    $creds = @($Adapter.session.credentials)
    foreach ($cred in $creds) {
        Assert-RelPathSafe -Path $cred -Kind 'credential' -ToolId $Adapter.id
    }
    foreach ($path in $paths) {
        if (-not $path) { continue }
        Assert-RelPathSafe -Path $path -Kind 'session path' -ToolId $Adapter.id
        $normPath = ($path -replace '\\', '/').TrimEnd('/')
        foreach ($cred in $creds) {
            if (-not $cred) { continue }
            $normCred = ($cred -replace '\\', '/').TrimEnd('/')
            if ($normPath -eq $normCred -or
                $normPath -like "$normCred/*" -or
                $normCred -like "$normPath/*") {
                throw "Adapter bug: session path '$path' overlaps credential '$cred' for '$($Adapter.id)'. Refusing to copy credentials."
            }
        }
    }
}

# True if any component of the dest-relative path matches a credential entry
# name, blocking files nested inside a credential-named directory.
function Test-IsCredentialName {
    param([string]$RelativePath, [string[]]$Credentials)
    $components = ($RelativePath -replace '\\', '/').Split('/') | Where-Object { $_ }
    foreach ($comp in $components) {
        foreach ($cred in $Credentials) {
            if (-not $cred) { continue }
            $credLeaf = Split-Path ($cred -replace '/', '\') -Leaf
            if ($comp -eq $credLeaf) { return $true }
        }
    }
    return $false
}

# True when a filesystem item is a symlink/junction/reparse point.
function Test-IsReparsePoint {
    param($Item)
    if ($Item.LinkType) { return $true }
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

# Return regular files below a session entry without following reparse-point
# directories. An explicit stack is required because Get-ChildItem -Recurse
# traverses nested junctions before their child files can be identified as links.
function Get-SessionFilesNoReparse {
    param([string]$Root)
    $files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    $stack = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $stack.Push((Get-Item -LiteralPath $Root -Force))
    while ($stack.Count -gt 0) {
        $directory = $stack.Pop()
        foreach ($item in (Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue)) {
            if (Test-IsReparsePoint $item) { continue }
            if ($item.PSIsContainer) { $stack.Push($item); continue }
            $files.Add($item)
        }
    }
    return $files
}

# Copy every adapter-declared session entry (file or directory, merged
# per-file). Reparse points are skipped so credential targets never travel;
# Copied/Skipped are ref counters shared across the whole run.
function Copy-SessionEntry {
    param(
        [string]$Source,
        [string]$Destination,
        [bool]$NoMerge,
        [bool]$DryRun,
        [string[]]$Credentials,
        [string]$RelativeRoot,
        [ref]$Copied,
        [ref]$Skipped
    )
    $srcItem = Get-Item -LiteralPath $Source -Force -ErrorAction SilentlyContinue
    if (-not $srcItem -or (Test-IsReparsePoint $srcItem)) { return }
    if (-not $srcItem.PSIsContainer) {
        Copy-SessionFile -Source $Source -Destination $Destination -NoMerge $NoMerge -DryRun $DryRun -Copied $Copied -Skipped $Skipped
        return
    }
    $sourceRoot = [System.IO.Path]::GetFullPath($Source).TrimEnd('\', '/')
    foreach ($item in (Get-SessionFilesNoReparse -Root $sourceRoot)) {
        $relative = $item.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
        if (Test-IsCredentialName -RelativePath "$RelativeRoot/$relative" -Credentials $Credentials) { continue }
        $target = Join-Path $Destination $relative
        Copy-SessionFile -Source $item.FullName -Destination $target -NoMerge $NoMerge -DryRun $DryRun -Copied $Copied -Skipped $Skipped
    }
}

# Copy one file atomically (temp in dest dir, then move over) preserving the
# source mtime. Skips when dest is strictly newer, or equal mtime + equal size;
# repairs a truncated dest whose mtime matches but whose size differs.
function Copy-SessionFile {
    param(
        [string]$Source,
        [string]$Destination,
        [bool]$NoMerge,
        [bool]$DryRun,
        [ref]$Copied,
        [ref]$Skipped
    )
    if ((-not $NoMerge) -and (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        $src = Get-Item -LiteralPath $Source
        $dst = Get-Item -LiteralPath $Destination
        if ($dst.LastWriteTimeUtc -gt $src.LastWriteTimeUtc) { $Skipped.Value++; return }
        if ($dst.LastWriteTimeUtc -eq $src.LastWriteTimeUtc -and $dst.Length -eq $src.Length) {
            $Skipped.Value++; return
        }
    }
    if ($DryRun) {
        Write-Host "  would copy $Source -> $Destination"
        $Copied.Value++
        return
    }
    $parent = Split-Path -Parent $Destination
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $tmp = Join-Path $parent (".mcli-copy." + [System.IO.Path]::GetRandomFileName())
    Copy-Item -LiteralPath $Source -Destination $tmp -Force
    (Get-Item -LiteralPath $tmp).LastWriteTimeUtc = (Get-Item -LiteralPath $Source).LastWriteTimeUtc
    Move-Item -LiteralPath $tmp -Destination $Destination -Force
    $Copied.Value++
}

# Read one redirected line as UTF-8 bytes so BOM handling never depends on the
# host console code page.
function Read-RedirectedLine {
    param([IO.Stream]$InputStream = $([Console]::OpenStandardInput()))
    $bytes = New-Object 'System.Collections.Generic.List[byte]'
    while ($true) {
        $value = $InputStream.ReadByte()
        if ($value -lt 0 -or $value -eq 10) { break }
        if ($value -ne 13) { $bytes.Add([byte]$value) }
    }
    if ($value -lt 0 -and $bytes.Count -eq 0) { return $null }
    $offset = if ($bytes.Count -ge 3 -and
        $bytes[0] -eq $UTF8_BOM_BYTES[0] -and
        $bytes[1] -eq $UTF8_BOM_BYTES[1] -and
        $bytes[2] -eq $UTF8_BOM_BYTES[2]) { 3 } else { 0 }
    return (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes.ToArray(), $offset, $bytes.Count - $offset)
}

# multi-cli auth set|status|clear: manage a process-secret profile's
# credential in the OS store, keyed by the profile's stable profileId.
function Invoke-Auth {
    param([string]$Action, [string]$Spec)
    $profile = Split-ProfileSpec $Spec
    $adapter = Get-Adapter $profile.Tool
    if ($adapter.account.mechanism -ne 'processSecret') {
        throw "Tool '$($profile.Tool)' does not use a process-secret credential."
    }
    $profileDir = Get-ProfileDir $profile.Tool $profile.Name
    $metadataPath = Join-Path $profileDir '.profile.json'
    if (-not (Test-Path -LiteralPath $metadataPath)) { throw "Schema-v2 profile '$Spec' does not exist." }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $environmentVariable = $adapter.account.secret.environmentVariable
    $target = "multi-cli/$($adapter.id)/$($metadata.profileId)/$environmentVariable"
    Import-Module (Resolve-MultiCliModulePath 'MultiCli.CredentialStore.psm1') -Force
    switch ($Action) {
        'set' {
            $plainSecret = $null
            if ([Console]::IsInputRedirected) {
                $plainSecret = Read-RedirectedLine
                if ([string]::IsNullOrEmpty($plainSecret)) { throw 'Credential input was empty.' }
            } else {
                $secureSecret = Read-Host "Enter $environmentVariable for $Spec" -AsSecureString
                $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
                try {
                    $plainSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
                } finally {
                    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
                }
            }
            try {
                Set-MultiCliCredential -Target $target -Secret $plainSecret
            } finally {
                $plainSecret = $null
            }
            Write-Host "Stored credential for $Spec."
        }
        'status' {
            $present = Test-MultiCliCredential -Target $target
            Write-Host $(if ($present) { "Credential present for $Spec." } else { "No credential stored for $Spec." })
            if (-not $present) { exit 1 }
        }
        'clear' {
            Remove-MultiCliCredential -Target $target | Out-Null
            Write-Host "Cleared credential for $Spec."
        }
        default { throw 'Usage: multi-cli auth <set|status|clear> <tool>/<profile>' }
    }
}

# Throw if any schema-v2 session path is unsafe or overlaps a declared
# credential -- the same invariant Test-SessionAdapterBug enforces for
# schema-v1 adapters, read from the v2 field names.
function Test-IsolatedSessionAdapterBug {
    param($Adapter)
    $normalState = Get-ObjectPropertySafe -Object $Adapter -Name 'normalState'
    $paths = @($normalState.sessionPaths)
    $creds = @($Adapter.account.credentialFiles)
    foreach ($cred in $creds) {
        Assert-RelPathSafe -Path $cred -Kind 'credential' -ToolId $Adapter.id
    }
    foreach ($path in $paths) {
        if (-not $path) { continue }
        Assert-RelPathSafe -Path $path -Kind 'session path' -ToolId $Adapter.id
        $normPath = ($path -replace '\\', '/').TrimEnd('/')
        foreach ($cred in $creds) {
            if (-not $cred) { continue }
            $normCred = ($cred -replace '\\', '/').TrimEnd('/')
            if ($normPath -eq $normCred -or
                $normPath -like "$normCred/*" -or
                $normCred -like "$normPath/*") {
                throw "Adapter bug: session path '$path' overlaps credential '$cred' for '$($Adapter.id)'. Refusing to copy credentials."
            }
        }
    }
}

# multi-cli continue <tool> <src> <dest>: copy adapter-declared session state
# between endpoints ('base' = the tool's real home). Merge policy keeps the
# newer file; credential paths never travel. Schema-v2 tools already share
# sessions, so this is a no-op message there.
function Invoke-Continue {
    param([string]$Tool, [string]$SrcName, [string]$DestName, [bool]$NoMerge = $false, [bool]$DryRun = $false)
    if (-not $Tool -or -not $SrcName -or -not $DestName) {
        throw "Usage: multi-cli continue <tool> <src-profile> <dest-profile> [--no-merge] [--dry-run]"
    }
    $adapter = Get-Adapter $Tool

    if ((Get-ObjectPropertySafe -Object $adapter -Name 'schemaVersion') -eq 2) {
        # Isolated profiles share nothing, so continuation is a real copy
        # between them (and 'base'), exactly like legacy endpoints. Shared
        # schema-v2 profiles keep the no-op.
        if ($SrcName -eq $DestName) { throw "Source and destination must differ" }
        $srcDir  = Resolve-SessionEndpoint $adapter $Tool $SrcName
        $destDir = Resolve-SessionEndpoint $adapter $Tool $DestName
        if (-not (Test-Path $srcDir)) {
            throw "Source endpoint '$SrcName' not found at $srcDir. Nothing to continue from."
        }
        if (-not (Test-Path $destDir)) {
            throw "Destination profile '$DestName' does not exist. Create it with: multi-cli new $Tool/$DestName"
        }
        $srcIsolated  = Test-Path -LiteralPath (Join-Path $srcDir '.isolated')
        $destIsolated = Test-Path -LiteralPath (Join-Path $destDir '.isolated')
        if (-not $srcIsolated -and -not $destIsolated) {
            Write-Host "$($adapter.displayName) profiles already share conversations through the shared normal state; nothing to continue."
            return
        }
        $normalState = Get-ObjectPropertySafe -Object $adapter -Name 'normalState'
        $sessionPaths = @($normalState.sessionPaths)
        if ($sessionPaths.Count -eq 0) {
            throw "$($adapter.displayName) declares no session paths; nothing to continue."
        }
        Test-IsolatedSessionAdapterBug $adapter

        $sourceState = $srcDir
        $destinationState = $destDir
        $runtimeSubdir = Get-ObjectPropertySafe -Object $normalState -Name 'runtimeSubdir'
        if ($runtimeSubdir) {
            $sourceState = Join-Path $srcDir ($runtimeSubdir -replace '/', '\')
            $destinationState = Join-Path $destDir ($runtimeSubdir -replace '/', '\')
        }
        $credentials = @($adapter.account.credentialFiles)
        $copied = 0; $skipped = 0; $found = $false
        if ($DryRun) { Write-Host "Dry run -- no files will be written." }
        foreach ($entry in $sessionPaths) {
            if (-not $entry) { continue }
            if (Test-IsCredentialName -RelativePath $entry -Credentials $credentials) { continue }
            $src = Join-Path $sourceState ($entry -replace '/', '\')
            if (-not (Test-Path $src)) { continue }
            $found = $true
            $dst = Join-Path $destinationState ($entry -replace '/', '\')
            $c = [ref]$copied; $s = [ref]$skipped
            Copy-SessionEntry -Source $src -Destination $dst -NoMerge $NoMerge -DryRun $DryRun -Credentials $credentials -RelativeRoot $entry -Copied $c -Skipped $s
            $copied = $c.Value; $skipped = $s.Value
        }
        if (-not $found) {
            Write-Host "No session data found at source '$SrcName'. Nothing to continue."
            return
        }
        Write-Host "Continued ${Tool}: $SrcName -> $DestName ($copied copied, $skipped skipped (same-or-newer))"
        return
    }

    if (-not $adapter.session -or -not $adapter.session.portable) {
        $reason = if ($adapter.session) { $adapter.session.reason } else { '' }
        Write-Host "$($adapter.displayName) sessions are not portable: $reason" -ForegroundColor Yellow
        exit 1
    }
    if ($SrcName -eq $DestName) { throw "Source and destination must differ" }
    Test-SessionAdapterBug $adapter

    $srcDir  = Resolve-SessionEndpoint $adapter $Tool $SrcName
    $destDir = Resolve-SessionEndpoint $adapter $Tool $DestName

    if (-not (Test-Path $srcDir)) {
        throw "Source endpoint '$SrcName' not found at $srcDir. Nothing to continue from."
    }
    if (-not (Test-Path $destDir)) {
        throw "Destination profile '$DestName' does not exist. Create it with: multi-cli new $Tool/$DestName"
    }

    $credentials = @($adapter.session.credentials)
    $copied = 0; $skipped = 0; $found = $false
    if ($DryRun) { Write-Host "Dry run -- no files will be written." }

    foreach ($entry in @($adapter.session.paths)) {
        if (-not $entry) { continue }
        if (Test-IsCredentialName -RelativePath $entry -Credentials $credentials) { continue }
        $src = Join-Path $srcDir ($entry -replace '/', '\')
        if (-not (Test-Path $src)) { continue }
        $found = $true
        $dst = Join-Path $destDir ($entry -replace '/', '\')
        $c = [ref]$copied; $s = [ref]$skipped
        Copy-SessionEntry -Source $src -Destination $dst -NoMerge $NoMerge -DryRun $DryRun -Credentials $credentials -RelativeRoot $entry -Copied $c -Skipped $s
        $copied = $c.Value; $skipped = $s.Value
    }

    if (-not $found) {
        Write-Host "No session data found at source '$SrcName'. Nothing to continue."
        exit 0
    }
    Write-Host "Continued ${Tool}: $SrcName -> $DestName ($copied copied, $skipped skipped (same-or-newer))"
    if ($adapter.session.resumeHint) { Write-Host $adapter.session.resumeHint }
}

# Total size in bytes of the adapter-declared session paths under a root.
function Get-SessionStateSize {
    param($Adapter, [string]$Root)
    $total = 0
    foreach ($entry in @($Adapter.session.paths)) {
        if (-not $entry) { continue }
        $path = Join-Path $Root ($entry -replace '/', '\')
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if (-not $item -or (Test-IsReparsePoint $item)) { continue }
        $files = if ($item.PSIsContainer) { Get-SessionFilesNoReparse -Root $path } else { @($item) }
        $sum = ($files | Measure-Object -Property Length -Sum).Sum
        if ($sum) { $total += $sum }
    }
    return $total
}

# Seed session state from base into a new profile, with a size guard above the
# threshold and a progress line for big-but-allowed copies. Returns copied count.
function Initialize-SessionSeed {
    param($Adapter, [string]$SysHome, [string]$ProfileDir)
    Test-SessionAdapterBug $Adapter
    $bytes = Get-SessionStateSize -Adapter $Adapter -Root $SysHome
    if ($bytes -gt $SEED_MAX_BYTES) {
        $name = Split-Path $ProfileDir -Leaf
        Write-Host "base session state is $(Format-Bytes $bytes); skipped automatic copy -- run: multi-cli continue $($Adapter.id) base $name"
        return 0
    }
    $credentials = @($Adapter.session.credentials)
    $copied = 0; $skipped = 0
    foreach ($entry in @($Adapter.session.paths)) {
        if (-not $entry) { continue }
        if (Test-IsCredentialName -RelativePath $entry -Credentials $credentials) { continue }
        $src = Join-Path $SysHome ($entry -replace '/', '\')
        if (-not (Test-Path $src)) { continue }
        $dst = Join-Path $ProfileDir ($entry -replace '/', '\')
        $c = [ref]$copied; $s = [ref]$skipped
        Copy-SessionEntry -Source $src -Destination $dst -NoMerge $false -DryRun $false -Credentials $credentials -RelativeRoot $entry -Copied $c -Skipped $s
        $copied = $c.Value; $skipped = $s.Value
    }
    if ($copied -gt 0) { Write-Host "seeding $copied session file(s) from base" }
    return $copied
}

function Initialize-ProfileSeed {
    param($Adapter, [string]$ProfileDir, [bool]$Shared)
    $sysHome = Get-AdapterSystemHome $Adapter
    $seeded = @()

    if ($Adapter.session -and $Adapter.session.portable -and $sysHome -and (Test-Path $sysHome)) {
        $copied = Initialize-SessionSeed -Adapter $Adapter -SysHome $sysHome -ProfileDir $ProfileDir
        if ($copied -gt 0) { $seeded += "$copied session file(s)" }
    }

    if (-not $Shared -and $Adapter.share -and $sysHome -and (Test-Path $sysHome)) {
        $assets = 0
        foreach ($entry in @($Adapter.share.linkable)) {
            if (-not $entry) { continue }
            $src = Join-Path $sysHome $entry
            $dst = Join-Path $ProfileDir $entry
            if ((Test-Path $src) -and (-not (Test-Path $dst))) {
                Copy-Item -Path $src -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
                $assets++
            }
        }
        if ($assets -gt 0) { $seeded += "$assets shared asset(s)" }
    }

    if ($seeded.Count -gt 0) {
        Write-Host "Seeded from base: $($seeded -join ', ')."
    }
}

# =============================================================================
# Profile addressing
# =============================================================================

# Parse <tool>/<name> into an object; throws on any other shape. Name
# validation is a separate step (Test-ProfileName).
function Split-ProfileSpec {
    param([string]$Spec)
    if (-not $Spec) { throw "Profile required: <tool>/<name>" }
    if ($Spec -notmatch '/') { throw "Profile must be in form <tool>/<name>. Got: '$Spec'" }
    $parts = $Spec.Split('/', 2)
    Test-ToolId $parts[0]
    return [pscustomobject]@{ Tool = $parts[0]; Name = $parts[1] }
}

# Throw unless $ToolId is a safe adapter id: alnum start, then alnum or
# hyphen. This blocks traversal before adapter/profile paths are joined.
function Test-ToolId {
    param([string]$ToolId)
    if ([string]::IsNullOrWhiteSpace($ToolId)) { throw 'Tool id required' }
    if ($ToolId -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]*$') {
        throw "Tool id '$ToolId' invalid: must start with alphanumeric, contain only letters/numbers/hyphens"
    }
}

# Throw unless $Name is a safe profile/template name: alnum start, then alnum
# or hyphen. This is what keeps profile specs inside the storage root.
function Test-ProfileName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { throw "Profile name required" }
    if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]*$') {
        throw "Profile name '$Name' invalid: must start with alphanumeric, contain only letters/numbers/hyphens"
    }
}

function Get-StorageCanonical {
    param([string]$Path)
    return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/')
}

function Test-StoragePathWithin {
    param([string]$Child, [string]$Root)
    if (-not $Root) { return $false }
    $prefix = $Root.TrimEnd('\', '/') + '\'
    return ($Child.TrimEnd('\', '/') + '\').StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-StorageLinkInfo {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    $linkType = Get-ObjectPropertySafe -Object $item -Name 'LinkType'
    if ($linkType -ne 'Junction' -and $linkType -ne 'SymbolicLink' -and $linkType -ne 'HardLink') { return $null }
    $target = @((Get-ObjectPropertySafe -Object $item -Name 'Target'))[0]
    if (-not $target) { return $null }
    return [pscustomobject]@{ Item = $item; LinkType = $linkType; Target = $target }
}

function Get-StorageLinkTarget {
    param([string]$Path)
    $link = Get-StorageLinkInfo -Path $Path
    if ($null -eq $link) { return $null }
    $target = $link.Target
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path (Split-Path -Parent $Path) $target
    }
    return Get-StorageCanonical -Path $target
}

function Assert-StoragePathSafe {
    param([string]$Path, [string]$Label)
    $baseCanonical = Get-StorageCanonical -Path $BASE
    $candidateCanonical = Get-StorageCanonical -Path $Path
    if (-not (Test-StoragePathWithin -Child $candidateCanonical -Root $baseCanonical)) {
        throw "Refusing to access $Label outside MULTICLI_HOME: '$candidateCanonical'."
    }
    if ($candidateCanonical.Length -le $baseCanonical.Length) { return }
    $relative = $candidateCanonical.Substring($baseCanonical.Length).TrimStart('\', '/')
    if (-not $relative) { return }
    $current = $baseCanonical
    foreach ($segment in ($relative -split '[\\/]')) {
        if (-not $segment) { continue }
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { break }
        $target = Get-StorageLinkTarget -Path $current
        if ($null -eq $target) { continue }
        if (-not (Test-StoragePathWithin -Child $target -Root $baseCanonical)) {
            throw "Refusing to access $Label because '$current' resolves outside MULTICLI_HOME."
        }
    }
}

function Resolve-StoragePath {
    param([string]$Label, [string[]]$Segments)
    $path = $BASE
    foreach ($segment in @($Segments)) {
        if ([string]::IsNullOrEmpty($segment)) { continue }
        $path = Join-Path $path $segment
    }
    Assert-StoragePathSafe -Path $path -Label $Label
    return $path
}

function Get-ProfileDir {
    param([string]$Tool,[string]$Name)
    Test-ToolId $Tool
    Test-ProfileName $Name
    return Resolve-StoragePath -Label "profile '$Tool/$Name'" -Segments @($Tool, $Name)
}
function Get-ToolProfilesDir {
    param([string]$Tool)
    Test-ToolId $Tool
    return Resolve-StoragePath -Label "profile root for '$Tool'" -Segments @($Tool)
}
function Get-AliasDir { Resolve-StoragePath -Label 'alias directory' -Segments @('bin') }
function Get-TemplatesDir { Resolve-StoragePath -Label 'template root' -Segments @('.templates') }

function Throw-LegacyTransferBlocked {
    param([string]$Action, [string]$Spec)
    throw "Cannot $Action '$Spec': legacy profile transfer is disabled because whole-root copies can leak tokens. Migrate the legacy profile first: multi-cli migrate $Spec"
}

function Throw-LegacyTemplateApplyBlocked {
    param([string]$Spec, [string]$TemplateName)
    throw "Cannot create '$Spec' from template '$TemplateName': legacy template application is disabled because old on-disk templates can contain credentials. Recreate the template from a migrated schema-v2 profile."
}

function Remove-StorageTreeNoReparse {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $isReparsePoint = ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    if ($isReparsePoint) {
        if ($item.PSIsContainer) {
            [System.IO.Directory]::Delete($item.FullName)
        } else {
            [System.IO.File]::Delete($item.FullName)
        }
        return
    }
    if ($item.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue) {
            Remove-StorageTreeNoReparse -Path $child.FullName
        }
    }
    Remove-Item -LiteralPath $item.FullName -Force
}

function Copy-StorageTreeNoReparse {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source)) { return }
    $item = Get-Item -LiteralPath $Source -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Cannot clone '$Source': nested reparse points are not supported inside isolated profile state."
    }
    if ($item.PSIsContainer) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        foreach ($child in Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue) {
            Copy-StorageTreeNoReparse -Source $child.FullName -Destination (Join-Path $Destination $child.Name)
        }
        return
    }
    $parent = Split-Path -Parent $Destination
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Force
}

# =============================================================================
# Profile CRUD
# =============================================================================

# Write .profile.json for any isolated schema-v2 profile atomically. The
# unique profileId keeps lifecycle and optional OS-store credentials distinct.
function Write-IsolatedProfileMetadata {
    param($Adapter, [string]$ProfileDir)
    $metadata = [ordered]@{
        schemaVersion = 2
        adapterId = $Adapter.id
        profileId = [guid]::NewGuid().ToString()
        mode = 'isolated'
    }
    $temporaryPath = Join-Path $ProfileDir '.profile.json.tmp'
    $metadata | ConvertTo-Json | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination (Join-Path $ProfileDir '.profile.json') -Force
}

# multi-cli new <tool>/<name>: create the profile dir, seed from base unless
# suppressed, wire schema-v2 runtime metadata when the adapter is
# accountOverlay, then create the alias and (for non-CLI kinds) a shortcut.
function New-Profile {
    param([string]$Spec, [bool]$Shared = $false, [bool]$Cli = $false, [string]$FromTemplate = '', [bool]$NoSeed = $false, [bool]$Isolated = $false)

    $p = Split-ProfileSpec $Spec
    Test-ProfileName $p.Name
    $adapter = Get-Adapter $p.Tool
    $profileDir = Get-ProfileDir $p.Tool $p.Name

    if ($Shared -and $Isolated) { throw '--shared and --isolated are mutually exclusive: choose one profile mode.' }
    if ($Isolated -and (Test-AdapterNeedsOsUser -Adapter $adapter)) {
        throw "Adapter '$($adapter.id)' cannot use --isolated because folder redirection does not isolate Windows Credential Manager."
    }
    if ($Isolated -and $adapter.isolation.strategy -ne 'accountOverlay') {
        throw "--isolated applies to schema-v2 (accountOverlay) adapters; '$($p.Tool)' uses '$($adapter.isolation.strategy)', which already isolates the whole root per profile."
    }

    if (Test-Path $profileDir) { throw "Profile '$Spec' already exists" }
    New-Item -ItemType Directory -Force -Path (Get-ToolProfilesDir $p.Tool) | Out-Null

    if ($FromTemplate) {
        $tplDir = Join-Path (Get-TemplatesDir) $FromTemplate
        if (-not (Test-Path $tplDir)) { throw "Template '$FromTemplate' not found" }
        if ($adapter.isolation.strategy -eq 'accountOverlay') {
            Import-Module (Resolve-MultiCliModulePath 'MultiCli.Transfer.psm1') -Force
            # Validation runs before creating the profile, then payload files go
            # to the state location the selected mode actually launches.
            [void](Assert-TransferTemplateCompatible -TemplateDir $tplDir -Adapter $adapter)
            New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
            Apply-MultiCliTemplate -TemplateDir $tplDir -Adapter $adapter -ProfileDir $profileDir -Isolated:$Isolated
        } else {
            Throw-LegacyTemplateApplyBlocked -Spec $Spec -TemplateName $FromTemplate
        }
    } elseif ($Shared) {
        New-SharedProfile -Adapter $adapter -ProfileDir $profileDir
    } else {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }

    if (-not $NoSeed -and -not $FromTemplate -and $adapter.isolation.strategy -ne 'accountOverlay') {
        Initialize-ProfileSeed -Adapter $adapter -ProfileDir $profileDir -Shared $Shared
    }

    if ($Isolated) {
        New-Item -ItemType File -Force -Path (Join-Path $profileDir '.isolated') | Out-Null
        # Every isolated schema-v2 profile carries a unique profileId. Lifecycle
        # operations then stay on the allowlisted transfer path instead of the
        # legacy whole-directory clone/export path.
        if (-not (Test-Path -LiteralPath (Join-Path $profileDir '.profile.json'))) {
            Write-IsolatedProfileMetadata -Adapter $adapter -ProfileDir $profileDir
        }
    } elseif ($adapter.isolation.strategy -eq 'accountOverlay') {
        Import-RuntimeModule
        Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $profileDir
    }

    if ($adapter.isolation.strategy -eq 'redirectHome') {
        $homeDir = Join-Path $profileDir '_home'
        New-Item -ItemType Directory -Force -Path $homeDir | Out-Null
        Set-RedirectHomeDotfileLinks -Adapter $adapter -HomeDir $homeDir
    }

    if ($Cli) { New-Item -ItemType File -Force -Path (Join-Path $profileDir '.cli') | Out-Null }

    New-AliasScript -Tool $p.Tool -Name $p.Name
    if (-not $Cli -and $adapter.kind -ne 'cli') {
        New-StartMenuShortcut -Tool $p.Tool -Name $p.Name -Adapter $adapter | Out-Null
    }

    $modeNote = if ($Isolated) { ', isolated' } else { '' }
    Write-Host "Created profile $Spec ($($adapter.displayName), strategy=$($adapter.isolation.strategy)$modeNote)"
    # Never persist a custom (test/scratch) MULTICLI_HOME into the user's PATH;
    # only the default profile root belongs there permanently.
    if (-not $env:MULTICLI_HOME -and -not (Test-AliasDirInPath)) {
        $aliasDir = Get-AliasDir
        $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($userPath -notlike "*$aliasDir*") {
            [Environment]::SetEnvironmentVariable('PATH', "$aliasDir;$userPath", 'User')
            $env:PATH = "$aliasDir;$env:PATH"
            Write-Host "Added $aliasDir to user PATH. Restart your terminal to use '$($p.Name)' or '$($p.Tool)-$($p.Name)' as a command."
        } else {
            Write-Host "$aliasDir is already in PATH."
        }
    }
}

# A --shared profile links the adapter's share.linkable entries from the
# tool's system home into the profile dir (copy fallback when linking fails).
function New-SharedProfile {
    param($Adapter, [string]$ProfileDir)
    New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $ProfileDir '.shared') | Out-Null
    if (-not $Adapter.share -or -not $Adapter.share.systemHome) { return }

    $sysHome = Resolve-PathToken $Adapter.share.systemHome
    if (-not (Test-Path $sysHome)) { return }

    foreach ($entry in @($Adapter.share.linkable)) {
        if (-not $entry) { continue }
        $src = Join-Path $sysHome $entry
        $dst = Join-Path $ProfileDir $entry
        if ((Test-Path $src) -and (-not (Test-Path $dst))) {
            try {
                New-Item -ItemType SymbolicLink -Path $dst -Target $src -ErrorAction Stop | Out-Null
            } catch {
                Write-Warning "Could not symlink $entry (Developer Mode may be required). Falling back to copy."
                Copy-Item -Path $src -Destination $dst -Recurse -ErrorAction SilentlyContinue
            }
        }
    }
}

# Link the adapter's shareFromRealHome dotfiles from the real user profile
# into the redirected profile home, leaving existing entries alone.
function Set-RedirectHomeDotfileLinks {
    param($Adapter, [string]$HomeDir)
    if (-not $Adapter.isolation.shareFromRealHome) { return }
    foreach ($entry in @($Adapter.isolation.shareFromRealHome)) {
        if (-not $entry) { continue }
        $src = Join-Path $env:USERPROFILE $entry
        $dst = Join-Path $HomeDir $entry
        if ((Test-Path $src) -and (-not (Test-Path $dst))) {
            try {
                New-Item -ItemType SymbolicLink -Path $dst -Target $src -ErrorAction Stop | Out-Null
            } catch {
                Write-Warning "Could not symlink shared dotfile $entry."
            }
        }
    }
}

# multi-cli delete: confirm, clear any process-secret credential, then remove
# the profile dir, alias, and shortcut.
function Remove-Profile {
    param([string]$Spec)
    $p = Split-ProfileSpec $Spec
    Test-ProfileName $p.Name
    $profileDir = Get-ProfileDir $p.Tool $p.Name
    if (-not (Test-Path $profileDir)) { throw "Profile '$Spec' does not exist" }

    # Read-Host consults the console on some hosts even when stdin is piped,
    # silently returning an empty answer and aborting scripted deletes. Read
    # the redirected stream directly so piped confirmations are honored.
    if ([Console]::IsInputRedirected) {
        Write-Host "Delete profile '$Spec' and all its data? [y/N]"
        $confirm = Read-RedirectedLine
    } else {
        $confirm = Read-Host "Delete profile '$Spec' and all its data? [y/N]"
    }
    if ($confirm -notmatch '^[Yy]$') { Write-Host "Aborted."; return }

    # An OS-user profile owns a sandbox user, optional legacy scheduled tasks,
    # and a Credential Manager entry; remove them before deleting the profile dir.
    # The helper verifies ownership and is a no-op without a record.
    if (Test-Path -LiteralPath (Join-Path $profileDir '.osuser.json')) {
        Import-Module (Resolve-MultiCliModulePath 'MultiCli.OsUser.psm1') -Force
        Remove-OsUserIsolation -ProfileDir $profileDir
    }

    # A process-secret profile owns a Credential Manager entry keyed by its
    # profileId; delete must not orphan it in the store. A missing adapter
    # manifest must not block deleting the profile itself.
    $metadataPath = Join-Path $profileDir '.profile.json'
    $adapterManifest = Join-Path (Join-Path $ToolsDir $p.Tool) 'adapter.json'
    if ((Test-Path -LiteralPath $metadataPath) -and (Test-Path -LiteralPath $adapterManifest)) {
        $adapter = Get-Adapter $p.Tool
        if ($adapter.account.mechanism -eq 'processSecret') {
            $environmentVariable = $adapter.account.secret.environmentVariable
            $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
            if ($environmentVariable -and $metadata.profileId) {
                Import-Module (Resolve-MultiCliModulePath 'MultiCli.CredentialStore.psm1') -Force
                [void](Remove-MultiCliCredential -Target "multi-cli/$($adapter.id)/$($metadata.profileId)/$environmentVariable")
            }
        }
    }
    Remove-StorageTreeNoReparse -Path $profileDir
    Remove-AliasScript -Tool $p.Tool -Name $p.Name
    Remove-StartMenuShortcut -Tool $p.Tool -Name $p.Name
    Write-Host "Deleted profile '$Spec'"
}

function Rename-Profile {
    param([string]$OldSpec, [string]$NewSpec)
    $a = Split-ProfileSpec $OldSpec
    $b = Split-ProfileSpec $NewSpec
    if ($a.Tool -ne $b.Tool) { throw "Cannot rename across tools" }
    Test-ProfileName $a.Name
    Test-ProfileName $b.Name
    $oldDir = Get-ProfileDir $a.Tool $a.Name
    $newDir = Get-ProfileDir $b.Tool $b.Name
    if (-not (Test-Path $oldDir)) { throw "Profile '$OldSpec' does not exist" }
    if (Test-Path $newDir) { throw "Profile '$NewSpec' already exists" }
    Rename-Item -Path $oldDir -NewName $b.Name
    Remove-AliasScript -Tool $a.Tool -Name $a.Name
    Remove-StartMenuShortcut -Tool $a.Tool -Name $a.Name
    New-AliasScript -Tool $b.Tool -Name $b.Name
    New-StartMenuShortcut -Tool $b.Tool -Name $b.Name -Adapter (Get-Adapter $b.Tool) | Out-Null
    Write-Host "Renamed '$OldSpec' to '$NewSpec'"
}

# Clone a profile. Schema-v2 clones receive a fresh identity and copy only the
# profile-local mode/state boundary; credentials and disposable runtime do not.
function Copy-ProfileTo {
    param([string]$SrcSpec, [string]$DestSpec)
    $a = Split-ProfileSpec $SrcSpec
    $b = Split-ProfileSpec $DestSpec
    if ($a.Tool -ne $b.Tool) { throw "Cannot clone across tools" }
    Test-ProfileName $a.Name
    Test-ProfileName $b.Name
    $srcDir  = Get-ProfileDir $a.Tool $a.Name
    $destDir = Get-ProfileDir $b.Tool $b.Name
    if (-not (Test-Path $srcDir)) { throw "Source profile '$SrcSpec' does not exist" }
    if (Test-Path $destDir) { throw "Destination profile '$DestSpec' already exists" }
    $adapter = Get-Adapter $a.Tool
    $metadataPath = Join-Path $srcDir '.profile.json'
    if (Test-Path -LiteralPath $metadataPath) {
        $mode = (Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json).mode
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        if ($mode -eq 'isolated') {
            $normalState = Get-ObjectPropertySafe -Object $adapter -Name 'normalState'
            $sourceState = $srcDir
            $destinationState = $destDir
            $runtimeSubdir = Get-ObjectPropertySafe -Object $normalState -Name 'runtimeSubdir'
            if ($runtimeSubdir) {
                $sourceState = Join-Path $srcDir ($runtimeSubdir -replace '/', '\')
                $destinationState = Join-Path $destDir ($runtimeSubdir -replace '/', '\')
            }
            try {
                foreach ($relativePath in @($normalState.sharedPaths) + @($normalState.sessionPaths)) {
                    if (-not $relativePath) { continue }
                    $source = Join-Path $sourceState ($relativePath -replace '/', '\')
                    if (-not (Test-Path -LiteralPath $source)) { continue }
                    $destination = Join-Path $destinationState ($relativePath -replace '/', '\')
                    $parent = Split-Path -Parent $destination
                    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
                    Copy-StorageTreeNoReparse -Source $source -Destination $destination
                }
                New-Item -ItemType File -Path (Join-Path $destDir '.isolated') | Out-Null
                Write-IsolatedProfileMetadata -Adapter $adapter -ProfileDir $destDir
            } catch {
                Remove-StorageTreeNoReparse -Path $destDir
                throw
            }
        } else {
            Import-RuntimeModule
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $destDir
        }
    } else {
        Throw-LegacyTransferBlocked -Action 'clone' -Spec $SrcSpec
    }
    New-AliasScript -Tool $b.Tool -Name $b.Name
    New-StartMenuShortcut -Tool $b.Tool -Name $b.Name -Adapter $adapter | Out-Null
    Write-Host "Cloned '$SrcSpec' to '$DestSpec'"
}

# =============================================================================
# Aliases & shortcuts
# =============================================================================

# Write <tool>-<name>.cmd (and, if free, <name>.cmd) alias shims into the
# alias dir; each runs this launcher with the profile spec.
function New-AliasScript {
    param([string]$Tool, [string]$Name)
    $aliasDir = Get-AliasDir
    New-Item -ItemType Directory -Force -Path $aliasDir | Out-Null
    $aliasPath = Join-Path $aliasDir "$Tool-$Name.cmd"
    $scriptPath = $PSCommandPath
@"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "$scriptPath" launch $Tool/$Name %*
"@ | Set-Content -Path $aliasPath -Encoding ASCII

    $shortAliasPath = Join-Path $aliasDir "$Name.cmd"
    if (-not (Test-Path $shortAliasPath)) {
@"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "$scriptPath" launch $Tool/$Name %*
"@ | Set-Content -Path $shortAliasPath -Encoding ASCII
    }
}

# Remove the full alias; the short alias goes only when it points at the same
# profile (another tool may have claimed the same short name first).
function Remove-AliasScript {
    param([string]$Tool, [string]$Name)
    $aliasPath = Join-Path (Get-AliasDir) "$Tool-$Name.cmd"
    if (Test-Path $aliasPath) { Remove-Item -Force $aliasPath }
    $shortAliasPath = Join-Path (Get-AliasDir) "$Name.cmd"
    if (Test-Path $shortAliasPath) {
        $content = Get-Content $shortAliasPath -Raw -ErrorAction SilentlyContinue
        if ($content -and $content -match "$Tool/$Name") {
            Remove-Item -Force $shortAliasPath
        }
    }
}

# True when the alias dir is on this process's PATH (exact component match).
function Test-AliasDirInPath {
    $dir = Get-AliasDir
    return ($env:PATH -split ';') -contains $dir
}

# Create a Start Menu shortcut launching the profile; warns and returns $null
# when the COM shortcut write fails (never blocks profile creation).
function New-StartMenuShortcut {
    param([string]$Tool, [string]$Name, $Adapter)
    try {
        $linkName = "multi-cli $Tool $Name.lnk"
        $linkPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$linkName"
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut($linkPath)
        $shortcut.TargetPath = 'powershell.exe'
        $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$MultiCliLauncherPath`" launch $Tool/$Name"
        $shortcut.Save()
        return $linkPath
    } catch {
        Write-Warning "Could not create Start Menu shortcut for ${Tool}/${Name}: $_"
        return $null
    }
}

function Remove-StartMenuShortcut {
    param([string]$Tool, [string]$Name)
    $linkPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\multi-cli $Tool $Name.lnk"
    if (Test-Path $linkPath) { Remove-Item -Force $linkPath }
}

# =============================================================================
# Launch -- strategy dispatch
# =============================================================================

# multi-cli launch <tool>/<name> [args...]: resolve the adapter, profile and
# binary, then hand off to the adapter's isolation strategy.
function Invoke-Launch {
    param([string]$Spec, [string[]]$BinaryArgs = @())
    $p = Split-ProfileSpec $Spec
    $adapter = Get-Adapter $p.Tool
    $profileDir = Get-ProfileDir $p.Tool $p.Name
    if (-not (Test-Path $profileDir)) { throw "Profile '$Spec' does not exist. Create with: multi-cli new $Spec" }
    if ($adapter.support.windows.level -eq 'unsupported') {
        throw "$($adapter.displayName) is unsupported on windows: $($adapter.support.windows.reason)"
    }

    $binary = Find-AdapterBinary $adapter
    if (-not $binary) {
        $hint = if ($adapter.install) { " Install with: $($adapter.install)" } else { '' }
        throw "$($adapter.displayName) binary not found.$hint"
    }
    if (Test-UriBinary -Binary $binary) {
        $BinaryArgs = @($adapter.isolation.args) + @($BinaryArgs)
    }

    # Isolated profiles share nothing: the profile dir is the tool's whole
    # root, so the account-overlay runtime (shared links, overlay) is bypassed.
    if ($adapter.isolation.strategy -eq 'accountOverlay' -and (Test-Path -LiteralPath (Join-Path $profileDir '.isolated'))) {
        if (Test-AdapterNeedsOsUser -Adapter $adapter) {
            throw "Profile '$Spec' cannot use --isolated because folder redirection does not isolate Windows Credential Manager."
        }
        Write-Host "Launching $($adapter.displayName) profile '$Spec' [$($adapter.isolation.strategy), isolated]"
        Invoke-LaunchIsolated -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs
        return
    }

    Write-Host "Launching $($adapter.displayName) profile '$Spec' [$($adapter.isolation.strategy)]"

    switch ($adapter.isolation.strategy) {
        'env'            { Invoke-LaunchEnv            -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs }
        'accountOverlay' { Invoke-LaunchAccountOverlay -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs }
        'userDataDir'    { Invoke-LaunchUserDataDir    -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs }
        'redirectHome'  { Invoke-LaunchRedirectHome -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs }
        'appdata'       { Invoke-LaunchAppData      -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs }
        'sandboxUser'   { Invoke-LaunchSandboxUser  -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs }
        default         { throw "Unknown isolation strategy '$($adapter.isolation.strategy)' for $($adapter.id)" }
    }
}

# Expand {profileDir} in an adapter-declared env value or argument.
function Expand-Placeholder {
    param([string]$Value, [string]$ProfileDir)
    return $Value.Replace('{profileDir}', $ProfileDir)
}

# env strategy: the whole isolation is the adapter's env map, expanded and
# set for the child only.
function Invoke-LaunchEnv {
    param($Adapter, [string]$ProfileDir, [string]$Binary, [string[]]$BinaryArgs)
    $envMap = @{}
    foreach ($prop in $Adapter.isolation.env.PSObject.Properties) {
        $envMap[$prop.Name] = (Expand-Placeholder $prop.Value $ProfileDir)
    }
    Start-WithEnv -Binary $Binary -BinaryArgs $BinaryArgs -EnvMap $envMap
}

# Quote one argument for a CreateProcess command line: double backslashes
# before a quote and at the end, escape quotes. Windows CRT rules.
function Quote-ProcessArgument {
    param([string]$Argument)
    if ($null -eq $Argument -or $Argument -eq '') { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }
    $escaped = $Argument -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

# Start a launch plan with full environment control. Foreground plans wait
# and propagate the child exit code as the launcher exit code; detached plans
# return immediately.
function Start-LaunchPlan {
    param($Plan)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Plan.Binary
    $startInfo.Arguments = (@($Plan.Arguments) | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' '
    $startInfo.UseShellExecute = $false
    foreach ($name in @($Plan.ClearEnvironment)) {
        if ($name) { [void]$startInfo.EnvironmentVariables.Remove($name) }
    }
    foreach ($name in $Plan.Environment.Keys) {
        $startInfo.EnvironmentVariables[$name] = [string]$Plan.Environment[$name]
    }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    if ($Plan.Mode -eq 'detached') { return }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        $global:LASTEXITCODE = $process.ExitCode
        exit $process.ExitCode
    }
}

# accountOverlay strategy: the schema-v2 runtime builds the launch plan (env,
# overlay, injected secret); the launcher only starts it.
function Invoke-LaunchAccountOverlay {
    param($Adapter, [string]$ProfileDir, [string]$Binary, [string[]]$BinaryArgs)
    if ($Adapter.account.mechanism -eq 'osUserCredentialStore') {
        Import-Module (Resolve-MultiCliModulePath 'MultiCli.OsUser.psm1') -Force
        $exitCode = Invoke-OsUserLaunch -Adapter $Adapter -ProfileDir $ProfileDir -Binary $Binary -BinaryArgs $BinaryArgs
        if ($exitCode -ne 0) {
            $global:LASTEXITCODE = $exitCode
            exit $exitCode
        }
        return
    }
    Import-RuntimeModule
    $plan = Get-AccountOverlayLaunchPlan -Adapter $Adapter -ProfileDir $ProfileDir -Binary $Binary -BinaryArgs $BinaryArgs
    Start-LaunchPlan -Plan $plan
}

# Isolated launch for schema-v2 profiles created with --isolated: the profile
# dir is the tool's whole root. No runtime overlay, no shared links, nothing
# read from or written to the native shared root. fileOverlay and
# processSecret point the adapter's home env at the profile dir itself;
# processSecret additionally injects the per-profile credential (fail-closed
# until `multi-cli auth set`). osUserCredentialStore and inseparable get a
# whole-home redirect into <profile>\_home -- no OS user, no shared state.
function Invoke-LaunchIsolated {
    param($Adapter, [string]$ProfileDir, [string]$Binary, [string[]]$BinaryArgs)
    $mechanism = $Adapter.account.mechanism
    $profileId = ''
    $metadataPath = Join-Path $ProfileDir '.profile.json'
    if (Test-Path -LiteralPath $metadataPath) {
        $profileId = (Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json).profileId
    }

    # Both {runtimeRoot} and {sharedStateRoot} resolve to the profile dir: in
    # isolated mode the profile is the root, so no placeholder can leak a path
    # into the native shared root.
    $environment = @{}
    foreach ($property in $Adapter.isolation.env.PSObject.Properties) {
        $environment[$property.Name] = $property.Value.
            Replace('{profileDir}', $ProfileDir).
            Replace('{profileId}', $profileId).
            Replace('{authDir}', (Join-Path $ProfileDir 'auth')).
            Replace('{runtimeRoot}', $ProfileDir).
            Replace('{sharedStateRoot}', $ProfileDir).
            Replace('{realHome}', $env:USERPROFILE)
    }
    if ($profileId) { $environment['MULTICLI_PROFILE_ID'] = $profileId }

    if ($mechanism -eq 'processSecret') {
        $environmentVariable = $Adapter.account.secret.environmentVariable
        if (-not $environmentVariable) { throw "Adapter '$($Adapter.id)' is missing account.secret.environmentVariable." }
        if (-not $profileId) { throw "Profile '$($Adapter.id)/$(Split-Path $ProfileDir -Leaf)' is missing schema-v2 metadata." }
        Import-Module (Resolve-MultiCliModulePath 'MultiCli.CredentialStore.psm1') -Force
        $target = "multi-cli/$($Adapter.id)/$profileId/$environmentVariable"
        $secret = Get-MultiCliCredential -Target $target
        if ([string]::IsNullOrEmpty($secret)) {
            throw "Profile '$($Adapter.id)/$(Split-Path $ProfileDir -Leaf)' has no stored credential. Run: multi-cli auth set $($Adapter.id)/$(Split-Path $ProfileDir -Leaf)"
        }
        $environment[$environmentVariable] = $secret
    }

    if ($mechanism -ne 'fileOverlay' -and $mechanism -ne 'processSecret') {
        $homeDir = Join-Path $ProfileDir '_home'
        $appdata = Join-Path $homeDir 'AppData\Roaming'
        $localApp = Join-Path $homeDir 'AppData\Local'
        $tempDir = Join-Path $homeDir 'AppData\Local\Temp'
        New-Item -ItemType Directory -Force -Path $homeDir  | Out-Null
        New-Item -ItemType Directory -Force -Path $appdata  | Out-Null
        New-Item -ItemType Directory -Force -Path $localApp | Out-Null
        New-Item -ItemType Directory -Force -Path $tempDir  | Out-Null
        $environment['USERPROFILE']  = $homeDir
        $environment['HOME']         = $homeDir
        $environment['HOMEDRIVE']    = $homeDir.Substring(0, 2)
        $environment['HOMEPATH']     = $homeDir.Substring(2)
        $environment['APPDATA']      = $appdata
        $environment['LOCALAPPDATA'] = $localApp
        $environment['TEMP']         = $tempDir
        $environment['TMP']          = $tempDir
    }

    Start-LaunchPlan -Plan ([pscustomobject]@{
        Binary = $Binary
        Arguments = @($BinaryArgs)
        Environment = $environment
        ClearEnvironment = @($Adapter.isolation.clearEnv)
        Mode = $Adapter.isolation.mode
    })
}

# userDataDir strategy: pass the adapter's --user-data-dir-style args and
# point USERPROFILE/APPDATA/TEMP at <profile>\_home so nothing leaks to the
# real user profile.
function Invoke-LaunchUserDataDir {
    param($Adapter, [string]$ProfileDir, [string]$Binary, [string[]]$BinaryArgs)
    $argsList = @()
    foreach ($a in @($Adapter.isolation.args)) { $argsList += (Expand-Placeholder $a $ProfileDir) }
    if ($BinaryArgs) { $argsList += $BinaryArgs }
    $homeDir  = Join-Path $ProfileDir '_home'
    $appdata  = Join-Path $homeDir 'AppData\Roaming'
    $localApp = Join-Path $homeDir 'AppData\Local'
    $tempDir  = Join-Path $homeDir 'AppData\Local\Temp'
    New-Item -ItemType Directory -Force -Path $homeDir  | Out-Null
    New-Item -ItemType Directory -Force -Path $appdata  | Out-Null
    New-Item -ItemType Directory -Force -Path $localApp | Out-Null
    New-Item -ItemType Directory -Force -Path $tempDir  | Out-Null
    Start-WithEnv -Binary $Binary -BinaryArgs $argsList -EnvMap @{
        USERPROFILE  = $homeDir
        HOME         = $homeDir
        HOMEDRIVE    = $homeDir.Substring(0, 2)
        HOMEPATH     = $homeDir.Substring(2)
        APPDATA      = $appdata
        LOCALAPPDATA = $localApp
        TEMP         = $tempDir
        TMP          = $tempDir
    }
}

# redirectHome strategy: like userDataDir, but the adapter's
# shareFromRealHome dotfiles are linked into the redirected home first, and
# any extra isolation env is applied.
function Invoke-LaunchRedirectHome {
    param($Adapter, [string]$ProfileDir, [string]$Binary, [string[]]$BinaryArgs)
    $homeDir = Join-Path $ProfileDir '_home'
    if (-not (Test-Path $homeDir)) { New-Item -ItemType Directory -Force -Path $homeDir | Out-Null }
    Set-RedirectHomeDotfileLinks -Adapter $Adapter -HomeDir $homeDir
    $appdata     = Join-Path $homeDir 'AppData\Roaming'
    $localApp    = Join-Path $homeDir 'AppData\Local'
    $tempDir     = Join-Path $homeDir 'AppData\Local\Temp'
    New-Item -ItemType Directory -Force -Path $appdata  | Out-Null
    New-Item -ItemType Directory -Force -Path $localApp | Out-Null
    New-Item -ItemType Directory -Force -Path $tempDir  | Out-Null
    $envMap = @{
        USERPROFILE  = $homeDir
        HOME         = $homeDir
        HOMEDRIVE    = $homeDir.Substring(0, 2)
        HOMEPATH     = $homeDir.Substring(2)
        APPDATA      = $appdata
        LOCALAPPDATA = $localApp
        TEMP         = $tempDir
        TMP          = $tempDir
    }
    if ($Adapter.isolation.env) {
        foreach ($prop in $Adapter.isolation.env.PSObject.Properties) {
            $envMap[$prop.Name] = (Expand-Placeholder $prop.Value $ProfileDir)
        }
    }
    Start-WithEnv -Binary $Binary -BinaryArgs $BinaryArgs -EnvMap $envMap
}

# appdata strategy: redirect only APPDATA into the profile; for tools whose
# state lives entirely under Roaming.
function Invoke-LaunchAppData {
    param($Adapter, [string]$ProfileDir, [string]$Binary, [string[]]$BinaryArgs)
    $appdata = Join-Path $ProfileDir 'AppData\Roaming'
    New-Item -ItemType Directory -Force -Path $appdata | Out-Null
    Start-WithEnv -Binary $Binary -BinaryArgs $BinaryArgs -EnvMap @{ APPDATA = $appdata }
}

# Create the mcli_<name> local user (admin only) with a random password; the
# DPAPI-encrypted password goes to <profile>\.sandbox_cred so later launches
# need no admin rights.
function New-SandboxUser {
    param([string]$Name, [string]$ProfileDir)
    $username = "mcli_$Name"
    if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) { return $username }
    Add-Type -AssemblyName System.Web
    $pass = [System.Web.Security.Membership]::GeneratePassword(20, 5)
    $secPass = ConvertTo-SecureString $pass -AsPlainText -Force
    New-LocalUser -Name $username -Password $secPass -Description "multi-cli sandbox for $Name" -PasswordNeverExpires | Out-Null
    $secPass | ConvertFrom-SecureString | Set-Content (Join-Path $ProfileDir '.sandbox_cred')
    $acl = Get-Acl $ProfileDir
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($username, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl $ProfileDir $acl
    return $username
}

# sandboxUser strategy: run the binary as the profile's dedicated OS user so
# per-user credential stores (Credential Manager) are per-profile. First
# launch requires admin to create the user.
function Invoke-LaunchSandboxUser {
    param($Adapter, [string]$ProfileDir, [string]$Binary, [string[]]$BinaryArgs)
    $profileName = Split-Path $ProfileDir -Leaf
    $username = "mcli_$profileName"
    $credFile = Join-Path $ProfileDir '.sandbox_cred'
    if (-not (Get-LocalUser -Name $username -ErrorAction SilentlyContinue)) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            throw "First launch requires admin. Run as Administrator: multi-cli launch $($Adapter.id)/$profileName"
        }
        New-SandboxUser -Name $profileName -ProfileDir $ProfileDir | Out-Null
    }
    if (-not (Test-Path $credFile)) {
        throw "Sandbox credential file missing at $credFile. Delete profile and recreate."
    }
    $secPass = Get-Content $credFile | ConvertTo-SecureString
    $cred = New-Object System.Management.Automation.PSCredential($username, $secPass)
    $argsList = @()
    if ($Adapter.isolation.args) {
        foreach ($a in @($Adapter.isolation.args)) { $argsList += (Expand-Placeholder $a $ProfileDir) }
    }
    if ($BinaryArgs) { $argsList += $BinaryArgs }
    $argString = ($argsList | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    $spParams = @{
        FilePath        = $Binary
        Credential      = $cred
        LoadUserProfile = $true
    }
    if ($argString) { $spParams['ArgumentList'] = $argString }
    Start-Process @spParams
}

# Run the binary with the env map applied to the child only: process-level
# variables are set, the child runs, and every variable is restored in
# 'finally'. The child's exit code becomes the launcher exit code.
function Start-WithEnv {
    param([string]$Binary, [string[]]$BinaryArgs, [hashtable]$EnvMap)
    $original = @{}
    foreach ($k in $EnvMap.Keys) {
        $original[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
        [Environment]::SetEnvironmentVariable($k, $EnvMap[$k], 'Process')
    }
    $childExitCode = 0
    try {
        if ($BinaryArgs -and $BinaryArgs.Count -gt 0) { & $Binary @BinaryArgs } else { & $Binary }
        # Native children do not throw on failure; their exit code is all we get.
        if ($null -ne $LASTEXITCODE) { $childExitCode = $LASTEXITCODE }
    } finally {
        foreach ($k in $original.Keys) {
            [Environment]::SetEnvironmentVariable($k, $original[$k], 'Process')
        }
    }
    $global:LASTEXITCODE = $childExitCode
    exit $childExitCode
}

# =============================================================================
# Listings & diagnostics
# =============================================================================

function Format-Bytes {
    param([long]$Size)
    if ($Size -ge 1GB) { '{0:N2} GB' -f ($Size / 1GB) }
    elseif ($Size -ge 1MB) { '{0:N2} MB' -f ($Size / 1MB) }
    elseif ($Size -ge 1KB) { '{0:N2} KB' -f ($Size / 1KB) }
    else { "$Size B" }
}

# Human-readable size of a directory tree; "0 B" for anything missing.
function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '0 B' }
    $size = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
    if (-not $size) { $size = 0 }
    Format-Bytes $size
}

# Every regular file under a root via an iterative stack walk. Reparse-point
# items are skipped entirely (never listed, never descended): a runtime
# overlay links into the shared normal state, and following those links would
# escape the profile and could loop.
function Get-RuntimeFilesNoReparse {
    param([string]$Root)
    $files = @()
    $stack = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $stack.Push((Get-Item -LiteralPath $Root))
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        foreach ($item in (Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue)) {
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            if ($item.PSIsContainer) { $stack.Push($item); continue }
            $files += $item.FullName
        }
    }
    return $files
}

function Show-List {
    param([string]$ToolFilter)
    if (-not (Test-Path $BASE)) { Write-Host "No profiles yet."; return }
    $tools = Get-ChildItem -Directory -Path $BASE | Where-Object { $_.Name -notmatch '^\.' -and $_.Name -ne 'bin' }
    if ($ToolFilter) { $tools = $tools | Where-Object { $_.Name -eq $ToolFilter } }
    foreach ($toolDir in $tools) {
        Write-Host ""
        Write-Host "[$($toolDir.Name)]" -ForegroundColor Cyan
        $profiles = Get-ChildItem -Directory -Path $toolDir.FullName -ErrorAction SilentlyContinue
        if (-not $profiles) { Write-Host "  (none)"; continue }
        foreach ($prof in $profiles) {
            $type = if (Test-Path (Join-Path $prof.FullName '.cli')) { 'cli' }
                    elseif (Test-Path (Join-Path $prof.FullName '.shared')) { 'shared' }
                    elseif (Test-Path (Join-Path $prof.FullName '.isolated')) { 'isolated' }
                    else { 'full' }
            Write-Host ("  {0,-20} {1,-8} {2}" -f $prof.Name, $type, (Get-FolderSize $prof.FullName))
        }
    }
}

function Show-Tools {
    Write-Host "Supported tools:"
    Write-Host ""
    Write-Host ("  {0,-18} {1,-12} {2,-15} {3,-10} {4}" -f 'TOOL', 'KIND', 'STRATEGY', 'STATUS', 'INSTALLED')
    Write-Host ("  {0,-18} {1,-12} {2,-15} {3,-10} {4}" -f '----', '----', '--------', '------', '---------')
    foreach ($a in (Get-Adapters | Sort-Object id)) {
        $bin = Find-AdapterBinary $a
        $installed = if ($bin) { "yes" } else { 'no' }
        $color = if ($bin) { 'Green' } else { 'DarkGray' }
        $platformSupport = if ($a.support -and $a.support.windows) { $a.support.windows } else { $null }
        $status = if ($platformSupport.level) { $platformSupport.level } elseif ($a.status) { $a.status } else { '?' }
        Write-Host ("  {0,-18} {1,-12} {2,-15} {3,-10} {4}" -f $a.id, $a.kind, $a.isolation.strategy, $status, $installed) -ForegroundColor $color
        if ($platformSupport.reason) { Write-Host "    $($platformSupport.reason)" }
    }
}

# multi-cli doctor: writable storage, alias dir on PATH, per-tool binary
# discovery and support caveats; --deep audits runtime overlays against their
# manifests. Exit code stays 0; the summary line carries the verdict.
function Show-Doctor {
    param([string]$Deep)
    $errors = 0; $warnings = 0
    Write-Host "multi-cli $VERSION  --  Windows"
    Write-Host ""
    Write-Host "Profile storage: $BASE"
    if (Test-Path $BASE) {
        try {
            $t = Join-Path $BASE '.write-test'
            New-Item -ItemType File -Path $t -Force | Out-Null
            Remove-Item $t -Force
            Write-Host "  [OK] writable" -ForegroundColor Green
        } catch { Write-Host "  [FAIL] not writable" -ForegroundColor Red; $errors++ }
    } else {
        Write-Host "  [INFO] not yet created (will be created on first profile)"
    }

    if (Test-AliasDirInPath) { Write-Host "Alias dir in PATH: yes" -ForegroundColor Green }
    else { Write-Host "Alias dir in PATH: no  ($((Get-AliasDir)) -- add to PATH for shorthand commands)" -ForegroundColor Yellow; $warnings++ }

    Write-Host ""
    Write-Host "Tools:"
    foreach ($a in (Get-Adapters | Sort-Object id)) {
        $bin = Find-AdapterBinary $a
        $support = if ($a.support -and $a.support.windows) { $a.support.windows } else { $null }
        if ($bin) { Write-Host "  [OK]   $($a.id) -> $bin" -ForegroundColor Green }
        else {
            $hint = if ($a.install) { "  install: $($a.install)" } else { '' }
            Write-Host "  [MISS] $($a.id)$hint" -ForegroundColor DarkGray
        }
        if ($support -and $support.reason) {
            if ($support.level -eq 'unsupported') {
                Write-Host "         $($support.level): $($support.reason)" -ForegroundColor Yellow
            } else {
                Write-Host "         $($support.level): $($support.reason)"
            }
        }
    }

    if ($Deep -eq '--deep' -and (Test-Path $BASE)) {
        Write-Host ""
        Write-Host "Runtime overlays:"
        $metadataFiles = @(Get-RuntimeFilesNoReparse $BASE | Where-Object { (Split-Path -Leaf $_) -eq '.profile.json' })
        foreach ($metadataFile in $metadataFiles) {
            $profileDir = Split-Path -Parent $metadataFile
            $runtimeDir = Join-Path $profileDir '.runtime'
            if (-not (Test-Path -LiteralPath $runtimeDir -PathType Container)) { continue }
            $manifestPath = Join-Path $runtimeDir '.runtime-manifest'
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                Write-Host "  [WARN] missing .runtime-manifest in $profileDir -- relaunch the profile to rebuild the runtime overlay" -ForegroundColor Yellow
                $warnings++
                continue
            }
            $manifestEntries = @{}
            foreach ($line in @(Get-Content -LiteralPath $manifestPath)) {
                if (-not $line) { continue }
                $entry = ($line -replace '\\', '/').Trim()
                if ($entry) { $manifestEntries[$entry] = $true }
            }
            foreach ($file in @(Get-RuntimeFilesNoReparse $runtimeDir)) {
                $relative = ($file.Substring($runtimeDir.Length).TrimStart('\', '/') -replace '\\', '/')
                if ($relative -eq '.runtime-manifest') { continue }
                if ($manifestEntries.ContainsKey($relative)) { continue }
                Write-Host "  [WARN] unexpected runtime file $relative in $profileDir -- adapter classification defect" -ForegroundColor Yellow
                $warnings++
            }
        }
    }

    Write-Host ""
    if ($errors -eq 0 -and $warnings -eq 0) {
        Write-Host "All good." -ForegroundColor Green
        return
    }
    if ($errors -eq 0) {
        Write-Host "$warnings warning(s)." -ForegroundColor Yellow
        if ($Deep -ne '--deep') { return }
    } else {
        Write-Host "$errors error(s), $warnings warning(s)." -ForegroundColor Red
    }
    exit 1
}

function Show-Stats {
    if (-not (Test-Path $BASE)) { Write-Host "No profiles yet."; return }
    Write-Host ("{0,-30} {1}" -f 'PROFILE', 'SIZE')
    foreach ($toolDir in Get-ChildItem -Directory -Path $BASE | Where-Object { $_.Name -notmatch '^\.' -and $_.Name -ne 'bin' }) {
        foreach ($p in Get-ChildItem -Directory -Path $toolDir.FullName -ErrorAction SilentlyContinue) {
            Write-Host ("{0,-30} {1}" -f "$($toolDir.Name)/$($p.Name)", (Get-FolderSize $p.FullName))
        }
    }
    Write-Host ""
    Write-Host "Total: $(Get-FolderSize $BASE)"
}

function Show-Status { Show-List }

# =============================================================================
# Templates / export / import
# =============================================================================

# multi-cli template save|list|delete: legacy profiles copy wholesale minus
# known credential files; schema-v2 profiles go through the allowlist
# transfer (Save-MultiCliTemplate).
function Invoke-Template {
    param([string]$Sub, [string]$A, [string]$B)
    switch ($Sub) {
        'save' {
            if (-not $A -or -not $B) { throw "Usage: multi-cli template save <tool>/<profile> <name>" }
            $p = Split-ProfileSpec $A
            $srcDir = Get-ProfileDir $p.Tool $p.Name
            if (-not (Test-Path $srcDir)) { throw "Profile '$A' does not exist" }
            Test-ProfileName $B
            if (Test-Path -LiteralPath (Join-Path $srcDir '.profile.json')) {
                Import-Module (Resolve-MultiCliModulePath 'MultiCli.Transfer.psm1') -Force
                Save-MultiCliTemplate -Adapter (Get-Adapter $p.Tool) -ProfileDir $srcDir -TemplatesRoot (Get-TemplatesDir) -Name $B
                Write-Host "Saved template '$B' from '$A'"
                return
            }
            Throw-LegacyTransferBlocked -Action 'save a template from' -Spec $A
        }
        'list' {
            $tplDir = Get-TemplatesDir
            Write-Host "Templates:"
            if (-not (Test-Path $tplDir)) { Write-Host "  (none)"; return }
            $items = Get-ChildItem -Directory -Path $tplDir
            if (-not $items) { Write-Host "  (none)"; return }
            foreach ($t in $items) { Write-Host ("  {0,-20} {1}" -f $t.Name, (Get-FolderSize $t.FullName)) }
        }
        'delete' {
            if (-not $A) { throw "Usage: multi-cli template delete <name>" }
            Test-ProfileName $A
            $dest = Join-Path (Get-TemplatesDir) $A
            if (-not (Test-Path $dest)) { throw "Template '$A' does not exist" }
            Remove-Item -Recurse -Force $dest
            Write-Host "Deleted template '$A'"
        }
        default { throw "Usage: multi-cli template <save|list|delete>" }
    }
}

# multi-cli export: schema-v2 profiles export via the allowlist transfer;
# legacy profiles zip the whole profile dir.
function Invoke-Export {
    param([string]$Spec, [string]$OutPath)
    $p = Split-ProfileSpec $Spec
    $srcDir = Get-ProfileDir $p.Tool $p.Name
    if (-not (Test-Path $srcDir)) { throw "Profile '$Spec' does not exist" }
    if (-not $OutPath) { $OutPath = ".\$($p.Tool)-$($p.Name).zip" }
    if (Test-Path -LiteralPath (Join-Path $srcDir '.profile.json')) {
        Import-Module (Resolve-MultiCliModulePath 'MultiCli.Transfer.psm1') -Force
        Export-MultiCliProfile -Adapter (Get-Adapter $p.Tool) -ProfileDir $srcDir -OutPath $OutPath -ProfileName $p.Name
        Write-Host "Exported '$Spec' to $OutPath"
        return
    }
    Throw-LegacyTransferBlocked -Action 'export' -Spec $Spec
}

# multi-cli import: schema-v2 archives are validated and re-identified by the
# transfer; legacy zips expand into the fresh profile dir.
function Invoke-Import {
    param([string]$ArchivePath, [string]$Spec)
    if (-not (Test-Path $ArchivePath)) { throw "File not found: $ArchivePath" }
    if (-not $Spec) { throw "Usage: multi-cli import <archive> <tool>/<name>" }
    $p = Split-ProfileSpec $Spec
    Test-ProfileName $p.Name
    $adapter = Get-Adapter $p.Tool
    $destDir = Get-ProfileDir $p.Tool $p.Name
    if (Test-Path $destDir) { throw "Profile '$Spec' already exists" }

    New-Item -ItemType Directory -Force -Path (Get-ToolProfilesDir $p.Tool) | Out-Null
    if ((Get-ObjectPropertySafe -Object $adapter -Name 'schemaVersion') -eq 2) {
        Import-Module (Resolve-MultiCliModulePath 'MultiCli.Transfer.psm1') -Force
        Import-MultiCliProfile -Adapter $adapter -ArchivePath $ArchivePath -DestinationDir $destDir
    } else {
        Throw-LegacyTransferBlocked -Action 'import into' -Spec $Spec
    }
    New-AliasScript -Tool $p.Tool -Name $p.Name
    New-StartMenuShortcut -Tool $p.Tool -Name $p.Name -Adapter $adapter | Out-Null
    Write-Host "Imported '$Spec'"
}

# =============================================================================
# Legacy -> schema-v2 migration
# =============================================================================

# multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]: legacy ->
# schema-v2 migration; the engine returns plan/output lines, the launcher
# prints them.
function Invoke-Migrate {
    param([string]$Spec, [string[]]$Tokens)
    $dryRun = $false; $preferProfile = $false
    foreach ($token in @($Tokens)) {
        switch ($token) {
            '--dry-run'        { $dryRun = $true }
            '--prefer-profile' { $preferProfile = $true }
        }
    }
    $p = Split-ProfileSpec $Spec
    Test-ProfileName $p.Name
    $adapter = Get-Adapter $p.Tool
    $profileDir = Get-ProfileDir $p.Tool $p.Name
    if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) { throw "Profile '$Spec' does not exist" }
    Import-Module (Resolve-MultiCliModulePath 'MultiCli.Migration.psm1') -Force
    $result = Invoke-MultiCliMigration -Adapter $adapter -ProfileDir $profileDir -DryRun:$dryRun -PreferProfile:$preferProfile
    foreach ($line in @($result.Lines)) { Write-Host $line }
    if ($result.Migrated) { Write-Host "Migrated $Spec to schema-v2 (accountOverlay)." }
}

# =============================================================================
# Help / completion
# =============================================================================

function Show-Help {
@"
multi-cli $VERSION -- sandboxed profiles for CLIs, IDEs, and GUI apps

USAGE
  multi-cli <command> [args]

COMMANDS
  new <tool>/<name> [--shared] [--isolated] [--cli] [--from <tpl>] [--no-seed]   Create a profile
  launch <tool>/<name> [-- args...]                     Launch the profile
  continue <tool> <src> <dest> [--no-merge] [--dry-run] Copy a chat session src->dest ('base' = real home)
  migrate <tool>/<name> [--dry-run] [--prefer-profile]  Migrate a legacy profile to schema-v2
  list [<tool>]                                         List profiles
  status                                                Same as list
  rename <tool>/<old> <tool>/<new>                      Rename
  delete <tool>/<name>                                  Delete (confirms)
  clone <tool>/<src> <tool>/<dest>                      Clone
  template save <tool>/<profile> <name>                 Save as template
  template list | delete <name>                         Manage templates
  export <tool>/<name> [path]                           Export to .zip
  import <archive> <tool>/<name>                        Import from .zip
  tools                                                 List supported tools
  doctor                                                Diagnose environment
  stats                                                 Storage usage
  completion powershell                                 Print completion script
  help | version                                        This / version

PROFILE SHORTHAND
  multi-cli <tool>/<name> [args...]   -- same as `launch`

ENVIRONMENT
  MULTICLI_HOME              Profile storage root (default ~/MultiCliProfiles)
  MULTICLI_OVERRIDE_BINARY   Override binary discovery for the next launch

EXAMPLES
  multi-cli new claude-cli/work
  multi-cli new codex/acme --isolated
  multi-cli new opencode/personal --isolated
  multi-cli launch codex/acme -- exec --search "fix the build"
  multi-cli continue codex rate-limited fresh-account   # resume a chat under another account
  claude-cli-work          # via auto-generated alias on `$PATH

"@ | Write-Host
}

function Show-Completion {
    param([string]$Shell = 'powershell')
    if ($Shell -ne 'powershell') {
        Write-Host "Only 'powershell' completion is supported on Windows."
        return
    }
@"
Register-ArgumentCompleter -Native -CommandName multi-cli -ScriptBlock {
    param(`$wordToComplete, `$commandAst, `$cursorPosition)
    `$base = if (`$env:MULTICLI_HOME) { `$env:MULTICLI_HOME } else { Join-Path `$env:USERPROFILE 'MultiCliProfiles' }
    `$tools = (Get-ChildItem -Directory '$ToolsDir' -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path `$_.FullName 'adapter.json') }).Name
    `$cmds = @('new','launch','continue','migrate','list','status','rename','delete','clone','template','export','import','tools','doctor','stats','completion','help','version')
    `$specs = @()
    foreach (`$t in `$tools) {
        `$dir = Join-Path `$base `$t
        if (Test-Path `$dir) {
            foreach (`$p in (Get-ChildItem -Directory `$dir -ErrorAction SilentlyContinue)) {
                `$specs += "`$t/`$(`$p.Name)"
            }
        }
    }
    (`$cmds + `$tools + `$specs) | Where-Object { `$_ -like "`$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(`$_, `$_, 'ParameterValue', `$_)
    }
}
"@ | Write-Host
}

# =============================================================================
# Main dispatch
# =============================================================================

# Split launch tokens on the first '--': tokens after it pass to the binary
# verbatim; without a delimiter everything is a passthrough arg.
function Split-LaunchArgs {
    param([string[]]$All)
    $idx = [Array]::IndexOf($All, '--')
    if ($idx -ge 0) {
        $pre = if ($idx -gt 0) { $All[0..($idx - 1)] } else { @() }
        $post = if ($idx + 1 -lt $All.Count) { $All[($idx + 1)..($All.Count - 1)] } else { @() }
        return [pscustomobject]@{ Pre = $pre; Post = $post; HadDelim = $true }
    }
    return [pscustomobject]@{ Pre = $All; Post = @(); HadDelim = $false }
}

# Parse 'new' flags (--shared/--isolated/--cli/--no-seed/--from <tpl>) from
# the token list; unknown tokens are ignored so forward compatibility holds.
function Read-NewFlags {
    param([string[]]$Tokens)
    $shared = $false; $cli = $false; $tpl = ''; $noSeed = $false; $isolated = $false
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        switch ($Tokens[$i]) {
            '--shared'  { $shared = $true }
            '--isolated' { $isolated = $true }
            '--isolate'  { $isolated = $true }
            '-i'         { $isolated = $true }
            '--cli'     { $cli = $true }
            '--no-seed' { $noSeed = $true }
            '--from' {
                $i++
                if ($i -ge $Tokens.Count -or $Tokens[$i].StartsWith('-')) { throw 'Usage: --from <template>' }
                $tpl = $Tokens[$i]
            }
            default { throw "Unknown option for new: '$($Tokens[$i])'. Run: multi-cli help" }
        }
    }
    return [pscustomobject]@{ Shared = $shared; Cli = $cli; FromTemplate = $tpl; NoSeed = $noSeed; Isolated = $isolated }
}

# Parse 'continue' args: flags anywhere, positionals are tool, src, dest.
function Read-ContinueArgs {
    param([string[]]$Tokens)
    $noMerge = $false; $dryRun = $false; $positional = @()
    foreach ($t in $Tokens) {
        switch ($t) {
            '--no-merge' { $noMerge = $true }
            '--dry-run'  { $dryRun = $true }
            default      { $positional += $t }
        }
    }
    return [pscustomobject]@{
        Tool    = $positional[0]
        SrcName = $positional[1]
        DestName = $positional[2]
        NoMerge = $noMerge
        DryRun  = $dryRun
    }
}

try {
    switch ($Cmd) {
        'new' {
            $tokens = @()
            if ($Arg2) { $tokens += $Arg2 }
            if ($ForwardArgs) { $tokens += $ForwardArgs }
            $flags = Read-NewFlags $tokens
            New-Profile -Spec $Arg1 -Shared $flags.Shared -Cli $flags.Cli -FromTemplate $flags.FromTemplate -NoSeed $flags.NoSeed -Isolated ($flags.Isolated -or $WholeRoot)
        }
        'auth' {
            $action = $Arg1
            $spec = $Arg2
            Invoke-Auth -Action $action -Spec $spec
        }
        'continue' {
            $tokens = @()
            if ($Arg1) { $tokens += $Arg1 }
            if ($Arg2) { $tokens += $Arg2 }
            if ($ForwardArgs) { $tokens += $ForwardArgs }
            $ca = Read-ContinueArgs $tokens
            Invoke-Continue -Tool $ca.Tool -SrcName $ca.SrcName -DestName $ca.DestName -NoMerge $ca.NoMerge -DryRun $ca.DryRun
        }
        'migrate' {
            $tokens = @()
            if ($Arg2) { $tokens += $Arg2 }
            if ($ForwardArgs) { $tokens += $ForwardArgs }
            Invoke-Migrate -Spec $Arg1 -Tokens $tokens
        }
        'launch' {
            $forward = @()
            if ($Arg2) { $forward += $Arg2 }
            if ($ForwardArgs) { $forward += $ForwardArgs }
            $split = Split-LaunchArgs $forward
            $passthrough = if ($split.HadDelim) { $split.Post } else { $split.Pre }
            Invoke-Launch -Spec $Arg1 -BinaryArgs $passthrough
        }
        'list'    { Show-List $Arg1 }
        'status'  { Show-Status }
        'rename'  { Rename-Profile $Arg1 $Arg2 }
        'delete'  { Remove-Profile $Arg1 }
        'clone'   { Copy-ProfileTo $Arg1 $Arg2 }
        'template' {
            $third = if ($ForwardArgs -and $ForwardArgs.Count -gt 0) { $ForwardArgs[0] } else { $null }
            Invoke-Template -Sub $Arg1 -A $Arg2 -B $third
        }
        'export'  { Invoke-Export $Arg1 $Arg2 }
        'import'  { Invoke-Import $Arg1 $Arg2 }
        'tools'   { Show-Tools }
        'doctor'  {
            $tokens = @()
            if ($Arg1) { $tokens += $Arg1 }
            if ($Arg2) { $tokens += $Arg2 }
            if ($ForwardArgs) { $tokens += $ForwardArgs }
            $deep = ''
            foreach ($token in $tokens) { if ($token -eq '--deep') { $deep = '--deep' } }
            Show-Doctor -Deep $deep
        }
        'stats'   { Show-Stats }
        'completion' { Show-Completion ($(if ($Arg1) { $Arg1 } else { 'powershell' })) }
        'help'      { Show-Help }
        '--help'    { Show-Help }
        '-h'        { Show-Help }
        'version'   { Write-Host "multi-cli $VERSION" }
        '--version' { Write-Host "multi-cli $VERSION" }
        '-v'        { Write-Host "multi-cli $VERSION" }
        ''          { Show-Help; exit 1 }
        default {
            if ($Cmd -match '/') {
                $forward = @()
                if ($Arg1) { $forward += $Arg1 }
                if ($Arg2) { $forward += $Arg2 }
                if ($ForwardArgs) { $forward += $ForwardArgs }
                $split = Split-LaunchArgs $forward
                $passthrough = if ($split.HadDelim) { $split.Post } else { $split.Pre }
                Invoke-Launch -Spec $Cmd -BinaryArgs $passthrough
            } else {
                Write-Host "Unknown command: $Cmd"
                Show-Help
                exit 1
            }
        }
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
