$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:ExpectedToolIds = @(
    'agy-cli', 'antigravity', 'claude-cli', 'codex', 'codex-gui', 'commandcode',
    'copilot-cli', 'copilot-vscode', 'cursor', 'cursor-cli', 'gemini-cli', 'grok-cli',
    'kimi-cli', 'kiro', 'opencode', 'windsurf', 'zed'
)

function Invoke-RepositoryLauncherTools {
    $launcher = Join-Path $script:RepoRoot 'multi-cli.ps1'
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = (Get-Command powershell.exe).Source
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`" tools"
    $startInfo.WorkingDirectory = $script:RepoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    [void]$startInfo.EnvironmentVariables.Remove('MULTICLI_TOOLS_DIR')
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = "$stdout$stderr" }
}

Describe 'repository AI-tool layout' {
    It 'stores every production adapter under ai-tools and none at the repository root' {
        $toolsRoot = Join-Path $script:RepoRoot 'ai-tools'
        (Test-Path -LiteralPath $toolsRoot -PathType Container) | Should Be $true

        $actualIds = @(
            Get-ChildItem -LiteralPath $toolsRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'adapter.json') -PathType Leaf } |
                Select-Object -ExpandProperty Name |
                Sort-Object
        )
        ($actualIds -join ',') | Should Be (($script:ExpectedToolIds | Sort-Object) -join ',')

        foreach ($toolId in $script:ExpectedToolIds) {
            (Test-Path -LiteralPath (Join-Path $script:RepoRoot "$toolId\adapter.json")) | Should Be $false
        }
    }

    It 'discovers all nested adapters with the repository launcher default' {
        $result = Invoke-RepositoryLauncherTools
        $result.ExitCode | Should Be 0
        foreach ($toolId in $script:ExpectedToolIds) {
            $result.Output | Should Match "(?m)^\s+$([regex]::Escape($toolId))\s"
        }
    }
}
