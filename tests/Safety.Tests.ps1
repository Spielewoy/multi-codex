<#
  Pester 3.4-compatible real-execution tests for the hardened safety branches in
  multi-cli.ps1: staleness repair, dest-newer / equal-size skips, adapter-bug
  path validation (.. / absolute / drive), nested credential-named directories,
  the seeding size guard, reparse-point (symlink) skipping, and hardlink skipping
  (credential-leak regression).

  No mocks: every test builds a real fixture tree in a temp sandbox, redirects
  USERPROFILE/HOME/MULTICLI_HOME into it, and runs the real launcher in a child
  PowerShell process (or dot-sources the launcher functions for unit branches).

  Run with: powershell -NoProfile -File tests/run-pester.ps1
#>

. (Join-Path $PSScriptRoot 'SessionContinuation.Helper.ps1')
. (Get-LauncherDefsPath)   # dot-source launcher functions for unit-level branch tests

$script:CodexDest = {
    param($Scratch, $Name) Join-Path (Join-Path $Scratch.MultiCliHome 'codex') $Name
}

Describe 'adapter binary discovery' {
    It 'does not treat an empty URI registration as an installed application' {
        $scheme = 'multicli-empty-' + [guid]::NewGuid().ToString('N')
        $key = "HKCU:\Software\Classes\$scheme"
        try {
            New-Item -Path $key -Force | Out-Null
            Set-ItemProperty -Path $key -Name 'URL Protocol' -Value ''
            (Test-UriProtocol -Scheme $scheme) | Should Be $false
            New-Item -Path "$key\shell\open\command" -Force | Out-Null
            Set-ItemProperty -Path "$key\shell\open\command" -Name '(default)' -Value 'explorer.exe "%1"'
            (Test-UriProtocol -Scheme $scheme) | Should Be $true
        } finally { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns null for an Appx package family that is not installed' {
        (Get-AppxAdapterBinary -PackageTarget 'multi-cli.missing_package!App') | Should Be $null
    }

    It 'returns an AppX activation target instead of a protected payload path' {
        function Get-AppxPackage { [pscustomobject]@{ PackageFamilyName = 'OpenAI.Codex_fixture'; SignatureKind = 'Store'; Version = [version]'2.0' } }
        function Get-AppxPackageManifest {
            [pscustomobject]@{ Package = [pscustomobject]@{ Applications = [pscustomobject]@{ Application = @(
                [pscustomobject]@{ Id = 'Helper' }, [pscustomobject]@{ Id = 'App' }
            ) } } }
        }
        (Get-AppxAdapterBinary -PackageTarget 'OpenAI.Codex!App') | Should Be 'appx:OpenAI.Codex_fixture!App'
    }
}

Describe 'redirected input normalization' {
    It 'strips a UTF-8 BOM and preserves UTF-8 content' {
        $encoding = New-Object Text.UTF8Encoding($false)
        $payload = $UTF8_BOM_BYTES + $encoding.GetBytes("sëcret`r`nignored")
        $stream = New-Object IO.MemoryStream -ArgumentList @(, $payload)
        try {
            (Read-RedirectedLine -InputStream $stream) | Should Be 'sëcret'
        } finally {
            $stream.Dispose()
        }
    }

    It 'preserves ordinary input and returns null at end of stream' {
        $payload = [Text.Encoding]::UTF8.GetBytes("confirm`n")
        $stream = New-Object IO.MemoryStream -ArgumentList @(, $payload)
        try {
            (Read-RedirectedLine -InputStream $stream) | Should Be 'confirm'
            (Read-RedirectedLine -InputStream $stream) | Should Be $null
        } finally {
            $stream.Dispose()
        }
    }

    It 'returns an empty string for an empty redirected line' {
        $stream = New-Object IO.MemoryStream -ArgumentList @(, ([byte[]](10)))
        try {
            (Read-RedirectedLine -InputStream $stream) | Should Be ''
        } finally {
            $stream.Dispose()
        }
    }
}

Describe 'multi-cli staleness branches (codex, real fixtures)' {

    It '(a) truncated dest with equal mtime + different size is repaired (re-copied)' {
        $s = New-Scratch
        try {
            $codex = New-CodexSystemHome -UserHome $s.Home
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh') | Out-Null

            $dst = Join-Path (& $script:CodexDest $s 'fresh') 'history.jsonl'
            $src = Join-Path $codex 'history.jsonl'
            $fullLen = (Get-Item $dst).Length

            # Corrupt the dest: shorten it, then force its mtime back to the source's.
            Set-Content -Path $dst -Value 'X' -Encoding UTF8 -NoNewline
            (Get-Item $dst).Length | Should Not Be $fullLen
            Set-FileMtime -Path $dst -Time (Get-Item $src).LastWriteTimeUtc

            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Match '\(1 copied, 1 skipped \(same-or-newer\)\)'
            (Get-Item $dst).Length | Should Be $fullLen
        } finally { Remove-Scratch $s }
    }

    It '(b) dest strictly newer than source is skipped, never overwritten' {
        $s = New-Scratch
        try {
            $codex = New-CodexSystemHome -UserHome $s.Home
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh') | Out-Null

            $dst = Join-Path (& $script:CodexDest $s 'fresh') 'history.jsonl'
            $src = Join-Path $codex 'history.jsonl'
            Set-Content -Path $dst -Value 'LOCAL-EDIT-keep-me' -Encoding UTF8
            Set-FileMtime -Path $dst -Time ((Get-Item $src).LastWriteTimeUtc.AddHours(1))

            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Match '\(0 copied, 2 skipped \(same-or-newer\)\)'
            (Get-Content $dst -Raw) | Should Match 'LOCAL-EDIT-keep-me'
        } finally { Remove-Scratch $s }
    }

    It '(b'') equal mtime + equal size is skipped' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh') | Out-Null
            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Match '\(0 copied, 2 skipped \(same-or-newer\)\)'
        } finally { Remove-Scratch $s }
    }
}

