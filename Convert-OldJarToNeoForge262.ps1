<#
.SYNOPSIS
  Full pipeline: finished .jar - decompile - NeoForge 26.2 scaffold.

.DESCRIPTION
  1) Convert-JarToProject.ps1  (Vineflower decompile + src layout)
  2) Convert-Forge1201-ToNeoForge262.ps1  (Gradle 26.2 + rewrites)

.EXAMPLE
  .\Convert-OldJarToNeoForge262.ps1 -JarPath "D:\mods\old.jar" -OutputPath "D:\mods\old-26.2"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$JarPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$DecompilePath = '',
    [string]$MinecraftVersion = '26.2',
    [string]$NeoVersion = '26.2.0.32-beta',
    [string]$GeckoLibVersion = '5.5.3',
    [switch]$Compile,
    [switch]$KeepDecompile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ToolRoot = $PSScriptRoot
$jarScript = Join-Path $ToolRoot 'Convert-JarToProject.ps1'
$convScript = Join-Path $ToolRoot 'Convert-Forge1201-ToNeoForge262.ps1'
if (-not (Test-Path $jarScript)) { throw "Missing $jarScript" }
if (-not (Test-Path $convScript)) { throw "Missing $convScript" }

$JarPath = (Resolve-Path -LiteralPath $JarPath).Path
if (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path (Get-Location) $OutputPath
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

if (-not $DecompilePath) {
    $base = [IO.Path]::GetFileNameWithoutExtension($JarPath)
    $parent = Split-Path $OutputPath -Parent
    if (-not $parent) { $parent = Get-Location }
    $DecompilePath = Join-Path $parent ($base + '-decompiled')
}
if (-not [IO.Path]::IsPathRooted($DecompilePath)) {
    $DecompilePath = Join-Path (Get-Location) $DecompilePath
}
$DecompilePath = [IO.Path]::GetFullPath($DecompilePath)

Write-Host ''
Write-Host 'RB Old JAR - NeoForge 26.2 (full pipeline)' -ForegroundColor White
Write-Host "  Jar       : $JarPath"
Write-Host "  Decompile : $DecompilePath"
Write-Host "  Final 26.2: $OutputPath"

if ($DryRun) {
    Write-Host 'Dry run: would decompile then convert.' -ForegroundColor Yellow
    & $jarScript -JarPath $JarPath -OutputPath $DecompilePath -DryRun
    return
}

& $jarScript -JarPath $JarPath -OutputPath $DecompilePath -MinecraftVersion $MinecraftVersion -NeoVersion $NeoVersion

$cargs = @{
    Path             = $DecompilePath
    OutputPath       = $OutputPath
    MinecraftVersion = $MinecraftVersion
    NeoVersion       = $NeoVersion
    GeckoLibVersion  = $GeckoLibVersion
}
if ($Compile) {
    & $convScript @cargs -Compile
}
else {
    & $convScript @cargs
}

if (-not $KeepDecompile) {
    Write-Host "==> Intermediate decompile kept at: $DecompilePath" -ForegroundColor Cyan
    Write-Host "    (pass -KeepDecompile is default keep; delete manually if desired)" -ForegroundColor DarkGray
}

Write-Host ''
Write-Host "Pipeline complete." -ForegroundColor Green
Write-Host "  Decompiled project : $DecompilePath"
Write-Host "  NeoForge 26.2      : $OutputPath"
