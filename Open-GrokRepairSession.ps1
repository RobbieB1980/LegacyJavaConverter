<#
.SYNOPSIS
  Thin wrapper: launch GokuAI GrokBuild repair for a failed converter output.
.EXAMPLE
  .\Open-GrokRepairSession.ps1 -FailedOutput "C:\mods\mymod-26.2"
#>
param(
  [Parameter(Mandatory)][string]$FailedOutput,
  [string]$GokuRoot = 'C:\gokuai',
  [string]$Workspace = 'C:\gokuai\projects\RB-Legacy-Java-Converter'
)
$ErrorActionPreference = 'Stop'
$start = Join-Path $GokuRoot 'Start-GokuAI.ps1'
if (-not (Test-Path $start)) { throw "Missing $start — install/update GokuAI first." }
if (-not (Test-Path $FailedOutput)) { throw "Failed output missing: $FailedOutput" }
$prompt = Join-Path $FailedOutput 'GROK_REPAIR_PROMPT.md'
if (-not (Test-Path $prompt)) {
  @"
Repair failed converter output: $FailedOutput
Read MIGRATION_EVIDENCE.md, SOURCE_PROFILE.json, compile-errors.log, then primer_changes + CASE files BEFORE inventing fixes.
"@ | Set-Content $prompt -Encoding utf8
}
& $start -ProjectPath $Workspace -Root $GokuRoot -PromptFile $prompt
