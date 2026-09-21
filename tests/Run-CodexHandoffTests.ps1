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
function Assert-FileDoesNotContain([string]$Path, [string]$Unexpected, [string]$Name) {
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "$Name file exists"
    Assert-NotContains (Get-Content -LiteralPath $Path -Raw) $Unexpected $Name
}
function Get-TreeHash([string]$Path) {
    return @(
        Get-ChildItem -LiteralPath $Path -Recurse -File |
            Sort-Object FullName |
            ForEach-Object { '{0}:{1}' -f $_.FullName.Substring($Path.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    ) -join "`n"
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('legacy codex handoff ' + [guid]::NewGuid().ToString('N'))
try {
    $overlay = Join-Path $repo 'gokuai-workspace-overlay'
    Assert-True (Test-Path -LiteralPath (Join-Path $overlay 'AGENTS.md')) 'native root guidance'
    Assert-True (Test-Path -LiteralPath (Join-Path $overlay '.agents\skills\legacy-java-converter-vnext\SKILL.md')) 'vNext skill'
    Assert-True (Test-Path -LiteralPath (Join-Path $overlay '.agents\skills\repair-failed-262-output\SKILL.md')) 'repair skill'
    Assert-True (Test-Path -LiteralPath (Join-Path $overlay '.codex\config.toml')) 'project MCP config'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $overlay '.grok'))) 'legacy overlay removed'

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

    $workspace = Join-Path $fixture 'repair workspace'
    $sentinel = Join-Path $workspace 'src\main\java\UserFile.java'
    New-Item -ItemType Directory -Path (Split-Path -Parent $sentinel) -Force | Out-Null
    Set-Content -LiteralPath $sentinel -Value 'class UserFile {}' -Encoding UTF8
    $gokuRoot = Join-Path $fixture 'fake GokuCodexAI'
    New-Item -ItemType Directory -Path (Join-Path $gokuRoot 'runtime\python-mcp\Scripts'), (Join-Path $gokuRoot 'scripts'), (Join-Path $gokuRoot 'Data'), (Join-Path $gokuRoot 'DataIndex\minecraft-knowledge-local') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $gokuRoot 'runtime\python-mcp\Scripts\python.exe') -Value 'fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $gokuRoot 'scripts\knowledge_mcp.py') -Value '# fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $gokuRoot 'DataIndex\minecraft-knowledge-local\knowledge.test.db') -Value 'fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $gokuRoot 'DataIndex\minecraft-knowledge-local\_ACTIVE_DB.txt') -Value 'knowledge.test.db' -Encoding ASCII

    $sync = Join-Path $repo 'scripts\Sync-CodexConverterWorkspace.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sync -RepoRoot $repo -Workspace $workspace -GokuRoot $gokuRoot -PrepareOnly
    if ($LASTEXITCODE -ne 0) { throw "native workspace synchronization failed with exit $LASTEXITCODE" }
    Assert-True (Test-Path -LiteralPath (Join-Path $workspace 'AGENTS.md')) 'guidance synced'
    Assert-True (Test-Path -LiteralPath (Join-Path $workspace '.agents\skills\legacy-java-converter-vnext\SKILL.md')) 'skill synced'
    Assert-True (Test-Path -LiteralPath (Join-Path $workspace '.codex\config.toml')) 'MCP config synced'
    Assert-True (Test-Path -LiteralPath $sentinel) 'user file preserved'
    Assert-FileDoesNotContain (Join-Path $workspace '.codex\config.toml') '__GOKU_' 'Goku placeholders resolved'
    Assert-FileDoesNotContain (Join-Path $workspace '.codex\config.toml') '__KNOWLEDGE_' 'knowledge placeholders resolved'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $workspace '.grok'))) 'legacy discovery not created'
    $firstHash = Get-TreeHash $workspace
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sync -RepoRoot $repo -Workspace $workspace -GokuRoot $gokuRoot -PrepareOnly
    if ($LASTEXITCODE -ne 0) { throw "second native workspace synchronization failed with exit $LASTEXITCODE" }
    Assert-Equal (Get-TreeHash $workspace) $firstHash 'workspace synchronization is idempotent'

    $compatSync = Join-Path $repo 'scripts\Sync-GokuaiConverterWorkspace.ps1'
    $compatOutput = (& powershell -NoProfile -ExecutionPolicy Bypass -File $compatSync -RepoRoot $repo -Workspace $workspace -GokuRoot $gokuRoot -SkillsOnly -PrepareOnly 3>&1 | Out-String)
    Assert-True ($LASTEXITCODE -eq 0) 'compatibility sync forwards successfully'
    Assert-Contains $compatOutput 'deprecated' 'compatibility sync warns'

    $staleOverlay = Join-Path $fixture 'stale overlay'
    Copy-Item -LiteralPath $overlay -Destination $staleOverlay -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $staleOverlay '.agents\skills\legacy-java-converter-vnext\SKILL.md') -Force
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $failureOutput = (& powershell -NoProfile -ExecutionPolicy Bypass -File $sync -RepoRoot $repo -OverlayRoot $staleOverlay -Workspace (Join-Path $fixture 'incomplete workspace') -GokuRoot $gokuRoot -PrepareOnly 2>&1 | Out-String)
        $failureExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    Assert-True ($failureExitCode -ne 0) 'incomplete native overlay fails closed'
    Assert-Contains $failureOutput '.agents\skills\legacy-java-converter-vnext\SKILL.md' 'missing native file identified'
}
finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}

Write-Host "Codex handoff tests passed: $script:passed" -ForegroundColor Green
