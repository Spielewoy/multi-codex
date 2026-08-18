$script:ProfileRepoRoot = Split-Path -Parent $PSScriptRoot
$script:ProfileLauncher = Join-Path $script:ProfileRepoRoot 'multi-cli.ps1'
Import-Module (Join-Path $script:ProfileRepoRoot 'lib\MultiCli.CredentialStore.psm1') -Force

function Invoke-ProfileLauncher {
    param([string]$Root, [string[]]$Arguments, [string]$StdinText, [int]$TimeoutSeconds = 120)
    $userHome = Join-Path $Root 'home'
    $profiles = Join-Path $Root 'profiles'
    New-Item -ItemType Directory -Force -Path $userHome, $profiles | Out-Null
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = (Get-Command powershell.exe).Source
    $quotedArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:ProfileLauncher) + $Arguments
    $startInfo.Arguments = ($quotedArguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    foreach ($entry in @{
        USERPROFILE = $userHome
        HOME = $userHome
        APPDATA = (Join-Path $userHome 'AppData\Roaming')
        LOCALAPPDATA = (Join-Path $userHome 'AppData\Local')
        MULTICLI_HOME = $profiles
        MULTICLI_OVERRIDE_BINARY = (Get-Command powershell.exe).Source
    }.GetEnumerator()) { $startInfo.EnvironmentVariables[$entry.Key] = $entry.Value }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    if ($null -ne $StdinText) {
        $inputBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($StdinText + "`n")
        $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
    }
    $process.StandardInput.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { $process.Kill(); $process.WaitForExit() }
    $output = $stdoutTask.Result + $stderrTask.Result
    return [pscustomobject]@{
        ExitCode = $(if ($timedOut) { -1 } else { $process.ExitCode })
        Output = $output
        Profiles = $profiles
        TimedOut = $timedOut
    }
}

