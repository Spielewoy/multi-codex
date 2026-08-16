$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:LauncherPath = Join-Path $script:RepoRoot 'multi-cli.ps1'
$script:CredentialStoreModule = Join-Path $script:RepoRoot 'lib\MultiCli.CredentialStore.psm1'
Import-Module $script:CredentialStoreModule -Force

# Real-execution tests for `multi-cli new <tool>/<name> --isolated` on Windows:
# whole-root isolation for schema-v2 adapters. An isolated profile shares
# NOTHING with the native tool home -- the adapter's home env points at the
# profile dir itself, no runtime overlay is built, nothing is seeded or linked
# from the shared root. No mocks: every test runs the real launcher in a child
# powershell against real fixture adapters in a temp scratch tree.

function New-IsolatedScratch {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_isolated_" + [guid]::NewGuid().ToString('N'))
    $userHome = Join-Path $root 'home'
    $profiles = Join-Path $root 'profiles'
    $tools = Join-Path $root 'tools'
    New-Item -ItemType Directory -Force -Path $userHome, $profiles | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tools 'fixture'), (Join-Path $tools 'secretcli'), (Join-Path $tools 'lockedcli') | Out-Null
    return [pscustomobject]@{ Root = $root; UserHome = $userHome; Profiles = $profiles; Tools = $tools }
}

function Write-FileOverlayAdapter {
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
            root = [ordered]@{ windows = '%USERPROFILE%\.fixture'; macos = '$HOME/.fixture'; linux = '$HOME/.fixture' }
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

function Write-ProcessSecretAdapter {
    param($Scratch)
    $adapter = [ordered]@{
        schemaVersion = 2
        id = 'secretcli'
        displayName = 'Secret CLI'
        kind = 'cli'
        binary = [ordered]@{ windows = @('secretcli.exe'); macos = @('secretcli'); linux = @('secretcli') }
        isolation = [ordered]@{
            strategy = 'accountOverlay'
            mode = 'foreground'
            env = [ordered]@{ SECRETCLI_HOME = '{sharedStateRoot}' }
            clearEnv = @()
        }
        account = [ordered]@{
            mechanism = 'processSecret'
            credentialFiles = @()
            credentialPrecedence = @('SECRETCLI_TOKEN')
            logoutScope = 'process'
            secret = [ordered]@{ environmentVariable = 'SECRETCLI_TOKEN' }
        }
        normalState = [ordered]@{
            root = [ordered]@{ windows = '%USERPROFILE%\.secretcli'; macos = '$HOME/.secretcli'; linux = '$HOME/.secretcli' }
            sharedPaths = @('config.toml')
            sessionPaths = @('sessions')
            filePaths = @('config.toml')
            unsafePaths = @()
        }
        concurrency = [ordered]@{ level = 'multiWriter'; singletonScope = 'none' }
        support = [ordered]@{
            windows = [ordered]@{ level = 'supported'; reason = 'Fixture only.' }
            macos = [ordered]@{ level = 'supported'; reason = 'Fixture only.' }
            linux = [ordered]@{ level = 'supported'; reason = 'Fixture only.' }
        }
    }
    $adapter | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $Scratch.Tools 'secretcli\adapter.json') -Encoding UTF8
}

function Write-OsUserAdapter {
    param($Scratch)
    $adapter = [ordered]@{
        schemaVersion = 2
        id = 'lockedcli'
        displayName = 'Locked CLI'
        kind = 'cli'
        binary = [ordered]@{ windows = @('lockedcli.exe'); macos = @('lockedcli'); linux = @('lockedcli') }
        isolation = [ordered]@{ strategy = 'accountOverlay'; mode = 'foreground'; env = [ordered]@{}; clearEnv = @() }
        account = [ordered]@{
            mechanism = 'osUserCredentialStore'
            credentialFiles = @()
            credentialPrecedence = @('Fixed OS credential')
            logoutScope = 'osUser'
        }
        normalState = [ordered]@{
            root = [ordered]@{ windows = '%USERPROFILE%\.lockedcli'; macos = '$HOME/.lockedcli'; linux = '$HOME/.lockedcli' }
            sharedPaths = @()
            sessionPaths = @()
            filePaths = @()
            unsafePaths = @()
        }
        concurrency = [ordered]@{ level = 'multiWriter'; singletonScope = 'osUser' }
        support = [ordered]@{
            windows = [ordered]@{ level = 'supported'; reason = 'Fixture only.' }
            macos = [ordered]@{ level = 'unsupported'; reason = 'Fixture only.' }
            linux = [ordered]@{ level = 'unsupported'; reason = 'Fixture only.' }
        }
    }
    $adapter | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $Scratch.Tools 'lockedcli\adapter.json') -Encoding UTF8
}

