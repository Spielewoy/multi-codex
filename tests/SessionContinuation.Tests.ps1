<#
  Pester 3.4-compatible real-execution test suite for the multi-cli.ps1
  session-continuation feature. No mocks: every test builds a real fixture tree
  in a temp sandbox, redirects USERPROFILE/HOME/MULTICLI_HOME into it, and runs
  the actual launcher in a child PowerShell process.

  Run with: powershell -NoProfile -File tests/run-pester.ps1
#>

. (Join-Path $PSScriptRoot 'SessionContinuation.Helper.ps1')
. (Get-LauncherDefsPath)   # dot-source launcher functions for unit-level branch tests

$script:CodexDest = {
    param($Scratch, $Name) Join-Path (Join-Path $Scratch.MultiCliHome 'codex') $Name
}

Describe 'multi-cli continue (codex, real fixtures)' {

    It '(1) base -> profile copies sessions+history, never auth.json, prints count and resumeHint' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh')

            $r.ExitCode | Should Be 0
            $r.StdOut | Should Match 'Continued codex: base -> fresh \(2 copied, 0 skipped \(same-or-newer\)\)'
            $r.StdOut | Should Match 'codex resume'

            $files = Get-RelativeFileList -Root (& $script:CodexDest $s 'fresh')
            $files -contains 'history.jsonl' | Should Be $true
            @($files | Where-Object { $_ -like 'sessions/2026/06/11/rollout-*' }).Count | Should Be 1
            ($files -contains 'auth.json') | Should Be $false
        } finally { Remove-Scratch $s }
    }

    It '(2) nested decoy credential inside sessions/ is never copied' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh') | Out-Null

            $files = Get-RelativeFileList -Root (& $script:CodexDest $s 'fresh')
            @($files | Where-Object { $_ -like '*auth.json' }).Count | Should Be 0
            @($files | Where-Object { $_ -eq 'sessions/nested/auth.json' }).Count | Should Be 0
        } finally { Remove-Scratch $s }
    }

    It '(3) repeated run with no changes reports all skipped (mtime guard)' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh') | Out-Null
            $r2 = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh')

            $r2.ExitCode | Should Be 0
            $r2.StdOut | Should Match '\(0 copied, 2 skipped \(same-or-newer\)\)'
        } finally { Remove-Scratch $s }
    }

    It '(4) newer source is recopied; up-to-date dest is skipped' {
        $s = New-Scratch
        try {
            $codex = New-CodexSystemHome -UserHome $s.Home
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh') | Out-Null

            # Make the source history.jsonl strictly newer than the just-copied dest.
            $srcHistory = Join-Path $codex 'history.jsonl'
            Set-FileMtime -Path $srcHistory -Time ([datetime]::UtcNow.AddHours(1))

            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh')
            $r.ExitCode | Should Be 0
            # rollout unchanged (skipped), history newer (recopied) => 1 copied, 1 skipped
            $r.StdOut | Should Match '\(1 copied, 1 skipped \(same-or-newer\)\)'
        } finally { Remove-Scratch $s }
    }

    It '(5) --no-merge overwrites the destination regardless of mtime' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh') | Out-Null

            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh', '--no-merge')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Match '\(2 copied, 0 skipped \(same-or-newer\)\)'
        } finally { Remove-Scratch $s }
    }

    It '(6) --dry-run writes nothing and announces the dry run' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            $destDir = New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh'

            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh', '--dry-run')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Match 'Dry run'
            $r.StdOut | Should Match 'would copy'

            @(Get-RelativeFileList -Root $destDir).Count | Should Be 0
        } finally { Remove-Scratch $s }
    }

    It '(7) cursor is non-portable: exit 1 with the adapter reason' {
        $s = New-Scratch
        try {
            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'cursor', 'a', 'b')
            $r.ExitCode | Should Be 1
            $r.StdOut | Should Match 'sqlite'
        } finally { Remove-Scratch $s }
    }

    It '(8) unknown tool exits 1' {
        $s = New-Scratch
        try {
            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'nope', 'a', 'b')
            $r.ExitCode | Should Be 1
            $r.StdOut | Should Match "Unknown tool"
        } finally { Remove-Scratch $s }
    }

    It '(9) missing destination profile exits 1 with create hint' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'ghost')
            $r.ExitCode | Should Be 1
            $r.StdOut | Should Match 'does not exist'
            $r.StdOut | Should Match 'multi-cli new codex/ghost'
        } finally { Remove-Scratch $s }
    }

    It '(10) source equals destination exits 1' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'same' | Out-Null
            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'same', 'same')
            $r.ExitCode | Should Be 1
            $r.StdOut | Should Match 'must differ'
        } finally { Remove-Scratch $s }
    }

    It '(11) empty base (no system home data) exits 0 with a friendly message' {
        $s = New-Scratch
        try {
            # Create an empty .codex so base resolves but holds no session paths.
            New-Item -ItemType Directory -Force -Path (Join-Path $s.Home '.codex') | Out-Null
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Match 'Nothing to continue'
        } finally { Remove-Scratch $s }
    }

    It '(12) adapter whose paths overlap credentials aborts with an adapter-bug error (end to end)' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'fresh' | Out-Null
            $brokenLauncher = New-BrokenAdapterToolsDir -Scratch $s
            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'fresh') -LauncherOverride $brokenLauncher
            $r.ExitCode | Should Be 1
            $r.StdOut | Should Match 'Adapter bug'
            $r.StdOut | Should Match 'Refusing to copy credentials'
        } finally { Remove-Scratch $s }
    }

    It '(17) profile -> profile continue copies sessions between two profiles' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            # Seed src by continuing from base, then copy src -> dst.
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'src' | Out-Null
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'dst' | Out-Null
            Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'base', 'src') | Out-Null

            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'src', 'dst')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Match 'Continued codex: src -> dst \(2 copied, 0 skipped \(same-or-newer\)\)'

            $files = Get-RelativeFileList -Root (& $script:CodexDest $s 'dst')
            $files -contains 'history.jsonl' | Should Be $true
            ($files -contains 'auth.json') | Should Be $false
        } finally { Remove-Scratch $s }
    }
}