Describe 'multi-cli adapter-bug path validation (Assert-RelPathSafe)' {

    It '(c) a session path containing .. throws as an adapter bug' {
        $adapter = [pscustomobject]@{ id = 'dotdot'; session = [pscustomobject]@{
            paths = @('../escape'); credentials = @() } }
        { Test-SessionAdapterBug $adapter } | Should Throw
    }

    It "(c') an absolute session path throws as an adapter bug" {
        $adapter = [pscustomobject]@{ id = 'abs'; session = [pscustomobject]@{
            paths = @('/etc/passwd'); credentials = @() } }
        { Test-SessionAdapterBug $adapter } | Should Throw
    }

    It "(c'') a drive-letter session path throws as an adapter bug" {
        $adapter = [pscustomobject]@{ id = 'drive'; session = [pscustomobject]@{
            paths = @('C:/Windows'); credentials = @() } }
        { Test-SessionAdapterBug $adapter } | Should Throw
    }

    It "(c''') a credential entry containing .. throws as an adapter bug" {
        $adapter = [pscustomobject]@{ id = 'credbad'; session = [pscustomobject]@{
            paths = @('sessions'); credentials = @('../secret') } }
        { Test-SessionAdapterBug $adapter } | Should Throw
    }

    It 'Assert-RelPathSafe accepts a plain relative path' {
        { Assert-RelPathSafe -Path 'sessions/2026' -Kind 'session path' -ToolId 'codex' } | Should Not Throw
    }
}

Describe 'multi-cli per-component credential blocklist (real fixtures)' {

    It '(d) a credential-named directory nested in the tree blocks its files; siblings copied' {
        $s = New-Scratch
        try {
            $codex = New-CodexSystemHome -UserHome $s.Home
            # auth.json is the codex credential. Plant a DIRECTORY named auth.json under
            # sessions/ holding a secret, plus a clean sibling file.
            $credDir = Join-Path $codex 'sessions\auth.json'
            New-Item -ItemType Directory -Force -Path $credDir | Out-Null
            Set-Content -Path (Join-Path $credDir 'leak.json') -Value '{"OPENAI_API_KEY":"sk-DIR-MUST-NOT-LEAK"}' -Encoding UTF8
            $keepDir = Join-Path $codex 'sessions\keep'
            New-Item -ItemType Directory -Force -Path $keepDir | Out-Null
            Set-Content -Path (Join-Path $keepDir 'ok.txt') -Value 'safe-sibling' -Encoding UTF8

            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh')
            $r.ExitCode | Should Be 0

            $files = Get-RelativeFileList -Root (& $script:CodexDest $s 'fresh')
            @($files | Where-Object { $_ -like 'sessions/auth.json/*' }).Count | Should Be 0
            ($files -contains 'sessions/keep/ok.txt') | Should Be $true
        } finally { Remove-Scratch $s }
    }
}

Describe 'multi-cli seeding size guard (real fixtures)' {

    It '(e) oversize base skips automatic seeding with an actionable message' {
        $s = New-Scratch
        try {
            $codex = Join-Path $s.Home '.codex'
            $sessionsDir = Join-Path $codex 'sessions\2026\06\11'
            New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null
            # fsutil createnew allocates a >500MB file instantly; Measure-Object reads
            # its full Length, so Get-SessionStateSize trips the SEED_MAX_BYTES guard.
            $big = Join-Path $sessionsDir 'rollout-big.jsonl'
            & fsutil file createnew $big 525336576 | Out-Null

            $r = Invoke-LauncherGuarded -Scratch $s -Arguments @('new', 'codex/heavy')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Match 'base session state is'
            $r.StdOut | Should Match 'skipped automatic copy'
            $r.StdOut | Should Match 'multi-cli continue codex base heavy'

            $files = Get-RelativeFileList -Root (& $script:CodexDest $s 'heavy')
            @($files | Where-Object { $_ -like 'sessions/*' }).Count | Should Be 0
        } finally { Remove-Scratch $s }
    }

    It "(e') under-threshold base prints the seeding progress line" {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            $r = Invoke-LauncherGuarded -Scratch $s -Arguments @('new', 'codex/light')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Match 'seeding 2 session file\(s\) from base'
        } finally { Remove-Scratch $s }
    }
}