# A probe "binary" (cmd shim wrapping powershell) that captures the child's
# environment into $Capture as JSON.
function New-EnvProbe {
    param($Scratch, [string]$Capture)
    $probeScript = Join-Path $Scratch.Root 'capture.ps1'
    @'
@{
  fixture_home = $env:FIXTURE_HOME
  secret_home = $env:SECRETCLI_HOME
  token = $env:SECRETCLI_TOKEN
  inherited = $env:GLOBAL_FIXTURE_TOKEN
  profile = $env:MULTICLI_PROFILE_ID
  home = $env:USERPROFILE
} | ConvertTo-Json | Set-Content -LiteralPath $env:CAPTURE_OUTPUT -Encoding UTF8
'@ | Set-Content -LiteralPath $probeScript -Encoding UTF8
    $probe = Join-Path $Scratch.Root 'capture.cmd'
    "@powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$probeScript`"" | Set-Content -LiteralPath $probe -Encoding ASCII
    return $probe
}

function Invoke-IsolatedLauncher {
    param($Scratch, [string[]]$Arguments, [string]$Probe, [string]$Capture)
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
    if ($Capture) { $environment['CAPTURE_OUTPUT'] = $Capture }
    $original = @{}
    foreach ($entry in $environment.GetEnumerator()) {
        $original[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:LauncherPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        foreach ($name in $original.Keys) { [Environment]::SetEnvironmentVariable($name, $original[$name], 'Process') }
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String) }
}

# Store a credential for an isolated process-secret profile directly in
# Credential Manager (auth set prompts interactively, so the test drives the
# store the same way the launcher's auth command does) and return the target
# for cleanup.
function Set-IsolatedProfileCredential {
    param($Scratch, [string]$Spec, [string]$Secret)
    $metadata = Get-Content -LiteralPath (Join-Path (Join-Path $Scratch.Profiles $Spec) '.profile.json') -Raw | ConvertFrom-Json
    $target = "multi-cli/secretcli/$($metadata.profileId)/SECRETCLI_TOKEN"
    Set-MultiCliCredential -Target $target -Secret $Secret
    return $target
}

