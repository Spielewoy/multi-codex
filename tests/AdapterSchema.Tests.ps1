$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:Validator = Join-Path $script:RepoRoot 'scripts\Validate-Adapters.ps1'

function New-AdapterSchemaScratch {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mcli_schema_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return $root
}

function Write-TestAdapter {
    param([string]$Root, [string]$Directory, [string]$Json)
    $adapterDir = Join-Path $Root $Directory
    New-Item -ItemType Directory -Force -Path $adapterDir | Out-Null
    Set-Content -LiteralPath (Join-Path $adapterDir 'adapter.json') -Value $Json -Encoding UTF8
}

function Get-ValidV2AdapterJson {
    $adapter = [ordered]@{
        schemaVersion = 2
        id = 'test-cli'
        displayName = 'Test CLI'
        kind = 'cli'
        binary = [ordered]@{
            windows = @('test-cli.exe')
            macos = @('test-cli')
            linux = @('test-cli')
        }
        isolation = [ordered]@{
            strategy = 'accountOverlay'
            mode = 'foreground'
            env = [ordered]@{ TEST_HOME = '{runtimeRoot}' }
            clearEnv = @('GLOBAL_TEST_TOKEN')
        }
        account = [ordered]@{
            mechanism = 'fileOverlay'
            credentialFiles = @('auth.json')
            credentialPrecedence = @('auth.json')
            logoutScope = 'profile'
        }
        normalState = [ordered]@{
            root = [ordered]@{
                windows = '%USERPROFILE%\.test-cli'
                macos = '$HOME/.test-cli'
                linux = '$HOME/.test-cli'
            }
            sharedPaths = @('config.toml', 'agents', 'skills')
            sessionPaths = @('sessions', 'history.jsonl')
            unsafePaths = @('cache/account.sqlite')
        }
        concurrency = [ordered]@{
            level = 'multiWriter'
            singletonScope = 'none'
        }
        support = [ordered]@{
            windows = [ordered]@{ level = 'supported'; reason = 'File overlay with profile-local auth.json.' }
            macos = [ordered]@{ level = 'supported' }
            linux = [ordered]@{ level = 'supported' }
        }
        install = 'https://example.test/install'
        versionCommand = @('--version')
    }
    return ($adapter | ConvertTo-Json -Depth 12)
}

function Invoke-AdapterValidator {
    param([string]$Root)
    $process = New-Object System.Diagnostics.ProcessStartInfo
    $process.FileName = (Get-Command powershell.exe).Source
    $process.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:Validator`" -ToolsRoot `"$Root`""
    $process.UseShellExecute = $false
    $process.RedirectStandardOutput = $true
    $process.RedirectStandardError = $true
    $process.CreateNoWindow = $true
    $child = [System.Diagnostics.Process]::Start($process)
    $stdoutTask = $child.StandardOutput.ReadToEndAsync()
    $stderrTask = $child.StandardError.ReadToEndAsync()
    $timedOut = -not $child.WaitForExit(120000)
    if ($timedOut) { try { $child.Kill() } catch { }; $child.WaitForExit() }
    return [pscustomobject]@{
        ExitCode = $(if ($timedOut) { -1 } else { $child.ExitCode })
        Output = "$($stdoutTask.Result)$($stderrTask.Result)"
    }
}

