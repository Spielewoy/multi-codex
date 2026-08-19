<#
.SYNOPSIS
  Test helper for the multi-cli.ps1 session-continuation Pester suite.

.DESCRIPTION
  Builds REAL fixture trees in temp dirs (no mocks) and invokes the actual
  multi-cli.ps1 launcher in a child PowerShell process with USERPROFILE/HOME
  and MULTICLI_HOME redirected into a scratch sandbox. Also dot-sources the
  launcher's functions into the current session for unit-level branch tests.

  Owned by the Pester side only. Bash/bats owns its temporary tool cache.
#>

Set-StrictMode -Version Latest

$script:LauncherPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'multi-cli.ps1'
$script:LauncherDefsPath = $null

function Get-LauncherPath { return $script:LauncherPath }

function New-Scratch {
    <# Creates an isolated sandbox: returns an object with Root, Home (fake USERPROFILE),
       MultiCliHome (MULTICLI_HOME profile root). #>
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mctest_" + [guid]::NewGuid().ToString('N'))
    $userHome = Join-Path $root 'userhome'
    $mcHome = Join-Path $root 'profiles'
    New-Item -ItemType Directory -Force -Path $userHome | Out-Null
    New-Item -ItemType Directory -Force -Path $mcHome   | Out-Null
    $tools = Join-Path $root 'tools'
    New-Item -ItemType Directory -Force -Path (Join-Path $tools 'codex'), (Join-Path $tools 'cursor') | Out-Null
    $codexAdapter = @{
        id = 'codex'; displayName = 'OpenAI Codex CLI'; kind = 'cli'
        binary = @{ windows = @('codex'); macos = @('codex'); linux = @('codex') }
        isolation = @{ strategy = 'env'; env = @{ CODEX_HOME = '{profileDir}' } }
        share = @{ systemHome = '$HOME/.codex'; linkable = @('config.toml', 'skills', 'agents'); neverLink = @('auth.json', 'sessions', 'history.jsonl') }
        session = @{ portable = $true; paths = @('sessions', 'history.jsonl', 'archived_sessions', 'session_index.jsonl'); credentials = @('auth.json'); resumeHint = 'Resume with codex resume.' }
        status = 'legacy-test'
    }
    $cursorAdapter = @{
        id = 'cursor'; displayName = 'Cursor'; kind = 'hybrid'
        binary = @{ windows = @('cursor'); macos = @('cursor'); linux = @('cursor') }
        isolation = @{ strategy = 'userDataDir'; args = @('--user-data-dir', '{profileDir}') }
        share = @{ systemHome = '$HOME/.cursor'; linkable = @(); neverLink = @() }
        session = @{ portable = $false; reason = 'Chats live in sqlite state databases keyed to the workspace path.' }
        status = 'legacy-test'
    }
    $codexAdapter | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tools 'codex\adapter.json') -Encoding UTF8
    $cursorAdapter | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tools 'cursor\adapter.json') -Encoding UTF8
    return [pscustomobject]@{
        Root         = $root
        Home         = $userHome
        MultiCliHome = $mcHome
        Tools        = $tools
    }
}

function Remove-Scratch {
    param([pscustomobject]$Scratch)
    if ($Scratch -and (Test-Path $Scratch.Root)) {
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Scratch.Root
    }
}

function New-SessionMetaLine {
    param([string]$Id)
    # Genuine first line of a Codex rollout file.
    $payload = [ordered]@{ id = $Id }
    $obj = [ordered]@{ type = 'session_meta'; payload = $payload }
    return ($obj | ConvertTo-Json -Compress -Depth 5)
}