Describe 'schema-v2 profile safety boundaries' {
    It 'refuses process-secret launches until a profile credential is stored' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_profile_" + [guid]::NewGuid().ToString('N'))
        try {
            $new = Invoke-ProfileLauncher -Root $root -Arguments @('new', 'copilot-cli/account-a', '--no-seed')
            $new.ExitCode | Should Be 0
            $launch = Invoke-ProfileLauncher -Root $root -Arguments @('launch', 'copilot-cli/account-a')
            $launch.ExitCode | Should Be 1
            $launch.Output | Should Match 'multi-cli auth set'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'routes OS-user adapters to the owned-user runtime and reports elevation precisely' {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host 'Host is elevated; the non-admin elevation assertion is covered on standard Windows runners.'
            return
        }
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_profile_" + [guid]::NewGuid().ToString('N'))
        try {
            $new = Invoke-ProfileLauncher -Root $root -Arguments @('new', 'antigravity/account-a', '--no-seed')
            $new.ExitCode | Should Be 0
            $launch = Invoke-ProfileLauncher -Root $root -Arguments @('launch', 'antigravity/account-a')
            $launch.ExitCode | Should Be 1
            $launch.Output | Should Match 'requires an elevated terminal \(Run as Administrator\)'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses inseparable adapters and directs users to --isolated' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_profile_" + [guid]::NewGuid().ToString('N'))
        try {
            $new = Invoke-ProfileLauncher -Root $root -Arguments @('new', 'opencode/account-a', '--no-seed')
            $new.ExitCode | Should Be 0
            $launch = Invoke-ProfileLauncher -Root $root -Arguments @('launch', 'opencode/account-a')
            $launch.ExitCode | Should Be 1
            $launch.Output | Should Match 'Create this profile with --isolated'
            $launch.Output | Should Not Match 'legacy-isolated'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'auth set consumes redirected stdin without hanging and stores the exact secret' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_profile_" + [guid]::NewGuid().ToString('N'))
        $target = $null
        try {
            $new = Invoke-ProfileLauncher -Root $root -Arguments @('new', 'copilot-cli/account-a', '--no-seed')
            $new.ExitCode | Should Be 0
            $metadata = Get-Content -LiteralPath (Join-Path $root 'profiles\copilot-cli\account-a\.profile.json') -Raw | ConvertFrom-Json
            $target = "multi-cli/copilot-cli/$($metadata.profileId)/COPILOT_GITHUB_TOKEN"

            $set = Invoke-ProfileLauncher -Root $root -Arguments @('auth', 'set', 'copilot-cli/account-a') -StdinText 'redirected-secret-value'
            if ($set.ExitCode -ne 0) { Write-Host $set.Output }
            $set.TimedOut | Should Be $false
            $set.ExitCode | Should Be 0
            $set.Output | Should Match 'Stored credential for copilot-cli/account-a'
            (Get-MultiCliCredential -Target $target) | Should Be 'redirected-secret-value'
        } finally {
            if ($target) { [void](Remove-MultiCliCredential -Target $target) }
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects empty redirected auth input and stores nothing' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_profile_" + [guid]::NewGuid().ToString('N'))
        $target = $null
        try {
            $new = Invoke-ProfileLauncher -Root $root -Arguments @('new', 'copilot-cli/account-a', '--no-seed')
            $new.ExitCode | Should Be 0
            $metadata = Get-Content -LiteralPath (Join-Path $root 'profiles\copilot-cli\account-a\.profile.json') -Raw | ConvertFrom-Json
            $target = "multi-cli/copilot-cli/$($metadata.profileId)/COPILOT_GITHUB_TOKEN"

            $set = Invoke-ProfileLauncher -Root $root -Arguments @('auth', 'set', 'copilot-cli/account-a') -StdinText ''
            $set.TimedOut | Should Be $false
            $set.ExitCode | Should Be 1
            $set.Output | Should Match 'Credential input was empty'
            (Test-MultiCliCredential -Target $target) | Should Be $false
        } finally {
            if ($target) { [void](Remove-MultiCliCredential -Target $target) }
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'delete clears the profile credential from the OS credential store' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_profile_" + [guid]::NewGuid().ToString('N'))
        $target = $null
        try {
            $new = Invoke-ProfileLauncher -Root $root -Arguments @('new', 'copilot-cli/account-a', '--no-seed')
            $new.ExitCode | Should Be 0
            $metadata = Get-Content -LiteralPath (Join-Path $root 'profiles\copilot-cli\account-a\.profile.json') -Raw | ConvertFrom-Json
            $target = "multi-cli/copilot-cli/$($metadata.profileId)/COPILOT_GITHUB_TOKEN"
            Set-MultiCliCredential -Target $target -Secret 'dummy-token-delete-me'
            (Test-MultiCliCredential -Target $target) | Should Be $true

            $delete = Invoke-ProfileLauncher -Root $root -Arguments @('delete', 'copilot-cli/account-a') -StdinText 'y'
            if ($delete.ExitCode -ne 0) { Write-Host $delete.Output }
            $delete.TimedOut | Should Be $false
            $delete.ExitCode | Should Be 0
            $delete.Output | Should Match "Deleted profile 'copilot-cli/account-a'"
            (Test-Path -LiteralPath (Join-Path $root 'profiles\copilot-cli\account-a')) | Should Be $false
            (Test-MultiCliCredential -Target $target) | Should Be $false
            $target = $null
        } finally {
            if ($target) { [void](Remove-MultiCliCredential -Target $target) }
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'clone gives schema-v2 profiles a fresh identity and no credential' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_profile_" + [guid]::NewGuid().ToString('N'))
        $sourceTarget = $null
        try {
            $new = Invoke-ProfileLauncher -Root $root -Arguments @('new', 'copilot-cli/account-a', '--no-seed')
            $new.ExitCode | Should Be 0
            $source = Join-Path $root 'profiles\copilot-cli\account-a'
            $sourceMetadata = Get-Content -LiteralPath (Join-Path $source '.profile.json') -Raw | ConvertFrom-Json
            $sourceTarget = "multi-cli/copilot-cli/$($sourceMetadata.profileId)/COPILOT_GITHUB_TOKEN"
            Set-MultiCliCredential -Target $sourceTarget -Secret 'source-only-token'

            $clone = Invoke-ProfileLauncher -Root $root -Arguments @('clone', 'copilot-cli/account-a', 'copilot-cli/account-b')

            if ($clone.ExitCode -ne 0) { Write-Host $clone.Output }
            $clone.ExitCode | Should Be 0
            $destination = Join-Path $root 'profiles\copilot-cli\account-b'
            $destinationMetadata = Get-Content -LiteralPath (Join-Path $destination '.profile.json') -Raw | ConvertFrom-Json
            $destinationMetadata.profileId | Should Not Be $sourceMetadata.profileId
            $destinationTarget = "multi-cli/copilot-cli/$($destinationMetadata.profileId)/COPILOT_GITHUB_TOKEN"
            (Test-MultiCliCredential -Target $destinationTarget) | Should Be $false
        } finally {
            if ($sourceTarget) { [void](Remove-MultiCliCredential -Target $sourceTarget) }
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Minimal schema-v2 fixture tools dir (same shape as tests/OverlayState.Tests.ps1)
# so launcher behaviors can be exercised without touching the real adapters.
function New-ProfileFixtureScratch {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_profile_fixture_" + [guid]::NewGuid().ToString('N'))
    $userHome = Join-Path $root 'home'
    $profiles = Join-Path $root 'profiles'
    $tools = Join-Path $root 'tools'
    New-Item -ItemType Directory -Force -Path $userHome, $profiles, (Join-Path $tools 'fixture') | Out-Null
    return [pscustomobject]@{ Root = $root; UserHome = $userHome; Profiles = $profiles; Tools = $tools }
}

function Write-ProfileFixtureAdapter {
    param($Scratch)
    $adapter = [ordered]@{
        schemaVersion = 2
        id = 'fixture'
        displayName = 'Fixture CLI'
        kind = 'cli'
        binary = [ordered]@{ windows = @('fixture.exe'); macos = @('fixture'); linux = @('fixture') }
        isolation = [ordered]@{
            strategy = 'accountOverlay'
            mode = 'foreground'
            env = [ordered]@{ FIXTURE_HOME = '{runtimeRoot}' }
            clearEnv = @('GLOBAL_FIXTURE_TOKEN')
        }
        account = [ordered]@{
            mechanism = 'fileOverlay'
            credentialFiles = @('auth.json')
            credentialPrecedence = @('auth.json')
            logoutScope = 'profile'
        }
        normalState = [ordered]@{
            root = [ordered]@{
                windows = '%USERPROFILE%\.fixture'
                macos = '$HOME/.fixture'
                linux = '$HOME/.fixture'
            }
            sharedPaths = @('config.toml', 'agents')
            sessionPaths = @('sessions', 'history.jsonl')
            filePaths = @('config.toml', 'history.jsonl')
            unsafePaths = @()
        }
        concurrency = [ordered]@{ level = 'multiWriter'; singletonScope = 'none' }
        support = [ordered]@{
            windows = [ordered]@{ level = 'supported'; reason = 'Fixture only.' }
            macos = [ordered]@{ level = 'supported'; reason = 'Fixture only.' }
            linux = [ordered]@{ level = 'supported'; reason = 'Fixture only.' }
        }
    }
    $adapter | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $Scratch.Tools 'fixture\adapter.json') -Encoding UTF8
}

function Write-LegacyProfileFixtureAdapter {
    param($Scratch, [string]$Id = 'legacycli')
    $adapterDir = Join-Path $Scratch.Tools $Id
    New-Item -ItemType Directory -Force -Path $adapterDir | Out-Null
    $json = @'
{"id":"LEGACY_ID","displayName":"Legacy CLI","kind":"cli","binary":{"windows":["legacy.exe"],"macos":["legacy"],"linux":["legacy"]},"isolation":{"strategy":"env","env":{"LEGACY_HOME":"{profileDir}"}},"share":{"systemHome":"$HOME/.legacy","linkable":["config.toml"],"neverLink":["auth.json"]},"session":{"portable":true,"paths":["sessions"],"credentials":["auth.json"]},"status":"legacy-test"}
'@.Replace('LEGACY_ID', $Id)
    Set-Content -LiteralPath (Join-Path $adapterDir 'adapter.json') -Value $json -Encoding UTF8
}

function Invoke-ProfileFixtureLauncher {
    param($Scratch, [string[]]$Arguments, [string]$Probe)
    $environment = @{
        USERPROFILE = $Scratch.UserHome
        HOME = $Scratch.UserHome
        APPDATA = (Join-Path $Scratch.UserHome 'AppData\Roaming')
        LOCALAPPDATA = (Join-Path $Scratch.UserHome 'AppData\Local')
        MULTICLI_HOME = $Scratch.Profiles
        MULTICLI_TOOLS_DIR = $Scratch.Tools
        PATH = "$($Scratch.Profiles)\bin;$env:PATH"
    }
    if ($Probe) { $environment['MULTICLI_OVERRIDE_BINARY'] = $Probe }
    $original = @{}
    foreach ($entry in $environment.GetEnumerator()) {
        $original[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ProfileLauncher @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        foreach ($name in $original.Keys) { [Environment]::SetEnvironmentVariable($name, $original[$name], 'Process') }
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String) }
}

Describe 'profile path containment and legacy transfer hardening' {
    It 'rejects a traversal tool id before touching paths outside MULTICLI_HOME' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            Copy-Item -LiteralPath (Join-Path $scratch.Tools 'fixture\adapter.json') -Destination (Join-Path $scratch.Root 'adapter.json')

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('new', '../victim', '--no-seed')

            $result.ExitCode | Should Be 1
            $result.Output | Should Match "Tool id '\.\.' invalid"
            (Test-Path -LiteralPath (Join-Path $scratch.Root 'victim')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses delete when a valid tool directory is a junction outside MULTICLI_HOME' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_profile_" + [guid]::NewGuid().ToString('N'))
        $toolLink = Join-Path $root 'profiles\codex'
        $outsideRoot = Join-Path $root 'outside-codex'
        try {
            New-Item -ItemType Directory -Force -Path (Join-Path $root 'profiles'), (Join-Path $outsideRoot 'account-a') | Out-Null
            Set-Content -LiteralPath (Join-Path $outsideRoot 'account-a\keep.txt') -Value 'outside-data' -Encoding ASCII
            New-Item -ItemType Junction -Path $toolLink -Target $outsideRoot | Out-Null

            $delete = Invoke-ProfileLauncher -Root $root -Arguments @('delete', 'codex/account-a') -StdinText 'y'

            $delete.TimedOut | Should Be $false
            $delete.ExitCode | Should Be 1
            $delete.Output | Should Match 'outside MULTICLI_HOME'
            (Get-Content -LiteralPath (Join-Path $outsideRoot 'account-a\keep.txt') -Raw).Trim() | Should Be 'outside-data'
            (Test-Path -LiteralPath (Join-Path $outsideRoot 'account-a')) | Should Be $true
        } finally {
            if (Test-Path -LiteralPath $toolLink) { [System.IO.Directory]::Delete($toolLink) }
            Remove-Item -LiteralPath $outsideRoot -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses rename when a valid tool directory is a junction outside MULTICLI_HOME' {
        $scratch = New-ProfileFixtureScratch
        $toolLink = Join-Path $scratch.Profiles 'fixture'
        $outsideRoot = Join-Path $scratch.Root 'outside-fixture'
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            New-Item -ItemType Directory -Force -Path (Join-Path $outsideRoot 'account-a') | Out-Null
            Set-Content -LiteralPath (Join-Path $outsideRoot 'account-a\keep.txt') -Value 'outside-data' -Encoding ASCII
            New-Item -ItemType Junction -Path $toolLink -Target $outsideRoot | Out-Null

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('rename', 'fixture/account-a', 'fixture/account-b')

            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'outside MULTICLI_HOME'
            (Test-Path -LiteralPath (Join-Path $outsideRoot 'account-a')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $outsideRoot 'account-b')) | Should Be $false
            (Get-Content -LiteralPath (Join-Path $outsideRoot 'account-a\keep.txt') -Raw).Trim() | Should Be 'outside-data'
        } finally {
            if (Test-Path -LiteralPath $toolLink) { [System.IO.Directory]::Delete($toolLink) }
            Remove-Item -LiteralPath $outsideRoot -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses export when a valid tool directory is a junction outside MULTICLI_HOME' {
        $scratch = New-ProfileFixtureScratch
        $toolLink = Join-Path $scratch.Profiles 'fixture'
        $outsideRoot = Join-Path $scratch.Root 'outside-fixture'
        $archive = Join-Path $scratch.Root 'escape.zip'
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            New-Item -ItemType Directory -Force -Path (Join-Path $outsideRoot 'account-a') | Out-Null
            Set-Content -LiteralPath (Join-Path $outsideRoot 'account-a\keep.txt') -Value 'outside-data' -Encoding ASCII
            New-Item -ItemType Junction -Path $toolLink -Target $outsideRoot | Out-Null

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('export', 'fixture/account-a', $archive)

            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'outside MULTICLI_HOME'
            (Test-Path -LiteralPath $archive) | Should Be $false
            (Get-Content -LiteralPath (Join-Path $outsideRoot 'account-a\keep.txt') -Raw).Trim() | Should Be 'outside-data'
        } finally {
            if (Test-Path -LiteralPath $toolLink) { [System.IO.Directory]::Delete($toolLink) }
            Remove-Item -LiteralPath $outsideRoot -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses export when a valid tool directory is a relative symlink outside MULTICLI_HOME' {
        $scratch = New-ProfileFixtureScratch
        $toolLink = Join-Path $scratch.Profiles 'fixture'
        $outsideRoot = Join-Path $scratch.Root 'outside-relative-fixture'
        $archive = Join-Path $scratch.Root 'relative-escape.zip'
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            New-Item -ItemType Directory -Force -Path (Join-Path $outsideRoot 'account-a') | Out-Null
            Set-Content -LiteralPath (Join-Path $outsideRoot 'account-a\keep.txt') -Value 'outside-data' -Encoding ASCII
            $made = $true
            try {
                New-Item -ItemType SymbolicLink -Path $toolLink -Target '..\outside-relative-fixture' -ErrorAction Stop | Out-Null
            } catch { $made = $false }
            if (-not $made) {
                Write-Host 'Host cannot create symlinks; this capability-specific assertion was not exercised.'
                return
            }

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('export', 'fixture/account-a', $archive)

            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'outside MULTICLI_HOME'
            (Test-Path -LiteralPath $archive) | Should Be $false
            (Get-Content -LiteralPath (Join-Path $outsideRoot 'account-a\keep.txt') -Raw).Trim() | Should Be 'outside-data'
        } finally {
            if (Test-Path -LiteralPath $toolLink) { [System.IO.Directory]::Delete($toolLink) }
            Remove-Item -LiteralPath $outsideRoot -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses template save for legacy whole-root profiles before any token files can travel' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            $legacy = Join-Path $scratch.Profiles 'fixture\legacy'
            New-Item -ItemType Directory -Force -Path $legacy | Out-Null
            Set-Content -LiteralPath (Join-Path $legacy 'config.toml') -Value 'model = "gpt-5"' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $legacy 'mcp-oauth-tokens.json') -Value '{"access_token":"tok"}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $legacy 'a2a-oauth-tokens.json') -Value '{"refresh_token":"tok"}' -Encoding ASCII

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('template', 'save', 'fixture/legacy', 'tpl')

            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'legacy profile'
            $result.Output | Should Match 'multi-cli migrate fixture/legacy'
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles '.templates\tpl')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses export for legacy whole-root profiles before any token files can travel' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            $legacy = Join-Path $scratch.Profiles 'fixture\legacy'
            $archive = Join-Path $scratch.Root 'legacy.zip'
            New-Item -ItemType Directory -Force -Path $legacy | Out-Null
            Set-Content -LiteralPath (Join-Path $legacy 'config.toml') -Value 'model = "gpt-5"' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $legacy 'mcp-oauth-tokens.json') -Value '{"access_token":"tok"}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $legacy 'a2a-oauth-tokens.json') -Value '{"refresh_token":"tok"}' -Encoding ASCII

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('export', 'fixture/legacy', $archive)

            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'legacy profile'
            $result.Output | Should Match 'multi-cli migrate fixture/legacy'
            (Test-Path -LiteralPath $archive) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses legacy template application before old on-disk templates can recreate credentials' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-LegacyProfileFixtureAdapter -Scratch $scratch
            $templateDir = Join-Path $scratch.Profiles '.templates\tpl'
            New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
            Set-Content -LiteralPath (Join-Path $templateDir 'config.toml') -Value 'model = "gpt-5"' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $templateDir 'auth.json') -Value '{"access_token":"tok"}' -Encoding ASCII

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('new', 'legacycli/work', '--from', 'tpl')

            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'legacy template application is disabled'
            $result.Output | Should Match "template 'tpl'"
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles 'legacycli\work')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses clone for legacy whole-root profiles before tokens can travel' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-LegacyProfileFixtureAdapter -Scratch $scratch
            $source = Join-Path $scratch.Profiles 'legacycli\source'
            New-Item -ItemType Directory -Force -Path $source | Out-Null
            Set-Content -LiteralPath (Join-Path $source 'config.toml') -Value 'model = "gpt-5"' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $source 'mcp-oauth-tokens.json') -Value '{"access_token":"tok"}' -Encoding ASCII

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('clone', 'legacycli/source', 'legacycli/dest')

            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'legacy profile transfer is disabled'
            $result.Output | Should Match 'multi-cli migrate legacycli/source'
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles 'legacycli\dest')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses import for legacy whole-root archives before tokens can travel' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-LegacyProfileFixtureAdapter -Scratch $scratch
            $archiveRoot = Join-Path $scratch.Root 'legacy-archive'
            $archive = Join-Path $scratch.Root 'legacy.zip'
            New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
            Set-Content -LiteralPath (Join-Path $archiveRoot 'config.toml') -Value 'model = "gpt-5"' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $archiveRoot 'auth.json') -Value '{"access_token":"tok"}' -Encoding ASCII
            Compress-Archive -Path (Join-Path $archiveRoot '*') -DestinationPath $archive -Force

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('import', $archive, 'legacycli/work')

            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'legacy profile transfer is disabled'
            $result.Output | Should Match 'multi-cli migrate legacycli/work'
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles 'legacycli\work')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'restored launcher behaviors' {
    It 'propagates a foreground child exit code as the launcher exit code' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            $new = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('new', 'fixture/account-a', '--no-seed')
            if ($new.ExitCode -ne 0) { Write-Host $new.Output }
            $new.ExitCode | Should Be 0
            $exit7Script = Join-Path $scratch.Root 'exit7.ps1'
            'exit 7' | Set-Content -LiteralPath $exit7Script -Encoding ASCII
            $exit7Cmd = Join-Path $scratch.Root 'exit7.cmd'
            "@powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$exit7Script`"" | Set-Content -LiteralPath $exit7Cmd -Encoding ASCII

            $launch = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('launch', 'fixture/account-a') -Probe $exit7Cmd

            if ($launch.ExitCode -ne 7) { Write-Host $launch.Output }
            $launch.ExitCode | Should Be 7
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'tools and doctor show supported-mode prerequisites' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            $adapterPath = Join-Path $scratch.Tools 'fixture\adapter.json'
            $adapter = Get-Content -LiteralPath $adapterPath -Raw | ConvertFrom-Json
            $adapter.support.windows.reason = 'requires --isolated whole-root'
            $adapter | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $adapterPath -Encoding UTF8

            $tools = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('tools')
            $tools.ExitCode | Should Be 0
            $tools.Output | Should Match 'requires --isolated whole-root'

            $doctor = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('doctor')
            $doctor.ExitCode | Should Be 0
            $doctor.Output | Should Match 'supported: requires --isolated whole-root'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'doctor --deep flags an unexpected runtime file and is clean otherwise' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            $new = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('new', 'fixture/account-a', '--no-seed')
            if ($new.ExitCode -ne 0) { Write-Host $new.Output }
            $new.ExitCode | Should Be 0
            $profileDir = Join-Path $scratch.Profiles 'fixture\account-a'

            $clean = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('doctor', '--deep')
            if ($clean.ExitCode -ne 0) { Write-Host $clean.Output }
            $clean.ExitCode | Should Be 0
            $clean.Output | Should Not Match 'unexpected runtime file'

            $runtimeDir = Join-Path $profileDir '.runtime'
            New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
            Set-Content -LiteralPath (Join-Path $runtimeDir '.runtime-manifest') -Value 'config.toml' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $runtimeDir 'config.toml') -Value 'shared-config' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $runtimeDir 'rogue.txt') -Value 'rogue' -Encoding ASCII

            $flagged = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('doctor', '--deep')
            $flagged.ExitCode | Should Be 1
            $flagged.Output | Should Match 'unexpected runtime file rogue\.txt'
            $flagged.Output | Should Match 'adapter classification defect'

            Remove-Item -LiteralPath (Join-Path $runtimeDir 'rogue.txt') -Force
            Remove-Item -LiteralPath (Join-Path $runtimeDir '.runtime-manifest') -Force
            $noManifest = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('doctor', '--deep')
            $noManifest.ExitCode | Should Be 1
            $noManifest.Output | Should Match 'missing \.runtime-manifest'
            $noManifest.Output | Should Not Match 'unexpected runtime file'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'migrate --dry-run prints the plan and writes nothing' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            $profileDir = Join-Path $scratch.Profiles 'fixture\work'
            New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
            Set-Content -LiteralPath (Join-Path $profileDir 'auth.json') -Value 'profile-token' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $profileDir 'config.toml') -Value 'profile-config' -Encoding ASCII

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('migrate', 'fixture/work', '--dry-run')

            if ($result.ExitCode -ne 0) { Write-Host $result.Output }
            $result.ExitCode | Should Be 0
            $result.Output | Should Match 'Migration plan for fixture/work'
            $result.Output | Should Match 'move credential auth\.json -> auth/auth\.json'
            $result.Output | Should Match 'Dry run -- no changes written\.'
            (Test-Path -LiteralPath (Join-Path $profileDir '.profile.json')) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $profileDir '.migration-journal.json')) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $profileDir 'auth')) | Should Be $false
            ((Get-Content -LiteralPath (Join-Path $profileDir 'auth.json') -Raw).Trim()) | Should Be 'profile-token'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'continue on existing shared schema-v2 profiles reports the shared-state no-op' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            (Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('new', 'fixture/a', '--no-seed')).ExitCode | Should Be 0
            (Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('new', 'fixture/b', '--no-seed')).ExitCode | Should Be 0

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('continue', 'fixture', 'a', 'b')

            if ($result.ExitCode -ne 0) { Write-Host $result.Output }
            $result.ExitCode | Should Be 0
            $result.Output | Should Match 'already share conversations through the shared normal state; nothing to continue'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'new --from with an incompatible template refuses before creating the profile' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            # A second adapter with a different id, for the cross-adapter refusal.
            $fixture2Dir = Join-Path $scratch.Tools 'fixture2'
            New-Item -ItemType Directory -Force -Path $fixture2Dir | Out-Null
            $other = Get-Content -LiteralPath (Join-Path $scratch.Tools 'fixture\adapter.json') -Raw | ConvertFrom-Json
            $other.id = 'fixture2'
            $other | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $fixture2Dir 'adapter.json') -Encoding UTF8

            $new = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('new', 'fixture/account-a', '--no-seed')
            if ($new.ExitCode -ne 0) { Write-Host $new.Output }
            $new.ExitCode | Should Be 0
            $save = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('template', 'save', 'fixture/account-a', 'tpl')
            if ($save.ExitCode -ne 0) { Write-Host $save.Output }
            $save.ExitCode | Should Be 0

            $apply = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('new', 'fixture2/wrong', '--from', 'tpl')

            $apply.ExitCode | Should Be 1
            $apply.Output | Should Match "cannot be applied to 'fixture2'"
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles 'fixture2\wrong')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'creates Start Menu shortcuts that point to the real launcher file' {
        $scratch = New-ProfileFixtureScratch
        try {
            Write-ProfileFixtureAdapter -Scratch $scratch
            $adapterPath = Join-Path $scratch.Tools 'fixture\adapter.json'
            $adapter = Get-Content -LiteralPath $adapterPath -Raw | ConvertFrom-Json
            $adapter.kind = 'ide'
            $adapter | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $adapterPath -Encoding UTF8
            $startMenu = Join-Path $scratch.UserHome 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'
            New-Item -ItemType Directory -Force -Path $startMenu | Out-Null

            $result = Invoke-ProfileFixtureLauncher -Scratch $scratch -Arguments @('new', 'fixture/work', '--no-seed')

            if ($result.ExitCode -ne 0) { Write-Host $result.Output }
            $result.ExitCode | Should Be 0
            $shortcutPath = Join-Path $startMenu 'multi-cli fixture work.lnk'
            (Test-Path -LiteralPath $shortcutPath -PathType Leaf) | Should Be $true
            $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
            $shortcut.TargetPath | Should Match 'powershell\.exe$'
            $shortcut.Arguments | Should Match ([regex]::Escape("-File `"$script:ProfileLauncher`" launch fixture/work"))
            $shortcut.Arguments | Should Not Match 'function New-StartMenuShortcut'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
