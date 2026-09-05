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

. (Join-Path $PSScriptRoot 'lib\ConversionCore.ps1')
# Always refresh the prompt + destination JDK pin so agents never start on ambient Java 8.
$prompt = Write-GrokRepairPrompt -FailedOutput $FailedOutput -DestinationJavaMajor 25 -TargetMinecraft '26.2'
Write-Host "Wrote repair prompt + destination Java pin: $prompt" -ForegroundColor Cyan

& $start -ProjectPath $Workspace -Root $GokuRoot -PromptFile $prompt
