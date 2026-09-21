<#
.SYNOPSIS
  Deprecated compatibility entry that forwards failed repairs to native Codex.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FailedOutput,
    [string]$GokuRoot = 'C:\GokuCodexAI',
    [string]$Workspace,
    [string]$CodexPath,
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
Write-Warning 'Open-GrokRepairSession.ps1 is deprecated; using Open-CodexRepairSession.ps1.'
$native = Join-Path $PSScriptRoot 'Open-CodexRepairSession.ps1'
if (-not (Test-Path -LiteralPath $native -PathType Leaf)) {
    throw "Native repair launcher missing: $native"
}
$arguments = @{
    FailedOutput = $FailedOutput
    GokuRoot = $GokuRoot
    PrepareOnly = $PrepareOnly
}
if ($CodexPath) { $arguments.CodexPath = $CodexPath }
& $native @arguments
exit $LASTEXITCODE
