<#
.SYNOPSIS
  In-process unit tests for lib/MultiCli.OsUser.psm1 (Pester 3.4).

.DESCRIPTION
  Real execution, no mocks. On this non-elevated Windows host the suite really
  proves: username derivation (fixed SHA-256 vector, determinism, collisions,
  length), ownership record write/read/refuse-foreign against real
  .osuser.json files, shared-state junction wiring against a fake sandbox
  home (junctions/hardlinks need no admin), the credential-bound wrapper
  process contract, the macOS/Linux
  fail-closed message, and the elevation gate firing BEFORE any provisioning
  (verified with a real `net user` probe). Elevated hosts return early from
  non-admin-only assertions; standard Windows CI executes those branches.
#>

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:LibDir = Join-Path $script:RepoRoot 'lib'

# Production contract: multi-cli.ps1 defines Resolve-PathToken at top level;
# the module resolves the operator shared root through it.
function global:Resolve-PathToken {
    param([string]$Path)
    if (-not $Path) { return $Path }
    $expanded = $Path -replace '\$HOME', $env:USERPROFILE.Replace('\', '\\')
    return [Environment]::ExpandEnvironmentVariables($expanded)
}

Import-Module (Join-Path $script:LibDir 'MultiCli.OsUser.psm1') -Force

function Invoke-ModuleInternal {
    <# Runs a scriptblock inside the module's session state so tests can
       reach non-exported helpers. Arguments are splatted positionally. #>
    param([string]$ModuleName, [scriptblock]$ScriptBlock, [object[]]$Arguments = @())
    $module = Get-Module $ModuleName
    if (-not $module) { throw "Module '$ModuleName' is not imported." }
    $bound = $module.NewBoundScriptBlock($ScriptBlock)
    return & $bound @Arguments
}

function Invoke-OsUserShimmed {
    param([scriptblock]$ScriptBlock, [object[]]$Arguments = @())
    $module = Get-Module MultiCli.OsUser
    $shimNames = @($ScriptBlock.Ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst]
    }, $true) | ForEach-Object { $_.Name -replace '^(script|global|local|private):', '' } | Sort-Object -Unique)
    $savedFunctions = @{}
    foreach ($name in $shimNames) {
        $savedFunctions[$name] = & $module.NewBoundScriptBlock([scriptblock]::Create("`${function:$name}"))
    }
    try {
        return Invoke-ModuleInternal 'MultiCli.OsUser' $ScriptBlock $Arguments
    } finally {
        foreach ($name in $shimNames) {
            & $module.NewBoundScriptBlock({
                param($FunctionName, $Definition)
                if ($null -eq $Definition) {
                    Remove-Item -LiteralPath "function:$FunctionName" -Force -ErrorAction SilentlyContinue
                } else {
                    Set-Item -LiteralPath "function:script:$FunctionName" -Value $Definition
                }
            }) $name $savedFunctions[$name]
        }
    }
}

function Assert-ThrownContains {
    <# Asserts the block throws and its message contains every fragment. #>
    param([scriptblock]$Block, [string[]]$Fragments)
    $caught = $null
    try { & $Block | Out-Null } catch { $caught = $_.Exception.Message }
    foreach ($fragment in $Fragments) {
        if ($null -eq $caught -or -not $caught.Contains($fragment)) {
            throw "Expected exception containing '$fragment'; caught '$caught'."
        }
    }
}

function Test-OsUserHostElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-OsUserScratch {
    <# Temp tree: fake home + profile dir (agy-cli/work) with schema-v2
       metadata. The caller redirects $env:USERPROFILE when it needs the
       shared root to resolve inside the scratch tree. #>
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_osuser_" + [guid]::NewGuid().ToString('N'))
    $userHome = Join-Path $root 'home'
    $profile = Join-Path $root 'profiles\agy-cli\work'
    New-Item -ItemType Directory -Force -Path $userHome, $profile | Out-Null
    [ordered]@{
        schemaVersion = 2
        adapterId = 'agy-cli'
        profileId = $script:FixtureProfileId
        mode = 'accountOverlay'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $profile '.profile.json') -Encoding UTF8
    return [pscustomobject]@{ Root = $root; Home = $userHome; ProfileDir = $profile }
}

