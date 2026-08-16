<#
.SYNOPSIS
  In-process unit tests for the multi-cli lib/*.psm1 modules.

.DESCRIPTION
  Pester 3.4's -CodeCoverage only sees commands that execute in its own
  runspace. The launcher-based suites run multi-cli.ps1 in child processes,
  so the modules report 0% there. This suite imports the lib/*.psm1 modules
  directly (Import-Module -Force) and calls their functions in-process: the
  exported surface directly, and module-internal helpers through the
  module's own session state via NewBoundScriptBlock.

  The runtime module resolves Resolve-PathToken from the caller's session
  state (multi-cli.ps1 defines it in production); this file provides the
  same global contract so module functions run exactly as in production.

  Everything runs against disposable temp trees. Credential Manager
  exercises use uniquely named targets (GUID suffixes, fake secrets) and are
  removed in finally blocks. No network, no git, no real secrets.
#>

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:LibDir = Join-Path $script:RepoRoot 'lib'

# Production contract: multi-cli.ps1 defines Resolve-PathToken at top level;
# MultiCli.Runtime calls it from module scope and finds it via the global
# session state. Tests must provide the identical global function.
function global:Resolve-PathToken {
    param([string]$Path)
    if (-not $Path) { return $Path }
    $expanded = $Path -replace '\$HOME', $env:USERPROFILE.Replace('\', '\\')
    return [Environment]::ExpandEnvironmentVariables($expanded)
}

Import-Module (Join-Path $script:LibDir 'MultiCli.AdapterValidation.psm1') -Force
# Transfer before Runtime on purpose: the first import in a fresh runspace
# exercises the transfer module's self-bootstrap of the runtime module.
Import-Module (Join-Path $script:LibDir 'MultiCli.Transfer.psm1') -Force
Import-Module (Join-Path $script:LibDir 'MultiCli.Runtime.psm1') -Force
Import-Module (Join-Path $script:LibDir 'MultiCli.CredentialStore.psm1') -Force
Import-Module (Join-Path $script:LibDir 'MultiCli.Migration.psm1') -Force

function Import-CredentialStoreModule {
    <# Get-AccountOverlayLaunchPlan re-imports the credential store from
       inside the runtime module, which strips the exports this test file
       relies on. Restore them into the global session state. #>
    Import-Module (Join-Path $script:LibDir 'MultiCli.CredentialStore.psm1') -Force -Global
}

function Invoke-ModuleInternal {
    <# Runs a scriptblock inside a module's session state so tests can reach
       non-exported helpers. Arguments are splatted positionally. #>
    param([string]$ModuleName, [scriptblock]$ScriptBlock, [object[]]$Arguments = @())
    $module = Get-Module $ModuleName
    if (-not $module) { throw "Module '$ModuleName' is not imported." }
    $bound = $module.NewBoundScriptBlock($ScriptBlock)
    return & $bound @Arguments
}

function New-ModuleFunctionScratch {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_modfn_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return $root
}

function New-RuntimeScratch {
    <# Temp tree with a fake home and one profile dir (leaf 'account-a'). #>
    $root = New-ModuleFunctionScratch
    $userHome = Join-Path $root 'home'
    $profile = Join-Path $root 'profiles\fixture\account-a'
    New-Item -ItemType Directory -Force -Path $userHome, $profile | Out-Null
    return [pscustomobject]@{ Root = $root; Home = $userHome; ProfileDir = $profile }
}

function Get-ManifestErrors {
    <# Writes Adapter (object or raw JSON) as <ExpectedId>\adapter.json in a
       throwaway temp dir and returns the validator's error list. #>
    param($Adapter, [string]$ExpectedId)
    $root = New-ModuleFunctionScratch
    try {
        $adapterDir = Join-Path $root $ExpectedId
        New-Item -ItemType Directory -Force -Path $adapterDir | Out-Null
        $json = if ($Adapter -is [string]) { $Adapter } else { $Adapter | ConvertTo-Json -Depth 12 }
        $manifest = Join-Path $adapterDir 'adapter.json'
        Set-Content -LiteralPath $manifest -Value $json -Encoding UTF8
        return @(Test-AdapterManifest -ManifestPath $manifest -ExpectedId $ExpectedId)
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-ValidV1Adapter {
    <# Complete schema-v1 adapter (object form). schemaVersion is omitted on
       purpose: the validator must default it to 1. #>
    $adapter = [ordered]@{
        id = 'v1tool'; displayName = 'V1 Tool'; kind = 'cli'
        binary = [ordered]@{ windows = @('v1tool.exe'); macos = @('v1tool'); linux = @('v1tool') }
        isolation = [ordered]@{ strategy = 'env'; env = [ordered]@{ V1_HOME = '{profileDir}' } }
        share = [ordered]@{ systemHome = '$HOME/.v1tool'; linkable = @('config.toml', 'skills'); neverLink = @('auth.json', 'sessions') }
        session = [ordered]@{ portable = $true; paths = @('sessions', 'history.jsonl'); credentials = @('auth.json') }
        status = 'stable'
    }
    return ($adapter | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
}

function Get-ValidV2Adapter {
    <# Complete schema-v2 fileOverlay adapter (object form). The env block
       uses all six supported placeholders; path lists include null/empty
       entries, which the validator and runtime must skip. #>
    $adapter = [ordered]@{
        schemaVersion = 2
        id = 'fixture'; displayName = 'Fixture CLI'; kind = 'cli'
        binary = [ordered]@{ windows = @('fixture.exe'); macos = @('fixture'); linux = @('fixture') }
        isolation = [ordered]@{
            strategy = 'accountOverlay'; mode = 'foreground'
            env = [ordered]@{
                FIXTURE_RUNTIME = '{runtimeRoot}'; FIXTURE_PROFILE = '{profileDir}'; FIXTURE_AUTH = '{authDir}'
                FIXTURE_SHARED = '{sharedStateRoot}'; FIXTURE_PID = '{profileId}'; FIXTURE_REALHOME = '{realHome}'
            }
            clearEnv = @('GLOBAL_FIXTURE_TOKEN')
        }
        account = [ordered]@{ mechanism = 'fileOverlay'; credentialFiles = @('auth.json', '') }
        normalState = [ordered]@{
            root = [ordered]@{ windows = '%USERPROFILE%\.fixture'; macos = '$HOME/.fixture'; linux = '$HOME/.fixture' }
            sharedPaths = @('config.toml', 'agents', '')
            sessionPaths = @('sessions', 'history.jsonl', $null)
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
    return ($adapter | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
}

function Set-AdapterMechanism {
    <# Rewrites the account block of a v2 adapter for the given mechanism.
       Round-trips through JSON: modules read account members via
       PSObject.Properties, which does not surface OrderedDictionary keys. #>
    param($Adapter, [string]$Mechanism)
    $account = [ordered]@{ mechanism = $Mechanism }
    switch ($Mechanism) {
        'fileOverlay' { $account['credentialFiles'] = @('auth.json', '') }
        'processSecret' {
            $account['credentialFiles'] = @('auth.json')
            $account['secret'] = [ordered]@{ environmentVariable = 'FIXTURE_API_TOKEN' }
        }
        'inseparable' { $account['reason'] = 'Vendor binds auth to the OS account.' }
    }
    $Adapter.account = ($account | ConvertTo-Json -Depth 6 | ConvertFrom-Json)
}

function Assert-ManifestError {
    <# Asserts the error list contains exactly one occurrence of Message. #>
    param([object[]]$Errors, [string]$Message)
    (@($Errors) | Where-Object { $_ -eq $Message }).Count | Should Be 1
}

function Invoke-ManifestCase {
    <# Executes one validation case: Base ('v1'/'v2') adapter with Mutate
       applied, or Raw JSON; asserts the exact error count and messages. #>
    param([hashtable]$Case)
    if ($Case.Raw) {
        $errors = Get-ManifestErrors -Adapter $Case.Raw -ExpectedId $Case.Id
    } else {
        $adapter = if ($Case.Base -eq 'v1') { Get-ValidV1Adapter } else { Get-ValidV2Adapter }
        if ($Case.Mutate) { & $Case.Mutate $adapter }
        $errors = Get-ManifestErrors -Adapter $adapter -ExpectedId $Case.Id
    }
    $errors.Count | Should Be $Case.Count
    foreach ($message in $Case.Messages) { Assert-ManifestError -Errors $errors -Message $message }
}

function Add-ManifestCases {
    <# Registers one named It per case. Pester 3.4 executes It blocks
       immediately, so each It sees the current loop value of $case. #>
    param([hashtable[]]$Cases)
    foreach ($case in $Cases) {
        It $case.Name { Invoke-ManifestCase -Case $case }
    }
}

Describe 'Test-AdapterManifest schema-v1 in-process' {
    Add-ManifestCases @(
        @{ Name = 'accepts a complete v1 adapter and defaults schemaVersion to 1'; Base = 'v1'; Id = 'v1tool'; Count = 0; Messages = @() },
        @{ Name = 'accepts v1 strategy userDataDir'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.isolation.strategy = 'userDataDir' }; Count = 0; Messages = @() },
        @{ Name = 'accepts v1 strategy redirectHome'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.isolation.strategy = 'redirectHome' }; Count = 0; Messages = @() },
        @{ Name = 'accepts v1 strategy appdata'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.isolation.strategy = 'appdata' }; Count = 0; Messages = @() },
        @{ Name = 'accepts v1 strategy sandboxUser with explicit schemaVersion 1'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.isolation.strategy = 'sandboxUser'; $a | Add-Member -NotePropertyName schemaVersion -NotePropertyValue 1 }; Count = 0; Messages = @() },
        @{ Name = 'rejects malformed JSON'; Raw = '{"id":"v1tool"'; Id = 'v1tool'; Count = 1; Messages = @('invalid JSON') },
        @{ Name = 'rejects a malformed id and reports the directory mismatch'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.id = 'Bad_ID' }; Count = 2; Messages = @('id must match ^[a-z0-9][a-z0-9-]*$', "directory 'v1tool' does not match id 'Bad_ID'") },
        @{ Name = 'reports every missing required field plus the missing isolation strategy'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) foreach ($p in @('displayName', 'kind', 'binary', 'isolation')) { $a.PSObject.Properties.Remove($p) } }; Count = 5; Messages = @('displayName is required', 'kind is required', 'binary is required', 'isolation is required', "isolation.strategy '' is not supported for schema-v1") },
        @{ Name = 'rejects an unsupported schemaVersion'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a | Add-Member -NotePropertyName schemaVersion -NotePropertyValue 3 }; Count = 1; Messages = @("schemaVersion '3' is not supported") },
        @{ Name = 'rejects the accountOverlay strategy under schema-v1'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.isolation.strategy = 'accountOverlay' }; Count = 1; Messages = @("isolation.strategy 'accountOverlay' is not supported for schema-v1") },
        @{ Name = 'flags an unsafe share.linkable path'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.share.linkable = @('config.toml', '../escape') }; Count = 1; Messages = @("share.linkable path '../escape' must be a safe relative path") },
        @{ Name = 'skips null and empty entries in v1 path lists'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.session.paths = @('', $null, 'sessions'); $a.session.credentials = @('auth.json', $null) }; Count = 0; Messages = @() },
        @{ Name = 'flags a linkable path that overlaps a neverLink path'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.share.linkable = @('auth.json'); $a.share.neverLink = @('auth.json') }; Count = 1; Messages = @("share.linkable path 'auth.json' overlaps share.neverLink path 'auth.json'") },
        @{ Name = 'flags a session path nested inside a credential path'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.session.paths = @('sessions/auth.json'); $a.session.credentials = @('sessions') }; Count = 1; Messages = @("session path 'sessions/auth.json' overlaps credential path 'sessions'") }
    )
}

Describe 'Test-AdapterManifest schema-v2 structure and mechanisms in-process' {
    Add-ManifestCases @(
        @{ Name = 'accepts a complete fileOverlay adapter with all six placeholders'; Base = 'v2'; Id = 'fixture'; Count = 0; Messages = @() },
        @{ Name = 'rejects a non-accountOverlay isolation strategy'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.isolation.strategy = 'env' }; Count = 1; Messages = @("isolation.strategy must be 'accountOverlay' for schema-v2") },
        @{ Name = 'rejects an invalid isolation mode'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.isolation.mode = 'background' }; Count = 1; Messages = @("isolation.mode must be 'foreground' or 'detached'") },
        @{ Name = 'accepts the detached isolation mode'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.isolation.mode = 'detached' }; Count = 0; Messages = @() },
        @{ Name = 'requires credentialFiles for fileOverlay when missing'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.account.PSObject.Properties.Remove('credentialFiles') }; Count = 1; Messages = @('account.credentialFiles must not be empty for fileOverlay') },
        @{ Name = 'requires credentialFiles for fileOverlay when empty'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.account.credentialFiles = @() }; Count = 1; Messages = @('account.credentialFiles must not be empty for fileOverlay') },
        @{ Name = 'accepts processSecret with an environment variable'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) Set-AdapterMechanism -Adapter $a -Mechanism 'processSecret' }; Count = 0; Messages = @() },
        @{ Name = 'rejects processSecret without an environment variable'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.account.mechanism = 'processSecret' }; Count = 1; Messages = @('account.secret.environmentVariable is required for processSecret') },
        @{ Name = 'accepts the osUserCredentialStore mechanism'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) Set-AdapterMechanism -Adapter $a -Mechanism 'osUserCredentialStore' }; Count = 0; Messages = @() },
        @{ Name = 'accepts complete AppX metadata'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) Set-AdapterMechanism -Adapter $a -Mechanism 'osUserCredentialStore'; $a.isolation.mode = 'detached'; $a.binary.windows = @('appx:OpenAI.Codex'); $a | Add-Member -NotePropertyName appx -NotePropertyValue ([pscustomobject]@{ packageName = 'OpenAI.Codex'; applicationId = 'App'; storeProductId = '9PLM9XGG6VKS' }) }; Count = 0; Messages = @() },
        @{ Name = 'requires AppX package and application identifiers'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) Set-AdapterMechanism -Adapter $a -Mechanism 'osUserCredentialStore'; $a.isolation.mode = 'detached'; $a | Add-Member -NotePropertyName appx -NotePropertyValue ([pscustomobject]@{ packageName = ''; applicationId = '' }) }; Count = 2; Messages = @('appx.packageName is required when appx is declared', 'appx.applicationId is required when appx is declared') },
        @{ Name = 'rejects AppX metadata outside the owned-user detached contract'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a | Add-Member -NotePropertyName appx -NotePropertyValue ([pscustomobject]@{ packageName = 'OpenAI.Codex'; applicationId = 'App' }) }; Count = 3; Messages = @('appx requires account.mechanism osUserCredentialStore', 'appx requires isolation.mode detached', "binary.windows must contain 'appx:OpenAI.Codex' when appx is declared") },
        @{ Name = 'rejects an unknown adapter kind'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.kind = 'desktop' }; Count = 1; Messages = @("kind 'desktop' is not one of: cli, ide, gui, hybrid") },
        @{ Name = 'accepts inseparable state with a reason'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) Set-AdapterMechanism -Adapter $a -Mechanism 'inseparable' }; Count = 0; Messages = @() },
        @{ Name = 'rejects inseparable state without a reason'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.account = [pscustomobject]@{ mechanism = 'inseparable' } }; Count = 1; Messages = @('account.reason is required for inseparable state') },
        @{ Name = 'rejects an unknown account mechanism'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) Set-AdapterMechanism -Adapter $a -Mechanism 'magic' }; Count = 1; Messages = @("account.mechanism 'magic' is not supported") },
        @{ Name = 'requires a normalState root for every platform'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.normalState.root.PSObject.Properties.Remove('linux') }; Count = 1; Messages = @('normalState.root.linux is required') },
        @{ Name = 'rejects unknown placeholders'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.isolation.env.FIXTURE_RUNTIME = '{mysteryRoot}' }; Count = 1; Messages = @("unknown placeholder '{mysteryRoot}'") }
    )
}

Describe 'Test-AdapterManifest schema-v2 paths and separation in-process' {
    Add-ManifestCases @(
        @{ Name = 'flags unsafe paths in all five v2 path lists'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.account.credentialFiles = @('C:/abs/cred.json'); $a.normalState.sharedPaths = @('/abs'); $a.normalState.sessionPaths = @('a/../b'); $a.normalState.filePaths = @('..'); $a.normalState.unsafePaths = @('C:/x') }; Count = 5; Messages = @("credential path 'C:/abs/cred.json' must be a safe relative path", "shared path '/abs' must be a safe relative path", "session path 'a/../b' must be a safe relative path", "file path '..' must be a safe relative path", "unsafe path 'C:/x' must be a safe relative path") },
        @{ Name = 'flags credential paths overlapping shared paths'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.account.credentialFiles = @('data/auth.json'); $a.normalState.sharedPaths = @('data') }; Count = 1; Messages = @("credential path 'data/auth.json' overlaps shared path 'data'") },
        @{ Name = 'flags credential paths overlapping session paths'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.account.credentialFiles = @('sessions/auth.json'); $a.normalState.sessionPaths = @('sessions') }; Count = 1; Messages = @("credential path 'sessions/auth.json' overlaps session path 'sessions'") },
        @{ Name = 'flags credential paths overlapping unsafe paths'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.account.credentialFiles = @('cache/c.json'); $a.normalState.unsafePaths = @('cache') }; Count = 1; Messages = @("credential path 'cache/c.json' overlaps unsafe path 'cache'") },
        @{ Name = 'flags shared paths overlapping unsafe paths'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.normalState.sharedPaths = @('cache/x'); $a.normalState.unsafePaths = @('cache') }; Count = 1; Messages = @("shared path 'cache/x' overlaps unsafe path 'cache'") },
        @{ Name = 'flags session paths overlapping unsafe paths'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.normalState.sessionPaths = @('cache/s'); $a.normalState.unsafePaths = @('cache') }; Count = 1; Messages = @("session path 'cache/s' overlaps unsafe path 'cache'") },
        @{ Name = 'accepts a safe normalState.runtimeSubdir'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.normalState | Add-Member -NotePropertyName runtimeSubdir -NotePropertyValue 'state' }; Count = 0; Messages = @() },
        @{ Name = 'flags an unsafe normalState.runtimeSubdir'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.normalState | Add-Member -NotePropertyName runtimeSubdir -NotePropertyValue '../escape' }; Count = 1; Messages = @("normalState.runtimeSubdir '../escape' must be a safe relative path") }
    )
}

Describe 'Test-AdapterManifest schema-v2 support, concurrency and binary in-process' {
    Add-ManifestCases @(
        @{ Name = 'accepts experimental support with a reason'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.support.windows = [pscustomobject]@{ level = 'experimental'; reason = 'Requires real Windows verification.' } }; Count = 0; Messages = @() },
        @{ Name = 'requires a reason for experimental support'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.support.windows = [pscustomobject]@{ level = 'experimental' } }; Count = 1; Messages = @("support.windows.reason is required for level 'experimental'") },
        @{ Name = 'rejects the retired verified level with a clear message'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.support.macos = [pscustomobject]@{ level = 'verified' } }; Count = 1; Messages = @("support.macos.level 'verified' was retired; use 'supported', 'experimental', or 'unsupported'") },
        @{ Name = 'accepts supported support without a reason'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.support.windows = [pscustomobject]@{ level = 'supported' } }; Count = 0; Messages = @() },
        @{ Name = 'requires a reason for unsupported platforms'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.support.linux = [pscustomobject]@{ level = 'unsupported' } }; Count = 1; Messages = @("support.linux.reason is required for level 'unsupported'") },
        @{ Name = 'accepts unsupported platforms with a reason'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.support.linux = [pscustomobject]@{ level = 'unsupported'; reason = 'No builds.' } }; Count = 0; Messages = @() },
        @{ Name = 'rejects an unknown support level'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.support.windows = [pscustomobject]@{ level = 'platinum' } }; Count = 1; Messages = @('support.windows.level must be supported, experimental, or unsupported') },
        @{ Name = 'rejects a missing support entry'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.support.PSObject.Properties.Remove('linux') }; Count = 1; Messages = @('support.linux.level must be supported, experimental, or unsupported') },
        @{ Name = 'rejects an invalid concurrency level'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.concurrency.level = 'chaos' }; Count = 1; Messages = @('concurrency.level is invalid') },
        @{ Name = 'requires concurrency.singletonScope'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.concurrency.PSObject.Properties.Remove('singletonScope') }; Count = 1; Messages = @('concurrency.singletonScope is required') },
        @{ Name = "rejects the legacy 'darwin' binary key"; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.binary | Add-Member -NotePropertyName darwin -NotePropertyValue @('fixture') }; Count = 1; Messages = @("binary uses unsupported platform key 'darwin'; use 'macos'") },
        @{ Name = 'rejects unknown binary platform keys'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.binary | Add-Member -NotePropertyName plan9 -NotePropertyValue @('fixture') }; Count = 1; Messages = @("binary uses unsupported platform key 'plan9'") },
        @{ Name = 'requires v2 binary candidates for a missing platform'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.binary.PSObject.Properties.Remove('windows') }; Count = 1; Messages = @('binary.windows must contain at least one candidate') },
        @{ Name = 'requires v2 binary candidates for an empty platform'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.binary.linux = @() }; Count = 1; Messages = @('binary.linux must contain at least one candidate') },
        @{ Name = 'rejects a non-array binary platform'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.binary.windows = 'fixture.exe' }; Count = 1; Messages = @('binary.windows must be an array of candidates') },
        @{ Name = 'rejects empty binary candidates'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.binary.windows = @('fixture.exe', '  ') }; Count = 1; Messages = @('binary.windows candidates must be non-empty strings') },
        @{ Name = 'rejects a non-integer schemaVersion without further validation'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a.schemaVersion = 'two' }; Count = 1; Messages = @("schemaVersion 'two' is not an integer") },
        @{ Name = 'accepts a v1 adapter with a windows-only binary'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.binary = [pscustomobject]@{ windows = @('v1tool.exe') } }; Count = 0; Messages = @() },
        @{ Name = 'rejects legacy fields in schema-v2'; Base = 'v2'; Id = 'fixture'; Mutate = { param($a) $a | Add-Member -NotePropertyName status -NotePropertyValue 'stable' }; Count = 1; Messages = @("unsupported top-level field 'status'") },
        @{ Name = 'rejects schema-v2 fields in schema-v1'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a | Add-Member -NotePropertyName support -NotePropertyValue ([pscustomobject]@{}) }; Count = 1; Messages = @("unsupported top-level field 'support'") },
        @{ Name = 'rejects unknown schema-v1 nested fields'; Base = 'v1'; Id = 'v1tool'; Mutate = { param($a) $a.share | Add-Member -NotePropertyName note -NotePropertyValue 'extra' }; Count = 1; Messages = @("unsupported field 'share.note'") }
    )
}

Describe 'adapter path-safety helpers in-process' {
    It 'Test-SafeAdapterPath accepts relative paths and rejects absolute, drive, dot and parent paths' {
        $cases = @(
            @{ Path = 'ok/path.txt'; Expected = $true }, @{ Path = 'sub\win\style.json'; Expected = $true },
            @{ Path = 'a/b/..x'; Expected = $true }, @{ Path = 'x/..y/z'; Expected = $true },
            @{ Path = $null; Expected = $false }, @{ Path = '   '; Expected = $false },
            @{ Path = '/abs/path'; Expected = $false }, @{ Path = 'C:\abs'; Expected = $false },
            @{ Path = 'c:/abs'; Expected = $false }, @{ Path = 'a:b'; Expected = $false },
            @{ Path = '.'; Expected = $false }, @{ Path = '..'; Expected = $false },
            @{ Path = 'x/../y'; Expected = $false }, @{ Path = '../escape'; Expected = $false }
        )
        foreach ($case in $cases) {
            (Invoke-ModuleInternal 'MultiCli.AdapterValidation' { param($p) Test-SafeAdapterPath -Path $p } @($case.Path)) | Should Be $case.Expected
        }
    }

    It 'Test-AdapterPathsOverlap detects equal, nested and separator-safe paths' {
        $cases = @(
            @{ Left = 'a'; Right = 'a'; Expected = $true }, @{ Left = 'a/'; Right = 'a'; Expected = $true },
            @{ Left = 'a\b'; Right = 'a/b'; Expected = $true }, @{ Left = 'a/b'; Right = 'a'; Expected = $true },
            @{ Left = 'a'; Right = 'a/b'; Expected = $true }, @{ Left = 'a/b'; Right = 'a/c'; Expected = $false },
            @{ Left = 'ab'; Right = 'a'; Expected = $false }, @{ Left = 'a'; Right = 'ab'; Expected = $false },
            @{ Left = 'AUTH.json'; Right = 'auth.json'; Expected = $true }, @{ Left = 'Agents'; Right = 'agents/x'; Expected = $true }
        )
        foreach ($case in $cases) {
            (Invoke-ModuleInternal 'MultiCli.AdapterValidation' { param($l, $r) Test-AdapterPathsOverlap -Left $l -Right $r } @($case.Left, $case.Right)) | Should Be $case.Expected
        }
    }
}

Describe 'runtime helper functions in-process' {
    It 'Get-RuntimeProperty returns values, and null for missing properties or a null object' {
        $object = '{"keep":"value"}' | ConvertFrom-Json
        (Invoke-ModuleInternal 'MultiCli.Runtime' { param($o) Get-RuntimeProperty -Object $o -Name 'keep' } @($object)) | Should Be 'value'
        (Invoke-ModuleInternal 'MultiCli.Runtime' { param($o) Get-RuntimeProperty -Object $o -Name 'missing' } @($object)) | Should Be $null
        (Invoke-ModuleInternal 'MultiCli.Runtime' { Get-RuntimeProperty -Object $null -Name 'keep' }) | Should Be $null
    }

    It 'Get-RuntimePlatformRoot resolves the windows root against USERPROFILE' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = '{"normalState":{"root":{"windows":"%USERPROFILE%\\.fixture"}}}' | ConvertFrom-Json
            $resolved = Invoke-ModuleInternal 'MultiCli.Runtime' { param($a) Get-RuntimePlatformRoot -Adapter $a } @($adapter)
            $resolved | Should Be ([System.IO.Path]::GetFullPath((Join-Path $scratch.Home '.fixture')))
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Expand-RuntimeValue replaces all six placeholders' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $expanded = Invoke-ModuleInternal 'MultiCli.Runtime' {
                Expand-RuntimeValue -Value '{profileDir}|{profileId}|{authDir}|{runtimeRoot}|{sharedStateRoot}|{realHome}' `
                    -ProfileDir 'PD' -ProfileId 'PID' -AuthDir 'AD' -RuntimeRoot 'RR' -SharedRoot 'SR'
            }
            $expanded | Should Be "PD|PID|AD|RR|SR|$($scratch.Home)"
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Test-RuntimeFilePath matches declared file paths only' {
        $adapter = '{"normalState":{"filePaths":["config.toml","history.jsonl"]}}' | ConvertFrom-Json
        (Invoke-ModuleInternal 'MultiCli.Runtime' { param($a) Test-RuntimeFilePath -Adapter $a -RelativePath 'config.toml' } @($adapter)) | Should Be $true
        (Invoke-ModuleInternal 'MultiCli.Runtime' { param($a) Test-RuntimeFilePath -Adapter $a -RelativePath 'agents' } @($adapter)) | Should Be $false
    }

    It 'New-RuntimeStateSource creates files, directories, parents, and keeps existing sources' {
        $scratch = New-RuntimeScratch
        try {
            $sharedRoot = Join-Path $scratch.Root 'shared'
            $adapter = '{"normalState":{"filePaths":["config.toml","deep/nested/history.jsonl"]}}' | ConvertFrom-Json

            $file = Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $s) New-RuntimeStateSource -Adapter $a -SharedRoot $s -RelativePath 'config.toml' } @($adapter, $sharedRoot)
            $file | Should Be (Join-Path $sharedRoot 'config.toml')
            (Test-Path -LiteralPath $file -PathType Leaf) | Should Be $true

            $directory = Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $s) New-RuntimeStateSource -Adapter $a -SharedRoot $s -RelativePath 'agents' } @($adapter, $sharedRoot)
            (Test-Path -LiteralPath $directory -PathType Container) | Should Be $true

            $nested = Join-Path $sharedRoot 'deep\nested\history.jsonl'
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $nested) | Out-Null
            Set-Content -LiteralPath $nested -Value 'keep-me' -Encoding ASCII
            $returned = Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $s) New-RuntimeStateSource -Adapter $a -SharedRoot $s -RelativePath 'deep/nested/history.jsonl' } @($adapter, $sharedRoot)
            $returned | Should Be $nested
            (Get-Content -LiteralPath $nested -Raw).Trim() | Should Be 'keep-me'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Get-ProfileCredentialTarget builds the profile-scoped credential target' {
        $adapter = '{"id":"tool","account":{"secret":{"environmentVariable":"MY_VAR"}}}' | ConvertFrom-Json
        $metadata = '{"profileId":"abc-123"}' | ConvertFrom-Json
        $target = Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $m) Get-ProfileCredentialTarget -Adapter $a -Metadata $m } @($adapter, $metadata)
        $target | Should Be 'multi-cli/tool/abc-123/MY_VAR'
    }
}

Describe 'Initialize-RuntimeProfile in-process' {
    It 'creates the auth tree, nested credential files, and profile metadata' {
        $scratch = New-RuntimeScratch
        try {
            $adapter = Get-ValidV2Adapter
            $adapter.account.credentialFiles = @('auth.json', 'tokens/nested.json', '')
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir

            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir 'auth') -PathType Container) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir 'auth\auth.json') -PathType Leaf) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir 'auth\tokens\nested.json') -PathType Leaf) | Should Be $true

            $metadataPath = Join-Path $scratch.ProfileDir '.profile.json'
            (Test-Path -LiteralPath $metadataPath -PathType Leaf) | Should Be $true
            (Test-Path -LiteralPath "$metadataPath.tmp") | Should Be $false
            $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
            $metadata.schemaVersion | Should Be 2
            $metadata.adapterId | Should Be 'fixture'
            $metadata.mode | Should Be 'accountOverlay'
            ([guid]::Parse($metadata.profileId) -is [guid]) | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'keeps existing credential file content on re-initialization' {
        $scratch = New-RuntimeScratch
        try {
            $adapter = Get-ValidV2Adapter
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir
            $credentialPath = Join-Path $scratch.ProfileDir 'auth\auth.json'
            Set-Content -LiteralPath $credentialPath -Value 'account-a-secret' -Encoding ASCII
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir
            (Get-Content -LiteralPath $credentialPath -Raw).Trim() | Should Be 'account-a-secret'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'runtime overlay links in-process' {
    It 'New-RuntimeLink hard-links files, junctions directories, and creates parents' {
        $scratch = New-RuntimeScratch
        try {
            $sourceFile = Join-Path $scratch.Root 'source.txt'
            Set-Content -LiteralPath $sourceFile -Value 'linked-content' -Encoding ASCII
            $destinationFile = Join-Path $scratch.Root 'links\nested\dest.txt'
            Invoke-ModuleInternal 'MultiCli.Runtime' { param($s, $d) New-RuntimeLink -Source $s -Destination $d -Label 'test file' } @($sourceFile, $destinationFile)
            (Get-Item -LiteralPath $destinationFile).LinkType | Should Be 'HardLink'
            (Get-Content -LiteralPath $destinationFile -Raw).Trim() | Should Be 'linked-content'

            $sourceDir = Join-Path $scratch.Root 'source-dir'
            New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
            $destinationDir = Join-Path $scratch.Root 'links\dest-dir'
            Invoke-ModuleInternal 'MultiCli.Runtime' { param($s, $d) New-RuntimeLink -Source $s -Destination $d -Label 'test dir' } @($sourceDir, $destinationDir)
            (Get-Item -LiteralPath $destinationDir).LinkType | Should Be 'Junction'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'New-RuntimeLink wraps link failures with source and destination context' {
        $scratch = New-RuntimeScratch
        try {
            $sourceFile = Join-Path $scratch.Root 'source.txt'
            $destinationFile = Join-Path $scratch.Root 'dest.txt'
            Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding ASCII
            Set-Content -LiteralPath $destinationFile -Value 'dest' -Encoding ASCII
            $caught = $null
            try {
                Invoke-ModuleInternal 'MultiCli.Runtime' { param($s, $d) New-RuntimeLink -Source $s -Destination $d -Label 'profile credential' } @($sourceFile, $destinationFile)
            } catch { $caught = $_.Exception.Message }
            ($caught -like "Cannot link profile credential '$destinationFile' to '$sourceFile'*") | Should Be $true
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Remove-RuntimeOverlay removes declared targets and the root, and ignores a missing root' {
        $scratch = New-RuntimeScratch
        try {
            $adapter = '{"normalState":{"sharedPaths":["a.txt",""],"sessionPaths":["b"]},"account":{"credentialFiles":["c.txt","missing.txt"]}}' | ConvertFrom-Json
            $runtimeRoot = Join-Path $scratch.Root 'runtime'
            New-Item -ItemType Directory -Force -Path (Join-Path $runtimeRoot 'b') | Out-Null
            Set-Content -LiteralPath (Join-Path $runtimeRoot 'a.txt') -Value 'a' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $runtimeRoot 'c.txt') -Value 'c' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $runtimeRoot 'extra.txt') -Value 'extra' -Encoding ASCII

            Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $r) Remove-RuntimeOverlay -Adapter $a -RuntimeRoot $r } @($adapter, $runtimeRoot)
            (Test-Path -LiteralPath $runtimeRoot) | Should Be $false

            $threw = $false
            try {
                Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $r) Remove-RuntimeOverlay -Adapter $a -RuntimeRoot $r } @($adapter, $runtimeRoot)
            } catch { $threw = $true }
            $threw | Should Be $false
            (Test-Path -LiteralPath $runtimeRoot) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'serializes concurrent overlay builds and leaves a complete runtime' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir
            $adapterPath = Join-Path $scratch.Root 'adapter.json'
            $adapter | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $adapterPath -Encoding UTF8
            $modulePath = Join-Path $script:LibDir 'MultiCli.Runtime.psm1'
            $launcherFunctions = @'
function Resolve-PathToken { param([string]$Path) $Path -replace '%USERPROFILE%', $env:USERPROFILE }
'@
            $scriptText = @"
$launcherFunctions
`$ErrorActionPreference = 'Stop'
Import-Module '$modulePath' -Force
`$adapter = Get-Content -LiteralPath '$adapterPath' -Raw | ConvertFrom-Json
`$executionContext.SessionState.InvokeCommand.GetCommand('New-RuntimeOverlay', 'Function') | Out-Null
& (Get-Module MultiCli.Runtime) { param(`$a, `$p) New-RuntimeOverlay -Adapter `$a -ProfileDir `$p } `$adapter '$($scratch.ProfileDir)'
"@
            $scriptPath = Join-Path $scratch.Root 'build-overlay.ps1'
            $firstError = Join-Path $scratch.Root 'first.stderr'
            $secondError = Join-Path $scratch.Root 'second.stderr'
            Set-Content -LiteralPath $scriptPath -Value $scriptText -Encoding UTF8
            $first = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) -PassThru -WindowStyle Hidden -RedirectStandardError $firstError -RedirectStandardOutput (Join-Path $scratch.Root 'first.stdout')
            $second = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) -PassThru -WindowStyle Hidden -RedirectStandardError $secondError -RedirectStandardOutput (Join-Path $scratch.Root 'second.stdout')
            $null = $first.Handle; $null = $second.Handle
            $first.WaitForExit(); $second.WaitForExit()

            if ($first.ExitCode -ne 0) { throw "First overlay builder failed: $([IO.File]::ReadAllText($firstError))" }
            if ($second.ExitCode -ne 0) { throw "Second overlay builder failed: $([IO.File]::ReadAllText($secondError))" }
            $runtime = Join-Path $scratch.ProfileDir '.runtime'
            (Test-Path -LiteralPath (Join-Path $runtime '.runtime-manifest')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $runtime 'config.toml')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $runtime 'auth.json')) | Should Be $true
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Test-RuntimeOverlayCurrent rejects stale manifests and missing declared paths' {
        $scratch = New-RuntimeScratch
        try {
            $adapter = Get-ValidV2Adapter
            $runtimeRoot = Join-Path $scratch.ProfileDir '.runtime'
            New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
            Set-Content -LiteralPath (Join-Path $runtimeRoot '.runtime-manifest') -Value 'wrong.txt' -Encoding ASCII

            (Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $r) Test-RuntimeOverlayCurrent -Adapter $a -RuntimeRoot $r } @($adapter, $runtimeRoot)) | Should Be $false

            Set-Content -LiteralPath (Join-Path $runtimeRoot '.runtime-manifest') -Value @('config.toml', 'agents', 'sessions', 'history.jsonl', 'auth.json') -Encoding ASCII
            (Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $r) Test-RuntimeOverlayCurrent -Adapter $a -RuntimeRoot $r } @($adapter, $runtimeRoot)) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'New-RuntimeOverlay survives a real abandoned mutex' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir
            $modulePath = Join-Path $script:LibDir 'MultiCli.Runtime.psm1'
            $profileDir = $scratch.ProfileDir
            $holderPath = Join-Path $scratch.Root 'abandon-mutex.ps1'
            @"
Import-Module '$modulePath' -Force
& (Get-Module MultiCli.Runtime) {
    `$mutex = New-Object Threading.Mutex(`$false, (Get-RuntimeMutexName -ProfileDir '$profileDir'))
    `$null = `$mutex.WaitOne()
}
"@ | Set-Content -LiteralPath $holderPath -Encoding UTF8
            $holder = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $holderPath) -PassThru -WindowStyle Hidden
            $holder.WaitForExit()
            $holder.ExitCode | Should Be 0

            $runtimeRoot = Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $p) New-RuntimeOverlay -Adapter $a -ProfileDir $p } @($adapter, $profileDir)
            $runtimeRoot | Should Be (Join-Path $profileDir '.runtime')
            (Test-Path -LiteralPath (Join-Path $runtimeRoot '.runtime-manifest')) | Should Be $true
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'New-RuntimeOverlay reports a mutex timeout and disposes the mutex' {
        $adapter = Get-ValidV2Adapter
        $disposed = [ref]$false
        $fake = [pscustomobject]@{}
        $fake | Add-Member ScriptMethod WaitOne { return $false }
        $fake | Add-Member ScriptMethod ReleaseMutex { throw 'release must not run' }
        $fake | Add-Member ScriptMethod Dispose { $disposed.Value = $true }.GetNewClosure()
        $caught = $null
        try {
            Invoke-ModuleInternal 'MultiCli.Runtime' {
                param($a, $mutex)
                function script:New-Object { return $mutex }
                New-RuntimeOverlay -Adapter $a -ProfileDir 'C:\unused'
            } @($adapter, $fake)
        } catch { $caught = $_.Exception.Message }
        $caught | Should Be 'Timed out waiting for the profile runtime lock. Close a stuck multi-cli launch and retry.'
        $disposed.Value | Should Be $true
    }

    # The timeout test replaces New-Object in module scope; restore the cmdlet
    # before later overlay tests construct lists, stacks, and mutexes.
    Invoke-ModuleInternal 'MultiCli.Runtime' {
        Remove-Item -LiteralPath function:New-Object -Force -ErrorAction SilentlyContinue
    }

    It 'New-RuntimeOverlay links shared and credential state, clears stale staging, and replaces an existing overlay' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir

            $staging = Join-Path $scratch.ProfileDir ".runtime.staging.$PID"
            New-Item -ItemType Directory -Force -Path $staging | Out-Null
            Set-Content -LiteralPath (Join-Path $staging 'stale.txt') -Value 'stale' -Encoding ASCII

            $sharedRoot = Join-Path $scratch.Home '.fixture'
            New-Item -ItemType Directory -Force -Path $sharedRoot | Out-Null
            Set-Content -LiteralPath (Join-Path $sharedRoot 'config.toml') -Value 'shared-config' -Encoding ASCII

            $runtimeRoot = Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $p) New-RuntimeOverlay -Adapter $a -ProfileDir $p } @($adapter, $scratch.ProfileDir)

            $runtimeRoot | Should Be (Join-Path $scratch.ProfileDir '.runtime')
            (Test-Path -LiteralPath $staging) | Should Be $false
            (Get-Content -LiteralPath (Join-Path $runtimeRoot 'config.toml') -Raw).Trim() | Should Be 'shared-config'
            (Get-Item -LiteralPath (Join-Path $runtimeRoot 'config.toml')).LinkType | Should Be 'HardLink'
            (Get-Item -LiteralPath (Join-Path $runtimeRoot 'agents')).LinkType | Should Be 'Junction'
            (Test-Path -LiteralPath (Join-Path $runtimeRoot 'sessions') -PathType Container) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $runtimeRoot 'history.jsonl') -PathType Leaf) | Should Be $true
            (Get-Item -LiteralPath (Join-Path $runtimeRoot 'auth.json')).LinkType | Should Be 'HardLink'
            ((Get-Content -LiteralPath (Join-Path $runtimeRoot '.runtime-manifest')) -join "`n") | Should Be (@('config.toml', 'agents', 'sessions', 'history.jsonl', 'auth.json') -join "`n")

            $rebuilt = Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $p) New-RuntimeOverlay -Adapter $a -ProfileDir $p } @($adapter, $scratch.ProfileDir)
            $rebuilt | Should Be $runtimeRoot
            (Get-Content -LiteralPath (Join-Path $rebuilt 'config.toml') -Raw).Trim() | Should Be 'shared-config'
            (Test-Path -LiteralPath (Join-Path $sharedRoot 'config.toml') -PathType Leaf) | Should Be $true
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'New-RuntimeOverlay honors runtimeSubdir, recreates missing credential sources, and writes a prefixed manifest' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            $adapter.normalState | Add-Member -NotePropertyName runtimeSubdir -NotePropertyValue 'state'
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir

            $sharedRoot = Join-Path $scratch.Home '.fixture'
            New-Item -ItemType Directory -Force -Path $sharedRoot | Out-Null
            Set-Content -LiteralPath (Join-Path $sharedRoot 'config.toml') -Value 'shared-config' -Encoding ASCII

            # The overlay must recreate a credential source the profile lacks.
            Remove-Item -LiteralPath (Join-Path $scratch.ProfileDir 'auth\auth.json') -Force

            $runtimeRoot = Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $p) New-RuntimeOverlay -Adapter $a -ProfileDir $p } @($adapter, $scratch.ProfileDir)

            (Get-Content -LiteralPath (Join-Path $runtimeRoot 'state\config.toml') -Raw).Trim() | Should Be 'shared-config'
            (Get-Item -LiteralPath (Join-Path $runtimeRoot 'state\agents')).LinkType | Should Be 'Junction'
            $recreated = Join-Path $runtimeRoot 'state\auth.json'
            (Get-Item -LiteralPath $recreated).LinkType | Should Be 'HardLink'
            ([string]::IsNullOrEmpty((Get-Content -LiteralPath $recreated -Raw))) | Should Be $true

            ((Get-Content -LiteralPath (Join-Path $runtimeRoot '.runtime-manifest')) -join "`n") |
                Should Be (@('state/config.toml', 'state/agents', 'state/sessions', 'state/history.jsonl', 'state/auth.json') -join "`n")
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'New-RuntimeOverlay refuses to build when its own staging path is a reparse point' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        $staging = $null
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir
            $decoy = Join-Path $scratch.Root 'decoy-target'
            New-Item -ItemType Directory -Force -Path $decoy | Out-Null
            Set-Content -LiteralPath (Join-Path $decoy 'keep.txt') -Value 'keep' -Encoding ASCII
            $staging = Join-Path $scratch.ProfileDir ".runtime.staging.$PID"
            New-Item -ItemType Junction -Path $staging -Target $decoy | Out-Null

            $caught = $null
            try {
                Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $p) New-RuntimeOverlay -Adapter $a -ProfileDir $p } @($adapter, $scratch.ProfileDir)
            } catch { $caught = $_.Exception.Message }

            ($caught -like "Refusing to build overlay: '$staging' is a reparse point.*") | Should Be $true
            # The junction and its target survive the refusal untouched.
            (Get-Item -LiteralPath $staging -Force).LinkType | Should Be 'Junction'
            (Get-Content -LiteralPath (Join-Path $decoy 'keep.txt') -Raw).Trim() | Should Be 'keep'
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.runtime')) | Should Be $false
        } finally {
            $env:USERPROFILE = $previousHome
            if ($staging -and (Test-Path -LiteralPath $staging)) { [System.IO.Directory]::Delete($staging) }
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'New-RuntimeOverlay sweeps stale staging dirs from other processes, including junctions' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir

            $stalePlain = Join-Path $scratch.ProfileDir '.runtime.staging.1'
            New-Item -ItemType Directory -Force -Path $stalePlain | Out-Null
            Set-Content -LiteralPath (Join-Path $stalePlain 'junk.txt') -Value 'junk' -Encoding ASCII
            $staleTarget = Join-Path $scratch.Root 'stale-target'
            New-Item -ItemType Directory -Force -Path $staleTarget | Out-Null
            Set-Content -LiteralPath (Join-Path $staleTarget 'keep.txt') -Value 'keep' -Encoding ASCII
            $staleJunction = Join-Path $scratch.ProfileDir '.runtime.staging.2'
            New-Item -ItemType Junction -Path $staleJunction -Target $staleTarget | Out-Null

            $runtimeRoot = Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $p) New-RuntimeOverlay -Adapter $a -ProfileDir $p } @($adapter, $scratch.ProfileDir)

            (Test-Path -LiteralPath $stalePlain) | Should Be $false
            (Test-Path -LiteralPath $staleJunction) | Should Be $false
            (Test-Path -LiteralPath $runtimeRoot -PathType Container) | Should Be $true
            # The junction target must survive the sweep untouched.
            (Get-Content -LiteralPath (Join-Path $staleTarget 'keep.txt') -Raw).Trim() | Should Be 'keep'
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Remove-RuntimeOverlay deletes nested directory junctions without following them' {
        $scratch = New-RuntimeScratch
        try {
            $adapter = '{"normalState":{"sharedPaths":[]},"account":{"credentialFiles":[]}}' | ConvertFrom-Json
            $runtimeRoot = Join-Path $scratch.Root 'runtime'
            $linkTarget = Join-Path $scratch.Root 'target'
            New-Item -ItemType Directory -Force -Path $runtimeRoot, $linkTarget | Out-Null
            Set-Content -LiteralPath (Join-Path $linkTarget 'keep.txt') -Value 'target-content' -Encoding ASCII
            New-Item -ItemType Junction -Path (Join-Path $runtimeRoot 'linked') -Target $linkTarget | Out-Null

            Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $r) Remove-RuntimeOverlay -Adapter $a -RuntimeRoot $r } @($adapter, $runtimeRoot)

            (Test-Path -LiteralPath $runtimeRoot) | Should Be $false
            (Get-Content -LiteralPath (Join-Path $linkTarget 'keep.txt') -Raw).Trim() | Should Be 'target-content'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Remove-RuntimeOverlay deletes reparse-point files without following them' {
        $scratch = New-RuntimeScratch
        try {
            $adapter = '{"normalState":{"sharedPaths":["a.txt"]},"account":{"credentialFiles":[]}}' | ConvertFrom-Json
            $runtimeRoot = Join-Path $scratch.Root 'runtime'
            New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
            Set-Content -LiteralPath (Join-Path $runtimeRoot 'a.txt') -Value 'a' -Encoding ASCII
            $linkTarget = Join-Path $scratch.Root 'target.txt'
            Set-Content -LiteralPath $linkTarget -Value 'target-content' -Encoding ASCII
            $link = Join-Path $runtimeRoot 'linked.txt'
            try {
                New-Item -ItemType SymbolicLink -Path $link -Target $linkTarget -ErrorAction Stop | Out-Null
            } catch {
                Write-Host 'Host cannot create file symlinks; the privileged coverage exception remains active.'
                return
            }

            Invoke-ModuleInternal 'MultiCli.Runtime' { param($a, $r) Remove-RuntimeOverlay -Adapter $a -RuntimeRoot $r } @($adapter, $runtimeRoot)

            (Test-Path -LiteralPath $runtimeRoot) | Should Be $false
            (Get-Content -LiteralPath $linkTarget -Raw).Trim() | Should Be 'target-content'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Get-AccountOverlayLaunchPlan in-process' {
    It 'builds a fileOverlay plan with an overlay runtime and fully expanded environment' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir
            $metadata = Get-Content -LiteralPath (Join-Path $scratch.ProfileDir '.profile.json') -Raw | ConvertFrom-Json

            $plan = Get-AccountOverlayLaunchPlan -Adapter $adapter -ProfileDir $scratch.ProfileDir -Binary 'C:\fixtures\fixture.exe' -BinaryArgs @('--verbose', 'two words')

            $plan.Binary | Should Be 'C:\fixtures\fixture.exe'
            ($plan.Arguments -join '|') | Should Be '--verbose|two words'
            $plan.Mode | Should Be 'foreground'
            ($plan.ClearEnvironment -join '|') | Should Be 'GLOBAL_FIXTURE_TOKEN'

            $runtimeRoot = Join-Path $scratch.ProfileDir '.runtime'
            $plan.Environment['FIXTURE_RUNTIME'] | Should Be $runtimeRoot
            (Test-Path -LiteralPath $runtimeRoot -PathType Container) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $runtimeRoot 'config.toml') -PathType Leaf) | Should Be $true
            $plan.Environment['FIXTURE_PROFILE'] | Should Be $scratch.ProfileDir
            $plan.Environment['FIXTURE_AUTH'] | Should Be (Join-Path $scratch.ProfileDir 'auth')
            $plan.Environment['FIXTURE_SHARED'] | Should Be ([System.IO.Path]::GetFullPath((Join-Path $scratch.Home '.fixture')))
            $plan.Environment['FIXTURE_PID'] | Should Be $metadata.profileId
            $plan.Environment['FIXTURE_REALHOME'] | Should Be $scratch.Home
            $plan.Environment['MULTICLI_PROFILE_ID'] | Should Be $metadata.profileId
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'builds a processSecret plan with the stored credential and no file overlay' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        $target = $null
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            Set-AdapterMechanism -Adapter $adapter -Mechanism 'processSecret'
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir
            $metadata = Get-Content -LiteralPath (Join-Path $scratch.ProfileDir '.profile.json') -Raw | ConvertFrom-Json
            $target = "multi-cli/fixture/$($metadata.profileId)/FIXTURE_API_TOKEN"
            $secret = 'mcli-test-secret-' + [guid]::NewGuid().ToString('N')
            Set-MultiCliCredential -Target $target -Secret $secret

            $plan = Get-AccountOverlayLaunchPlan -Adapter $adapter -ProfileDir $scratch.ProfileDir -Binary 'C:\fixtures\fixture.exe' -BinaryArgs @()

            $plan.Environment['FIXTURE_API_TOKEN'] | Should Be $secret
            $plan.Environment['MULTICLI_PROFILE_ID'] | Should Be $metadata.profileId
            $sharedRoot = [System.IO.Path]::GetFullPath((Join-Path $scratch.Home '.fixture'))
            $plan.Environment['FIXTURE_RUNTIME'] | Should Be $sharedRoot
            $plan.Environment['FIXTURE_SHARED'] | Should Be $sharedRoot
            (Test-Path -LiteralPath (Join-Path $scratch.ProfileDir '.runtime')) | Should Be $false
        } finally {
            Import-CredentialStoreModule
            if ($target) { Remove-MultiCliCredential -Target $target | Out-Null }
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a processSecret launch when no credential is stored and names the auth command' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        $target = $null
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            Set-AdapterMechanism -Adapter $adapter -Mechanism 'processSecret'
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir
            $metadata = Get-Content -LiteralPath (Join-Path $scratch.ProfileDir '.profile.json') -Raw | ConvertFrom-Json
            $target = "multi-cli/fixture/$($metadata.profileId)/FIXTURE_API_TOKEN"
            Remove-MultiCliCredential -Target $target | Out-Null

            $caught = $null
            try {
                Get-AccountOverlayLaunchPlan -Adapter $adapter -ProfileDir $scratch.ProfileDir -Binary 'C:\fixtures\fixture.exe' -BinaryArgs @()
            } catch { $caught = $_.Exception.Message }
            ($caught.Contains("Profile 'fixture/account-a' has no stored credential.")) | Should Be $true
            ($caught.Contains('Run: multi-cli auth set fixture/account-a')) | Should Be $true
        } finally {
            Import-CredentialStoreModule
            if ($target) { Remove-MultiCliCredential -Target $target | Out-Null }
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'routes osUserCredentialStore profiles to the dedicated OS-user launcher' {
        $adapter = Get-ValidV2Adapter
        Set-AdapterMechanism -Adapter $adapter -Mechanism 'osUserCredentialStore'
        $profileDir = Join-Path ([System.IO.Path]::GetTempPath()) 'fixture\account-a'
        $caught = $null
        try {
            Get-AccountOverlayLaunchPlan -Adapter $adapter -ProfileDir $profileDir -Binary 'C:\fixtures\fixture.exe' -BinaryArgs @()
        } catch { $caught = $_.Exception.Message }
        ($caught.Contains("Profile 'fixture/account-a' uses the OS-user runtime")) | Should Be $true
        ($caught.Contains('must launch through Invoke-OsUserLaunch')) | Should Be $true
    }

    It 'rejects inseparable profiles with the adapter reason and --isolated guidance' {
        $adapter = Get-ValidV2Adapter
        Set-AdapterMechanism -Adapter $adapter -Mechanism 'inseparable'
        $profileDir = Join-Path ([System.IO.Path]::GetTempPath()) 'fixture\account-a'
        $caught = $null
        try {
            Get-AccountOverlayLaunchPlan -Adapter $adapter -ProfileDir $profileDir -Binary 'C:\fixtures\fixture.exe' -BinaryArgs @()
        } catch { $caught = $_.Exception.Message }
        ($caught.Contains('Vendor binds auth to the OS account.')) | Should Be $true
        ($caught.Contains('Create this profile with --isolated to use a separate whole-root profile.')) | Should Be $true
    }

    It 'rejects unknown account mechanisms' {
        $adapter = Get-ValidV2Adapter
        Set-AdapterMechanism -Adapter $adapter -Mechanism 'magic'
        $profileDir = Join-Path ([System.IO.Path]::GetTempPath()) 'fixture\account-a'
        { Get-AccountOverlayLaunchPlan -Adapter $adapter -ProfileDir $profileDir -Binary 'C:\fixtures\fixture.exe' -BinaryArgs @() } |
            Should Throw "Unsupported schema-v2 account mechanism 'magic'."
    }
}

Describe 'credential store in-process' {
    It 'rejects an empty target, an empty secret, and an oversized secret' {
        { Set-MultiCliCredential -Target '' -Secret 'x' } | Should Throw 'Credential target is required.'
        { Set-MultiCliCredential -Target 'multi-cli/tests/unused' -Secret '' } | Should Throw 'Credential secret must not be empty.'
        $oversized = 'x' * 2561
        { Set-MultiCliCredential -Target 'multi-cli/tests/unused' -Secret $oversized } | Should Throw 'Credential secret exceeds the Windows Credential Manager limit.'
    }

    It 'round-trips a secret through the real Credential Manager and reports absence' {
        $target = 'multi-cli/tests/' + [guid]::NewGuid().ToString('N')
        $secret = 'mcli-test-secret-' + [guid]::NewGuid().ToString('N')
        try {
            (Get-MultiCliCredential -Target $target) | Should Be $null
            (Remove-MultiCliCredential -Target $target) | Should Be $false
            (Test-MultiCliCredential -Target $target) | Should Be $false

            Set-MultiCliCredential -Target $target -Secret $secret
            (Test-MultiCliCredential -Target $target) | Should Be $true
            (Get-MultiCliCredential -Target $target) | Should Be $secret

            (Remove-MultiCliCredential -Target $target) | Should Be $true
            (Test-MultiCliCredential -Target $target) | Should Be $false
            (Get-MultiCliCredential -Target $target) | Should Be $null
        } finally {
            Remove-MultiCliCredential -Target $target | Out-Null
        }
    }

    It 'round-trips non-ASCII secrets byte-exactly' {
        $target = 'multi-cli/tests/' + [guid]::NewGuid().ToString('N')
        $secret = 'mcli-test-secret-' + [guid]::NewGuid().ToString('N') + '-äöü'
        try {
            Set-MultiCliCredential -Target $target -Secret $secret
            (Get-MultiCliCredential -Target $target) | Should Be $secret
        } finally {
            Remove-MultiCliCredential -Target $target | Out-Null
        }
    }

    It 'returns an empty string for a zero-length credential blob' {
        $target = 'multi-cli/tests/' + [guid]::NewGuid().ToString('N')
        $credential = New-Object MultiCli.NativeCredential
        $credential.Type = [MultiCli.NativeCredentialStore]::Generic
        $credential.TargetName = $target
        $credential.CredentialBlobSize = 0
        $credential.CredentialBlob = [IntPtr]::Zero
        $credential.Persist = [MultiCli.NativeCredentialStore]::LocalMachine
        $credential.UserName = 'multi-cli'
        try {
            ([MultiCli.NativeCredentialStore]::Write([ref]$credential, 0)) | Should Be $true
            (Get-MultiCliCredential -Target $target) | Should Be ''
            (Test-MultiCliCredential -Target $target) | Should Be $true
        } finally {
            Remove-MultiCliCredential -Target $target | Out-Null
        }
    }

    It 'surfaces a real Credential Manager write failure with the Win32 error' {
        # A lone NUL passes target validation (non-empty, length 1) but
        # marshals to an empty TargetName; CredWrite rejects it with
        # ERROR_INVALID_PARAMETER (87 on a bare runspace, probed). The
        # instrumented Pester runspace can clear the Win32 error before the
        # message reads it, so only the stable prefix is asserted.
        { Set-MultiCliCredential -Target "`0" -Secret 'x' } | Should Throw 'Credential Manager write failed with Win32 error'
        (Get-MultiCliCredential -Target "`0") | Should Be $null
    }

    It 'rejects over-long Credential Manager targets before P/Invoke' {
        $longTarget = 'multi-cli/tests/' + ('x' * 40000)
        { Set-MultiCliCredential -Target $longTarget -Secret 'x' } | Should Throw 'Credential target exceeds the Windows Credential Manager name limit.'
        { Get-MultiCliCredential -Target $longTarget } | Should Throw 'Credential target exceeds the Windows Credential Manager name limit.'
        { Remove-MultiCliCredential -Target $longTarget } | Should Throw 'Credential target exceeds the Windows Credential Manager name limit.'
    }
}

function Assert-ThrownContains {
    <# Asserts the block throws and its message contains every fragment. #>
    param([scriptblock]$Block, [string[]]$Fragments)
    $caught = $null
    try { & $Block | Out-Null } catch { $caught = $_.Exception.Message }
    foreach ($fragment in $Fragments) {
        ($null -ne $caught -and $caught.Contains($fragment)) | Should Be $true
    }
}

function New-TransferSharedFixture {
    <# Populates the fake home's shared root with ordinary declared state. #>
    param($Scratch)
    $shared = Join-Path $Scratch.Home '.fixture'
    New-Item -ItemType Directory -Force -Path (Join-Path $shared 'agents') | Out-Null
    Set-Content -LiteralPath (Join-Path $shared 'config.toml') -Value 'shared-config' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $shared 'agents\agent.md') -Value 'agent' -Encoding ASCII
    return $shared
}

function New-TestZip {
    <# Builds a real zip; entries named with a trailing slash become
       directory entries. #>
    param([string]$Path, [hashtable[]]$Entries)
    $stream = [System.IO.File]::Open($Path, 'Create')
    $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($spec in $Entries) {
            $entry = $archive.CreateEntry($spec.Name)
            if ($spec.Name.EndsWith('/')) { continue }
            $writer = New-Object System.IO.StreamWriter($entry.Open())
            try { $writer.Write($spec.Content) } finally { $writer.Dispose() }
        }
    } finally {
        $archive.Dispose()
        $stream.Dispose()
    }
}

function Get-TestZipEntryNames {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read)
    try {
        return @($archive.Entries | ForEach-Object { $_.FullName -replace '\\', '/' } | Sort-Object)
    } finally {
        $archive.Dispose()
        $stream.Dispose()
    }
}

function Get-ExportManifestJson {
    param([string]$AdapterId)
    return (@{ schemaVersion = 2; adapterId = $AdapterId; name = 'staged'; kind = 'export'; createdUtc = '2026-07-17T00:00:00Z' } | ConvertTo-Json -Compress)
}

Describe 'migration helper functions in-process' {
    It 'Get-MigrationProperty returns values, and null for missing properties or a null object' {
        $object = '{"keep":"value"}' | ConvertFrom-Json
        (Invoke-ModuleInternal 'MultiCli.Migration' { param($o) Get-MigrationProperty -Object $o -Name 'keep' } @($object)) | Should Be 'value'
        (Invoke-ModuleInternal 'MultiCli.Migration' { param($o) Get-MigrationProperty -Object $o -Name 'missing' } @($object)) | Should Be $null
        (Invoke-ModuleInternal 'MultiCli.Migration' { Get-MigrationProperty -Object $null -Name 'keep' }) | Should Be $null
    }

    It 'Resolve-MigrationPathToken returns falsy paths untouched and expands home tokens' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            (Invoke-ModuleInternal 'MultiCli.Migration' { Resolve-MigrationPathToken -Path '' }) | Should Be ''
            $resolved = Invoke-ModuleInternal 'MultiCli.Migration' { Resolve-MigrationPathToken -Path '%USERPROFILE%\.fixture' }
            $resolved | Should Be ([System.IO.Path]::GetFullPath((Join-Path $scratch.Home '.fixture')))
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Get-MigrationSharedRoot throws when the adapter has no windows root' {
        $adapter = '{"id":"fixture","normalState":{"root":{"macos":"$HOME/.fixture"}}}' | ConvertFrom-Json
        Assert-ThrownContains { Invoke-ModuleInternal 'MultiCli.Migration' { param($a) Get-MigrationSharedRoot -Adapter $a } @($adapter) } @("Adapter 'fixture' has no normal-state root for windows.")
    }

    It 'Test-MigrationReparsePoint detects junctions and tolerates missing paths' {
        $scratch = New-RuntimeScratch
        try {
            $plain = Join-Path $scratch.Root 'plain'
            New-Item -ItemType Directory -Force -Path $plain | Out-Null
            $junction = Join-Path $scratch.Root 'junction'
            New-Item -ItemType Junction -Path $junction -Target $plain | Out-Null
            (Invoke-ModuleInternal 'MultiCli.Migration' { param($p) Test-MigrationReparsePoint -Path $p } @($plain)) | Should Be $false
            (Invoke-ModuleInternal 'MultiCli.Migration' { param($p) Test-MigrationReparsePoint -Path $p } @($junction)) | Should Be $true
            (Invoke-ModuleInternal 'MultiCli.Migration' { param($p) Test-MigrationReparsePoint -Path $p } @(Join-Path $scratch.Root 'missing')) | Should Be $false
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Get-MigrationLinkTarget reads junction targets and reports unreadable ones' {
        $scratch = New-RuntimeScratch
        try {
            $plain = Join-Path $scratch.Root 'plain'
            New-Item -ItemType Directory -Force -Path $plain | Out-Null
            $junction = Join-Path $scratch.Root 'junction'
            New-Item -ItemType Junction -Path $junction -Target $plain | Out-Null
            (Invoke-ModuleInternal 'MultiCli.Migration' { param($p) Get-MigrationLinkTarget -Path $p } @($junction)) | Should Be $plain
            (Invoke-ModuleInternal 'MultiCli.Migration' { param($p) Get-MigrationLinkTarget -Path $p } @(Join-Path $scratch.Root 'missing')) | Should Be '?'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Get-MigrationOpLine formats known operations and falls back for unknown ones' {
        $move = [pscustomobject]@{ Op = 'move-credential'; Rel = 'auth.json'; From = 'f'; To = 't'; Note = '' }
        (Invoke-ModuleInternal 'MultiCli.Migration' { param($o) Get-MigrationOpLine -Op $o } @($move)) | Should Be '  move credential auth.json -> auth/auth.json'
        $bogus = [pscustomobject]@{ Op = 'bogus-op'; Rel = 'x.txt'; From = ''; To = ''; Note = '' }
        (Invoke-ModuleInternal 'MultiCli.Migration' { param($o) Get-MigrationOpLine -Op $o } @($bogus)) | Should Be '  bogus-op x.txt'
    }
}

Describe 'Invoke-MultiCliMigration guard rails in-process' {
    It 'throws for a missing profile directory' {
        $adapter = Get-ValidV2Adapter
        Assert-ThrownContains {
            Invoke-MultiCliMigration -Adapter $adapter -ProfileDir (Join-Path ([System.IO.Path]::GetTempPath()) 'mcli-ghost\nope')
        } @("Profile 'fixture/nope' does not exist")
    }

    It 'rejects adapters with an unsupported account mechanism' {
        $scratch = New-RuntimeScratch
        try {
            $adapter = Get-ValidV2Adapter
            Set-AdapterMechanism -Adapter $adapter -Mechanism 'magic'
            Assert-ThrownContains {
                Invoke-MultiCliMigration -Adapter $adapter -ProfileDir $scratch.ProfileDir -DryRun
            } @("Cannot migrate fixture/account-a: unsupported account mechanism 'magic'.")
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses migration when profile storage and the shared root are on different volumes' {
        $letter = $null
        foreach ($candidate in @('Z', 'Y', 'X', 'W', 'V', 'U')) {
            if (-not (Test-Path "${candidate}:\")) { $letter = $candidate; break }
        }
        if (-not $letter) {
            Write-Host 'No free drive letter; the cross-volume subst assertion was not exercised.'
            return
        }
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        $substituted = $false
        try {
            $env:USERPROFILE = $scratch.Home
            & subst "${letter}:" $scratch.Root | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'subst is unavailable; the cross-volume assertion was not exercised.'
                return
            }
            $substituted = $true
            $profileDir = "${letter}:\profiles\fixture\account-b"
            New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
            $adapter = Get-ValidV2Adapter
            Assert-ThrownContains {
                Invoke-MultiCliMigration -Adapter $adapter -ProfileDir $profileDir
            } @('Cannot migrate fixture/account-b: profile storage and the shared state root', 'are on different volumes', 'atomic same-volume moves')
        } finally {
            if ($substituted) { & subst "${letter}:" /d | Out-Null }
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'classifies state under directories that are strict ancestors of declared shared paths' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            $adapter.normalState.sharedPaths = @('config.toml', 'agents', 'vault/settings.json')
            $adapter.normalState.filePaths = @('config.toml', 'history.jsonl', 'vault/settings.json')
            New-Item -ItemType Directory -Force -Path (Join-Path $scratch.ProfileDir 'vault') | Out-Null
            Set-Content -LiteralPath (Join-Path $scratch.ProfileDir 'vault\settings.json') -Value 'settings' -Encoding ASCII

            $result = Invoke-MultiCliMigration -Adapter $adapter -ProfileDir $scratch.ProfileDir -DryRun

            $result.Mode | Should Be 'dry-run'
            $expected = "  merge shared vault/settings.json -> " + (Join-Path (Join-Path $scratch.Home '.fixture') 'vault\settings.json')
            ($result.Lines -contains $expected) | Should Be $true
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'journals a failed state and throws when an operation is unknown' {
        $scratch = New-RuntimeScratch
        try {
            $adapter = Get-ValidV2Adapter
            $ops = New-Object System.Collections.ArrayList
            [void]$ops.Add([ordered]@{ Op = 'bogus-op'; Rel = 'x'; From = ''; To = ''; Status = 'pending'; Note = '' })
            $context = [pscustomobject]@{ Tool = 'fixture'; Name = 'account-a'; Spec = 'fixture/account-a'; SharedRoot = $scratch.Home; PreferProfile = $false }
            $lines = New-Object System.Collections.ArrayList
            $journal = Join-Path $scratch.ProfileDir '.migration-journal.json'

            Assert-ThrownContains {
                Invoke-ModuleInternal 'MultiCli.Migration' { param($a, $p, $j, $c, $o, $l) Invoke-MigrationOps -Adapter $a -ProfileDir $p -JournalPath $j -Context $c -Ops $o -Lines $l } @($adapter, $scratch.ProfileDir, $journal, $context, $ops, $lines)
            } @("Migration failed: unknown operation 'bogus-op'", 'Roll-forward/rollback journal')

            $payload = Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json
            $payload.status | Should Be 'failed'
            $payload.operations[0].status | Should Be 'failed'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'transfer helper functions in-process' {
    It 'Get-TransferProperty returns values, and null for missing properties or a null object' {
        $object = '{"keep":"value"}' | ConvertFrom-Json
        (Invoke-ModuleInternal 'MultiCli.Transfer' { param($o) Get-TransferProperty -Object $o -Name 'keep' } @($object)) | Should Be 'value'
        (Invoke-ModuleInternal 'MultiCli.Transfer' { param($o) Get-TransferProperty -Object $o -Name 'missing' } @($object)) | Should Be $null
        (Invoke-ModuleInternal 'MultiCli.Transfer' { Get-TransferProperty -Object $null -Name 'keep' }) | Should Be $null
    }

    It 'Test-TransferCredentialPath flags declared files, credential basenames, and the auth boundary' {
        $adapter = Get-ValidV2Adapter
        (Invoke-ModuleInternal 'MultiCli.Transfer' { param($a) Test-TransferCredentialPath -Adapter $a -RelativePath 'auth.json' } @($adapter)) | Should Be $true
        (Invoke-ModuleInternal 'MultiCli.Transfer' { param($a) Test-TransferCredentialPath -Adapter $a -RelativePath 'agents/.credentials.json' } @($adapter)) | Should Be $true
        (Invoke-ModuleInternal 'MultiCli.Transfer' { param($a) Test-TransferCredentialPath -Adapter $a -RelativePath 'auth' } @($adapter)) | Should Be $true
        (Invoke-ModuleInternal 'MultiCli.Transfer' { param($a) Test-TransferCredentialPath -Adapter $a -RelativePath 'auth/nested.txt' } @($adapter)) | Should Be $true
        (Invoke-ModuleInternal 'MultiCli.Transfer' { param($a) Test-TransferCredentialPath -Adapter $a -RelativePath 'agents/agent.md' } @($adapter)) | Should Be $false
    }

    It 'Resolve-TransferPathToken returns falsy paths untouched' {
        (Invoke-ModuleInternal 'MultiCli.Transfer' { Resolve-TransferPathToken -Path '' }) | Should Be ''
    }

    It 'Get-TransferSharedRoot throws when the adapter has no windows root' {
        $adapter = '{"id":"fixture","normalState":{"root":{"linux":"$HOME/.fixture"}}}' | ConvertFrom-Json
        Assert-ThrownContains { Invoke-ModuleInternal 'MultiCli.Transfer' { param($a) Get-TransferSharedRoot -Adapter $a } @($adapter) } @("Adapter 'fixture' has no normal-state root for windows.")
    }

    It 'Test-TransferPathWithin matches only children of the root' {
        (Invoke-ModuleInternal 'MultiCli.Transfer' { Test-TransferPathWithin -Child 'C:\root\sub' -Root 'C:\root' }) | Should Be $true
        (Invoke-ModuleInternal 'MultiCli.Transfer' { Test-TransferPathWithin -Child 'C:\rootx\sub' -Root 'C:\root' }) | Should Be $false
        (Invoke-ModuleInternal 'MultiCli.Transfer' { Test-TransferPathWithin -Child 'C:\root\sub' -Root '' }) | Should Be $false
    }

    It 'Get-TransferLinkTarget resolves junctions and returns null for non-links and missing paths' {
        $scratch = New-RuntimeScratch
        try {
            $plain = Join-Path $scratch.Root 'plain'
            New-Item -ItemType Directory -Force -Path $plain | Out-Null
            $junction = Join-Path $scratch.Root 'junction'
            New-Item -ItemType Junction -Path $junction -Target $plain | Out-Null
            (Invoke-ModuleInternal 'MultiCli.Transfer' { param($p) Get-TransferLinkTarget -Path $p } @($junction)) | Should Be $plain
            (Invoke-ModuleInternal 'MultiCli.Transfer' { param($p) Get-TransferLinkTarget -Path $p } @($plain)) | Should Be $null
            (Invoke-ModuleInternal 'MultiCli.Transfer' { param($p) Get-TransferLinkTarget -Path $p } @(Join-Path $scratch.Root 'missing')) | Should Be $null
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Get-TransferProfileSource prefers the overlay, falls back to the shared root, then null' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $shared = New-TransferSharedFixture -Scratch $scratch
            $runtime = Join-Path $scratch.ProfileDir '.runtime'
            New-Item -ItemType Directory -Force -Path $runtime | Out-Null
            Set-Content -LiteralPath (Join-Path $runtime 'config.toml') -Value 'overlay-config' -Encoding ASCII

            $fromOverlay = Invoke-ModuleInternal 'MultiCli.Transfer' { param($a, $p, $s) Get-TransferProfileSource -Adapter $a -ProfileDir $p -RelativePath 'config.toml' -SharedRoot $s } @((Get-ValidV2Adapter), $scratch.ProfileDir, $shared)
            $fromOverlay | Should Be (Join-Path $runtime 'config.toml')
            $fromShared = Invoke-ModuleInternal 'MultiCli.Transfer' { param($a, $p, $s) Get-TransferProfileSource -Adapter $a -ProfileDir $p -RelativePath 'agents' -SharedRoot $s } @((Get-ValidV2Adapter), $scratch.ProfileDir, $shared)
            $fromShared | Should Be (Join-Path $shared 'agents')
            $missing = Invoke-ModuleInternal 'MultiCli.Transfer' { param($a, $p, $s) Get-TransferProfileSource -Adapter $a -ProfileDir $p -RelativePath 'nope.txt' -SharedRoot $s } @((Get-ValidV2Adapter), $scratch.ProfileDir, $shared)
            $missing | Should Be $null

            $isolatedAdapter = Get-ValidV2Adapter
            $isolatedAdapter.normalState | Add-Member -NotePropertyName runtimeSubdir -NotePropertyValue 'state'
            @{ mode = 'isolated' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $scratch.ProfileDir '.profile.json') -Encoding UTF8
            New-Item -ItemType Directory -Force -Path (Join-Path $scratch.ProfileDir 'state') | Out-Null
            Set-Content -LiteralPath (Join-Path $scratch.ProfileDir 'state\config.toml') -Value 'isolated-config' -Encoding ASCII
            $isolatedSource = Invoke-ModuleInternal 'MultiCli.Transfer' { param($a, $p, $s) Get-TransferProfileSource -Adapter $a -ProfileDir $p -RelativePath 'config.toml' -SharedRoot $s } @($isolatedAdapter, $scratch.ProfileDir, $shared)
            $isolatedSource | Should Be (Join-Path $scratch.ProfileDir 'state\config.toml')
            $isolatedMissing = Invoke-ModuleInternal 'MultiCli.Transfer' { param($a, $p, $s) Get-TransferProfileSource -Adapter $a -ProfileDir $p -RelativePath 'still-missing.txt' -SharedRoot $s } @($isolatedAdapter, $scratch.ProfileDir, $shared)
            $isolatedMissing | Should Be $null
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Save-MultiCliTemplate guard rails in-process' {
    It 'rejects a missing adapter id, an invalid name, and a missing profile' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $templates = Join-Path $scratch.Root 'templates'
            $noId = Get-ValidV2Adapter
            $noId.id = $null
            Assert-ThrownContains { Save-MultiCliTemplate -Adapter $noId -ProfileDir $scratch.ProfileDir -TemplatesRoot $templates -Name 'tpl1' } @('Adapter manifest has no id.')
            $adapter = Get-ValidV2Adapter
            Assert-ThrownContains { Save-MultiCliTemplate -Adapter $adapter -ProfileDir $scratch.ProfileDir -TemplatesRoot $templates -Name 'bad name!' } @("Template name 'bad name!' invalid")
            Assert-ThrownContains { Save-MultiCliTemplate -Adapter $adapter -ProfileDir (Join-Path $scratch.Root 'missing') -TemplatesRoot $templates -Name 'tpl1' } @('does not exist.')
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses to overwrite an existing template' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            New-TransferSharedFixture -Scratch $scratch | Out-Null
            $adapter = Get-ValidV2Adapter
            $templates = Join-Path $scratch.Root 'templates'
            Save-MultiCliTemplate -Adapter $adapter -ProfileDir $scratch.ProfileDir -TemplatesRoot $templates -Name 'tpl1'
            (Test-Path -LiteralPath (Join-Path $templates 'tpl1\.multicli-manifest.json')) | Should Be $true
            Assert-ThrownContains { Save-MultiCliTemplate -Adapter $adapter -ProfileDir $scratch.ProfileDir -TemplatesRoot $templates -Name 'tpl1' } @("Template 'tpl1' already exists")
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes a manifest-only template when no shared state exists' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            $templates = Join-Path $scratch.Root 'templates'
            Save-MultiCliTemplate -Adapter $adapter -ProfileDir $scratch.ProfileDir -TemplatesRoot $templates -Name 'empty'
            $templateDir = Join-Path $templates 'empty'
            $items = @(Get-ChildItem -LiteralPath $templateDir -Force)
            $items.Count | Should Be 1
            $items[0].Name | Should Be '.multicli-manifest.json'
            $manifest = Get-Content -LiteralPath $items[0].FullName -Raw | ConvertFrom-Json
            $manifest.adapterId | Should Be 'fixture'
            $manifest.name | Should Be 'empty'
            $manifest.kind | Should Be 'template'
            $manifest.schemaVersion | Should Be 2
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'copies overlay content when the shared root is missing' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $runtime = Join-Path $scratch.ProfileDir '.runtime'
            New-Item -ItemType Directory -Force -Path $runtime | Out-Null
            Set-Content -LiteralPath (Join-Path $runtime 'config.toml') -Value 'overlay-config' -Encoding ASCII
            $adapter = Get-ValidV2Adapter
            $templates = Join-Path $scratch.Root 'templates'

            Save-MultiCliTemplate -Adapter $adapter -ProfileDir $scratch.ProfileDir -TemplatesRoot $templates -Name 'tpl1'

            (Get-Content -LiteralPath (Join-Path $templates 'tpl1\config.toml') -Raw).Trim() | Should Be 'overlay-config'
            (Test-Path -LiteralPath (Join-Path $templates 'tpl1\.multicli-manifest.json')) | Should Be $true
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'copies profile-local overlay links when the shared root is missing' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $runtime = Join-Path $scratch.ProfileDir '.runtime'
            $local = Join-Path $scratch.ProfileDir 'local-agents'
            New-Item -ItemType Directory -Force -Path $runtime, $local | Out-Null
            Set-Content -LiteralPath (Join-Path $local 'agent.md') -Value 'local-agent' -Encoding ASCII
            New-Item -ItemType Junction -Path (Join-Path $runtime 'agents') -Target $local | Out-Null
            $adapter = Get-ValidV2Adapter
            $templates = Join-Path $scratch.Root 'templates'

            Save-MultiCliTemplate -Adapter $adapter -ProfileDir $scratch.ProfileDir -TemplatesRoot $templates -Name 'tpl1'

            (Get-Content -LiteralPath (Join-Path $templates 'tpl1\agents\agent.md') -Raw).Trim() | Should Be 'local-agent'
        } finally {
            $env:USERPROFILE = $previousHome
            $links = @(Get-ChildItem -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })
            foreach ($link in $links) { [System.IO.Directory]::Delete($link.FullName) }
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'clears a stale staging directory before saving' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            New-TransferSharedFixture -Scratch $scratch | Out-Null
            $adapter = Get-ValidV2Adapter
            $templates = Join-Path $scratch.Root 'templates'
            New-Item -ItemType Directory -Force -Path $templates | Out-Null
            $staging = Join-Path $templates ".staging.tpl1.$PID"
            New-Item -ItemType Directory -Force -Path $staging | Out-Null
            Set-Content -LiteralPath (Join-Path $staging 'stale.txt') -Value 'stale' -Encoding ASCII

            Save-MultiCliTemplate -Adapter $adapter -ProfileDir $scratch.ProfileDir -TemplatesRoot $templates -Name 'tpl1'

            (Test-Path -LiteralPath $staging) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $templates 'tpl1\.multicli-manifest.json')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $templates 'tpl1\config.toml')) | Should Be $true
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses oversized and binary files that cannot be secret-scanned safely' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $shared = New-TransferSharedFixture -Scratch $scratch
            $oversized = Join-Path $shared 'agents\big.txt'
            [System.IO.File]::WriteAllText($oversized, ('x' * (1MB + 1)) + 'OPENAI_API_KEY=sk-real-secret')
            $adapter = Get-ValidV2Adapter
            $templates = Join-Path $scratch.Root 'templates'

            Assert-ThrownContains {
                Save-MultiCliTemplate -Adapter $adapter -ProfileDir $scratch.ProfileDir -TemplatesRoot $templates -Name 'large'
            } @('agents/big.txt', 'larger than', 'secret-scan limit')
            (Test-Path -LiteralPath (Join-Path $templates 'large')) | Should Be $false

            Remove-Item -LiteralPath $oversized -Force
            $binary = Join-Path $shared 'agents\bin.dat'
            $bytes = New-Object byte[] 64
            $bytes[0] = 0
            [Text.Encoding]::ASCII.GetBytes('sk-binary-secret').CopyTo($bytes, 1)
            [System.IO.File]::WriteAllBytes($binary, $bytes)

            Assert-ThrownContains {
                Save-MultiCliTemplate -Adapter $adapter -ProfileDir $scratch.ProfileDir -TemplatesRoot $templates -Name 'binary'
            } @('agents/bin.dat', 'binary', 'secret-scanned safely')
            (Test-Path -LiteralPath (Join-Path $templates 'binary')) | Should Be $false
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses a nested link pointing outside the allowed roots' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $shared = New-TransferSharedFixture -Scratch $scratch
            $outside = Join-Path $scratch.Root 'outside'
            New-Item -ItemType Directory -Force -Path $outside | Out-Null
            New-Item -ItemType Junction -Path (Join-Path $shared 'agents\evil') -Target $outside | Out-Null
            $adapter = Get-ValidV2Adapter
            Assert-ThrownContains {
                Save-MultiCliTemplate -Adapter $adapter -ProfileDir $scratch.ProfileDir -TemplatesRoot (Join-Path $scratch.Root 'templates') -Name 'tpl1'
            } @("Cannot save template 'tpl1': 'agents/evil' is a link to '", "' outside the profile's shared state. Remove the link and retry.")
        } finally {
            $env:USERPROFILE = $previousHome
            $links = @(Get-ChildItem -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })
            foreach ($link in $links) { [System.IO.Directory]::Delete($link.FullName) }
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Export-MultiCliProfile and Import-MultiCliProfile guard rails in-process' {
    It 'rejects export with a missing adapter id or profile' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $noId = Get-ValidV2Adapter
            $noId.id = $null
            Assert-ThrownContains { Export-MultiCliProfile -Adapter $noId -ProfileDir $scratch.ProfileDir -OutPath (Join-Path $scratch.Root 'out.zip') -ProfileName 'account-a' } @('Adapter manifest has no id.')
            $adapter = Get-ValidV2Adapter
            Assert-ThrownContains { Export-MultiCliProfile -Adapter $adapter -ProfileDir (Join-Path $scratch.Root 'missing') -OutPath (Join-Path $scratch.Root 'out.zip') -ProfileName 'account-a' } @('does not exist.')
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'exports declared state and overwrites an existing archive' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            New-TransferSharedFixture -Scratch $scratch | Out-Null
            $adapter = Get-ValidV2Adapter
            Initialize-RuntimeProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir
            $out = Join-Path $scratch.Root 'export.zip'

            Export-MultiCliProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir -OutPath $out -ProfileName 'account-a'
            $first = Get-TestZipEntryNames -Path $out
            Set-Content -LiteralPath $out -Value 'junk' -Encoding ASCII
            Export-MultiCliProfile -Adapter $adapter -ProfileDir $scratch.ProfileDir -OutPath $out -ProfileName 'account-a'
            $second = Get-TestZipEntryNames -Path $out

            ($first -join '|') | Should Be ($second -join '|')
            ($second -join '|') | Should Be '.multicli-manifest.json|.profile.json|agents/agent.md|config.toml'
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects import with a missing adapter id, archive, or free destination' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $archive = Join-Path $scratch.Root 'in.zip'
            New-TestZip -Path $archive -Entries @(@{ Name = '.multicli-manifest.json'; Content = (Get-ExportManifestJson -AdapterId 'fixture') })
            $destination = Join-Path $scratch.Root 'imports\account-b'
            $noId = Get-ValidV2Adapter
            $noId.id = $null
            Assert-ThrownContains { Import-MultiCliProfile -Adapter $noId -ArchivePath $archive -DestinationDir $destination } @('Adapter manifest has no id.')
            $adapter = Get-ValidV2Adapter
            Assert-ThrownContains { Import-MultiCliProfile -Adapter $adapter -ArchivePath (Join-Path $scratch.Root 'missing.zip') -DestinationDir $destination } @('File not found:')
            New-Item -ItemType Directory -Force -Path $destination | Out-Null
            Assert-ThrownContains { Import-MultiCliProfile -Adapter $adapter -ArchivePath $archive -DestinationDir $destination } @("Profile destination '$destination' already exists")
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'imports dot-slash and directory entries and regenerates profile identity' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $archive = Join-Path $scratch.Root 'in.zip'
            New-TestZip -Path $archive -Entries @(
                @{ Name = '.multicli-manifest.json'; Content = (Get-ExportManifestJson -AdapterId 'fixture') },
                @{ Name = './config.toml'; Content = 'plain config' },
                @{ Name = 'agents/' }
            )
            $adapter = Get-ValidV2Adapter
            $destination = Join-Path $scratch.Root 'imports\account-b'

            Import-MultiCliProfile -Adapter $adapter -ArchivePath $archive -DestinationDir $destination

            (Get-Content -LiteralPath (Join-Path $scratch.Home '.fixture\config.toml') -Raw).Trim() | Should Be 'plain config'
            (Test-Path -LiteralPath (Join-Path $scratch.Home '.fixture\agents') -PathType Container) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $destination '.multicli-manifest.json')) | Should Be $false
            $metadata = Get-Content -LiteralPath (Join-Path $destination '.profile.json') -Raw | ConvertFrom-Json
            $metadata.adapterId | Should Be 'fixture'
            $metadata.mode | Should Be 'accountOverlay'
            (Test-Path -LiteralPath (Join-Path $destination 'auth\auth.json') -PathType Leaf) | Should Be $true
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses archives containing disposable runtime state' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $archive = Join-Path $scratch.Root 'in.zip'
            New-TestZip -Path $archive -Entries @(
                @{ Name = '.multicli-manifest.json'; Content = (Get-ExportManifestJson -AdapterId 'fixture') },
                @{ Name = '.runtime/junk.txt'; Content = 'junk' }
            )
            $adapter = Get-ValidV2Adapter
            Assert-ThrownContains {
                Import-MultiCliProfile -Adapter $adapter -ArchivePath $archive -DestinationDir (Join-Path $scratch.Root 'imports\account-b')
            } @("Refusing to import: archive entry '.runtime/junk.txt' is disposable runtime state.")
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses an archive whose manifest has no adapter id' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $archive = Join-Path $scratch.Root 'in.zip'
            $manifest = @{ schemaVersion = 2; name = 'staged'; kind = 'export' } | ConvertTo-Json -Compress
            New-TestZip -Path $archive -Entries @(@{ Name = '.multicli-manifest.json'; Content = $manifest })
            $adapter = Get-ValidV2Adapter
            Assert-ThrownContains {
                Import-MultiCliProfile -Adapter $adapter -ArchivePath $archive -DestinationDir (Join-Path $scratch.Root 'imports\account-b')
            } @('Refusing to import: archive manifest is invalid.')
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a template with an unreadable manifest' {
        $scratch = New-RuntimeScratch
        try {
            $templateDir = Join-Path $scratch.Root 'templates\broken'
            New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
            Set-Content -LiteralPath (Join-Path $templateDir '.multicli-manifest.json') -Value '{invalid' -Encoding ASCII
            $adapter = Get-ValidV2Adapter
            Assert-ThrownContains {
                Assert-TransferTemplateCompatible -TemplateDir $templateDir -Adapter $adapter
            } @("Template 'broken' has no manifest; it was not saved by this version of multi-cli.")
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses template links and invalid UTF-8 files through the scanner' {
        $scratch = New-RuntimeScratch
        try {
            $adapter = Get-ValidV2Adapter
            $templateDir = Join-Path $scratch.Root 'templates\unsafe'
            $outside = Join-Path $scratch.Root 'outside'
            New-Item -ItemType Directory -Force -Path $templateDir, $outside | Out-Null
            Invoke-ModuleInternal 'MultiCli.Transfer' { param($d) Write-TransferManifest -Destination $d -AdapterId 'fixture' -Name 'unsafe' -Kind 'template' } @((Join-Path $templateDir '.multicli-manifest.json'))
            New-Item -ItemType Junction -Path (Join-Path $templateDir 'agents') -Target $outside | Out-Null
            Assert-ThrownContains {
                Invoke-ModuleInternal 'MultiCli.Transfer' { param($t, $a) Get-TransferTemplatePlan -TemplateDir $t -Adapter $a } @($templateDir, $adapter)
            } @("Template 'unsafe' contains link 'agents'")
            [System.IO.Directory]::Delete((Join-Path $templateDir 'agents'))

            New-Item -ItemType Directory -Force -Path (Join-Path $templateDir 'agents') | Out-Null
            $invalidUtf8 = Join-Path $templateDir 'agents\invalid.txt'
            [System.IO.File]::WriteAllBytes($invalidUtf8, [byte[]](0xC3, 0x28))
            Assert-ThrownContains {
                Invoke-ModuleInternal 'MultiCli.Transfer' { param($t, $a) Get-TransferTemplatePlan -TemplateDir $t -Adapter $a } @($templateDir, $adapter)
            } @("Template 'unsafe' file 'agents/invalid.txt' is binary and cannot be secret-scanned safely")
            (Invoke-ModuleInternal 'MultiCli.Transfer' { param($p) Test-TransferFileSecret -Path $p } @($invalidUtf8)) | Should Be $true
        } finally {
            $links = @(Get-ChildItem -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })
            foreach ($link in $links) { [System.IO.Directory]::Delete($link.FullName) }
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'applies compatible templates to shared and isolated destinations' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            $templateDir = Join-Path $scratch.Root 'templates\valid'
            New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
            Invoke-ModuleInternal 'MultiCli.Transfer' { param($d) Write-TransferManifest -Destination $d -AdapterId 'fixture' -Name 'valid' -Kind 'template' } @((Join-Path $templateDir '.multicli-manifest.json'))
            Set-Content -LiteralPath (Join-Path $templateDir 'config.toml') -Value 'template-config' -Encoding ASCII

            Apply-MultiCliTemplate -TemplateDir $templateDir -Adapter $adapter -ProfileDir $scratch.ProfileDir
            (Get-Content -LiteralPath (Join-Path $scratch.Home '.fixture\config.toml') -Raw).Trim() | Should Be 'template-config'

            Remove-Item -LiteralPath (Join-Path $scratch.Home '.fixture') -Recurse -Force
            Apply-MultiCliTemplate -TemplateDir $templateDir -Adapter $adapter -ProfileDir $scratch.ProfileDir -Isolated
            (Get-Content -LiteralPath (Join-Path $scratch.ProfileDir 'config.toml') -Raw).Trim() | Should Be 'template-config'
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'applies templates inside an isolated runtimeSubdir' {
        $scratch = New-RuntimeScratch
        try {
            $adapter = Get-ValidV2Adapter
            $adapter.normalState | Add-Member -NotePropertyName runtimeSubdir -NotePropertyValue 'state'
            $templateDir = Join-Path $scratch.Root 'templates\subdir'
            New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
            Invoke-ModuleInternal 'MultiCli.Transfer' { param($d) Write-TransferManifest -Destination $d -AdapterId 'fixture' -Name 'subdir' -Kind 'template' } @((Join-Path $templateDir '.multicli-manifest.json'))
            Set-Content -LiteralPath (Join-Path $templateDir 'config.toml') -Value 'subdir-config' -Encoding ASCII

            Apply-MultiCliTemplate -TemplateDir $templateDir -Adapter $adapter -ProfileDir $scratch.ProfileDir -Isolated

            (Get-Content -LiteralPath (Join-Path $scratch.ProfileDir 'state\config.toml') -Raw).Trim() | Should Be 'subdir-config'
        } finally { Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects undeclared archive entries and malformed archived profile metadata' {
        $scratch = New-RuntimeScratch
        $previousHome = $env:USERPROFILE
        try {
            $env:USERPROFILE = $scratch.Home
            $adapter = Get-ValidV2Adapter
            Assert-ThrownContains {
                Invoke-ModuleInternal 'MultiCli.Transfer' { param($a) Assert-TransferEntrySafe -Name 'undeclared.txt' -Adapter $a } @($adapter)
            } @("archive entry 'undeclared.txt' is not adapter-declared shared state")

            $archive = Join-Path $scratch.Root 'malformed.zip'
            New-TestZip -Path $archive -Entries @(
                @{ Name = '.multicli-manifest.json'; Content = (Get-ExportManifestJson -AdapterId 'fixture') },
                @{ Name = '.profile.json'; Content = '{invalid' }
            )
            Assert-ThrownContains {
                Import-MultiCliProfile -Adapter $adapter -ArchivePath $archive -DestinationDir (Join-Path $scratch.Root 'imports\account-b')
            } @('Refusing to import: archived profile metadata is invalid.')
        } finally {
            $env:USERPROFILE = $previousHome
            Remove-Item -LiteralPath $scratch.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
