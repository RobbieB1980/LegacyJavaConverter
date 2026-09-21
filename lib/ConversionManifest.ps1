function ConvertTo-ManifestRelativePath {
    param([Parameter(Mandatory)][string]$BasePath, [Parameter(Mandatory)][string]$FullPath)
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $full = [IO.Path]::GetFullPath($FullPath)
    if ($full.Equals($base, [StringComparison]::OrdinalIgnoreCase)) {
        return [IO.Path]::GetFileName($full).Replace('\', '/')
    }
    return $full.Substring($base.Length).TrimStart('\', '/').Replace('\', '/')
}

function New-ConversionManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$TargetMinecraft,
        [Parameter(Mandatory)][string]$TargetNeoForge,
        [Parameter(Mandatory)][string]$ConverterVersion
    )

    $resolved = (Resolve-Path -LiteralPath $InputPath).Path
    $isDirectory = Test-Path -LiteralPath $resolved -PathType Container
    $base = if ($isDirectory) { $resolved } else { Split-Path $resolved -Parent }
    $inputFiles = if ($isDirectory) {
        @(Get-ChildItem -LiteralPath $resolved -Recurse -File | Sort-Object FullName)
    } else {
        @((Get-Item -LiteralPath $resolved))
    }
    $files = @($inputFiles | ForEach-Object {
        [ordered]@{
            path = ConvertTo-ManifestRelativePath -BasePath $base -FullPath $_.FullName
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            size = $_.Length
        }
    } | Sort-Object path)

    $validation = [ordered]@{}
    foreach ($stage in @('intake','deterministic','javaParsed','built','clientBooted','worldLoaded','contentSmokeTested')) {
        $validation[$stage] = [ordered]@{ status = 'notRun'; evidencePath = '' }
    }

    return [ordered]@{
        schemaVersion = 1
        run = [ordered]@{ createdUtc = [DateTime]::UtcNow.ToString('o') }
        input = [ordered]@{
            path = $resolved.Replace('\', '/')
            kind = if ($isDirectory) { 'directory' } else { 'file' }
            files = $files
        }
        target = [ordered]@{ minecraft = $TargetMinecraft; neoforge = $TargetNeoForge }
        converter = [ordered]@{ version = $ConverterVersion }
        rules = @()
        validation = $validation
    }
}

function Add-ManifestRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Manifest,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RuleId,
        [string[]]$Files = @(),
        [Parameter(Mandatory)][AllowEmptyString()][string]$Evidence
    )

    $normalizedFiles = @($Files | ForEach-Object { ([string]$_).Replace('\', '/') } | Sort-Object -Unique)
    $existing = @($Manifest.rules | Where-Object { $_.id -eq $RuleId }) | Select-Object -First 1
    if ($null -ne $existing) {
        $sameFiles = ((@($existing.files) -join "`n") -ceq ($normalizedFiles -join "`n"))
        if ([string]$existing.evidence -ceq $Evidence -and $sameFiles) { return }
        throw "conflicting duplicate rule: $RuleId"
    }
    $Manifest.rules = @($Manifest.rules) + [ordered]@{ id = $RuleId; files = $normalizedFiles; evidence = $Evidence }
}

function Set-ManifestValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Manifest,
        [Parameter(Mandatory)][ValidateSet('intake','deterministic','javaParsed','built','clientBooted','worldLoaded','contentSmokeTested')][string]$Stage,
        [Parameter(Mandatory)][ValidateSet('notRun','passed','failed','blocked')][string]$Status,
        [AllowEmptyString()][string]$EvidencePath = ''
    )

    $stages = @('intake','deterministic','javaParsed','built','clientBooted','worldLoaded','contentSmokeTested')
    $index = [Array]::IndexOf($stages, $Stage)
    if ($Status -eq 'passed' -and $index -gt 0) {
        $previous = $stages[$index - 1]
        if ($Manifest.validation[$previous].status -ne 'passed') {
            throw "Cannot mark $Stage passed before previous stage $previous passed"
        }
    }
    $Manifest.validation[$Stage] = [ordered]@{
        status = $Status
        evidencePath = $EvidencePath.Replace('\', '/')
    }
}

function Write-ConversionManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Manifest,
        [Parameter(Mandatory)][string]$Path
    )

    $Manifest.input.files = @($Manifest.input.files | Sort-Object path)
    foreach ($rule in @($Manifest.rules)) { $rule.files = @($rule.files | Sort-Object -Unique) }
    $Manifest.rules = @($Manifest.rules | Sort-Object id)
    $parent = Split-Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json = $Manifest | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Path), $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
