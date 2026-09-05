<#
.SYNOPSIS
  Sync Fix-in-Grok migration skills/agents/workflows into a GokuAI workspace.
.PARAMETER Workspace
  Target workspace folder (default: RB-Legacy-Java-Converter project).
.PARAMETER SkillsOnly
  Copy .grok + Agents.md + Build-WithDestinationJava/Lint only (for arbitrary/new workspaces).
  Without this switch, also refreshes full converter tools/lib into the workspace.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$Workspace = 'C:\gokuai\projects\RB-Legacy-Java-Converter',
    [switch]$SkillsOnly
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) {
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $RepoRoot = (Resolve-Path (Join-Path $here '..')).Path
}

$overlay = Join-Path $RepoRoot 'gokuai-workspace-overlay'
$fallbackGrok = 'C:\gokuai\projects\RB-Legacy-Java-Converter\.grok'

if (-not (Test-Path -LiteralPath $Workspace)) {
    New-Item -ItemType Directory -Path $Workspace -Force | Out-Null
}

$grokSrc = $null
if (Test-Path (Join-Path $overlay '.grok')) {
    $grokSrc = Join-Path $overlay '.grok'
} elseif (Test-Path -LiteralPath $fallbackGrok) {
    $grokSrc = $fallbackGrok
} else {
    throw "No migration overlay found at $overlay or $fallbackGrok"
}

Write-Host ("==> Syncing migration skills -> {0}" -f $Workspace) -ForegroundColor Cyan
& robocopy.exe $grokSrc (Join-Path $Workspace '.grok') /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -gt 7) { throw "robocopy .grok failed: $LASTEXITCODE" }

$agentsSrc = Join-Path $overlay 'Agents.md'
if (-not (Test-Path $agentsSrc)) {
    $agentsSrc = 'C:\gokuai\projects\RB-Legacy-Java-Converter\Agents.md'
}
if (Test-Path $agentsSrc) {
    Copy-Item $agentsSrc (Join-Path $Workspace 'Agents.md') -Force
}

$toolsDst = Join-Path $Workspace 'tools'
if (-not (Test-Path $toolsDst)) { New-Item -ItemType Directory -Path $toolsDst -Force | Out-Null }

# Always seed destination-Java helper + lint from overlay or converter tools
foreach ($pair in @(
        @{ Src = Join-Path $overlay 'tools\Build-WithDestinationJava.ps1'; Name = 'Build-WithDestinationJava.ps1' },
        @{ Src = Join-Path $overlay 'tools\Lint-MigrationSkills.ps1'; Name = 'Lint-MigrationSkills.ps1' },
        @{ Src = Join-Path $RepoRoot 'Build-WithDestinationJava.ps1'; Name = 'Build-WithDestinationJava.ps1' },
        @{ Src = Join-Path $RepoRoot 'Lint-MigrationSkills.ps1'; Name = 'Lint-MigrationSkills.ps1' },
        @{ Src = 'C:\gokuai\projects\RB-Legacy-Java-Converter\tools\Build-WithDestinationJava.ps1'; Name = 'Build-WithDestinationJava.ps1' },
        @{ Src = 'C:\gokuai\projects\RB-Legacy-Java-Converter\tools\Lint-MigrationSkills.ps1'; Name = 'Lint-MigrationSkills.ps1' }
    )) {
    if (Test-Path -LiteralPath $pair.Src) {
        $dest = Join-Path $toolsDst $pair.Name
        $srcFull = [IO.Path]::GetFullPath($pair.Src)
        $dstFull = [IO.Path]::GetFullPath($dest)
        if (-not [string]::Equals($srcFull, $dstFull, [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item $pair.Src $dest -Force
        }
    }
}

if (-not $SkillsOnly) {
    $toolsSrc = Join-Path $overlay 'tools'
    if (Test-Path $toolsSrc) {
        Copy-Item (Join-Path $toolsSrc '*') $toolsDst -Force
    }
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
}

Write-Host ("OK: migration skills synced ({0})." -f $(if ($SkillsOnly) { 'skills-only' } else { 'full' })) -ForegroundColor Green