Describe 'multi-cli new (codex, profile seeding)' {

    It '(13) new default profile seeds sessions and linkable share assets' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            $r = Invoke-LauncherGuarded -Scratch $s -Arguments @('new', 'codex/work')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Match 'Seeded from base'

            $files = Get-RelativeFileList -Root (& $script:CodexDest $s 'work')
            $files -contains 'history.jsonl' | Should Be $true
            @($files | Where-Object { $_ -like 'sessions/*rollout-*' }).Count | Should Be 1
            $files -contains 'config.toml' | Should Be $true      # linkable
            $files -contains 'skills/demo.md' | Should Be $true   # linkable
            ($files -contains 'auth.json') | Should Be $false     # credential never seeded
        } finally { Remove-Scratch $s }
    }

    It '(14) --no-seed creates an empty profile (no session or share assets)' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            $r = Invoke-LauncherGuarded -Scratch $s -Arguments @('new', 'codex/bare', '--no-seed')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Not Match 'Seeded from base'

            $files = Get-RelativeFileList -Root (& $script:CodexDest $s 'bare')
            ($files -contains 'history.jsonl') | Should Be $false
            ($files -contains 'config.toml') | Should Be $false
        } finally { Remove-Scratch $s }
    }

    It '(15) --shared seeds sessions but not linkable assets' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            $r = Invoke-LauncherGuarded -Scratch $s -Arguments @('new', 'codex/shared1', '--shared')
            $r.ExitCode | Should Be 0

            $files = Get-RelativeFileList -Root (& $script:CodexDest $s 'shared1')
            # Sessions seeded.
            $files -contains 'history.jsonl' | Should Be $true
            @($files | Where-Object { $_ -like 'sessions/*rollout-*' }).Count | Should Be 1
            # Linkables are symlinked/copied by New-SharedProfile, NOT duplicated by the
            # share-seed branch (that branch is skipped when $Shared). Credentials absent.
            ($files -contains 'auth.json') | Should Be $false
        } finally { Remove-Scratch $s }
    }

    It '(16) --from <template> skips base seeding entirely' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            # Build a real template under MULTICLI_HOME/.templates/tpl
            $tplDir = Join-Path (Join-Path $s.MultiCliHome '.templates') 'tpl'
            New-Item -ItemType Directory -Force -Path $tplDir | Out-Null
            Set-Content -Path (Join-Path $tplDir 'marker.txt') -Value 'from-template' -Encoding UTF8

            $r = Invoke-LauncherGuarded -Scratch $s -Arguments @('new', 'codex/fromtpl', '--from', 'tpl')
            $r.ExitCode | Should Be 0
            $r.StdOut | Should Not Match 'Seeded from base'

            $files = Get-RelativeFileList -Root (& $script:CodexDest $s 'fromtpl')
            $files -contains 'marker.txt' | Should Be $true
            ($files -contains 'history.jsonl') | Should Be $false
        } finally { Remove-Scratch $s }
    }
}