function Write-RolloutFile {
    <# Writes a real rollout-*.jsonl whose first line is a session_meta record. #>
    param([string]$Path, [string]$SessionId)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $lines = @(
        (New-SessionMetaLine -Id $SessionId),
        (@{ type = 'message'; payload = @{ role = 'user'; text = 'hello' } } | ConvertTo-Json -Compress -Depth 5),
        (@{ type = 'message'; payload = @{ role = 'assistant'; text = 'hi' } } | ConvertTo-Json -Compress -Depth 5)
    )
    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

function New-CodexSystemHome {
    <#
      Builds a realistic ~/.codex tree under the fake USERPROFILE:
        sessions/2026/06/11/rollout-<id>.jsonl   (real session_meta first line)
        sessions/nested/auth.json                (DECOY credential, must never copy)
        history.jsonl
        auth.json                                (real-looking credential, must never copy)
        config.toml, skills/, agents/            (linkable share assets)
      Returns the .codex path.
    #>
    param([string]$UserHome)
    $codex = Join-Path $UserHome '.codex'
    $sessionsDir = Join-Path $codex 'sessions\2026\06\11'
    New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null

    Write-RolloutFile -Path (Join-Path $sessionsDir 'rollout-2026-06-11T09-00-00-aaaa1111.jsonl') -SessionId 'aaaa1111-2222-3333-4444-555566667777'

    # history.jsonl at the codex root (a portable session path).
    $history = @(
        (@{ session_id = 'aaaa1111'; ts = 1; text = 'q1' } | ConvertTo-Json -Compress),
        (@{ session_id = 'aaaa1111'; ts = 2; text = 'q2' } | ConvertTo-Json -Compress)
    )
    Set-Content -Path (Join-Path $codex 'history.jsonl') -Value $history -Encoding UTF8

    # Real-looking credential at the root (must NEVER be copied).
    $auth = @{ OPENAI_API_KEY = 'sk-test-REAL-LOOKING-SECRET-do-not-copy'; tokens = @{ access = 'abc' } } | ConvertTo-Json -Depth 5
    Set-Content -Path (Join-Path $codex 'auth.json') -Value $auth -Encoding UTF8

    # Nested DECOY credential inside sessions/ (must NEVER be copied -- leaf-name match).
    $decoyDir = Join-Path $codex 'sessions\nested'
    New-Item -ItemType Directory -Force -Path $decoyDir | Out-Null
    Set-Content -Path (Join-Path $decoyDir 'auth.json') -Value (@{ OPENAI_API_KEY = 'sk-DECOY-nested-secret' } | ConvertTo-Json) -Encoding UTF8

    # Linkable share assets.
    Set-Content -Path (Join-Path $codex 'config.toml') -Value "model = `"o1`"`n" -Encoding UTF8
    $skillsDir = Join-Path $codex 'skills'
    New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
    Set-Content -Path (Join-Path $skillsDir 'demo.md') -Value "# demo skill`n" -Encoding UTF8
    $agentsDir = Join-Path $codex 'agents'
    New-Item -ItemType Directory -Force -Path $agentsDir | Out-Null
    Set-Content -Path (Join-Path $agentsDir 'a.md') -Value "# agent`n" -Encoding UTF8

    return $codex
}

function New-CodexProfile {
    <# Creates an empty (or pre-populated) destination profile dir under MULTICLI_HOME
       without running the launcher (avoids PATH/seed side-effects for continue tests). #>
    param([string]$MultiCliHome, [string]$Name)
    $dir = Join-Path (Join-Path $MultiCliHome 'codex') $Name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Invoke-Launcher {
    <#
      Runs multi-cli.ps1 in a child PowerShell with USERPROFILE/HOME redirected to the
      scratch fake home and MULTICLI_HOME set to the scratch profile root.
      Returns @{ ExitCode; StdOut; StdErr }.
      ToolsDirOverride lets a test point the launcher at a scratch tools dir holding a
      deliberately broken adapter (drives the adapter-bug abort end to end).
    #>
    param(
        [pscustomobject]$Scratch,
        [string[]]$Arguments,
        [string]$LauncherOverride
    )
    $launcher = if ($LauncherOverride) { $LauncherOverride } else { $script:LauncherPath }

    $argLine = ($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '""') + '"' } else { $_ }
    }) -join ' '

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command powershell.exe).Source
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`" $argLine"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $Scratch.Root

    # Redirect home + profile root so `base` and BASE resolve into the sandbox.
    $psi.EnvironmentVariables['USERPROFILE'] = $Scratch.Home
    $psi.EnvironmentVariables['HOME'] = $Scratch.Home
    $psi.EnvironmentVariables['HOMEDRIVE'] = $Scratch.Home.Substring(0, 2)
    $psi.EnvironmentVariables['HOMEPATH'] = $Scratch.Home.Substring(2)
    $psi.EnvironmentVariables['MULTICLI_HOME'] = $Scratch.MultiCliHome
    if (-not $LauncherOverride) {
        $psi.EnvironmentVariables['MULTICLI_TOOLS_DIR'] = $Scratch.Tools
    } else {
        [void]$psi.EnvironmentVariables.Remove('MULTICLI_TOOLS_DIR')
    }
    # Park APPDATA in the sandbox so Start Menu shortcut writes never touch the real profile.
    $appdata = Join-Path $Scratch.Home 'AppData\Roaming'
    New-Item -ItemType Directory -Force -Path (Join-Path $appdata 'Microsoft\Windows\Start Menu\Programs') | Out-Null
    $psi.EnvironmentVariables['APPDATA'] = $appdata

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

function Set-FileMtime {
    param([string]$Path, [datetime]$Time)
    (Get-Item $Path).LastWriteTimeUtc = $Time.ToUniversalTime()
}

function Get-RelativeFileList {
    <# Returns sorted relative paths (forward-slash) of all files under Root. #>
    param([string]$Root)
    if (-not (Test-Path $Root)) { return @() }
    $full = [System.IO.Path]::GetFullPath($Root)
    Get-ChildItem -Path $full -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName.Substring($full.Length).TrimStart('\', '/') -replace '\\', '/' } |
        Sort-Object
}

function Import-LauncherFunctions {
    <#
      Dot-sources the launcher's function definitions into the CALLER'S scope so unit
      tests can call Test-SessionAdapterBug etc. directly. We write the launcher content
      truncated at the dispatch marker (dropping the trailing try/catch that would run
      Show-Help; exit 1) to a temp .ps1, then dot-source that file. The leading param()
      block dot-sources harmlessly (parameters are simply left unbound).

      Must be called as:  . (Get-LauncherDefsPath)   OR via the convenience pattern
      used by the tests:  Import-LauncherFunctions  (dot-source happens at script scope
      because this function itself is dot-sourced from the helper).
    #>
    $defsPath = Get-LauncherDefsPath
    . $defsPath
}

function Get-LauncherDefsPath {
    <# Writes (once) a temp .ps1 holding only the launcher's definitions and returns its path. #>
    if ($script:LauncherDefsPath -and (Test-Path $script:LauncherDefsPath)) {
        return $script:LauncherDefsPath
    }
    $raw = Get-Content -Raw $script:LauncherPath
    # Truncate at the dispatch try{} block so every function definition (including the
    # arg parsers that live just below the "Main dispatch" banner) is dot-sourced, but
    # the trailing switch that would run Show-Help; exit 1 is dropped.
    $marker = "`ntry {"
    $idx = $raw.IndexOf($marker)
    if ($idx -lt 0) { throw "Could not locate dispatch try block in launcher" }
    $defs = $raw.Substring(0, $idx)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_defs_" + [guid]::NewGuid().ToString('N') + ".ps1")
    Set-Content -Path $tmp -Value $defs -Encoding UTF8
    $script:LauncherDefsPath = $tmp
    return $tmp
}

