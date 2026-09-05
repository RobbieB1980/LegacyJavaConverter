<#
.SYNOPSIS
  Sync Fix-in-Grok workspace overlay (skills/agents/workflows/rules) into C:\gokuai\projects\RB-Legacy-Java-Converter.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$Workspace = 'C:\gokuai\projects\RB-Legacy-Java-Converter'
)

$ErrorActionPreference = 'Stop'
$overlay = Join-Path $RepoRoot 'gokuai-workspace-overlay'
if (-not (Test-Path -LiteralPath $overlay)) { throw "Missing overlay: $overlay" }
if (-not (Test-Path -LiteralPath $Workspace)) {
    New-Item -ItemType Directory -Path $Workspace -Force | Out-Null
}

Write-Host "==> Syncing overlay -> $Workspace" -ForegroundColor Cyan
& robocopy.exe (Join-Path $overlay '.grok') (Join-Path $Workspace '.grok') /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -gt 7) { throw "robocopy .grok failed: $LASTEXITCODE" }

if (Test-Path (Join-Path $overlay 'Agents.md')) {
    Copy-Item (Join-Path $overlay 'Agents.md') (Join-Path $Workspace 'Agents.md') -Force
}

$toolsSrc = Join-Path $overlay 'tools'
$toolsDst = Join-Path $Workspace 'tools'
if (Test-Path $toolsSrc) {
    if (-not (Test-Path $toolsDst)) { New-Item -ItemType Directory -Path $toolsDst -Force | Out-Null }
    Copy-Item (Join-Path $toolsSrc '*') $toolsDst -Force
}

# Also refresh converter scripts from packaging repo root into workspace tools/
foreach ($s in @(
        'Convert-Forge1201-ToNeoForge262.ps1',
        'Convert-JarToProject.ps1',
        'Convert-OldJarToNeoForge262.ps1',
        'Open-GrokRepairSession.ps1',
        'Build-WithDestinationJava.ps1',
        'Lint-MigrationSkills.ps1',
        'CHANGELOG.md'
    )) {
    $src = Join-Path $RepoRoot $s
    if (Test-Path $src) { Copy-Item $src (Join-Path $toolsDst $s) -Force }
}
if (Test-Path (Join-Path $RepoRoot 'lib')) {
    & robocopy.exe (Join-Path $RepoRoot 'lib') (Join-Path $toolsDst 'lib') /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "robocopy lib failed: $LASTEXITCODE" }
}

Write-Host "OK: Fix-in-Grok workspace updated." -ForegroundColor Green