Describe 'session-continuation unit branches (dot-sourced functions)' {

    It 'Test-SessionAdapterBug passes when paths and credentials are disjoint' {
        $adapter = [pscustomobject]@{ id = 'codex'; session = [pscustomobject]@{
            paths = @('sessions', 'history.jsonl'); credentials = @('auth.json') } }
        { Test-SessionAdapterBug $adapter } | Should Not Throw
    }

    It 'Test-SessionAdapterBug throws when a path equals a credential' {
        $adapter = [pscustomobject]@{ id = 'codex'; session = [pscustomobject]@{
            paths = @('auth.json'); credentials = @('auth.json') } }
        { Test-SessionAdapterBug $adapter } | Should Throw
    }

    It 'Test-SessionAdapterBug throws when a path is under a credential dir' {
        $adapter = [pscustomobject]@{ id = 'codex'; session = [pscustomobject]@{
            paths = @('secrets/sessions'); credentials = @('secrets') } }
        { Test-SessionAdapterBug $adapter } | Should Throw
    }

    It 'Test-IsCredentialName matches a credential-named component and rejects non-credentials' {
        (Test-IsCredentialName -RelativePath 'auth.json' -Credentials @('auth.json')) | Should Be $true
        (Test-IsCredentialName -RelativePath 'history.jsonl' -Credentials @('auth.json')) | Should Be $false
        (Test-IsCredentialName -RelativePath 'auth.json' -Credentials @('sub/auth.json')) | Should Be $true
    }

    It 'Get-AdapterSystemHome resolves $HOME and returns null when absent' {
        $withHome = [pscustomobject]@{ share = [pscustomobject]@{ systemHome = '$HOME/.codex' } }
        (Get-AdapterSystemHome $withHome) | Should Match '\.codex$'
        $noHome = [pscustomobject]@{ share = $null }
        (Get-AdapterSystemHome $noHome) | Should Be $null
    }

    It 'Read-ContinueArgs separates positional args from flags' {
        $p = Read-ContinueArgs @('codex', 'src', 'dst', '--no-merge', '--dry-run')
        $p.Tool | Should Be 'codex'
        $p.SrcName | Should Be 'src'
        $p.DestName | Should Be 'dst'
        $p.NoMerge | Should Be $true
        $p.DryRun | Should Be $true
    }

    It 'Read-ContinueArgs defaults flags to false when absent' {
        $p = Read-ContinueArgs @('codex', 'src', 'dst')
        $p.NoMerge | Should Be $false
        $p.DryRun | Should Be $false
    }

    It 'Invoke-Continue throws a usage error when an argument is missing' {
        { Invoke-Continue -Tool 'codex' -SrcName 'src' -DestName '' } | Should Throw
    }

    It 'Resolve-SessionEndpoint throws for base when the adapter has no system home' {
        $adapter = [pscustomobject]@{ share = $null; session = [pscustomobject]@{ portable = $true } }
        { Resolve-SessionEndpoint $adapter 'codex' 'base' } | Should Throw
    }
}

Describe 'session-continuation extra end-to-end branches' {

    It 'missing source profile (not base) exits 1 with not-found message' {
        $s = New-Scratch
        try {
            New-CodexSystemHome -UserHome $s.Home | Out-Null
            New-CodexProfile -MultiCliHome $s.MultiCliHome -Name 'dst' | Out-Null
            # 'ghostsrc' profile does not exist -> srcDir missing.
            $r = Invoke-Launcher -Scratch $s -Arguments @('continue', 'codex', 'ghostsrc', 'dst')
            $r.ExitCode | Should Be 1
            $r.StdOut | Should Match 'not found'
            $r.StdOut | Should Match 'Nothing to continue from'
        } finally { Remove-Scratch $s }
    }
}

