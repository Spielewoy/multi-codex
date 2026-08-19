param(
    [string]$ToolsRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'ai-tools')
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\MultiCli.AdapterValidation.psm1'
Import-Module $modulePath -Force

$manifests = @(
    Get-ChildItem -LiteralPath $ToolsRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $manifest = Join-Path $_.FullName 'adapter.json'
            if (Test-Path -LiteralPath $manifest -PathType Leaf) { $manifest }
        }
)

if ($manifests.Count -eq 0) {
    Write-Error "No adapters found under $ToolsRoot"
    exit 1
}

$hasErrors = $false
foreach ($manifest in $manifests) {
    $expectedId = Split-Path (Split-Path $manifest -Parent) -Leaf
    $errors = @(Test-AdapterManifest -ManifestPath $manifest -ExpectedId $expectedId)
    foreach ($validationError in $errors) {
        [Console]::Error.WriteLine("${manifest}: $validationError")
        $hasErrors = $true
    }
}

if ($hasErrors) { exit 1 }
Write-Host "Validated $($manifests.Count) adapter(s)."
