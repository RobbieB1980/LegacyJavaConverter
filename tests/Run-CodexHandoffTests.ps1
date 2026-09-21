[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\ConversionCore.ps1')

$script:passed = 0
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "${Name}: condition was false" }
    $script:passed++
}
function Assert-Contains([string]$Text, [string]$Expected, [string]$Name) {
    if (-not $Text.Contains($Expected)) { throw "${Name}: missing [$Expected]" }
    $script:passed++
}
function Assert-NotContains([string]$Text, [string]$Unexpected, [string]$Name) {
    if ($Text.Contains($Unexpected)) { throw "${Name}: unexpectedly contained [$Unexpected]" }
    $script:passed++
}
function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -ne $Expected) { throw "${Name}: expected [$Expected], got [$Actual]" }
    $script:passed++
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('legacy codex handoff ' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    $body = Get-CodexRepairRequestBody -FailedOutput $fixture -DestinationJavaMajor 25 -TargetMinecraft '26.2'
    Assert-Contains $body 'Codex is the repair orchestrator' 'orchestrator authority'
    Assert-Contains $body 'legacy-java-converter-vnext' 'native vNext skill'
    Assert-Contains $body '.agents/skills' 'native repository skill location'
    Assert-Contains $body '.codex/config.toml' 'native MCP configuration'
    Assert-Contains $body 'Solutions Index' 'known solution stage'
    Assert-Contains $body 'Build-WithDestinationJava.ps1' 'destination Java build'
    Assert-Contains $body 'runtime' 'runtime validation remains separate'
    Assert-Contains $body 'assets, models, items, entities, AI, and behaviour' 'preservation scope'
    Assert-NotContains $body 'GROK_HOME' 'no Grok environment'
    Assert-NotContains $body '.grok/' 'no Grok project configuration'

    $request = Write-CodexRepairRequest -FailedOutput $fixture -DestinationJavaMajor 25 -TargetMinecraft '26.2'
    Assert-Equal (Split-Path -Leaf $request) 'CODEX_REPAIR_REQUEST.md' 'native request filename'
    Assert-True (Test-Path -LiteralPath $request -PathType Leaf) 'native request written'
    Assert-Contains (Get-Content -LiteralPath $request -Raw) 'Codex is the repair orchestrator' 'written request content'
}
finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}

Write-Host "Codex handoff tests passed: $script:passed" -ForegroundColor Green