Describe 'schema-v2 isolated mode on Windows' {
    It 'creates a marked isolated profile with --isolated and every alias form' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            $i = 0
            foreach ($flag in @('--isolated', '--isolate', '-i')) {
                $i++
                $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', "fixture/iso-$i", $flag, '--no-seed')
                if ($result.ExitCode -ne 0) { Write-Host $result.Output }
                $result.ExitCode | Should Be 0
                (Test-Path -LiteralPath (Join-Path $scratch.Profiles "fixture\iso-$i\.isolated")) | Should Be $true
            }
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects misspelled and undocumented isolated options instead of silently changing profile mode' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            foreach ($option in @('--isloated', '-isolate')) {
                $name = 'typo-' + ($option -replace '[^a-z]', '')
                $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', "fixture/$name", $option, '--no-seed')
                $result.ExitCode | Should Be 1
                ($result.Output -match [regex]::Escape("Unknown option for new: '$option'")) | Should Be $true
                (Test-Path -LiteralPath (Join-Path $scratch.Profiles "fixture\$name")) | Should Be $false
            }
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'requires a template name after --from' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/missing-template', '--from')
            $result.ExitCode | Should Be 1
            ($result.Output -match 'Usage: --from <template>') | Should Be $true
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles 'fixture\missing-template')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'fails --shared and --isolated together with a clear message and creates nothing' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/clash', '--shared', '--isolated', '--no-seed')
            $result.ExitCode | Should Be 1
            ($result.Output -match '--shared') | Should Be $true
            ($result.Output -match '--isolated') | Should Be $true
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles 'fixture\clash')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'creates an isolated profile with metadata, no overlay skeleton, and no seeding' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            $shared = Join-Path $scratch.UserHome '.fixture'
            New-Item -ItemType Directory -Force -Path $shared | Out-Null
            Set-Content -LiteralPath (Join-Path $shared 'history.jsonl') -Value 'shared-session' -Encoding ASCII
            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso', '--isolated', '--no-seed')
            $result.ExitCode | Should Be 0
            $profile = Join-Path $scratch.Profiles 'fixture\iso'
            (Test-Path -LiteralPath (Join-Path $profile '.isolated')) | Should Be $true
            $metadata = Get-Content -LiteralPath (Join-Path $profile '.profile.json') -Raw | ConvertFrom-Json
            $metadata.schemaVersion | Should Be 2
            $metadata.adapterId | Should Be 'fixture'
            $metadata.mode | Should Be 'isolated'
            ([guid]::Parse($metadata.profileId) -is [guid]) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $profile 'auth')) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $profile 'history.jsonl')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'points the adapter home env at the profile dir, builds no overlay, and leaves the shared-root canary untouched' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            $shared = Join-Path $scratch.UserHome '.fixture'
            New-Item -ItemType Directory -Force -Path $shared | Out-Null
            Set-Content -LiteralPath (Join-Path $shared 'canary.txt') -Value 'canary' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $shared 'history.jsonl') -Value 'shared-session' -Encoding ASCII
            $capture = Join-Path $scratch.Root 'capture.json'
            $probe = New-EnvProbe -Scratch $scratch -Capture $capture
            $profile = Join-Path $scratch.Profiles 'fixture\iso'

            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso', '--isolated', '--no-seed')).ExitCode | Should Be 0
            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('launch', 'fixture/iso') -Probe $probe -Capture $capture
            if ($result.ExitCode -ne 0) { Write-Host $result.Output }
            $result.ExitCode | Should Be 0
            $captured = Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json
            $captured.fixture_home | Should Be $profile
            (Test-Path -LiteralPath (Join-Path $profile '.runtime')) | Should Be $false
            (Get-Content -LiteralPath (Join-Path $shared 'canary.txt') -Raw).Trim() | Should Be 'canary'
            (Test-Path -LiteralPath (Join-Path $profile 'history.jsonl')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'never creates the native shared root on isolated launch' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            $capture = Join-Path $scratch.Root 'capture.json'
            $probe = New-EnvProbe -Scratch $scratch -Capture $capture
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso', '--isolated', '--no-seed')).ExitCode | Should Be 0
            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('launch', 'fixture/iso') -Probe $probe -Capture $capture
            $result.ExitCode | Should Be 0
            (Test-Path -LiteralPath (Join-Path $scratch.UserHome '.fixture')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'still clears inherited account variables on isolated launch' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            $capture = Join-Path $scratch.Root 'capture.json'
            $probe = New-EnvProbe -Scratch $scratch -Capture $capture
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso', '--isolated', '--no-seed')).ExitCode | Should Be 0
            $env:GLOBAL_FIXTURE_TOKEN = 'wrong-account-secret'
            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('launch', 'fixture/iso') -Probe $probe -Capture $capture
            Remove-Item Env:GLOBAL_FIXTURE_TOKEN -ErrorAction SilentlyContinue
            if ($result.ExitCode -ne 0) { Write-Host $result.Output }
            $result.ExitCode | Should Be 0
            $captured = Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json
            [string]::IsNullOrEmpty($captured.inherited) | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'clears Command Code higher-precedence API-key inheritance' {
        $scratch = New-IsolatedScratch
        try {
            $commandCodeDir = Join-Path $scratch.Tools 'commandcode'
            New-Item -ItemType Directory -Force -Path $commandCodeDir | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'commandcode\adapter.json') -Destination (Join-Path $commandCodeDir 'adapter.json')
            $capture = Join-Path $scratch.Root 'commandcode-key.txt'
            $probeScript = Join-Path $scratch.Root 'capture-commandcode.ps1'
            '[Environment]::GetEnvironmentVariable(''COMMAND_CODE_API_KEY'', ''Process'') | Set-Content -LiteralPath $env:CAPTURE_OUTPUT -NoNewline' |
                Set-Content -LiteralPath $probeScript -Encoding ASCII
            $probe = Join-Path $scratch.Root 'capture-commandcode.cmd'
            "@powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$probeScript`"" | Set-Content -LiteralPath $probe -Encoding ASCII
            $env:COMMAND_CODE_API_KEY = 'wrong-account-secret'

            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'commandcode/iso', '--isolated', '--no-seed')).ExitCode | Should Be 0
            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('launch', 'commandcode/iso') -Probe $probe -Capture $capture

            if ($result.ExitCode -ne 0) { Write-Host $result.Output }
            $result.ExitCode | Should Be 0
            (Get-Item -LiteralPath $capture).Length | Should Be 0
            $env:COMMAND_CODE_API_KEY | Should Be 'wrong-account-secret'
        } finally {
            Remove-Item Env:COMMAND_CODE_API_KEY -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps two isolated process-secret profiles on distinct credentials with home inside each profile' {
        $scratch = New-IsolatedScratch
        $targets = @()
        try {
            Write-ProcessSecretAdapter -Scratch $scratch
            $capture = Join-Path $scratch.Root 'capture.json'
            $probe = New-EnvProbe -Scratch $scratch -Capture $capture
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'secretcli/account-a', '--isolated', '--no-seed')).ExitCode | Should Be 0
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'secretcli/account-b', '--isolated', '--no-seed')).ExitCode | Should Be 0
            $targets += Set-IsolatedProfileCredential -Scratch $scratch -Spec 'secretcli\account-a' -Secret 'token-account-a'
            $targets += Set-IsolatedProfileCredential -Scratch $scratch -Spec 'secretcli\account-b' -Secret 'token-account-b'

            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('launch', 'secretcli/account-a') -Probe $probe -Capture $capture
            if ($result.ExitCode -ne 0) { Write-Host $result.Output }
            $result.ExitCode | Should Be 0
            $captured = Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json
            $captured.token | Should Be 'token-account-a'
            $captured.secret_home | Should Be (Join-Path $scratch.Profiles 'secretcli\account-a')
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles 'secretcli\account-a\.runtime')) | Should Be $false

            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('launch', 'secretcli/account-b') -Probe $probe -Capture $capture
            $result.ExitCode | Should Be 0
            $captured = Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json
            $captured.token | Should Be 'token-account-b'
            $captured.secret_home | Should Be (Join-Path $scratch.Profiles 'secretcli\account-b')
            (Test-Path -LiteralPath (Join-Path $scratch.UserHome '.secretcli')) | Should Be $false
        } finally {
            foreach ($target in $targets) { Remove-MultiCliCredential -Target $target | Out-Null }
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed with the auth hint when an isolated process-secret profile has no stored credential' {
        $scratch = New-IsolatedScratch
        try {
            Write-ProcessSecretAdapter -Scratch $scratch
            $capture = Join-Path $scratch.Root 'capture.json'
            $probe = New-EnvProbe -Scratch $scratch -Capture $capture
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'secretcli/account-a', '--isolated', '--no-seed')).ExitCode | Should Be 0
            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('launch', 'secretcli/account-a') -Probe $probe -Capture $capture
            $result.ExitCode | Should Be 1
            ($result.Output -match 'multi-cli auth set secretcli/account-a') | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'redirects whole-home environment paths into the profile for isolated launch' {
        $scratch = New-IsolatedScratch
        try {
            Write-OsUserAdapter -Scratch $scratch
            $capture = Join-Path $scratch.Root 'capture.json'
            $probe = New-EnvProbe -Scratch $scratch -Capture $capture
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'lockedcli/iso', '--isolated', '--no-seed')).ExitCode | Should Be 0
            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('launch', 'lockedcli/iso') -Probe $probe -Capture $capture
            if ($result.ExitCode -ne 0) { Write-Host $result.Output }
            $result.ExitCode | Should Be 0
            $captured = Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json
            $captured.home | Should Be (Join-Path $scratch.Profiles 'lockedcli\iso\_home')
            (Test-Path -LiteralPath (Join-Path $scratch.UserHome '.lockedcli')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses folder-only isolation for an AppX credential-store GUI' {
        $scratch = New-IsolatedScratch
        try {
            Write-OsUserAdapter -Scratch $scratch
            $adapterPath = Join-Path $scratch.Tools 'lockedcli\adapter.json'
            $adapter = Get-Content -LiteralPath $adapterPath -Raw | ConvertFrom-Json
            $adapter.kind = 'gui'
            $adapter.isolation.mode = 'detached'
            $adapter.binary.windows = @('appx:OpenAI.Codex')
            $adapter | Add-Member -NotePropertyName appx -NotePropertyValue ([pscustomobject]@{
                packageName = 'OpenAI.Codex'
                applicationId = 'App'
                storeProductId = '9PLM9XGG6VKS'
            })
            $adapter | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $adapterPath -Encoding UTF8

            $created = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'lockedcli/iso', '--isolated', '--no-seed')
            $created.ExitCode | Should Be 1
            $created.Output | Should Match 'folder redirection does not isolate Windows Credential Manager'
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles 'lockedcli\iso')) | Should Be $false

            $profileDir = Join-Path $scratch.Profiles 'lockedcli\legacy'
            New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
            New-Item -ItemType File -Force -Path (Join-Path $profileDir '.isolated') | Out-Null
            $capture = Join-Path $scratch.Root 'capture.json'
            $probe = New-EnvProbe -Scratch $scratch -Capture $capture
            $launched = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('launch', 'lockedcli/legacy') -Probe $probe -Capture $capture
            $launched.ExitCode | Should Be 1
            $launched.Output | Should Match 'folder redirection does not isolate Windows Credential Manager'
            (Test-Path -LiteralPath $capture) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not let isolated mode override unsupported Windows status' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            $adapterPath = Join-Path $scratch.Tools 'fixture\adapter.json'
            $adapter = Get-Content -LiteralPath $adapterPath -Raw | ConvertFrom-Json
            $adapter.support.windows = [pscustomobject]@{ level = 'unsupported'; reason = 'No Windows product.' }
            $adapter | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $adapterPath -Encoding UTF8
            $capture = Join-Path $scratch.Root 'capture.json'
            $probe = New-EnvProbe -Scratch $scratch -Capture $capture
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso', '--isolated', '--no-seed')).ExitCode | Should Be 0

            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('launch', 'fixture/iso') -Probe $probe -Capture $capture

            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'unsupported on windows: No Windows product\.'
            (Test-Path -LiteralPath $capture) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'shows isolated profiles as isolated in list' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso', '--isolated', '--no-seed')).ExitCode | Should Be 0
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/plain', '--no-seed')).ExitCode | Should Be 0
            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('list', 'fixture')
            $result.ExitCode | Should Be 0
            $isoLine = ($result.Output -split "`n" | Where-Object { $_ -match '^\s+iso\s' }) -join ''
            ($isoLine -match 'isolated') | Should Be $true
            $plainLine = ($result.Output -split "`n" | Where-Object { $_ -match '^\s+plain\s' }) -join ''
            ($plainLine -match 'isolated') | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'honors normalState.runtimeSubdir across isolated continue and clone' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            $adapterPath = Join-Path $scratch.Tools 'fixture\adapter.json'
            $adapter = Get-Content -LiteralPath $adapterPath -Raw | ConvertFrom-Json
            $adapter.normalState | Add-Member -NotePropertyName runtimeSubdir -NotePropertyValue 'state'
            $adapter | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $adapterPath -Encoding UTF8
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso-a', '--isolated', '--no-seed')).ExitCode | Should Be 0
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso-b', '--isolated', '--no-seed')).ExitCode | Should Be 0
            $source = Join-Path $scratch.Profiles 'fixture\iso-a'
            New-Item -ItemType Directory -Force -Path (Join-Path $source 'state\sessions'), (Join-Path $source 'sessions') | Out-Null
            Set-Content -LiteralPath (Join-Path $source 'state\sessions\chat.jsonl') -Value 'nested-session' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $source 'state\config.toml') -Value 'nested-config' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $source 'sessions\decoy.jsonl') -Value 'wrong-root' -Encoding ASCII

            $continued = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('continue', 'fixture', 'iso-a', 'iso-b')
            if ($continued.ExitCode -ne 0) { Write-Host $continued.Output }
            $continued.ExitCode | Should Be 0
            ((Get-Content -LiteralPath (Join-Path $scratch.Profiles 'fixture\iso-b\state\sessions\chat.jsonl') -Raw).Trim()) | Should Be 'nested-session'
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles 'fixture\iso-b\sessions\decoy.jsonl')) | Should Be $false

            $cloned = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('clone', 'fixture/iso-a', 'fixture/iso-clone')
            if ($cloned.ExitCode -ne 0) { Write-Host $cloned.Output }
            $cloned.ExitCode | Should Be 0
            ((Get-Content -LiteralPath (Join-Path $scratch.Profiles 'fixture\iso-clone\state\config.toml') -Raw).Trim()) | Should Be 'nested-config'
            ((Get-Content -LiteralPath (Join-Path $scratch.Profiles 'fixture\iso-clone\state\sessions\chat.jsonl') -Raw).Trim()) | Should Be 'nested-session'
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles 'fixture\iso-clone\sessions\decoy.jsonl')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'copies sessions between isolated profiles on continue, never credentials' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso-a', '--isolated', '--no-seed')).ExitCode | Should Be 0
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso-b', '--isolated', '--no-seed')).ExitCode | Should Be 0
            $src = Join-Path $scratch.Profiles 'fixture\iso-a'
            $dst = Join-Path $scratch.Profiles 'fixture\iso-b'
            New-Item -ItemType Directory -Force -Path (Join-Path $src 'sessions\2026\06\11') | Out-Null
            Set-Content -LiteralPath (Join-Path $src 'sessions\2026\06\11\rollout-abc-123.jsonl') -Value '{"type":"session_meta","payload":{"id":"abc-123"}}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $src 'history.jsonl') -Value '{"session":"abc-123"}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $src 'auth.json') -Value '{"token":"sk-secret"}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $src 'sessions\auth.json') -Value '{"token":"sk-decoy"}' -Encoding ASCII

            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('continue', 'fixture', 'iso-a', 'iso-b')
            if ($result.ExitCode -ne 0) { Write-Host $result.Output }
            $result.ExitCode | Should Be 0
            (Test-Path -LiteralPath (Join-Path $dst 'sessions\2026\06\11\rollout-abc-123.jsonl')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $dst 'history.jsonl')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $dst 'auth.json')) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $dst 'sessions\auth.json')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to follow a nested junction outside the isolated session root' {
        $scratch = New-IsolatedScratch
        $junction = $null
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso-a', '--isolated', '--no-seed')).ExitCode | Should Be 0
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/iso-b', '--isolated', '--no-seed')).ExitCode | Should Be 0
            $source = Join-Path $scratch.Profiles 'fixture\iso-a\sessions'
            $outside = Join-Path $scratch.Root 'outside'
            New-Item -ItemType Directory -Force -Path $source, $outside | Out-Null
            Set-Content -LiteralPath (Join-Path $outside 'stolen.txt') -Value 'must-not-travel' -Encoding ASCII
            $junction = Join-Path $source 'linked'
            New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null

            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('continue', 'fixture', 'iso-a', 'iso-b')

            $result.ExitCode | Should Be 0
            (Test-Path -LiteralPath (Join-Path $scratch.Profiles 'fixture\iso-b\sessions\linked\stolen.txt')) | Should Be $false
            ($result.Output -match '0 copied') | Should Be $true
        } finally {
            if ($junction -and (Test-Path -LiteralPath $junction)) { [System.IO.Directory]::Delete($junction) }
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps continue between existing shared schema-v2 profiles a no-op' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/account-a', '--no-seed')).ExitCode | Should Be 0
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/account-b', '--no-seed')).ExitCode | Should Be 0
            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('continue', 'fixture', 'account-a', 'account-b')
            $result.ExitCode | Should Be 0
            ($result.Output -match 'already share conversations') | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a missing shared schema-v2 endpoint instead of reporting a no-op' {
        $scratch = New-IsolatedScratch
        try {
            Write-FileOverlayAdapter -Scratch $scratch
            (Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('new', 'fixture/account-a', '--no-seed')).ExitCode | Should Be 0

            $result = Invoke-IsolatedLauncher -Scratch $scratch -Arguments @('continue', 'fixture', 'account-a', 'missing')

            $result.ExitCode | Should Be 1
            ($result.Output -match "Destination profile 'missing' does not exist") | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