function New-BrokenAdapterToolsDir {
    <#
      Builds a scratch tools dir containing a single codex adapter whose session.paths
      OVERLAP its session.credentials -> drives Test-SessionAdapterBug to throw.
      Returns the path to a copy of multi-cli.ps1 wired to that tools dir.
    #>
    param([pscustomobject]$Scratch)
    $toolsDir = Join-Path $Scratch.Root 'broken-tools'
    $codexDir = Join-Path $toolsDir 'ai-tools\codex'
    New-Item -ItemType Directory -Force -Path $codexDir | Out-Null
    $adapter = [ordered]@{
        id          = 'codex'
        displayName = 'Broken Codex'
        kind        = 'cli'
        binary      = @{ windows = @('codex') }
        isolation   = @{ strategy = 'env'; env = @{ CODEX_HOME = '{profileDir}' } }
        share       = @{ systemHome = '$HOME/.codex'; linkable = @(); neverLink = @() }
        session     = [ordered]@{
            portable    = $true
            paths       = @('sessions', 'auth.json')   # overlaps credential below
            credentials = @('auth.json')
            resumeHint  = 'hint'
        }
        status      = 'stable'
    }
    Set-Content -Path (Join-Path $codexDir 'adapter.json') -Value ($adapter | ConvertTo-Json -Depth 6) -Encoding UTF8

    # Copy the launcher and runtime modules so its default ai-tools dir picks up the broken adapter.
    $launcherCopy = Join-Path $toolsDir 'multi-cli.ps1'
    Copy-Item -Path $script:LauncherPath -Destination $launcherCopy -Force
    $sourceLib = Join-Path (Split-Path -Parent $script:LauncherPath) 'lib'
    Copy-Item -Path $sourceLib -Destination (Join-Path $toolsDir 'lib') -Recurse -Force
    return $launcherCopy
}

function Get-UserPathSnapshot {
    return [Environment]::GetEnvironmentVariable('PATH', 'User')
}

function Restore-UserPath {
    <#
      Restores the persistent User PATH to a snapshot AND strips any mctest scratch bin
      entries the launcher may have appended. Idempotent. This is the containment for the
      launcher's documented global side effect (New-Profile appends $BASE\bin to User PATH).
    #>
    param([string]$Snapshot)
    $current = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $cleaned = ($current -split ';' | Where-Object { $_ -notmatch 'mctest_' }) -join ';'
    if ($null -ne $Snapshot) {
        $snapCleaned = ($Snapshot -split ';' | Where-Object { $_ -notmatch 'mctest_' }) -join ';'
        $cleaned = $snapCleaned
    }
    if ($cleaned -ne $current) {
        [Environment]::SetEnvironmentVariable('PATH', $cleaned, 'User')
    }
}

function Invoke-LauncherGuarded {
    <#
      Like Invoke-Launcher, but snapshots the persistent User PATH before the run and
      restores it after, neutralizing New-Profile's append-to-User-PATH side effect.
      Start Menu shortcuts are contained because Invoke-Launcher points APPDATA into the
      sandbox, so they are written under the scratch tree and removed with it.
    #>
    param(
        [pscustomobject]$Scratch,
        [string[]]$Arguments,
        [string]$LauncherOverride
    )
    $snapshot = Get-UserPathSnapshot
    try {
        return Invoke-Launcher -Scratch $Scratch -Arguments $Arguments -LauncherOverride $LauncherOverride
    } finally {
        Restore-UserPath -Snapshot $snapshot
    }
}
