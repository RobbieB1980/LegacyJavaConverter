<#
.SYNOPSIS
  Synchronize the versioned Legacy Java Converter repair bundle into GokuAI.
.PARAMETER RepoRoot
  Optional repository root, portable root, or portable tools directory. When
  omitted, the script detects its repository or packaged location.
.PARAMETER Workspace
  Target GokuAI workspace.
.PARAMETER SkillsOnly
  Install only the overlay, standing orders, destination-Java helper, and lint.
  The failure launcher always uses a full synchronization.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$Workspace = 'C:\gokuai\projects\RB-Legacy-Java-Converter',
    [switch]$SkillsOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-ConverterBundle {
    param([string]$Root)

    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $candidates = New-Object Collections.Generic.List[string]
    if ($Root) { $candidates.Add([IO.Path]::GetFullPath($Root)) | Out-Null }
    $candidates.Add([IO.Path]::GetFullPath($here)) | Out-Null
    $candidates.Add([IO.Path]::GetFullPath((Join-Path $here '..'))) | Out-Null

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'gokuai-workspace-overlay\.grok')) {
            $isRepository = Test-Path -LiteralPath (Join-Path $candidate 'scripts\Sync-GokuaiConverterWorkspace.ps1')
            return [pscustomobject]@{
                Root = $candidate
                ToolRoot = $candidate
                Overlay = Join-Path $candidate 'gokuai-workspace-overlay'
                Repository = $isRepository
            }
        }

        $portableTools = Join-Path $candidate 'tools'
        if (Test-Path -LiteralPath (Join-Path $portableTools 'gokuai-workspace-overlay\.grok')) {
            return [pscustomobject]@{
                Root = $candidate
                ToolRoot = $portableTools
                Overlay = Join-Path $portableTools 'gokuai-workspace-overlay'
                Repository = $false
            }
        }
    }

    throw 'Converter repair bundle not found. Expected gokuai-workspace-overlay beside the sync script or under tools.'
}

function Copy-TreeChecked([string]$Source, [string]$Destination, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Missing $Label source: $Source" }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & robocopy.exe $Source $Destination /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "robocopy $Label failed: $LASTEXITCODE" }
}

function Assert-RequiredFile([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing $Description`: $Path" }
}

$bundle = Resolve-ConverterBundle -Root $RepoRoot
$overlay = $bundle.Overlay
$toolRoot = $bundle.ToolRoot
$grokSrc = Join-Path $overlay '.grok'
$vnextSource = Join-Path $grokSrc 'skills\legacy-java-converter-vnext\SKILL.md'
$repairSource = Join-Path $grokSrc 'skills\repair-failed-262-output\SKILL.md'

Assert-RequiredFile $vnextSource 'vNext orchestration skill'
Assert-RequiredFile $repairSource 'failed-output repair skill'
Assert-RequiredFile (Join-Path $overlay 'Agents.md') 'GokuAI standing orders'

$sourceLib = if ($bundle.Repository) { Join-Path $bundle.Root 'lib' } else { Join-Path $toolRoot 'lib' }
$sourceAstWorker = if ($bundle.Repository) { Join-Path $bundle.Root 'tools\lib\ast-worker' } else { Join-Path $sourceLib 'ast-worker' }
if (-not $SkillsOnly) {
    foreach ($required in @('ConversionCore.ps1', 'ConversionManifest.ps1', 'AstWorkerBridge.ps1', 'SolvedConversionIndex.json')) {
        Assert-RequiredFile (Join-Path $sourceLib $required) "repair library $required"
    }
    if (-not (Get-ChildItem -LiteralPath $sourceAstWorker -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        throw "Missing JavaParser AST worker runtime: $sourceAstWorker"
    }
}

New-Item -ItemType Directory -Path $Workspace -Force | Out-Null
Write-Host ("==> Syncing versioned repair bundle -> {0}" -f $Workspace) -ForegroundColor Cyan
Copy-TreeChecked -Source $grokSrc -Destination (Join-Path $Workspace '.grok') -Label '.grok overlay'
Copy-Item -LiteralPath (Join-Path $overlay 'Agents.md') -Destination (Join-Path $Workspace 'Agents.md') -Force

$toolsDst = Join-Path $Workspace 'tools'
New-Item -ItemType Directory -Path $toolsDst -Force | Out-Null

$scriptNames = @(
    'Build-WithDestinationJava.ps1',
    'Lint-MigrationSkills.ps1'
)
if (-not $SkillsOnly) {
    $scriptNames += @(
        'Convert-Forge1201-ToNeoForge262.ps1',
        'Convert-JarToProject.ps1',
        'Convert-OldJarToNeoForge262.ps1',
        'Open-GrokRepairSession.ps1',
        'Sync-GokuaiConverterWorkspace.ps1'
    )
}

foreach ($name in $scriptNames) {
    $sourceCandidates = @(
        (Join-Path $toolRoot $name),
        (Join-Path $overlay ('tools\' + $name))
    )
    if ($bundle.Repository) { $sourceCandidates += Join-Path $bundle.Root ('scripts\' + $name) }
    $source = $sourceCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $source) { throw "Missing required repair tool: $name" }
    $destination = Join-Path $toolsDst $name
    if (-not [string]::Equals([IO.Path]::GetFullPath($source), [IO.Path]::GetFullPath($destination), [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
}

if (-not $SkillsOnly) {
    $libDestination = Join-Path $toolsDst 'lib'
    Copy-TreeChecked -Source $sourceLib -Destination $libDestination -Label 'repair libraries'
    if ($bundle.Repository) {
        Copy-TreeChecked -Source $sourceAstWorker -Destination (Join-Path $libDestination 'ast-worker') -Label 'AST worker'
    }
}

$requiredDestinations = @(
    (Join-Path $Workspace '.grok\skills\legacy-java-converter-vnext\SKILL.md'),
    (Join-Path $Workspace '.grok\skills\repair-failed-262-output\SKILL.md'),
    (Join-Path $Workspace 'Agents.md'),
    (Join-Path $toolsDst 'Build-WithDestinationJava.ps1'),
    (Join-Path $toolsDst 'Lint-MigrationSkills.ps1')
)
if (-not $SkillsOnly) {
    $requiredDestinations += @(
        (Join-Path $toolsDst 'lib\ConversionManifest.ps1'),
        (Join-Path $toolsDst 'lib\AstWorkerBridge.ps1')
    )
}
foreach ($required in $requiredDestinations) { Assert-RequiredFile $required 'synchronized repair component' }
if (-not $SkillsOnly -and -not (Get-ChildItem -LiteralPath (Join-Path $toolsDst 'lib\ast-worker') -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    throw 'Synchronized repair workspace has no JavaParser AST worker runtime.'
}

$mode = if ($SkillsOnly) { 'skills-only' } else { 'full' }
Write-Host "OK: versioned repair bundle synchronized and verified ($mode)." -ForegroundColor Green