function Get-OsUserFixtureAdapter {
    <# agy-cli-shaped osUser adapter with shared/session/file paths, an env
       block exercising two placeholders, and one clearEnv entry. #>
    $adapter = [ordered]@{
        schemaVersion = 2
        id = 'agy-cli'; displayName = 'Fixture agy'; kind = 'cli'
        binary = [ordered]@{ windows = @('agy.exe'); macos = @('agy'); linux = @('agy') }
        isolation = [ordered]@{
            strategy = 'accountOverlay'; mode = 'foreground'
            env = [ordered]@{ FIXTURE_STATE = '{runtimeRoot}'; FIXTURE_SHARED = '{sharedStateRoot}' }
            clearEnv = @('GLOBAL_AGY_TOKEN')
        }
        account = [ordered]@{ mechanism = 'osUserCredentialStore'; credentialFiles = @(); logoutScope = 'osUser' }
        normalState = [ordered]@{
            root = [ordered]@{ windows = '%USERPROFILE%\.fixture-osuser'; macos = '$HOME/.fixture-osuser'; linux = '$HOME/.fixture-osuser' }
            sharedPaths = @('settings.json', 'plugins', 'skills')
            sessionPaths = @('sessions', 'history.jsonl')
            filePaths = @('settings.json', 'history.jsonl')
            unsafePaths = @()
        }
    }
    return ($adapter | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
}

function Write-OsUserRecord {
    <# Ownership record for the scratch profile with $Username recorded
       (matching or foreign, depending on the test). #>
    param([string]$ProfileDir, [string]$Username)
    [ordered]@{
        schemaVersion = 1
        tool = 'agy-cli'
        profileId = $script:FixtureProfileId
        username = $Username
        taskName = 'multi-cli-' + $Username.Substring(5)
        credentialTarget = "multi-cli/osuser/$Username"
        createdUtc = '2026-07-20T00:00:00.0000000Z'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ProfileDir '.osuser.json') -Encoding UTF8
}

$script:FixtureProfileId = '11111111-2222-3333-4444-555555555555'
# sha256("agy-cli:11111111-2222-3333-4444-555555555555") = fcfb4582f558...
$script:FixtureUsername = 'mcli_fcfb4582f558'

Describe 'Get-OsUserName' {
    It 'matches the fixed SHA-256 vector and is deterministic' {
        (Get-OsUserName -Tool 'agy-cli' -ProfileId $script:FixtureProfileId) | Should Be $script:FixtureUsername
        (Get-OsUserName -Tool 'agy-cli' -ProfileId $script:FixtureProfileId) | Should Be $script:FixtureUsername
    }

    It 'fits the 20-char Windows SAM limit and uses lowercase hex' {
        $name = Get-OsUserName -Tool 'kiro' -ProfileId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $name.Length | Should Be 17
        ($name -match '^mcli_[0-9a-f]{12}$') | Should Be $true
    }

    It 'is collision-safe across every osUser adapter and across profiles' {
        $names = @('antigravity', 'agy-cli', 'kiro', 'zed', 'windsurf', 'copilot-vscode', 'cursor') | ForEach-Object {
            Get-OsUserName -Tool $_ -ProfileId $script:FixtureProfileId
        }
        @($names | Sort-Object -Unique).Count | Should Be 7
        (Get-OsUserName -Tool 'agy-cli' -ProfileId '99999999-8888-7777-6666-555555555555') | Should Not Be $script:FixtureUsername
    }

    It 'ignores tool id case' {
        (Get-OsUserName -Tool 'AGY-CLI' -ProfileId $script:FixtureProfileId) | Should Be $script:FixtureUsername
    }

    It 'rejects a missing tool id or profileId' {
        Assert-ThrownContains { Get-OsUserName -Tool '' -ProfileId $script:FixtureProfileId } @('requires a tool id')
        Assert-ThrownContains { Get-OsUserName -Tool 'agy-cli' -ProfileId '' } @('requires a profileId')
    }
}

Describe 'Get-OsUserTaskName and Get-OsUserCredentialTarget' {
    It 'derives the task name and credential target formats' {
        (Get-OsUserTaskName -Username $script:FixtureUsername) | Should Be 'multi-cli-fcfb4582f558'
        (Get-OsUserCredentialTarget -Username $script:FixtureUsername) | Should Be 'multi-cli/osuser/mcli_fcfb4582f558'
    }
}

Describe 'New-OsUserPassword' {
    It 'generates 24-char passwords covering every complexity class, never identical' {
        $password = Invoke-ModuleInternal 'MultiCli.OsUser' { New-OsUserPassword }
        $password.Length | Should Be 24
        ($password -cmatch '[A-Z]') | Should Be $true
        ($password -cmatch '[a-z]') | Should Be $true
        ($password -match '[0-9]') | Should Be $true
        ($password -match '[!#$%&*+\-=?@^_.]') | Should Be $true
        ($password -match '["''\\]') | Should Be $false
        (Invoke-ModuleInternal 'MultiCli.OsUser' { New-OsUserPassword }) | Should Not Be $password
    }
}

Describe 'ownership record' {
    It 'writes and reads back every field' {
        $scratch = New-OsUserScratch
        try {
            Invoke-ModuleInternal 'MultiCli.OsUser' { param($p, $id, $u) Write-OsUserOwnership -ProfileDir $p -Tool 'agy-cli' -ProfileId $id -Username $u } @($scratch.ProfileDir, $script:FixtureProfileId, $script:FixtureUsername)
            $record = Get-OsUserOwnership -ProfileDir $scratch.ProfileDir
            $record.tool | Should Be 'agy-cli'
            $record.profileId | Should Be $script:FixtureProfileId
            $record.username | Should Be $script:FixtureUsername
            $record.taskName | Should Be 'multi-cli-fcfb4582f558'
            $record.credentialTarget | Should Be 'multi-cli/osuser/mcli_fcfb4582f558'
            ([DateTime]::Parse($record.createdUtc) -is [DateTime]) | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns null when the profile has no record' {
        $scratch = New-OsUserScratch
        try {
            (Get-OsUserOwnership -ProfileDir $scratch.ProfileDir) | Should Be $null
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'accepts a consistent record and refuses a fabricated foreign one' {
        $scratch = New-OsUserScratch
        try {
            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username $script:FixtureUsername
            $record = Invoke-ModuleInternal 'MultiCli.OsUser' { param($p) Assert-OsUserOwnership -ProfileDir $p } @($scratch.ProfileDir)
            $record.username | Should Be $script:FixtureUsername

            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username 'mcli_deadbeef0000'
            Assert-ThrownContains {
                Invoke-ModuleInternal 'MultiCli.OsUser' { param($p) Assert-OsUserOwnership -ProfileDir $p } @($scratch.ProfileDir)
            } @("Refusing to touch OS user 'mcli_deadbeef0000'", "does not match the derived identity '$script:FixtureUsername'", 'not multi-cli-owned')
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json')) | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses an internally valid ownership record copied from another profile' {
        $scratch = New-OsUserScratch
        try {
            $otherId = '99999999-8888-7777-6666-555555555555'
            $otherUsername = Get-OsUserName -Tool 'agy-cli' -ProfileId $otherId
            [ordered]@{
                schemaVersion = 1
                tool = 'agy-cli'
                profileId = $otherId
                username = $otherUsername
                taskName = Get-OsUserTaskName -Username $otherUsername
                credentialTarget = Get-OsUserCredentialTarget -Username $otherUsername
                createdUtc = '2026-07-20T00:00:00Z'
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json') -Encoding UTF8

            Assert-ThrownContains {
                Invoke-ModuleInternal 'MultiCli.OsUser' { param($p) Assert-OsUserOwnership -ProfileDir $p } @($scratch.ProfileDir)
            } @("Refusing to touch OS user '$otherUsername'", 'belongs to another profile')
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses a valid username with tampered task or credential coordinates' {
        $scratch = New-OsUserScratch
        try {
            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username $script:FixtureUsername
            $record = Get-Content -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json') -Raw | ConvertFrom-Json
            $record.taskName = 'unrelated-task'
            $record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json') -Encoding UTF8
            Assert-ThrownContains {
                Invoke-ModuleInternal 'MultiCli.OsUser' { param($p) Assert-OsUserOwnership -ProfileDir $p } @($scratch.ProfileDir)
            } @('does not match the derived identity', 'not multi-cli-owned')

            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username $script:FixtureUsername
            $record = Get-Content -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json') -Raw | ConvertFrom-Json
            $record.credentialTarget = 'unrelated/credential'
            $record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json') -Encoding UTF8
            Assert-ThrownContains {
                Invoke-ModuleInternal 'MultiCli.OsUser' { param($p) Assert-OsUserOwnership -ProfileDir $p } @($scratch.ProfileDir)
            } @('does not match the derived identity', 'not multi-cli-owned')
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'platform gate' {
    It 'fails closed on macOS and Linux with the precise message' {
        Assert-ThrownContains {
            Invoke-ModuleInternal 'MultiCli.OsUser' { param($p) Assert-OsUserWindows -Platform $p } @('macos')
        } @('OS-user isolation on macos is not implemented (needs sudo-backed user provisioning); use a process-secret or file-overlay profile')
        Assert-ThrownContains {
            Invoke-ModuleInternal 'MultiCli.OsUser' { param($p) Assert-OsUserWindows -Platform $p } @('linux')
        } @('OS-user isolation on linux is not implemented (needs sudo-backed user provisioning); use a process-secret or file-overlay profile')
        { Invoke-ModuleInternal 'MultiCli.OsUser' { param($p) Assert-OsUserWindows -Platform $p } @('windows') } | Should Not Throw
    }
}

Describe 'Get-OsUserSandboxRoot' {
    It 'maps every home token onto the sandbox home' {
        $adapter = Get-OsUserFixtureAdapter
        $sandboxHome = 'C:\SandboxHome'
        $mapped = Invoke-ModuleInternal 'MultiCli.OsUser' { param($a, $s) Get-OsUserSandboxRoot -Adapter $a -SandboxHome $s } @($adapter, $sandboxHome)
        $mapped | Should Be 'C:\SandboxHome\.fixture-osuser'

        $appdataAdapter = Get-OsUserFixtureAdapter
        $appdataAdapter.normalState.root.windows = '%APPDATA%\Tool'
        $mapped = Invoke-ModuleInternal 'MultiCli.OsUser' { param($a, $s) Get-OsUserSandboxRoot -Adapter $a -SandboxHome $s } @($appdataAdapter, $sandboxHome)
        $mapped | Should Be 'C:\SandboxHome\AppData\Roaming\Tool'

        $localAdapter = Get-OsUserFixtureAdapter
        $localAdapter.normalState.root.windows = '%LOCALAPPDATA%\Tool'
        $mapped = Invoke-ModuleInternal 'MultiCli.OsUser' { param($a, $s) Get-OsUserSandboxRoot -Adapter $a -SandboxHome $s } @($localAdapter, $sandboxHome)
        $mapped | Should Be 'C:\SandboxHome\AppData\Local\Tool'
    }
}

Describe 'Add-OsUserStateLinks' {
    It 'junctions shared/session state from a fake sandbox home into the shared root' {
        $scratch = New-OsUserScratch
        try {
            $sharedRoot = Join-Path $scratch.Home '.fixture-osuser'
            $sandboxRoot = Join-Path $scratch.Root 'sandbox\.fixture-osuser'
            New-Item -ItemType Directory -Force -Path (Join-Path $sharedRoot 'plugins'), (Join-Path $sharedRoot 'sessions') | Out-Null
            Set-Content -LiteralPath (Join-Path $sharedRoot 'settings.json') -Value 'shared-settings' -Encoding ASCII
            $adapter = Get-OsUserFixtureAdapter
            Invoke-ModuleInternal 'MultiCli.OsUser' { param($a, $s, $d) Add-OsUserStateLinks -Adapter $a -SharedRoot $s -SandboxRoot $d } @($adapter, $sharedRoot, $sandboxRoot)

            # Directories are junctions (reparse points) into the shared root.
            foreach ($dir in 'plugins', 'skills', 'sessions') {
                $item = Get-Item -LiteralPath (Join-Path $sandboxRoot $dir) -Force
                ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) | Should Not Be 0
            }
            # Missing sources are created first: skills dir and history file.
            (Test-Path -LiteralPath (Join-Path $sharedRoot 'skills') -PathType Container) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $sharedRoot 'history.jsonl') -PathType Leaf) | Should Be $true
            # File links carry content in both directions (hardlink).
            (Get-Content -LiteralPath (Join-Path $sandboxRoot 'settings.json') -Raw).Trim() | Should Be 'shared-settings'
            Set-Content -LiteralPath (Join-Path $sandboxRoot 'history.jsonl') -Value 'session-line' -Encoding ASCII
            (Get-Content -LiteralPath (Join-Path $sharedRoot 'history.jsonl') -Raw).Trim() | Should Be 'session-line'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'never clobbers a real destination directory the sandbox user already wrote' {
        $scratch = New-OsUserScratch
        try {
            $sharedRoot = Join-Path $scratch.Home '.fixture-osuser'
            $sandboxRoot = Join-Path $scratch.Root 'sandbox\.fixture-osuser'
            $realPlugins = Join-Path $sandboxRoot 'plugins'
            New-Item -ItemType Directory -Force -Path $realPlugins | Out-Null
            Set-Content -LiteralPath (Join-Path $realPlugins 'marker.txt') -Value 'sandbox-owned' -Encoding ASCII
            $adapter = Get-OsUserFixtureAdapter
            Invoke-ModuleInternal 'MultiCli.OsUser' { param($a, $s, $d) Add-OsUserStateLinks -Adapter $a -SharedRoot $s -SandboxRoot $d } @($adapter, $sharedRoot, $sandboxRoot)

            $item = Get-Item -LiteralPath $realPlugins -Force
            ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) | Should Be 0
            (Get-Content -LiteralPath (Join-Path $realPlugins 'marker.txt') -Raw).Trim() | Should Be 'sandbox-owned'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Get-OsUserWrapperContent' {
    It 'encodes command, environment, and path payloads instead of interpolating them' {
        $environment = [ordered]@{ MULTICLI_PROFILE_ID = "id % ! ü`nsecond" }
        $content = Invoke-ModuleInternal 'MultiCli.OsUser' {
            param($e)
            Get-OsUserWrapperContent -Binary 'C:\Tools\fixture %.exe' -Arguments @('value with space', '100%!', "line`nbreak", 'λ') -Environment $e -ClearEnvironment @('GLOBAL_TOKEN') -LogPath 'C:\p !\log.txt' -ExitCodePath 'C:\p %\code.txt'
        } @($environment)

        $content.Contains('C:\Tools\fixture %.exe') | Should Be $false
        $content.Contains('value with space') | Should Be $false
        $content.Contains('id % ! ü') | Should Be $false
        $content.Contains('[Convert]::FromBase64String') | Should Be $true
        $content.Contains('SetEnvironmentVariable') | Should Be $true
    }

    It 'preserves hostile arguments and returns the foreground child exit code' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_osuser_wrapper_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        try {
            $exitCodePath = Join-Path $root 'exit code.txt'
            $logPath = Join-Path $root 'child log.txt'
            $wrapperPath = Join-Path $root 'wrapper.ps1'
            $childPath = Join-Path $root 'child.ps1'
            @'
$args -join "|" | Write-Output
exit 7
'@ | Set-Content -LiteralPath $childPath -Encoding UTF8
            $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $childPath, 'value with space', '100%!')
            $content = Invoke-ModuleInternal 'MultiCli.OsUser' {
                param($binary, $arguments, $log, $exit)
                Get-OsUserWrapperContent -Binary $binary -Arguments $arguments -Environment $null -ClearEnvironment @() -LogPath $log -ExitCodePath $exit
            } @((Join-Path $PSHOME 'powershell.exe'), $arguments, $logPath, $exitCodePath)
            Set-Content -LiteralPath $wrapperPath -Value $content -Encoding UTF8

            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapperPath

            (Get-Content -LiteralPath $exitCodePath -Raw).Trim() | Should Be '7'
            (Get-Content -LiteralPath $logPath -Raw).Trim() | Should Be 'value with space|100%!'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'credential process boundary' {
    It 'starts a wrapper through PSCredential without placing the password in process arguments' {
        $capture = Invoke-OsUserShimmed {
            function script:Import-OsUserCredentialStore {}
            function script:Get-MultiCliCredential { return 'Credential-Secret-123' }
            function script:Start-Process {
                param($FilePath, $Credential, [switch]$LoadUserProfile, [switch]$PassThru, $ArgumentList)
                $script:ProcessCapture = [pscustomobject]@{
                    FilePath = $FilePath
                    Username = $Credential.UserName
                    Password = $Credential.GetNetworkCredential().Password
                    LoadUserProfile = [bool]$LoadUserProfile
                    PassThru = [bool]$PassThru
                    Arguments = [string]$ArgumentList
                }
                return [pscustomobject]@{ Id = 123 }
            }
            $process = Start-OsUserWrapperProcess -Username 'mcli_test000000' -CredentialTarget 'target' -WrapperPath 'C:\profile with spaces\launch.ps1'
            [pscustomobject]@{ Started = [bool]$process; Process = $script:ProcessCapture }
        }
        $capture.Started | Should Be $true
        $capture.Process.FilePath | Should Be (Join-Path $PSHOME 'powershell.exe')
        $capture.Process.Username | Should Be '.\mcli_test000000'
        $capture.Process.Password | Should Be 'Credential-Secret-123'
        $capture.Process.LoadUserProfile | Should Be $true
        $capture.Process.PassThru | Should Be $true
        $capture.Process.Arguments | Should Be '-NoProfile -ExecutionPolicy Bypass -File "C:\profile with spaces\launch.ps1"'
        $capture.Process.Arguments.Contains('Credential-Secret-123') | Should Be $false
    }
}

Describe 'Start-OsUserInteractiveProcess' {
    It 'refuses a detached launch when the owned-user credential is missing' {
        $target = Get-OsUserCredentialTarget -Username $script:FixtureUsername
        Import-Module (Join-Path $script:RepoRoot 'lib\MultiCli.CredentialStore.psm1') -Force
        Remove-MultiCliCredential -Target $target | Out-Null
        Assert-ThrownContains {
            Invoke-ModuleInternal 'MultiCli.OsUser' {
                param($u, $t)
                Start-OsUserInteractiveProcess -Username $u -CredentialTarget $t -Binary 'C:\missing.exe' -BinaryArgs @()
            } @($script:FixtureUsername, $target)
        } @("OS-user credential for '$script:FixtureUsername' is missing", $target)
    }
}

Describe 'Get-OsUserLaunchPlan' {
    It 'plans identity, wiring coordinates, environment and task action without touching the system' {
        $scratch = New-OsUserScratch
        $previousUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $scratch.Home
        try {
            $adapter = Get-OsUserFixtureAdapter
            $sandboxHome = Join-Path $scratch.Root 'sandbox'
            $plan = Get-OsUserLaunchPlan -Adapter $adapter -ProfileDir $scratch.ProfileDir -Binary 'C:\Tools\agy.exe' -BinaryArgs @('--version') -SandboxHome $sandboxHome

            $plan.Username | Should Be $script:FixtureUsername
            $plan.CredentialTarget | Should Be 'multi-cli/osuser/mcli_fcfb4582f558'
            $plan.Mode | Should Be 'foreground'
            $plan.SharedRoot | Should Be (Join-Path $scratch.Home '.fixture-osuser')
            $plan.SandboxRoot | Should Be (Join-Path $sandboxHome '.fixture-osuser')
            $plan.WrapperPath | Should Be (Join-Path $scratch.ProfileDir '.osuser-task.ps1')
            $plan.Environment['MULTICLI_PROFILE_ID'] | Should Be $script:FixtureProfileId
            $plan.Environment['FIXTURE_STATE'] | Should Be $plan.SandboxRoot
            $plan.Environment['FIXTURE_SHARED'] | Should Be $plan.SharedRoot
            @($plan.ClearEnvironment)[0] | Should Be 'GLOBAL_AGY_TOKEN'
            $plan.WrapperContent.Contains('C:\Tools\agy.exe') | Should Be $false
            $plan.WrapperContent.Contains('[Convert]::FromBase64String') | Should Be $true
            # Pure planning: no ownership record, no wrapper file written.
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json')) | Should Be $false
            (Test-Path -LiteralPath $plan.WrapperPath) | Should Be $false
        } finally {
            $env:USERPROFILE = $previousUserProfile
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'elevation gate' {
    It 'reports the host elevation state as a boolean' {
        (Invoke-ModuleInternal 'MultiCli.OsUser' { Test-OsUserElevated }) | Should Be (Test-OsUserHostElevated)
    }

    It 'refuses a profile missing schema-v2 metadata before any elevation check' {
        $scratch = New-OsUserScratch
        try {
            Remove-Item -LiteralPath (Join-Path $scratch.ProfileDir '.profile.json') -Force
            Assert-ThrownContains {
                Initialize-OsUserIsolation -Adapter (Get-OsUserFixtureAdapter) -ProfileDir $scratch.ProfileDir
            } @("Profile 'agy-cli/work' is missing schema-v2 metadata.")
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'fails precisely BEFORE creating anything when not elevated' {
        if (Test-OsUserHostElevated) {
            Write-Host 'Host is elevated; the non-admin elevation assertion is covered on standard Windows runners.'
            return
        }
        $scratch = New-OsUserScratch
        try {
            Assert-ThrownContains {
                Initialize-OsUserIsolation -Adapter (Get-OsUserFixtureAdapter) -ProfileDir $scratch.ProfileDir
            } @('OS-user isolation for agy-cli/work requires an elevated terminal (Run as Administrator).')
            # Proof nothing was created: the derived user does not exist and
            # no ownership record was written. The probe goes through the
            # module's native-invocation helper so net.exe's stderr cannot
            # become a terminating ErrorRecord under Pester's ErrorActionPreference.
            $probeExit = Invoke-ModuleInternal 'MultiCli.OsUser' { param($u)
                $null = Invoke-OsUserNative -FilePath net.exe -NativeArgs @('user', $u)
                return $LASTEXITCODE
            } @($script:FixtureUsername)
            ($probeExit -ne 0) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Remove-OsUserIsolation' {
    It 'is a no-op returning false when the profile owns nothing (profile delete safety)' {
        $scratch = New-OsUserScratch
        try {
            (Remove-OsUserIsolation -ProfileDir $scratch.ProfileDir) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses a fabricated foreign record before any deletion' {
        $scratch = New-OsUserScratch
        try {
            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username 'mcli_deadbeef0000'
            Assert-ThrownContains {
                Remove-OsUserIsolation -ProfileDir $scratch.ProfileDir
            } @("Refusing to touch OS user 'mcli_deadbeef0000'", 'not multi-cli-owned')
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json')) | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stops at the elevation gate for an owned record when not elevated' {
        if (Test-OsUserHostElevated) {
            Write-Host 'Host is elevated; the non-admin elevation assertion is covered on standard Windows runners.'
            return
        }
        $scratch = New-OsUserScratch
        try {
            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username $script:FixtureUsername
            Assert-ThrownContains {
                Remove-OsUserIsolation -ProfileDir $scratch.ProfileDir
            } @('OS-user isolation for agy-cli/work requires an elevated terminal (Run as Administrator).')
            # The record survives: nothing was deleted.
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json')) | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'internal validation failures' {
    It 'returns null for null objects and missing properties' {
        $values = Invoke-ModuleInternal 'MultiCli.OsUser' {
            @(
                Get-OsUserProperty -Object $null -Name 'value'
                Get-OsUserProperty -Object ([pscustomobject]@{ other = 1 }) -Name 'value'
            )
        }
        @($values).Count | Should Be 2
        $values[0] | Should Be $null
        $values[1] | Should Be $null
    }

    It 'rejects missing task and credential usernames' {
        Assert-ThrownContains { Get-OsUserTaskName -Username '' } @('task name requires a username')
        Assert-ThrownContains { Get-OsUserCredentialTarget -Username '' } @('credential target requires a username')
    }

    It 'detects macOS through the runtime-platform probe' {
        $previousOs = $env:OS
        try {
            $env:OS = ''
            $platform = Invoke-OsUserShimmed {
                function script:Test-OsUserRuntimePlatform { return $true }
                Get-OsUserPlatform
            }
            $platform | Should Be 'macos'
        } finally { $env:OS = $previousOs }
    }

    It 'detects the Linux fallback when Windows is not reported' {
        $previousOs = $env:OS
        try {
            $env:OS = ''
            (Invoke-ModuleInternal 'MultiCli.OsUser' { Get-OsUserPlatform }) | Should Be 'linux'
        } finally { $env:OS = $previousOs }
    }

    It 'fails explicitly when the credential-store module root is unavailable' {
        Assert-ThrownContains {
            Invoke-OsUserShimmed {
                function script:Get-OsUserModuleRoot { return $null }
                Import-OsUserCredentialStore
            }
        } @('Cannot locate MultiCli.CredentialStore.psm1: module directory unknown')
    }

    It 'returns null ownership and rejects a record whose profile metadata is missing' {
        $scratch = New-OsUserScratch
        try {
            (Invoke-ModuleInternal 'MultiCli.OsUser' { param($p) Assert-OsUserOwnership -ProfileDir $p } @($scratch.ProfileDir)) | Should Be $null
            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username $script:FixtureUsername
            Remove-Item -LiteralPath (Join-Path $scratch.ProfileDir '.profile.json') -Force
            Assert-ThrownContains {
                Invoke-ModuleInternal 'MultiCli.OsUser' { param($p) Assert-OsUserOwnership -ProfileDir $p } @($scratch.ProfileDir)
            } @($script:FixtureUsername, 'missing schema-v2 profile metadata')
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects adapters without a Windows normal-state root' {
        $adapter = Get-OsUserFixtureAdapter
        $adapter.normalState.root.windows = ''
        Assert-ThrownContains {
            Invoke-ModuleInternal 'MultiCli.OsUser' { param($a) Get-OsUserSharedRoot -Adapter $a } @($adapter)
        } @("Adapter 'agy-cli' has no normal-state root for windows")
        Assert-ThrownContains {
            Invoke-ModuleInternal 'MultiCli.OsUser' { param($a) Get-OsUserSandboxRoot -Adapter $a -SandboxHome 'C:\sandbox' } @($adapter)
        } @("Adapter 'agy-cli' has no normal-state root for windows")
    }

    It 'wraps link-creation failures with source and destination context' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('mcli_osuser_link_' + [guid]::NewGuid().ToString('N'))
        $source = Join-Path $root 'missing-source.txt'
        $destination = Join-Path $root 'nested\destination.txt'
        try {
            Assert-ThrownContains {
                Invoke-ModuleInternal 'MultiCli.OsUser' {
                    param($s, $d) New-OsUserLink -Source $s -Destination $d -Label 'shared state'
                } @($source, $destination)
            } @('Cannot link shared state', $destination, $source)
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

}

Describe 'native account and ACL orchestration' {
    It 'creates and marks the owned account with exact native arguments' {
        $calls = Invoke-OsUserShimmed {
            $script:NativeCalls = New-Object 'System.Collections.Generic.List[string]'
            function script:Invoke-OsUserNative {
                param([string]$FilePath, [string[]]$NativeArgs)
                $script:NativeCalls.Add("$FilePath|$($NativeArgs -join '|')")
                $global:LASTEXITCODE = 0
                return ''
            }
            New-OsUserAccount -Username 'mcli_test000000' -Password 'Secret-123' -Tool 'fixture'
            return @($script:NativeCalls)
        }
        @($calls).Count | Should Be 2
        $calls[0] | Should Be 'net.exe|user|mcli_test000000|Secret-123|/add|/expires:never|/passwordchg:no'
        $calls[1] | Should Be 'net.exe|user|mcli_test000000|/comment:multi-cli owned sandbox user for fixture'
    }

    It 'surfaces account creation and ownership-marker failures' {
        foreach ($failure in @(
            [pscustomobject]@{ Index = 1; Fragment = "Failed to create OS user 'mcli_test000000': create denied" },
            [pscustomobject]@{ Index = 2; Fragment = "Failed to mark OS user 'mcli_test000000' as multi-cli-owned: comment denied" }
        )) {
            Assert-ThrownContains {
                Invoke-OsUserShimmed {
                    param($failAt)
                    $script:NativeIndex = 0
                    function script:Invoke-OsUserNative {
                        param([string]$FilePath, [string[]]$NativeArgs)
                        $script:NativeIndex++
                        if ($script:NativeIndex -eq $failAt) {
                            $global:LASTEXITCODE = 1
                            return @('create denied', 'comment denied')[$failAt - 1]
                        }
                        $global:LASTEXITCODE = 0
                        return ''
                    }
                    New-OsUserAccount -Username 'mcli_test000000' -Password 'Secret-123' -Tool 'fixture'
                } @($failure.Index)
            } @($failure.Fragment)
        }
    }

    It 'grants recursive Modify access and reports icacls failures' {
        $call = Invoke-OsUserShimmed {
            function script:Invoke-OsUserNative {
                param([string]$FilePath, [string[]]$NativeArgs)
                $global:LASTEXITCODE = 0
                return "$FilePath|$($NativeArgs -join '|')"
            }
            Grant-OsUserAccess -Path 'C:\profile' -Username 'mcli_test000000'
            return Invoke-OsUserNative -FilePath icacls.exe -NativeArgs @('C:\profile', '/grant', 'mcli_test000000:(OI)(CI)M', '/T')
        }
        $call | Should Be 'icacls.exe|C:\profile|/grant|mcli_test000000:(OI)(CI)M|/T'

        Assert-ThrownContains {
            Invoke-OsUserShimmed {
                function script:Invoke-OsUserNative {
                    $global:LASTEXITCODE = 5
                    return 'access denied'
                }
                Grant-OsUserAccess -Path 'C:\profile' -Username 'mcli_test000000'
            }
        } @("Failed to grant OS user 'mcli_test000000' access to 'C:\profile': access denied")
    }
}

Describe 'provisioning orchestration with safe boundaries' {
    It 'adopts an existing user only when its ownership record matches' {
        $scratch = New-OsUserScratch
        try {
            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username $script:FixtureUsername
            $username = Invoke-OsUserShimmed {
                param($adapter, $profileDir)
                function script:Test-OsUserExists { return $true }
                function script:Assert-OsUserElevated { throw 'elevation must not run for adoption' }
                Initialize-OsUserIsolation -Adapter $adapter -ProfileDir $profileDir
            } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir)
            $username | Should Be $script:FixtureUsername
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses to adopt an existing user without an ownership record' {
        $scratch = New-OsUserScratch
        try {
            Assert-ThrownContains {
                Invoke-OsUserShimmed {
                    param($adapter, $profileDir)
                    function script:Test-OsUserExists { return $true }
                    Initialize-OsUserIsolation -Adapter $adapter -ProfileDir $profileDir
                } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir)
            } @($script:FixtureUsername, 'already exists', 'not recorded as multi-cli-owned', 'refusing to touch it')
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'provisions a new user, stores its credential, records ownership, and grants access' {
        $scratch = New-OsUserScratch
        try {
            $outcome = Invoke-OsUserShimmed {
                param($adapter, $profileDir)
                $script:ProvisionEvents = New-Object 'System.Collections.Generic.List[string]'
                function script:Test-OsUserExists { return $false }
                function script:Test-OsUserElevated { return $true }
                function script:Import-OsUserCredentialStore { $script:ProvisionEvents.Add('import') }
                function script:New-OsUserPassword { return 'Fixed-Password-123' }
                function script:New-OsUserAccount {
                    param($Username, $Password, $Tool)
                    $script:ProvisionEvents.Add("account|$Username|$Password|$Tool")
                }
                function script:Set-MultiCliCredential {
                    param($Target, $Secret)
                    $script:ProvisionEvents.Add("credential|$Target|$Secret")
                }
                function script:Grant-OsUserAccess {
                    param($Path, $Username)
                    $script:ProvisionEvents.Add("acl|$Path|$Username")
                }
                $username = Initialize-OsUserIsolation -Adapter $adapter -ProfileDir $profileDir
                [pscustomobject]@{ Username = $username; Events = @($script:ProvisionEvents) }
            } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir)
            $outcome.Username | Should Be $script:FixtureUsername
            @($outcome.Events).Count | Should Be 4
            $outcome.Events[0] | Should Be 'import'
            $outcome.Events[1] | Should Be "account|$script:FixtureUsername|Fixed-Password-123|agy-cli"
            $outcome.Events[2] | Should Be "credential|multi-cli/osuser/$script:FixtureUsername|Fixed-Password-123"
            $outcome.Events[3] | Should Be "acl|$($scratch.ProfileDir)|$script:FixtureUsername"
            (Get-OsUserOwnership -ProfileDir $scratch.ProfileDir).username | Should Be $script:FixtureUsername
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rolls back the credential, record, and user when ACL setup fails' {
        $scratch = New-OsUserScratch
        try {
            $events = New-Object 'System.Collections.Generic.List[string]'
            Assert-ThrownContains {
                Invoke-OsUserShimmed {
                    param($adapter, $profileDir, $capturedEvents)
                    function script:Test-OsUserExists { return $false }
                    function script:Test-OsUserElevated { return $true }
                    function script:Import-OsUserCredentialStore {}
                    function script:New-OsUserPassword { return 'Fixed-Password-123' }
                    function script:New-OsUserAccount {}
                    function script:Set-MultiCliCredential { $capturedEvents.Add('credential-created') }
                    function script:Remove-MultiCliCredential {
                        param($Target)
                        $capturedEvents.Add("credential-removed|$Target")
                    }
                    function script:Grant-OsUserAccess { throw 'ACL setup failed' }
                    function script:Invoke-OsUserNative {
                        param($FilePath, $NativeArgs)
                        $capturedEvents.Add("$FilePath|$($NativeArgs -join '|')")
                        $global:LASTEXITCODE = 0
                        return ''
                    }
                    Initialize-OsUserIsolation -Adapter $adapter -ProfileDir $profileDir
                } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir, $events)
            } @('ACL setup failed')
            ($events -join "`n") | Should Be (@(
                'credential-created'
                "credential-removed|multi-cli/osuser/$script:FixtureUsername"
                "net.exe|user|$script:FixtureUsername|/delete"
            ) -join "`n")
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'deletes the new user when credential storage fails and writes no ownership record' {
        $scratch = New-OsUserScratch
        try {
            $rollbackCalls = New-Object 'System.Collections.Generic.List[string]'
            Assert-ThrownContains {
                Invoke-OsUserShimmed {
                    param($adapter, $profileDir, $calls)
                    function script:Test-OsUserExists { return $false }
                    function script:Test-OsUserElevated { return $true }
                    function script:Import-OsUserCredentialStore {}
                    function script:New-OsUserPassword { return 'Fixed-Password-123' }
                    function script:New-OsUserAccount {}
                    function script:Set-MultiCliCredential { throw 'credential store unavailable' }
                    function script:Invoke-OsUserNative {
                        param($FilePath, $NativeArgs)
                        $calls.Add("$FilePath|$($NativeArgs -join '|')")
                        $global:LASTEXITCODE = 0
                        return ''
                    }
                    Initialize-OsUserIsolation -Adapter $adapter -ProfileDir $profileDir
                } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir, $rollbackCalls)
            } @('credential store unavailable')
            @($rollbackCalls).Count | Should Be 1
            $rollbackCalls[0] | Should Be "net.exe|user|$script:FixtureUsername|/delete"
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'detached process boundary' {
    It 'starts with the owned-user credential and exact argument list' {
        $capture = Invoke-OsUserShimmed {
            function script:Import-OsUserCredentialStore {}
            function script:Get-MultiCliCredential { return 'Credential-Secret-123' }
            function script:Start-Process {
                param($FilePath, $Credential, [switch]$LoadUserProfile, [switch]$PassThru, $ArgumentList)
                $script:ProcessCapture = [pscustomobject]@{
                    FilePath = $FilePath
                    Username = $Credential.UserName
                    Password = $Credential.GetNetworkCredential().Password
                    LoadUserProfile = [bool]$LoadUserProfile
                    PassThru = [bool]$PassThru
                    Arguments = @($ArgumentList)
                }
                return [pscustomobject]@{ Id = 123 }
            }
            $started = Start-OsUserInteractiveProcess -Username 'mcli_test000000' -CredentialTarget 'target' -Binary 'C:\fixture.exe' -BinaryArgs @('--one', 'two words')
            [pscustomobject]@{ Started = $started; Process = $script:ProcessCapture }
        }
        $capture.Started | Should Be $true
        $capture.Process.FilePath | Should Be 'C:\fixture.exe'
        $capture.Process.Username | Should Be '.\mcli_test000000'
        $capture.Process.Password | Should Be 'Credential-Secret-123'
        $capture.Process.LoadUserProfile | Should Be $true
        $capture.Process.PassThru | Should Be $true
        ($capture.Process.Arguments -join '|') | Should Be '--one|two words'
    }

    It 'omits the argument list and returns false when no process starts' {
        $capture = Invoke-OsUserShimmed {
            function script:Import-OsUserCredentialStore {}
            function script:Get-MultiCliCredential { return 'Credential-Secret-123' }
            function script:Start-Process {
                param($FilePath, $Credential, [switch]$LoadUserProfile, [switch]$PassThru, $ArgumentList)
                $script:HasArgumentList = $PSBoundParameters.ContainsKey('ArgumentList')
                return $null
            }
            $started = Start-OsUserInteractiveProcess -Username 'mcli_test000000' -CredentialTarget 'target' -Binary 'C:\fixture.exe' -BinaryArgs @()
            [pscustomobject]@{ Started = $started; HasArgumentList = $script:HasArgumentList }
        }
        $capture.Started | Should Be $false
        $capture.HasArgumentList | Should Be $false
    }
}

Describe 'sandbox profile lookup boundary' {
    It 'returns a profile image path from translated account identity' {
        $profileHome = Invoke-OsUserShimmed {
            function script:New-Object {
                param([string]$TypeName, $ArgumentList)
                $account = [pscustomobject]@{}
                $account | Add-Member ScriptMethod Translate { [pscustomobject]@{ Value = 'S-1-5-21-test' } }
                return $account
            }
            function script:Get-ItemProperty {
                [pscustomobject]@{ ProfileImagePath = 'C:\Users\fixture' }
            }
            Get-OsUserSandboxHome -Username 'mcli_test000000'
        }
        $profileHome | Should Be 'C:\Users\fixture'
    }

    It 'returns null when account translation or profile lookup fails' {
        $profileHome = Invoke-OsUserShimmed {
            function script:New-Object { throw 'unknown account' }
            Get-OsUserSandboxHome -Username 'mcli_missing0000'
        }
        $profileHome | Should Be $null
    }
}

Describe 'sandbox-home bootstrap orchestration' {
    It 'refuses bootstrap before task creation when the credential is missing' {
        Assert-ThrownContains {
            Invoke-OsUserShimmed {
                function script:Import-OsUserCredentialStore {}
                function script:Get-MultiCliCredential { return $null }
                Initialize-OsUserSandboxHome -Username 'mcli_test000000' -CredentialTarget 'target'
            }
        } @("OS-user credential for 'mcli_test000000' is missing", 'target')
    }

    It 'starts a credential-bound process and observes immediate profile materialization' {
        $events = Invoke-OsUserShimmed {
            function script:Start-OsUserInteractiveProcess {
                param($Username, $CredentialTarget, $Binary, $BinaryArgs)
                $script:BootstrapCall = "start|$Username|$CredentialTarget|$Binary|$($BinaryArgs -join '|')"
                return $true
            }
            function script:Get-OsUserSandboxHome { return 'C:\Users\fixture' }
            Initialize-OsUserSandboxHome -Username 'mcli_test000000' -CredentialTarget 'target'
            return $script:BootstrapCall
        }
        $events | Should Be "start|mcli_test000000|target|$env:ComSpec|/d|/c|exit 0"
    }

    It 'reports a bootstrap process that does not start' {
        Assert-ThrownContains {
            Invoke-OsUserShimmed {
                function script:Start-OsUserInteractiveProcess { return $false }
                Initialize-OsUserSandboxHome -Username 'mcli_test000000' -CredentialTarget 'target'
            }
        } @("Could not start the profile bootstrap process for OS user 'mcli_test000000'")
    }

    It 'polls every 500 milliseconds until the profile materializes' {
        $capture = Invoke-OsUserShimmed {
            $script:HomeLookupCount = 0
            $script:SleepMilliseconds = 0
            function script:Start-OsUserInteractiveProcess { return $true }
            function script:Get-OsUserSandboxHome {
                $script:HomeLookupCount++
                if ($script:HomeLookupCount -eq 1) { return $null }
                return 'C:\Users\fixture'
            }
            function script:Start-Sleep {
                param($Milliseconds)
                $script:SleepMilliseconds = $Milliseconds
            }
            function script:Invoke-OsUserNative {
                $global:LASTEXITCODE = 0
                return ''
            }
            Initialize-OsUserSandboxHome -Username 'mcli_test000000' -CredentialTarget 'target'
            [pscustomobject]@{ Lookups = $script:HomeLookupCount; SleepMilliseconds = $script:SleepMilliseconds }
        }
        $capture.Lookups | Should Be 2
        $capture.SleepMilliseconds | Should Be 500
    }

    It 'times out without sleeping after the deadline expires' {
        Assert-ThrownContains {
            Invoke-OsUserShimmed {
                function script:Start-OsUserInteractiveProcess { return $true }
                function script:Get-OsUserSandboxHome { return $null }
                function script:Start-Sleep { throw 'sleep must not run after an expired deadline' }
                Initialize-OsUserSandboxHome -Username 'mcli_test000000' -CredentialTarget 'target' -TimeoutSeconds -1
            }
        } @("The profile directory for OS user 'mcli_test000000' did not materialize within -1 seconds", 'Windows user profile event log')
    }
}

Describe 'launch execution orchestration' {
    It 'routes AppX targets through the owned-user launcher' {
        $scratch = New-OsUserScratch
        try {
            $capture = Invoke-OsUserShimmed {
                param($adapter, $profileDir)
                function script:Initialize-OsUserIsolation { return 'mcli_fcfb4582f558' }
                function script:Invoke-OsUserAppxLaunch {
                    param($Username, $CredentialTarget, $ProfileDir, $Target, $TimeoutSeconds)
                    $script:AppxCall = "$Username|$CredentialTarget|$Target"
                    return 0
                }
                function script:Get-OsUserLaunchPlan { throw 'generic launch plan must not run for AppX' }
                $exitCode = Invoke-OsUserLaunch -Adapter $adapter -ProfileDir $profileDir -Binary 'appx:OpenAI.Codex_2p2nqsd0c76g0!App' -BinaryArgs @()
                [pscustomobject]@{ ExitCode = $exitCode; Call = $script:AppxCall }
            } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir)

            $capture.ExitCode | Should Be 0
            $capture.Call | Should Be "$script:FixtureUsername|multi-cli/osuser/$script:FixtureUsername|appx:OpenAI.Codex_2p2nqsd0c76g0!App"
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'accepts only the owned SID and initiating session from AppX activation' {
        $scratch = New-OsUserScratch
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        try {
            $messages = Invoke-OsUserShimmed {
                param($username, $expectedSid, $profileDir)
                $script:AppxCase = 'success'
                function script:Get-Process {
                    param($Id)
                    if ($Id -eq $PID) { return [pscustomobject]@{ SessionId = 2 } }
                    return [pscustomobject]@{ HasExited = $false; MainWindowHandle = 1 }
                }
                function script:Start-Sleep {}
                function script:Start-OsUserWrapperProcess {
                    @{ processId = 4321 } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $profileDir '.osuser-appx.json') -Encoding UTF8
                    $waiter = New-Object psobject
                    $waiter | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($milliseconds) return $true }
                    return $waiter
                }
                function script:Get-CimInstance {
                    $script:CimCalls++
                    if ($script:AppxCase -eq 'success' -and $script:CimCalls -eq 1) { return $null }
                    $session = if ($script:AppxCase -eq 'session') { 9 } else { 2 }
                    return [pscustomobject]@{ ProcessId = 4321; SessionId = $session }
                }
                function script:Invoke-CimMethod {
                    $sid = if ($script:AppxCase -eq 'owner') { 'S-1-0-0' } else { $expectedSid }
                    return [pscustomobject]@{ ReturnValue = 0; Sid = $sid }
                }

                $target = 'appx:OpenAI.Codex_2p2nqsd0c76g0!App'
                $outcomes = New-Object 'System.Collections.Generic.List[string]'
                foreach ($case in @('success', 'owner', 'session')) {
                    $script:AppxCase = $case
                    $script:CimCalls = 0
                    try {
                        $code = Invoke-OsUserAppxLaunch -Username $username -CredentialTarget 'fixture' -ProfileDir $profileDir -Target $target
                        $outcomes.Add("$case|$code|$script:CimCalls")
                    } catch {
                        $outcomes.Add("$case|$($_.Exception.Message)")
                    }
                }
                return @($outcomes)
            } @($currentUser, $currentSid, $scratch.ProfileDir)

            $messages[0] | Should Be 'success|0|2'
            $messages[1] | Should Match '(?s)owner\|.*Phase: owner-check'
            $messages[2] | Should Match '(?s)session\|.*Phase: session-check'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'fails closed when the owned-user AppX helper cannot be trusted' {
        $scratch = New-OsUserScratch
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        try {
            $messages = Invoke-OsUserShimmed {
                param($username, $expectedSid, $profileDir)
                function script:Get-Process {
                    param($Id)
                    if ($Id -ne $PID) {
                        $script:GuiCalls++
                        if ($script:FailureCase -eq 'no-window') { return [pscustomobject]@{ HasExited = $false; MainWindowHandle = 0 } }
                        return [pscustomobject]@{ HasExited = ($script:GuiCalls -gt 1); MainWindowHandle = 1 }
                    }
                    if ($script:FailureCase -eq 'session') { return [pscustomobject]@{ SessionId = 0 } }
                    return [pscustomobject]@{ SessionId = 2 }
                }
                function script:Start-Sleep {}
                function script:Start-OsUserWrapperProcess {
                    if ($script:FailureCase -eq 'start-throws') { throw 'logon denied' }
                    if ($script:FailureCase -eq 'start-null') { return $null }
                    $resultPath = Join-Path $profileDir '.osuser-appx.json'
                    if ($script:FailureCase -eq 'invalid-result') { Set-Content -LiteralPath $resultPath -Value '{bad' -Encoding UTF8 }
                    if ($script:FailureCase -eq 'error-result') { @{ error = 'activation failed' } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8 }
                    if ($script:FailureCase -in @('no-process', 'no-window', 'short-lived')) { @{ processId = 4321 } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8 }
                    if ($script:FailureCase -eq 'no-pid') { @{ phase = 'activate' } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8 }
                    $waiter = [pscustomobject]@{ Completed = ($script:FailureCase -ne 'timeout') }
                    $waiter | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($milliseconds) return $this.Completed }
                    return $waiter
                }
                function script:Get-CimInstance {
                    if ($script:FailureCase -eq 'no-process') { return $null }
                    return [pscustomobject]@{ ProcessId = 4321; SessionId = 2 }
                }
                function script:Invoke-CimMethod { [pscustomobject]@{ ReturnValue = 0; Sid = $expectedSid } }

                $outcomes = New-Object 'System.Collections.Generic.List[string]'
                foreach ($case in @('target', 'session', 'start-throws', 'start-null', 'timeout', 'no-result', 'invalid-result', 'error-result', 'no-pid', 'no-process', 'no-window', 'short-lived')) {
                    $script:FailureCase = $case
                    $script:GuiCalls = 0
                    $target = if ($case -eq 'target') { 'appx:invalid' } else { 'appx:OpenAI.Codex_2p2nqsd0c76g0!App' }
                    try {
                        Invoke-OsUserAppxLaunch -Username $username -CredentialTarget 'fixture' -ProfileDir $profileDir -Target $target -TimeoutSeconds 1 | Out-Null
                    } catch {
                        $outcomes.Add("$case|$($_.Exception.Message)")
                    }
                }
                return @($outcomes)
            } @($currentUser, $currentSid, $scratch.ProfileDir)

            $joined = $messages -join "`n"
            $joined | Should Match '(?s)target\|.*package family and application id'
            $joined | Should Match '(?s)session\|.*not in an interactive Windows session'
            $joined | Should Match '(?s)start-throws\|.*logon denied'
            $joined | Should Match '(?s)start-null\|.*did not start'
            $joined | Should Match '(?s)timeout\|.*timed out'
            $joined | Should Match '(?s)no-result\|.*returned no result'
            $joined | Should Match '(?s)invalid-result\|.*invalid result'
            $joined | Should Match '(?s)error-result\|.*activation failed'
            $joined | Should Match '(?s)no-pid\|.*returned no process ID'
            $joined | Should Match '(?s)no-process\|.*does not belong to the owned user'
            $joined | Should Match '(?s)no-window\|.*did not produce a visible GUI window'
            $joined | Should Match '(?s)short-lived\|.*exited before launch verification completed'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns zero for a detached launch that starts under the owned user' {
        $scratch = New-OsUserScratch
        try {
            $adapter = Get-OsUserFixtureAdapter
            $adapter.isolation.mode = 'detached'
            $capture = Invoke-OsUserShimmed {
                param($fixtureAdapter, $profileDir, $sandboxHome)
                function script:Initialize-OsUserIsolation { return 'mcli_fcfb4582f558' }
                function script:Assert-OsUserElevated {}
                function script:Start-OsUserInteractiveProcess {
                    param($Username, $CredentialTarget, $Binary, $BinaryArgs)
                    $script:DetachedCapture = "$Username|$CredentialTarget|$Binary|$($BinaryArgs -join '|')"
                    return $true
                }
                $exitCode = Invoke-OsUserLaunch -Adapter $fixtureAdapter -ProfileDir $profileDir -Binary 'C:\fixture.exe' -BinaryArgs @('--open', 'file.txt') -SandboxHome $sandboxHome
                [pscustomobject]@{ ExitCode = $exitCode; Call = $script:DetachedCapture }
            } @($adapter, $scratch.ProfileDir, (Join-Path $scratch.Root 'sandbox'))
            $capture.ExitCode | Should Be 0
            $capture.Call | Should Be "$script:FixtureUsername|multi-cli/osuser/$script:FixtureUsername|C:\fixture.exe|--open|file.txt"
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports a detached launch that returns no process' {
        $scratch = New-OsUserScratch
        try {
            $adapter = Get-OsUserFixtureAdapter
            $adapter.isolation.mode = 'detached'
            Assert-ThrownContains {
                Invoke-OsUserShimmed {
                    param($fixtureAdapter, $profileDir, $sandboxHome)
                    function script:Initialize-OsUserIsolation { return 'mcli_fcfb4582f558' }
                    function script:Assert-OsUserElevated {}
                    function script:Start-OsUserInteractiveProcess { return $false }
                    Invoke-OsUserLaunch -Adapter $fixtureAdapter -ProfileDir $profileDir -Binary 'C:\fixture.exe' -BinaryArgs @() -SandboxHome $sandboxHome
                } @($adapter, $scratch.ProfileDir, (Join-Path $scratch.Root 'sandbox'))
            } @("OS-user launch of 'C:\fixture.exe' did not start")
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'materializes a missing home before planning a detached launch' {
        $scratch = New-OsUserScratch
        try {
            $adapter = Get-OsUserFixtureAdapter
            $adapter.isolation.mode = 'detached'
            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username $script:FixtureUsername
            $capture = Invoke-OsUserShimmed {
                param($fixtureAdapter, $profileDir, $materializedHome)
                $script:HomeLookups = 0
                function script:Initialize-OsUserIsolation { return 'mcli_fcfb4582f558' }
                function script:Assert-OsUserElevated {}
                function script:Get-OsUserSandboxHome {
                    $script:HomeLookups++
                    if ($script:HomeLookups -eq 1) { return $null }
                    return $materializedHome
                }
                function script:Initialize-OsUserSandboxHome {
                    param($Username, $CredentialTarget)
                    $script:BootstrapCapture = "$Username|$CredentialTarget"
                }
                function script:Start-OsUserInteractiveProcess { return $true }
                $exitCode = Invoke-OsUserLaunch -Adapter $fixtureAdapter -ProfileDir $profileDir -Binary 'C:\fixture.exe' -BinaryArgs @() -SandboxHome ''
                [pscustomobject]@{ ExitCode = $exitCode; HomeLookups = $script:HomeLookups; Bootstrap = $script:BootstrapCapture }
            } @($adapter, $scratch.ProfileDir, (Join-Path $scratch.Root 'materialized'))
            $capture.ExitCode | Should Be 0
            $capture.HomeLookups | Should Be 2
            $capture.Bootstrap | Should Be "$script:FixtureUsername|multi-cli/osuser/$script:FixtureUsername"
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'wires declared state, starts the credential-bound wrapper, and returns its exact exit code' {
        $scratch = New-OsUserScratch
        $previousUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $scratch.Home
        try {
            $sandboxHome = Join-Path $scratch.Root 'sandbox'
            $events = Invoke-OsUserShimmed {
                param($adapter, $profileDir, $sandboxHome)
                $script:LaunchEvents = New-Object 'System.Collections.Generic.List[string]'
                function script:Initialize-OsUserIsolation { return 'mcli_fcfb4582f558' }
                function script:Assert-OsUserElevated {}
                function script:Grant-OsUserAccess {
                    param($Path, $Username)
                    $script:LaunchEvents.Add("acl|$Path|$Username")
                }
                function script:Start-OsUserWrapperProcess {
                    param($Username, $CredentialTarget, $WrapperPath)
                    $script:LaunchEvents.Add("start|$Username|$CredentialTarget|$WrapperPath")
                    Set-Content -LiteralPath (Join-Path $profileDir '.osuser-launch.exitcode') -Value '7' -Encoding ASCII
                    return [pscustomobject]@{ Id = 123 }
                }
                $exitCode = Invoke-OsUserLaunch -Adapter $adapter -ProfileDir $profileDir -Binary 'C:\fixture.exe' -BinaryArgs @('--version') -SandboxHome $sandboxHome
                [pscustomobject]@{ ExitCode = $exitCode; Events = @($script:LaunchEvents) }
            } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir, $sandboxHome)
            $events.ExitCode | Should Be 7
            $events.Events[0] | Should Be "acl|$(Join-Path $scratch.Home '.fixture-osuser')|$script:FixtureUsername"
            $events.Events[1] | Should Be "start|$script:FixtureUsername|multi-cli/osuser/$script:FixtureUsername|$(Join-Path $scratch.ProfileDir '.osuser-task.ps1')"
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser-task.ps1') -PathType Leaf) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $scratch.Root 'sandbox\.fixture-osuser\plugins')) | Should Be $true
        } finally {
            $env:USERPROFILE = $previousUserProfile
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses a foreground launch with no stored credential before task creation' {
        $scratch = New-OsUserScratch
        $previousUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $scratch.Home
        try {
            Assert-ThrownContains {
                Invoke-OsUserShimmed {
                    param($adapter, $profileDir, $sandboxHome)
                    function script:Initialize-OsUserIsolation { return 'mcli_fcfb4582f558' }
                    function script:Assert-OsUserElevated {}
                    function script:Grant-OsUserAccess {}
                    function script:Start-OsUserWrapperProcess {
                        param($Username, $CredentialTarget)
                        New-OsUserCredential -Username $Username -CredentialTarget $CredentialTarget | Out-Null
                        throw 'wrapper must not start without a credential'
                    }
                    function script:Import-OsUserCredentialStore {}
                    function script:Get-MultiCliCredential { return $null }
                    Invoke-OsUserLaunch -Adapter $adapter -ProfileDir $profileDir -Binary 'C:\fixture.exe' -BinaryArgs @() -SandboxHome $sandboxHome
                } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir, (Join-Path $scratch.Root 'sandbox'))
            } @("OS-user credential for '$script:FixtureUsername' is missing", "multi-cli/osuser/$script:FixtureUsername")
        } finally {
            $env:USERPROFILE = $previousUserProfile
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reports a foreground wrapper process that does not start' {
        $scratch = New-OsUserScratch
        $previousUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $scratch.Home
        try {
            Assert-ThrownContains {
                Invoke-OsUserShimmed {
                    param($adapter, $profileDir, $sandboxHome)
                    function script:Initialize-OsUserIsolation { return 'mcli_fcfb4582f558' }
                    function script:Assert-OsUserElevated {}
                    function script:Grant-OsUserAccess {}
                    function script:Start-OsUserWrapperProcess { return $null }
                    Invoke-OsUserLaunch -Adapter $adapter -ProfileDir $profileDir -Binary 'C:\fixture.exe' -BinaryArgs @() -SandboxHome $sandboxHome
                } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir, (Join-Path $scratch.Root 'sandbox'))
            } @("OS-user launch of 'C:\fixture.exe' did not start")
        } finally {
            $env:USERPROFILE = $previousUserProfile
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'polls every 500 milliseconds until the foreground exit code appears' {
        $scratch = New-OsUserScratch
        $previousUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $scratch.Home
        try {
            $capture = Invoke-OsUserShimmed {
                param($adapter, $profileDir, $sandboxHome)
                $script:ExitProbeCount = 0
                $script:SleepMilliseconds = 0
                function script:Initialize-OsUserIsolation { return 'mcli_fcfb4582f558' }
                function script:Assert-OsUserElevated {}
                function script:Grant-OsUserAccess {}
                function script:Start-OsUserWrapperProcess { return [pscustomobject]@{ Id = 123 } }
                function script:Test-Path {
                    param($LiteralPath, $PathType)
                    if ($LiteralPath -notlike '*.osuser-launch.exitcode') {
                        $parameters = @{ LiteralPath = $LiteralPath }
                        if ($PathType) { $parameters.PathType = $PathType }
                        return Microsoft.PowerShell.Management\Test-Path @parameters
                    }
                    $script:ExitProbeCount++
                    if ($script:ExitProbeCount -eq 1) { return $false }
                    Set-Content -LiteralPath $LiteralPath -Value '9' -Encoding ASCII
                    return $true
                }
                function script:Start-Sleep {
                    param($Milliseconds)
                    $script:SleepMilliseconds = $Milliseconds
                }
                function script:Invoke-OsUserNative {
                    $global:LASTEXITCODE = 0
                    return ''
                }
                $exitCode = Invoke-OsUserLaunch -Adapter $adapter -ProfileDir $profileDir -Binary 'C:\fixture.exe' -BinaryArgs @() -SandboxHome $sandboxHome
                [pscustomobject]@{ ExitCode = $exitCode; Probes = $script:ExitProbeCount; SleepMilliseconds = $script:SleepMilliseconds }
            } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir, (Join-Path $scratch.Root 'sandbox'))
            $capture.ExitCode | Should Be 9
            $capture.Probes | Should Be 2
            $capture.SleepMilliseconds | Should Be 500
        } finally {
            $env:USERPROFILE = $previousUserProfile
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'stops a timed-out foreground wrapper process' {
        $scratch = New-OsUserScratch
        $previousUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $scratch.Home
        try {
            $stopped = $false
            Assert-ThrownContains {
                Invoke-OsUserShimmed {
                    param($adapter, $profileDir, $sandboxHome, [ref]$wasStopped)
                    function script:Initialize-OsUserIsolation { return 'mcli_fcfb4582f558' }
                    function script:Assert-OsUserElevated {}
                    function script:Grant-OsUserAccess {}
                    $script:WrapperProcess = [pscustomobject]@{ Id = 123; HasExited = $false }
                    $script:WrapperProcess | Add-Member ScriptMethod Kill { $wasStopped.Value = $true }
                    function script:Start-OsUserWrapperProcess { return $script:WrapperProcess }
                    function script:Start-Sleep { throw 'sleep must not run after an expired deadline' }
                    Invoke-OsUserLaunch -Adapter $adapter -ProfileDir $profileDir -Binary 'C:\fixture.exe' -BinaryArgs @() -SandboxHome $sandboxHome -TimeoutSeconds -1
                } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir, (Join-Path $scratch.Root 'sandbox'), ([ref]$stopped))
            } @("OS-user launch of 'C:\fixture.exe' did not finish within -1 seconds", 'process was stopped')
            $stopped | Should Be $true
        } finally {
            $env:USERPROFILE = $previousUserProfile
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a malformed exit-code file' {
        $scratch = New-OsUserScratch
        $previousUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $scratch.Home
        try {
            Assert-ThrownContains {
                Invoke-OsUserShimmed {
                    param($adapter, $profileDir, $sandboxHome)
                    function script:Initialize-OsUserIsolation { return 'mcli_fcfb4582f558' }
                    function script:Assert-OsUserElevated {}
                    function script:Grant-OsUserAccess {}
                    function script:Start-OsUserWrapperProcess {
                        Set-Content -LiteralPath (Join-Path $profileDir '.osuser-launch.exitcode') -Value 'not-a-number' -Encoding ASCII
                        return [pscustomobject]@{ Id = 123 }
                    }
                    Invoke-OsUserLaunch -Adapter $adapter -ProfileDir $profileDir -Binary 'C:\fixture.exe' -BinaryArgs @() -SandboxHome $sandboxHome
                } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir, (Join-Path $scratch.Root 'sandbox'))
            } @('wrote a malformed exit-code file', '.osuser-launch.exitcode', '.osuser-launch.log')
        } finally {
            $env:USERPROFILE = $previousUserProfile
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'owned-user deletion orchestration' {
    It 'deletes an existing task, user, credential, and ownership record in order' {
        $scratch = New-OsUserScratch
        try {
            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username $script:FixtureUsername
            $events = Invoke-OsUserShimmed {
                param($profileDir)
                $script:DeleteEvents = New-Object 'System.Collections.Generic.List[string]'
                $script:NativeIndex = 0
                function script:Test-OsUserElevated { return $true }
                function script:Import-OsUserCredentialStore {}
                function script:Test-OsUserExists { return $true }
                function script:Invoke-OsUserNative {
                    param($FilePath, $NativeArgs)
                    $script:NativeIndex++
                    $script:DeleteEvents.Add("$FilePath|$($NativeArgs -join '|')")
                    $global:LASTEXITCODE = 0
                    return ''
                }
                function script:Remove-MultiCliCredential {
                    param($Target)
                    $script:DeleteEvents.Add("credential|$Target")
                    return $true
                }
                $removed = Remove-OsUserIsolation -ProfileDir $profileDir
                [pscustomobject]@{ Removed = $removed; Events = @($script:DeleteEvents) }
            } @($scratch.ProfileDir)
            $events.Removed | Should Be $true
            ($events.Events -join "`n") | Should Be ( @(
                'schtasks.exe|/query|/tn|multi-cli-fcfb4582f558'
                'schtasks.exe|/delete|/tn|multi-cli-fcfb4582f558|/f'
                "net.exe|user|$script:FixtureUsername|/delete"
                "credential|multi-cli/osuser/$script:FixtureUsername"
            ) -join "`n")
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'removes credentials and ownership when task and user are already absent' {
        $scratch = New-OsUserScratch
        try {
            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username $script:FixtureUsername
            $events = Invoke-OsUserShimmed {
                param($profileDir)
                $script:DeleteEvents = New-Object 'System.Collections.Generic.List[string]'
                function script:Test-OsUserElevated { return $true }
                function script:Import-OsUserCredentialStore {}
                function script:Test-OsUserExists { return $false }
                function script:Invoke-OsUserNative {
                    $global:LASTEXITCODE = 1
                    return 'not found'
                }
                function script:Remove-MultiCliCredential {
                    param($Target)
                    $script:DeleteEvents.Add($Target)
                }
                $removed = Remove-OsUserIsolation -ProfileDir $profileDir
                [pscustomobject]@{ Removed = $removed; Events = @($script:DeleteEvents) }
            } @($scratch.ProfileDir)
            $events.Removed | Should Be $true
            @($events.Events).Count | Should Be 1
            $events.Events[0] | Should Be "multi-cli/osuser/$script:FixtureUsername"
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'preserves later resources when scheduled-task deletion fails' {
        $scratch = New-OsUserScratch
        try {
            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username $script:FixtureUsername
            Assert-ThrownContains {
                Invoke-OsUserShimmed {
                    param($profileDir)
                    $script:NativeIndex = 0
                    function script:Test-OsUserElevated { return $true }
                    function script:Import-OsUserCredentialStore {}
                    function script:Invoke-OsUserNative {
                        $script:NativeIndex++
                        if ($script:NativeIndex -eq 1) { $global:LASTEXITCODE = 0; return '' }
                        $global:LASTEXITCODE = 5
                        return 'access denied'
                    }
                    function script:Test-OsUserExists { throw 'user probe must not run' }
                    function script:Remove-MultiCliCredential { throw 'credential removal must not run' }
                    Remove-OsUserIsolation -ProfileDir $profileDir
                } @($scratch.ProfileDir)
            } @("Failed to delete scheduled task 'multi-cli-fcfb4582f558': access denied")
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json')) | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'preserves the credential and ownership record when user deletion fails' {
        $scratch = New-OsUserScratch
        try {
            Write-OsUserRecord -ProfileDir $scratch.ProfileDir -Username $script:FixtureUsername
            Assert-ThrownContains {
                Invoke-OsUserShimmed {
                    param($profileDir)
                    function script:Test-OsUserElevated { return $true }
                    function script:Import-OsUserCredentialStore {}
                    function script:Test-OsUserExists { return $true }
                    function script:Invoke-OsUserNative {
                        param($FilePath, $NativeArgs)
                        if ($FilePath -eq 'schtasks.exe') { $global:LASTEXITCODE = 1; return 'not found' }
                        $global:LASTEXITCODE = 5
                        return 'access denied'
                    }
                    function script:Remove-MultiCliCredential { throw 'credential removal must not run' }
                    Remove-OsUserIsolation -ProfileDir $profileDir
                } @($scratch.ProfileDir)
            } @("Failed to delete OS user '$script:FixtureUsername': access denied")
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.osuser.json')) | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'launch-plan home discovery' {
    It 'uses the discovered sandbox home when none is supplied' {
        $scratch = New-OsUserScratch
        $previousUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $scratch.Home
        try {
            $plan = Invoke-OsUserShimmed {
                param($adapter, $profileDir)
                function script:Get-OsUserSandboxHome { return 'C:\DiscoveredHome' }
                Get-OsUserLaunchPlan -Adapter $adapter -ProfileDir $profileDir -Binary 'C:\fixture.exe' -BinaryArgs @() -SandboxHome ''
            } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir)
            $plan.SandboxHome | Should Be 'C:\DiscoveredHome'
            $plan.SandboxRoot | Should Be 'C:\DiscoveredHome\.fixture-osuser'
        } finally {
            $env:USERPROFILE = $previousUserProfile
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'falls back to the conventional user-profile path when discovery returns null' {
        $scratch = New-OsUserScratch
        $previousUserProfile = $env:USERPROFILE
        $previousSystemDrive = $env:SystemDrive
        $env:USERPROFILE = $scratch.Home
        $env:SystemDrive = 'C:'
        try {
            $plan = Invoke-OsUserShimmed {
                param($adapter, $profileDir)
                function script:Get-OsUserSandboxHome { return $null }
                Get-OsUserLaunchPlan -Adapter $adapter -ProfileDir $profileDir -Binary 'C:\fixture.exe' -BinaryArgs @() -SandboxHome ''
            } @((Get-OsUserFixtureAdapter), $scratch.ProfileDir)
            $plan.SandboxHome | Should Be "C:\Users\$script:FixtureUsername"
        } finally {
            $env:USERPROFILE = $previousUserProfile
            $env:SystemDrive = $previousSystemDrive
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