Describe 'multi-cli reparse-point (symlink) skipping' {

    It '(f) Test-IsReparsePoint flags a real symlink and ignores a plain file' {
        $s = New-Scratch
        try {
            $target = Join-Path $s.Home 'target.txt'
            Set-Content -Path $target -Value 'x' -Encoding UTF8
            $plain = Get-Item $target
            (Test-IsReparsePoint $plain) | Should Be $false

            $link = Join-Path $s.Home 'link.txt'
            $made = $true
            try {
                New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
            } catch { $made = $false }
            if (-not $made) {
                Write-Host 'Host cannot create symlinks; this capability-specific assertion was not exercised.'
                return
            }
            (Test-IsReparsePoint (Get-Item $link -Force)) | Should Be $true
        } finally { Remove-Scratch $s }
    }

    It '(f-end-to-end) a symlink inside a session tree is never dereferenced' {
        $s = New-Scratch
        try {
            $codex = New-CodexSystemHome -UserHome $s.Home
            $secret = Join-Path $s.Root 'outside-secret.txt'
            Set-Content -Path $secret -Value 'sk-SYMLINK-TARGET-MUST-NOT-LEAK' -Encoding UTF8
            $link = Join-Path $codex 'sessions\link.json'
            $made = $true
            try {
                New-Item -ItemType SymbolicLink -Path $link -Target $secret -ErrorAction Stop | Out-Null
            } catch { $made = $false }
            if (-not $made) {
                Write-Host 'Host cannot create symlinks; this capability-specific assertion was not exercised.'
                return
            }

            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh') | Out-Null

            $files = Get-RelativeFileList -Root (& $script:CodexDest $s 'fresh')
            @($files | Where-Object { $_ -like 'sessions/link.json*' }).Count | Should Be 0
        } finally { Remove-Scratch $s }
    }
}

Describe 'multi-cli hardlink credential-leak regression (real fixtures)' {

    It '(h) a hardlink to the base credential inside the session tree is skipped, never copied' {
        $s = New-Scratch
        try {
            $codex = New-CodexSystemHome -UserHome $s.Home
            $marker = "sk-HARDLINK-REGRESSION-$(Get-Random)$(Get-Random)"
            $auth = Join-Path $codex 'auth.json'
            Set-Content -Path $auth -Value (@{ OPENAI_API_KEY = $marker } | ConvertTo-Json) -Encoding UTF8

            # Hardlink a session-tree file onto the base credential. Hardlinks need no
            # admin on NTFS same-volume; skip only if the host refuses creation.
            $link = Join-Path $codex 'sessions\2026\06\11\innocent.jsonl'
            $made = $true
            try {
                New-Item -ItemType HardLink -Path $link -Target $auth -ErrorAction Stop | Out-Null
            } catch {
                & cmd /c mklink /H "`"$link`"" "`"$auth`"" 2>&1 | Out-Null
                if (-not (Test-Path -LiteralPath $link)) { $made = $false }
            }
            if (-not $made) {
                Write-Host 'Host refused hardlink creation; this capability-specific assertion was not exercised.'
                return
            }
            # Precondition: the link really shares bytes with the credential.
            (Get-Content -LiteralPath $link -Raw) | Should Be (Get-Content -LiteralPath $auth -Raw)
            (Get-Item -LiteralPath $link).LinkType | Should Be 'HardLink'

            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh')
            $r.ExitCode | Should Be 0
            # Only the 2 legitimate session files (rollout + history.jsonl) were copied.
            $r.StdOut | Should Match '\(2 copied, 0 skipped \(same-or-newer\)\)'

            $dest = & $script:CodexDest $s 'fresh'
            $files = Get-RelativeFileList -Root $dest
            ($files -contains 'history.jsonl') | Should Be $true
            @($files | Where-Object { $_ -like 'sessions/2026/06/11/rollout-*.jsonl' }).Count | Should Be 1
            # The hardlink itself never materialized in the destination.
            @($files | Where-Object { $_ -like 'sessions/2026/06/11/innocent.jsonl' }).Count | Should Be 0
            # No file anywhere under dest carries the credential marker (exactly 0 matches).
            $hits = @(Get-ChildItem -Path $dest -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape($marker) })
            $hits.Count | Should Be 0
        } finally { Remove-Scratch $s }
    }
}
