<#
.SYNOPSIS
  Thin wrapper: launch GokuAI GrokBuild repair for a failed converter output.
  Refreshes knowledge wiring + ensures minecraft-knowledge MCP before start.
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
$grokHome = Join-Path $GokuRoot 'grok-home'
$grok = Join-Path $grokHome 'bin\grok.exe'
if (-not (Test-Path $start)) { throw "Missing $start — install/update GokuAI first." }
if (-not (Test-Path $FailedOutput)) { throw "Failed output missing: $FailedOutput" }

. (Join-Path $PSScriptRoot 'lib\ConversionCore.ps1')

$python = Join-Path $GokuRoot 'runtime\mia-kit\.venv\Scripts\python.exe'
$mcpScript = Join-Path $GokuRoot 'scripts\knowledge_mcp.py'
$knowledgeDb = Join-Path $GokuRoot 'DataIndex\minecraft-knowledge\knowledge.db'
$dataRoot = Join-Path $GokuRoot 'Data'
if (-not (Test-Path -LiteralPath $python)) { throw "Python missing for knowledge MCP: $python" }
if (-not (Test-Path -LiteralPath $mcpScript)) { throw "knowledge_mcp.py missing: $mcpScript" }

$env:GROK_HOME = $grokHome

# Prefer official project-scope registration; fall back to writing .grok/config.toml.
if (Test-Path -LiteralPath $grok) {
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  Push-Location $Workspace
  try {
    & $grok mcp remove minecraft-knowledge -s project 2>$null | Out-Null
    & $grok mcp add minecraft-knowledge -s project -- $python $mcpScript --db $knowledgeDb --root $dataRoot
    if ($LASTEXITCODE -ne 0) { throw "grok mcp add -s project failed with exit $LASTEXITCODE" }
  } finally {
    Pop-Location
    $ErrorActionPreference = $prevEap
  }
  Write-Host "Registered project MCP minecraft-knowledge" -ForegroundColor Cyan
} else {
  $projectGrokConfig = Join-Path $Workspace '.grok\config.toml'
  $mcpToml = @"
[mcp]
max_output_bytes = 20000

[mcp_servers.minecraft-knowledge]
command = '$python'
args = [
    '$mcpScript',
    "--db",
    '$knowledgeDb',
    "--root",
    '$dataRoot',
]
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 600
"@
  $grokDir = Split-Path -Parent $projectGrokConfig
  if (-not (Test-Path -LiteralPath $grokDir)) { New-Item -ItemType Directory -Path $grokDir | Out-Null }
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($projectGrokConfig, $mcpToml.TrimEnd() + "`r`n", $utf8NoBom)
  Write-Host "Wrote project MCP config: $projectGrokConfig" -ForegroundColor Cyan
}

# Refresh structured knowledge context (JSON). Keep hand-tuned .grok/rules/*.md intact.
$wire = Join-Path $GokuRoot 'Update-ProjectKnowledgeWiring.ps1'
if (Test-Path -LiteralPath $wire) {
  $rulesDir = Join-Path $Workspace '.grok\rules'
  $snapshots = @{}
  foreach ($name in @('knowledge-sources.md', 'session-knowledge-context.md', 'knowledge-read-allowlist.md')) {
    $path = Join-Path $rulesDir $name
    if (Test-Path -LiteralPath $path) { $snapshots[$name] = Get-Content -LiteralPath $path -Raw -Encoding UTF8 }
  }
  & $wire -ProjectPath $Workspace -Root $GokuRoot
  if ($LASTEXITCODE -ne 0) { throw "Knowledge wiring refresh failed with exit $LASTEXITCODE" }
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  foreach ($name in $snapshots.Keys) {
    $path = Join-Path $rulesDir $name
    [IO.File]::WriteAllText($path, $snapshots[$name], $utf8NoBom)
  }
  Write-Host "Refreshed knowledge-context.json; preserved converter-tuned rules." -ForegroundColor Cyan
}

# Always refresh the prompt + destination JDK pin so agents never start on ambient Java 8.
$prompt = Write-GrokRepairPrompt -FailedOutput $FailedOutput -DestinationJavaMajor 25 -TargetMinecraft '26.2'
Write-Host "Wrote repair prompt + destination Java pin: $prompt" -ForegroundColor Cyan

& $start -ProjectPath $Workspace -Root $GokuRoot -PromptFile $prompt
