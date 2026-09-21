[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\ConversionManifest.ps1')

$script:passed = 0
function Assert-Equal([object]$Actual, [object]$Expected, [string]$Name) {
    if ([string]$Actual -cne [string]$Expected) { throw "${Name}: expected [$Expected], got [$Actual]" }
    $script:passed++
}
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "${Name}: condition was false" }
    $script:passed++
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Name) {
    try { & $Action; throw "${Name}: action did not throw" }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw "${Name}: wrong error [$($_.Exception.Message)]" }
        $script:passed++
    }
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('legacy-manifest-test-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    $input = Join-Path $fixture 'input.jar'
    [IO.File]::WriteAllText($input, 'hello', [Text.UTF8Encoding]::new($false))

    $manifest = New-ConversionManifest -InputPath $input -TargetMinecraft '26.2' -TargetNeoForge '26.2.0.72' -ConverterVersion '2.11.0'
    Assert-Equal $manifest.schemaVersion 1 'manifest schema version'
    Assert-Equal $manifest.input.files.Count 1 'manifest input file count'
    Assert-Equal $manifest.input.files[0].path 'input.jar' 'manifest forward-relative input path'
    Assert-Equal $manifest.input.files[0].sha256 '2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824' 'manifest literal SHA-256'
    Assert-Equal $manifest.target.minecraft '26.2' 'manifest target Minecraft'
    Assert-Equal $manifest.target.neoforge '26.2.0.72' 'manifest target NeoForge'
    Assert-Equal $manifest.rules.Count 0 'manifest starts without rules'
    foreach ($stage in @('intake','deterministic','javaParsed','built','clientBooted','worldLoaded','contentSmokeTested')) {
        Assert-Equal $manifest.validation[$stage].status 'notRun' "manifest stage $stage starts notRun"
    }

    Add-ManifestRule -Manifest $manifest -RuleId 'rule-b' -Files @('z/File.java','a/File.java') -Evidence 'fixture:B'
    Add-ManifestRule -Manifest $manifest -RuleId 'rule-a' -Files @('b/File.java') -Evidence 'fixture:A'
    Add-ManifestRule -Manifest $manifest -RuleId 'rule-a' -Files @('b/File.java') -Evidence 'fixture:A'
    Assert-Equal $manifest.rules.Count 2 'identical duplicate rule is a no-op'
    Assert-Throws { Add-ManifestRule -Manifest $manifest -RuleId 'rule-a' -Files @('other.java') -Evidence 'fixture:A' } 'conflicting duplicate rule' 'conflicting rule files rejected'
    Assert-Throws { Add-ManifestRule -Manifest $manifest -RuleId 'rule-a' -Files @('b/File.java') -Evidence 'other evidence' } 'conflicting duplicate rule' 'conflicting rule evidence rejected'

    Assert-Throws { Set-ManifestValidation -Manifest $manifest -Stage 'built' -Status 'passed' -EvidencePath 'build.log' } 'previous stage javaParsed' 'out-of-order validation rejected'
    Set-ManifestValidation -Manifest $manifest -Stage 'intake' -Status 'passed' -EvidencePath 'SOURCE_PROFILE.json'
    Set-ManifestValidation -Manifest $manifest -Stage 'deterministic' -Status 'passed' -EvidencePath 'LEGACY_MIGRATION_REPORT.md'
    Set-ManifestValidation -Manifest $manifest -Stage 'javaParsed' -Status 'passed' -EvidencePath 'parse-report.json'
    Set-ManifestValidation -Manifest $manifest -Stage 'built' -Status 'passed' -EvidencePath 'build.log'
    Assert-Equal $manifest.validation.built.status 'passed' 'ordered validation accepted'

    $output = Join-Path $fixture 'CONVERSION_MANIFEST.json'
    Write-ConversionManifest -Manifest $manifest -Path $output
    $written = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    Assert-Equal $written.rules[0].id 'rule-a' 'written rules sorted by id'
    Assert-Equal ($written.rules[1].files -join ',') 'a/File.java,z/File.java' 'written rule files sorted'
}
finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}

Write-Host "Manifest tests passed: $script:passed" -ForegroundColor Green
