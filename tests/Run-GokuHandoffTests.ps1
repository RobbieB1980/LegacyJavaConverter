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

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('legacy goku handoff ' + [guid]::NewGuid().ToString('N'))
$portable = Join-Path $fixture 'portable bundle'
$tools = Join-Path $portable 'tools'
$workspace = Join-Path $fixture 'repair workspace'
$failedOutput = Join-Path $fixture 'failed output'
$gokuRoot = Join-Path $fixture 'fake goku'

try {
    New-Item -ItemType Directory -Path $tools, $workspace, $failedOutput -Force | Out-Null
    Copy-Item (Join-Path $repo 'scripts\Sync-GokuaiConverterWorkspace.ps1') $tools -Force
    Copy-Item (Join-Path $repo 'gokuai-workspace-overlay') $tools -Recurse -Force

    foreach ($name in @(
            'Convert-Forge1201-ToNeoForge262.ps1',
            'Convert-JarToProject.ps1',
            'Convert-OldJarToNeoForge262.ps1',
            'Open-GrokRepairSession.ps1',
            'Build-WithDestinationJava.ps1',
            'Lint-MigrationSkills.ps1'
        )) {
        Copy-Item (Join-Path $repo $name) $tools -Force
    }

    $lib = Join-Path $tools 'lib'
    $astWorker = Join-Path $lib 'ast-worker'
    New-Item -ItemType Directory -Path $astWorker -Force | Out-Null
    foreach ($name in @('ConversionCore.ps1', 'ConversionManifest.ps1', 'AstWorkerBridge.ps1', 'SolvedConversionIndex.json')) {
        Copy-Item (Join-Path $repo ('lib\' + $name)) $lib -Force
    }
    Set-Content -LiteralPath (Join-Path $astWorker 'legacy-java-ast-worker.jar') -Value 'fixture' -Encoding ASCII

    $staleSkill = Join-Path $workspace '.grok\skills\legacy-java-converter-vnext'
    New-Item -ItemType Directory -Path $staleSkill -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $staleSkill 'SKILL.md') -Value 'stale' -Encoding ASCII

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'Sync-GokuaiConverterWorkspace.ps1') -Workspace $workspace
    if ($LASTEXITCODE -ne 0) { throw "workspace synchronization failed with exit $LASTEXITCODE" }

    $vnextSkill = Join-Path $workspace '.grok\skills\legacy-java-converter-vnext\SKILL.md'
    Assert-True (Test-Path -LiteralPath $vnextSkill) 'vNext skill installed'
    $vnextText = Get-Content -LiteralPath $vnextSkill -Raw
    Assert-Contains $vnextText 'deterministic' 'stale vNext skill replaced'
    Assert-Contains $vnextText 'Target Minecraft/NeoForge 26.2 only' 'skill pins target 26.2'
    Assert-Contains $vnextText 'Solutions Index' 'skill requires persistent known solutions'
    Assert-Contains $vnextText 'JavaParser AST worker' 'skill routes structural Java changes through AST'
    Assert-Contains $vnextText 'assets/data/models/items/entities/AI/behaviour' 'skill requires content and behaviour preservation status'
    Assert-Contains $vnextText 'Never describe a clean build alone as a successful conversion' 'skill separates build from runtime success'
    Assert-Contains $vnextText 'Escalate only unresolved' 'skill delays Goku escalation'
    Assert-True (Test-Path -LiteralPath (Join-Path $workspace '.grok\skills\repair-failed-262-output\SKILL.md')) 'failed-output skill installed'
    Assert-True (Test-Path -LiteralPath (Join-Path $workspace 'Agents.md')) 'standing orders installed'
    Assert-True (Test-Path -LiteralPath (Join-Path $workspace 'tools\lib\ConversionManifest.ps1')) 'conversion manifest helper installed'
    Assert-True (Test-Path -LiteralPath (Join-Path $workspace 'tools\lib\AstWorkerBridge.ps1')) 'AST bridge installed'
    Assert-True (Test-Path -LiteralPath (Join-Path $workspace 'tools\lib\ast-worker\legacy-java-ast-worker.jar')) 'AST worker installed'

    $prompt = Get-GrokRepairPromptBody -FailedOutput $failedOutput -DestinationJavaMajor 25 -TargetMinecraft '26.2'
    Assert-Contains $prompt '/legacy-java-converter-vnext' 'repair prompt invokes vNext orchestration skill'
    Assert-Contains $prompt '/repair-failed-262-output' 'repair prompt invokes failed-output skill'
    Assert-True ($prompt.IndexOf('/legacy-java-converter-vnext') -lt $prompt.IndexOf('/repair-failed-262-output')) 'vNext skill precedes failed-output skill'

    New-Item -ItemType Directory -Path (Join-Path $gokuRoot 'runtime\mia-kit\.venv\Scripts'), (Join-Path $gokuRoot 'scripts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $gokuRoot 'Start-GokuAI.ps1') -Value "throw 'PrepareOnly should not launch GokuAI'" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $gokuRoot 'runtime\mia-kit\.venv\Scripts\python.exe') -Value 'fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $gokuRoot 'scripts\knowledge_mcp.py') -Value '# fixture' -Encoding ASCII

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'Open-GrokRepairSession.ps1') `
        -FailedOutput $failedOutput -GokuRoot $gokuRoot -Workspace $workspace -PrepareOnly
    if ($LASTEXITCODE -ne 0) { throw "prepare-only launcher failed with exit $LASTEXITCODE" }
    $writtenPrompt = Join-Path $failedOutput 'GROK_REPAIR_PROMPT.md'
    Assert-True (Test-Path -LiteralPath $writtenPrompt) 'prepare-only launcher writes repair prompt'
    Assert-Contains (Get-Content -LiteralPath $writtenPrompt -Raw) '/legacy-java-converter-vnext' 'prepared prompt carries vNext orchestration'
    Assert-True (Test-Path -LiteralPath (Join-Path $workspace '.grok\config.toml')) 'prepare-only launcher configures knowledge MCP'

    Remove-Item -LiteralPath (Join-Path $tools 'gokuai-workspace-overlay\.grok\skills\legacy-java-converter-vnext') -Recurse -Force
    $failedClosed = $false
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'Sync-GokuaiConverterWorkspace.ps1') -Workspace (Join-Path $fixture 'incomplete workspace') 2>$null
        $failedClosed = $LASTEXITCODE -ne 0
    }
    catch {
        $failedClosed = $true
    }
    Assert-True $failedClosed 'incomplete bundle fails closed'
}
finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}

Write-Host "Goku handoff tests passed: $script:passed" -ForegroundColor Green
