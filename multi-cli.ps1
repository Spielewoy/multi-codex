<#
.SYNOPSIS
  multi-cli.ps1 -- Run multiple sandboxed profiles of any supported AI CLI or IDE.

.DESCRIPTION
  Adapter-driven launcher: each supported tool (codex, claude-cli, cursor,
  opencode, commandcode, gemini-cli) ships an adapter.json
  describing how to find its binary and how to isolate its state. multi-cli reads
  the adapter and applies one of four isolation strategies: env, userDataDir,
  redirectHome, or appdata.

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

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardArgs
)

$ErrorActionPreference = 'Stop'
$VERSION = '0.1.0'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ToolsDir  = $ScriptDir
$BASE = if ($env:MULTICLI_HOME) { $env:MULTICLI_HOME } else { Join-Path $env:USERPROFILE 'MultiCliProfiles' }

# =============================================================================
# Adapter loading
# =============================================================================

function Get-Adapters {
    if (-not (Test-Path $ToolsDir)) { return @() }
    $adapters = @()
    foreach ($dir in Get-ChildItem -Directory -Path $ToolsDir) {
        $manifest = Join-Path $dir.FullName 'adapter.json'
        if (Test-Path $manifest) {
            try {
                $adapters += (Get-Content $manifest -Raw | ConvertFrom-Json)
            } catch {
                Write-Warning "Skipping invalid adapter at $manifest : $_"
            }
        }
    }
    return $adapters
}

function Get-Adapter {
    param([string]$ToolId)
    $manifest = Join-Path (Join-Path $ToolsDir $ToolId) 'adapter.json'
    if (-not (Test-Path $manifest)) { throw "Unknown tool '$ToolId'. Run: multi-cli tools" }
    return Get-Content $manifest -Raw | ConvertFrom-Json
}