Describe 'adapter schema validation' {
    It 'accepts a complete schema-v2 account overlay' {
        $root = New-AdapterSchemaScratch
        try {
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json (Get-ValidV2AdapterJson)
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 0
            $result.Output | Should Match 'Validated 1 adapter\(s\)'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'accepts schema-v1 adapters for legacy compatibility' {
        $root = New-AdapterSchemaScratch
        try {
            $json = '{"id":"legacy","displayName":"Legacy","kind":"cli","binary":{"windows":["legacy.exe"],"macos":["legacy"],"linux":["legacy"]},"isolation":{"strategy":"env","env":{"LEGACY_HOME":"{profileDir}"}},"share":{"systemHome":"$HOME/.legacy","linkable":["config"],"neverLink":["auth.json"]},"status":"stable"}'
            Write-TestAdapter -Root $root -Directory 'legacy' -Json $json
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 0
            $result.Output | Should Match 'Validated 1 adapter\(s\)'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects malformed JSON with the adapter path' {
        $root = New-AdapterSchemaScratch
        try {
            Write-TestAdapter -Root $root -Directory 'broken' -Json '{"id":"broken"'
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'broken[\\/]adapter.json: invalid JSON'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects credential paths overlapping shared sessions' {
        $root = New-AdapterSchemaScratch
        try {
            $adapter = Get-ValidV2AdapterJson | ConvertFrom-Json
            $adapter.account.credentialFiles = @('sessions/auth.json')
            $adapter.normalState.sessionPaths = @('sessions')
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 1
            $result.Output | Should Match "credential path 'sessions/auth.json' overlaps session path 'sessions'"
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects unknown placeholders' {
        $root = New-AdapterSchemaScratch
        try {
            $adapter = Get-ValidV2AdapterJson | ConvertFrom-Json
            $adapter.isolation.env.TEST_HOME = '{mysteryRoot}'
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 1
            $result.Output | Should Match "unknown placeholder '\{mysteryRoot\}'"
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'requires a reason for unsupported support' {
        $root = New-AdapterSchemaScratch
        try {
            $adapter = Get-ValidV2AdapterJson | ConvertFrom-Json
            $adapter.support.windows = [pscustomobject]@{ level = 'unsupported' }
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 1
            $result.Output | Should Match "support.windows.reason is required for level 'unsupported'"
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'accepts an experimental support level with a reason' {
        $root = New-AdapterSchemaScratch
        try {
            $adapter = Get-ValidV2AdapterJson | ConvertFrom-Json
            $adapter.support.windows = [pscustomobject]@{ level = 'experimental'; reason = 'Requires real Windows verification.' }
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 0
            $result.Output | Should Match 'Validated 1 adapter\(s\)'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'accepts the gui kind and rejects an unknown kind' {
        $root = New-AdapterSchemaScratch
        try {
            $adapter = Get-ValidV2AdapterJson | ConvertFrom-Json
            $adapter.kind = 'gui'
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            (Invoke-AdapterValidator -Root $root).ExitCode | Should Be 0

            $adapter.kind = 'desktop'
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            $result = Invoke-AdapterValidator -Root $root
            $result.ExitCode | Should Be 1
            $result.Output | Should Match "kind 'desktop' is not one of"
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'requires a reason for experimental support' {
        $root = New-AdapterSchemaScratch
        try {
            $adapter = Get-ValidV2AdapterJson | ConvertFrom-Json
            $adapter.support.windows = [pscustomobject]@{ level = 'experimental' }
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 1
            $result.Output | Should Match "support.windows.reason is required for level 'experimental'"
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'accepts AppX metadata and rejects an incomplete declaration' {
        $root = New-AdapterSchemaScratch
        try {
            $adapter = Get-ValidV2AdapterJson | ConvertFrom-Json
            $adapter.account.mechanism = 'osUserCredentialStore'
            $adapter.account.PSObject.Properties.Remove('credentialFiles')
            $adapter.account.PSObject.Properties.Remove('credentialPrecedence')
            $adapter.isolation.mode = 'detached'
            $adapter.binary.windows = @('appx:OpenAI.Codex')
            $adapter | Add-Member -NotePropertyName appx -NotePropertyValue ([pscustomobject]@{ packageName = 'OpenAI.Codex'; applicationId = 'App'; storeProductId = '9PLM9XGG6VKS' })
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            (Invoke-AdapterValidator -Root $root).ExitCode | Should Be 0

            $adapter.appx.applicationId = ''
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            $result = Invoke-AdapterValidator -Root $root
            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'appx.applicationId is required when appx is declared'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects AppX metadata outside its owned-user detached contract' {
        $root = New-AdapterSchemaScratch
        try {
            $adapter = Get-ValidV2AdapterJson | ConvertFrom-Json
            $adapter | Add-Member -NotePropertyName appx -NotePropertyValue ([pscustomobject]@{ packageName = 'OpenAI.Codex'; applicationId = 'App' })
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 1
            $result.Output | Should Match 'appx requires account.mechanism osUserCredentialStore'
            $result.Output | Should Match 'appx requires isolation.mode detached'
            $result.Output | Should Match "binary.windows must contain 'appx:OpenAI.Codex'"
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects retired evidenceId metadata' {
        $root = New-AdapterSchemaScratch
        try {
            $adapter = Get-ValidV2AdapterJson | ConvertFrom-Json
            $adapter | Add-Member -NotePropertyName evidenceId -NotePropertyValue 'EV-1'
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 1
            $result.Output | Should Match "unsupported top-level field 'evidenceId'"
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects unknown nested fields' {
        $root = New-AdapterSchemaScratch
        try {
            $adapter = Get-ValidV2AdapterJson | ConvertFrom-Json
            $adapter.support.windows | Add-Member -NotePropertyName note -NotePropertyValue 'not part of the contract'
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 1
            $result.Output | Should Match "unsupported field 'support.windows.note'"
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects legacy fields in schema-v2' {
        $root = New-AdapterSchemaScratch
        try {
            $adapter = Get-ValidV2AdapterJson | ConvertFrom-Json
            $adapter | Add-Member -NotePropertyName status -NotePropertyValue 'stable'
            Write-TestAdapter -Root $root -Directory 'test-cli' -Json ($adapter | ConvertTo-Json -Depth 12)
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 1
            $result.Output | Should Match "unsupported top-level field 'status'"
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects unknown schema-v1 nested fields' {
        $root = New-AdapterSchemaScratch
        try {
            $json = '{"id":"legacy","displayName":"Legacy","kind":"cli","binary":{"windows":["legacy"],"macos":["legacy"],"linux":["legacy"]},"isolation":{"strategy":"env","env":{"HOME":"{profileDir}"}},"share":{"systemHome":"$HOME/.legacy","linkable":["config"],"neverLink":["auth.json"],"note":"extra"},"status":"stable"}'
            Write-TestAdapter -Root $root -Directory 'legacy' -Json $json
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 1
            $result.Output | Should Match "unsupported field 'share.note'"
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects v1 linkable and neverLink overlap' {
        $root = New-AdapterSchemaScratch
        try {
            $json = '{"id":"legacy","displayName":"Legacy","kind":"cli","binary":{"windows":["legacy"],"macos":["legacy"],"linux":["legacy"]},"isolation":{"strategy":"env","env":{"HOME":"{profileDir}"}},"share":{"systemHome":"$HOME/.legacy","linkable":["auth.json"],"neverLink":["auth.json"]},"status":"stable"}'
            Write-TestAdapter -Root $root -Directory 'legacy' -Json $json
            $result = Invoke-AdapterValidator -Root $root

            $result.ExitCode | Should Be 1
            $result.Output | Should Match "share.linkable path 'auth.json' overlaps share.neverLink path 'auth.json'"
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