function Resolve-PathToken {
    param([string]$Path)
    if (-not $Path) { return $Path }
    $expanded = $Path -replace '\$HOME', $env:USERPROFILE.Replace('\', '\\')
    return [Environment]::ExpandEnvironmentVariables($expanded)
}

function Find-AdapterBinary {
    param($Adapter)
    if ($env:MULTICLI_OVERRIDE_BINARY) { return $env:MULTICLI_OVERRIDE_BINARY }
    $candidates = @()
    if ($Adapter.binary.windows) { $candidates += $Adapter.binary.windows }
    foreach ($c in $candidates) {
        $resolved = Resolve-PathToken $c
        if (Test-Path $resolved -ErrorAction SilentlyContinue) { return $resolved }
        $cmd = Get-Command $resolved -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

# =============================================================================
# Session continuation
# =============================================================================

$SESSION_RESERVED_ENDPOINT = 'base'

# Skip automatic session seeding when the base state exceeds this size.
$SEED_MAX_BYTES = 500 * 1024 * 1024

function Get-AdapterSystemHome {
    param($Adapter)
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
    if (-not $srcItem) { return }
    if (Test-IsReparsePoint $srcItem) { return }
    if (Test-Path -LiteralPath $Source -PathType Leaf) {
        Copy-SessionFile -Source $Source -Destination $Destination -NoMerge $NoMerge -DryRun $DryRun -Copied $Copied -Skipped $Skipped
        return
    }
    $sourceRoot = [System.IO.Path]::GetFullPath($Source)
    $items = Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        if (Test-IsReparsePoint $item) { continue }
        $resolved = [System.IO.Path]::GetFullPath($item.FullName)
        if (-not $resolved.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }
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

function Invoke-Continue {
    param([string]$Tool, [string]$SrcName, [string]$DestName, [bool]$NoMerge = $false, [bool]$DryRun = $false)
    if (-not $Tool -or -not $SrcName -or -not $DestName) {
        throw "Usage: multi-cli continue <tool> <src-profile> <dest-profile> [--no-merge] [--dry-run]"
    }
    $adapter = Get-Adapter $Tool

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
        $p = Join-Path $Root ($entry -replace '/', '\')
        if (-not (Test-Path $p)) { continue }
        $sum = (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
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

function Split-ProfileSpec {
    param([string]$Spec)
    if (-not $Spec) { throw "Profile required: <tool>/<name>" }
    if ($Spec -notmatch '/') { throw "Profile must be in form <tool>/<name>. Got: '$Spec'" }
    $parts = $Spec.Split('/', 2)
    return [pscustomobject]@{ Tool = $parts[0]; Name = $parts[1] }
}

function Test-ProfileName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { throw "Profile name required" }
    if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]*$') {
        throw "Profile name '$Name' invalid: must start with alphanumeric, contain only letters/numbers/hyphens"
    }
}

function Get-ProfileDir { param([string]$Tool,[string]$Name) Join-Path (Join-Path $BASE $Tool) $Name }
function Get-ToolProfilesDir { param([string]$Tool) Join-Path $BASE $Tool }
function Get-AliasDir { Join-Path $BASE 'bin' }
function Get-TemplatesDir { Join-Path $BASE '.templates' }

# =============================================================================
# Profile CRUD
# =============================================================================

function New-Profile {
    param([string]$Spec, [bool]$Shared = $false, [bool]$Cli = $false, [string]$FromTemplate = '', [bool]$NoSeed = $false)

    $p = Split-ProfileSpec $Spec
    Test-ProfileName $p.Name
    $adapter = Get-Adapter $p.Tool
    $profileDir = Get-ProfileDir $p.Tool $p.Name

    if (Test-Path $profileDir) { throw "Profile '$Spec' already exists" }
    New-Item -ItemType Directory -Force -Path (Get-ToolProfilesDir $p.Tool) | Out-Null

    if ($FromTemplate) {
        $tplDir = Join-Path (Get-TemplatesDir) $FromTemplate
        if (-not (Test-Path $tplDir)) { throw "Template '$FromTemplate' not found" }
        Copy-Item -Path $tplDir -Destination $profileDir -Recurse
    } elseif ($Shared) {
        New-SharedProfile -Adapter $adapter -ProfileDir $profileDir
    } else {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }

    if (-not $NoSeed -and -not $FromTemplate) {
        Initialize-ProfileSeed -Adapter $adapter -ProfileDir $profileDir -Shared $Shared
    }

    if ($adapter.isolation.strategy -eq 'redirectHome') {
        $homeDir = Join-Path $profileDir '_home'
        New-Item -ItemType Directory -Force -Path $homeDir | Out-Null
        Set-RedirectHomeDotfileLinks -Adapter $adapter -HomeDir $homeDir
    }

    if ($Cli) { New-Item -ItemType File -Force -Path (Join-Path $profileDir '.cli') | Out-Null }

    New-AliasScript -Tool $p.Tool -Name $p.Name
    New-StartMenuShortcut -Tool $p.Tool -Name $p.Name -Adapter $adapter | Out-Null

    Write-Host "Created profile $Spec ($($adapter.displayName), strategy=$($adapter.isolation.strategy))"
    if (-not (Test-AliasDirInPath)) {
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

function Remove-Profile {
    param([string]$Spec)
    $p = Split-ProfileSpec $Spec
    Test-ProfileName $p.Name
    $profileDir = Get-ProfileDir $p.Tool $p.Name
    if (-not (Test-Path $profileDir)) { throw "Profile '$Spec' does not exist" }

    $confirm = Read-Host "Delete profile '$Spec' and all its data? [y/N]"
    if ($confirm -notmatch '^[Yy]$') { Write-Host "Aborted."; return }

    Remove-Item -Recurse -Force $profileDir
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
    Copy-Item -Path $srcDir -Destination $destDir -Recurse
    New-AliasScript -Tool $b.Tool -Name $b.Name
    New-StartMenuShortcut -Tool $b.Tool -Name $b.Name -Adapter (Get-Adapter $b.Tool) | Out-Null
    Write-Host "Cloned '$SrcSpec' to '$DestSpec'"
}

# =============================================================================
# Aliases & shortcuts
# =============================================================================

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

function Test-AliasDirInPath {
    $dir = Get-AliasDir
    return ($env:PATH -split ';') -contains $dir
}

function New-StartMenuShortcut {
    param([string]$Tool, [string]$Name, $Adapter)
    try {
        $linkName = "multi-cli $Tool $Name.lnk"
        $linkPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$linkName"
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut($linkPath)
        $shortcut.TargetPath = 'powershell.exe'
        $scriptPath = $MyInvocation.MyCommand.Definition
        if (-not $scriptPath) { $scriptPath = $PSCommandPath }
        $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$scriptPath`" launch $Tool/$Name"
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

function Invoke-Launch {
    param([string]$Spec, [string[]]$BinaryArgs = @())
    $p = Split-ProfileSpec $Spec
    $adapter = Get-Adapter $p.Tool
    $profileDir = Get-ProfileDir $p.Tool $p.Name
    if (-not (Test-Path $profileDir)) { throw "Profile '$Spec' does not exist. Create with: multi-cli new $Spec" }

    $binary = Find-AdapterBinary $adapter
    if (-not $binary) {
        $hint = if ($adapter.install) { " ($($adapter.install))" } else { '' }
        throw "$($adapter.displayName) binary not found.$hint"
    }

    Write-Host "Launching $($adapter.displayName) profile '$Spec' [$($adapter.isolation.strategy)]"

    switch ($adapter.isolation.strategy) {
        'env'           { Invoke-LaunchEnv          -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs }
        'userDataDir'   { Invoke-LaunchUserDataDir  -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs }
        'redirectHome'  { Invoke-LaunchRedirectHome -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs }
        'appdata'       { Invoke-LaunchAppData      -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs }
        'sandboxUser'   { Invoke-LaunchSandboxUser  -Adapter $adapter -ProfileDir $profileDir -Binary $binary -BinaryArgs $BinaryArgs }
        default         { throw "Unknown isolation strategy '$($adapter.isolation.strategy)' for $($adapter.id)" }
    }
}

function Expand-Placeholder {
    param([string]$Value, [string]$ProfileDir)
    return $Value.Replace('{profileDir}', $ProfileDir)
}

function Invoke-LaunchEnv {
    param($Adapter, [string]$ProfileDir, [string]$Binary, [string[]]$BinaryArgs)
    $envMap = @{}
    foreach ($prop in $Adapter.isolation.env.PSObject.Properties) {
        $envMap[$prop.Name] = (Expand-Placeholder $prop.Value $ProfileDir)
    }
    Start-WithEnv -Binary $Binary -BinaryArgs $BinaryArgs -EnvMap $envMap
}

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

function Invoke-LaunchAppData {
    param($Adapter, [string]$ProfileDir, [string]$Binary, [string[]]$BinaryArgs)
    $appdata = Join-Path $ProfileDir 'AppData\Roaming'
    New-Item -ItemType Directory -Force -Path $appdata | Out-Null
    Start-WithEnv -Binary $Binary -BinaryArgs $BinaryArgs -EnvMap @{ APPDATA = $appdata }
}

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

function Remove-SandboxUser {
    param([string]$Name)
    $username = "mcli_$Name"
    if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $username
    }
}

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

function Start-WithEnv {
    param([string]$Binary, [string[]]$BinaryArgs, [hashtable]$EnvMap)
    $original = @{}
    foreach ($k in $EnvMap.Keys) {
        $original[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
        [Environment]::SetEnvironmentVariable($k, $EnvMap[$k], 'Process')
    }
    try {
        if ($BinaryArgs -and $BinaryArgs.Count -gt 0) { & $Binary @BinaryArgs } else { & $Binary }
    } finally {
        foreach ($k in $original.Keys) {
            [Environment]::SetEnvironmentVariable($k, $original[$k], 'Process')
        }
    }
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

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '0 B' }
    $size = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
    if (-not $size) { $size = 0 }
    Format-Bytes $size
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
        $status = if ($a.status) { $a.status } else { '?' }
        Write-Host ("  {0,-18} {1,-12} {2,-15} {3,-10} {4}" -f $a.id, $a.kind, $a.isolation.strategy, $status, $installed) -ForegroundColor $color
    }
}

function Show-Doctor {
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
        if ($bin) { Write-Host "  [OK]   $($a.id) -> $bin" -ForegroundColor Green }
        else {
            $hint = if ($a.install) { "  install: $($a.install)" } else { '' }
            Write-Host "  [MISS] $($a.id)$hint" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    if ($errors -eq 0 -and $warnings -eq 0) { Write-Host "All good." -ForegroundColor Green }
    elseif ($errors -eq 0) { Write-Host "$warnings warning(s)." -ForegroundColor Yellow }
    else { Write-Host "$errors error(s), $warnings warning(s)." -ForegroundColor Red }
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

function Invoke-Template {
    param([string]$Sub, [string]$A, [string]$B)
    switch ($Sub) {
        'save' {
            if (-not $A -or -not $B) { throw "Usage: multi-cli template save <tool>/<profile> <name>" }
            $p = Split-ProfileSpec $A
            $srcDir = Get-ProfileDir $p.Tool $p.Name
            if (-not (Test-Path $srcDir)) { throw "Profile '$A' does not exist" }
            Test-ProfileName $B
            $tplDir = Get-TemplatesDir
            New-Item -ItemType Directory -Force -Path $tplDir | Out-Null
            $dest = Join-Path $tplDir $B
            if (Test-Path $dest) { throw "Template '$B' already exists" }
            Copy-Item -Path $srcDir -Destination $dest -Recurse
            foreach ($f in @('.shared', '.cli', 'auth.json', '.credentials.json', 'oauth_creds.json')) {
                $strip = Join-Path $dest $f
                if (Test-Path $strip) { Remove-Item -Recurse -Force $strip }
            }
            Write-Host "Saved template '$B' from '$A'"
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

function Invoke-Export {
    param([string]$Spec, [string]$OutPath)
    $p = Split-ProfileSpec $Spec
    $srcDir = Get-ProfileDir $p.Tool $p.Name
    if (-not (Test-Path $srcDir)) { throw "Profile '$Spec' does not exist" }
    if (-not $OutPath) { $OutPath = ".\$($p.Tool)-$($p.Name).zip" }
    Compress-Archive -Path $srcDir -DestinationPath $OutPath -Force
    Write-Host "Exported '$Spec' to $OutPath"
}

function Invoke-Import {
    param([string]$ArchivePath, [string]$Spec)
    if (-not (Test-Path $ArchivePath)) { throw "File not found: $ArchivePath" }
    if (-not $Spec) { throw "Usage: multi-cli import <archive> <tool>/<name>" }
    $p = Split-ProfileSpec $Spec
    Test-ProfileName $p.Name
    Get-Adapter $p.Tool | Out-Null
    $destDir = Get-ProfileDir $p.Tool $p.Name
    if (Test-Path $destDir) { throw "Profile '$Spec' already exists" }

    New-Item -ItemType Directory -Force -Path (Get-ToolProfilesDir $p.Tool) | Out-Null
    $tmp = Join-Path $env:TEMP "multicli_import_$(Get-Random)"
    Expand-Archive -Path $ArchivePath -DestinationPath $tmp -Force
    $top = Get-ChildItem -Directory -Path $tmp
    if ($top.Count -eq 1) {
        Move-Item -Path $top[0].FullName -Destination $destDir
        Remove-Item $tmp -Recurse -Force
    } else {
        Move-Item -Path $tmp -Destination $destDir
    }
    New-AliasScript -Tool $p.Tool -Name $p.Name
    New-StartMenuShortcut -Tool $p.Tool -Name $p.Name -Adapter (Get-Adapter $p.Tool) | Out-Null
    Write-Host "Imported '$Spec'"
}

# =============================================================================
# Help / completion
# =============================================================================

function Show-Help {
@"
multi-cli $VERSION -- sandboxed profiles for AI CLIs and agent IDEs

USAGE
  multi-cli <command> [args]

COMMANDS
  new <tool>/<name> [--shared] [--cli] [--from <tpl>] [--no-seed]   Create a profile
  launch <tool>/<name> [-- args...]                     Launch the profile
  continue <tool> <src> <dest> [--no-merge] [--dry-run] Copy a chat session src->dest ('base' = real home)
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
  multi-cli new cursor/personal --shared
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
    `$tools = (Get-ChildItem -Directory '$ScriptDir/tools' -ErrorAction SilentlyContinue).Name
    `$cmds = @('new','launch','continue','list','status','rename','delete','clone','template','export','import','tools','doctor','stats','completion','help','version')
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

function Read-NewFlags {
    param([string[]]$Tokens)
    $shared = $false; $cli = $false; $tpl = ''; $noSeed = $false
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        switch ($Tokens[$i]) {
            '--shared'  { $shared = $true }
            '--cli'     { $cli = $true }
            '--no-seed' { $noSeed = $true }
            '--from'    { $i++; if ($i -lt $Tokens.Count) { $tpl = $Tokens[$i] } }
        }
    }
    return [pscustomobject]@{ Shared = $shared; Cli = $cli; FromTemplate = $tpl; NoSeed = $noSeed }
}

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
            New-Profile -Spec $Arg1 -Shared $flags.Shared -Cli $flags.Cli -FromTemplate $flags.FromTemplate -NoSeed $flags.NoSeed
        }
        'continue' {
            $tokens = @()
            if ($Arg1) { $tokens += $Arg1 }
            if ($Arg2) { $tokens += $Arg2 }
            if ($ForwardArgs) { $tokens += $ForwardArgs }
            $ca = Read-ContinueArgs $tokens
            Invoke-Continue -Tool $ca.Tool -SrcName $ca.SrcName -DestName $ca.DestName -NoMerge $ca.NoMerge -DryRun $ca.DryRun
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
        'doctor'  { Show-Doctor }
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
