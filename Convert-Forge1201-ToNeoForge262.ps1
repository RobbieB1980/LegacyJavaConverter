<#
.SYNOPSIS
  Experimental converter: Minecraft Forge 1.20.1 workspace -> NeoForge 26.2 scaffold.

.DESCRIPTION
  Copies the project, rewrites Gradle to ModDevGradle 26.2, maps known deps
  (GeckoLib, SmartBrainLib), applies mechanical Forge->NeoForge renames, and
  optionally runs compileJava to produce an error report.

  This is NOT a full automatic port. Expect many remaining compile errors on
  large mods. Goal of v1: runnable Gradle + modern deps + first-pass rewrites.

.EXAMPLE
  .\Convert-Forge1201-ToNeoForge262.ps1 -Path "F:\Grok Build Apps\Legacy\friend-main" -OutputPath "F:\Grok Build Apps\Friend-26.2" -Compile
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$MinecraftVersion = '26.2',
    [string]$NeoVersion = '26.2.0.32-beta',
    [string]$ModDevGradleVersion = '2.0.141',
    [string]$GeckoLibVersion = '5.5.3',
    [string]$SmartBrainLibVersion = '2.0.0',
    [string]$LocalLibDir = '',
    [switch]$Compile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ToolRoot = $PSScriptRoot

function Write-Step([string]$m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok([string]$m) { Write-Host "    $m" -ForegroundColor Green }
function Write-Warn2([string]$m) { Write-Host "    WARN: $m" -ForegroundColor Yellow }
function Write-Info([string]$m) { Write-Host "    $m" }

function Copy-ProjectTree {
    param([string]$Source, [string]$Dest)
    $exclude = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('build', 'run', 'run-data', '.gradle', '.git', 'bin', 'out', '.idea'),
        [StringComparer]::OrdinalIgnoreCase
    )
    if (Test-Path -LiteralPath $Dest) {
        $items = @(Get-ChildItem -LiteralPath $Dest -Force -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) { throw "Output folder not empty: $Dest" }
    }
    else {
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    }
    $count = 0
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($Source)
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $rel = if ($cur.Length -le $Source.Length) { '' } else { $cur.Substring($Source.Length).TrimStart('\', '/') }
        $destDir = if ($rel) { Join-Path $Dest $rel } else { $Dest }
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        foreach ($item in Get-ChildItem -LiteralPath $cur -Force -ErrorAction SilentlyContinue) {
            if ($item.PSIsContainer) {
                if ($exclude.Contains($item.Name)) { continue }
                $stack.Push($item.FullName)
            }
            else {
                Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $destDir $item.Name) -Force
                $count++
            }
        }
    }
    return $count
}

function Get-ModMetaFromSource {
    param([string]$Root)
    $meta = @{
        mod_id      = 'examplemod'
        mod_name    = 'Example Mod'
        mod_version = '1.0.0'
        mod_group   = 'com.example'
        mod_authors = 'Unknown'
        mod_license = 'All Rights Reserved'
        mod_desc    = 'Converted from Forge 1.20.1'
    }
    $folder = Split-Path $Root -Leaf
    $meta.mod_id = ($folder -replace '[^a-z0-9_]', '').ToLower()
    if ($meta.mod_id.Length -lt 2) { $meta.mod_id = 'friend' }

    $gp = Join-Path $Root 'gradle.properties'
    if (Test-Path $gp) {
        foreach ($line in Get-Content $gp) {
            if ($line -match '^\s*mod_version\s*=\s*(.+)$') { $meta.mod_version = $Matches[1].Trim() }
            if ($line -match '^\s*mod_id\s*=\s*(.+)$') { $meta.mod_id = $Matches[1].Trim() }
        }
    }
    $bg = Join-Path $Root 'build.gradle'
    if (Test-Path $bg) {
        $t = Get-Content $bg -Raw
        if ($t -match "group\s*=\s*'([^']+)'") { $meta.mod_group = $Matches[1] }
        if ($t -match "archivesName\s*=\s*'([^']+)'") {
            $meta.mod_id = $Matches[1]
            $meta.mod_name = $Matches[1]
        }
        if ($t -match "mod_name\s*:\s*'([^']+)'") { $meta.mod_name = $Matches[1] }
        if ($t -match "mod_authors\s*:\s*'([^']+)'") { $meta.mod_authors = $Matches[1] }
        if ($t -match "mod_description\s*:\s*'([^']+)'") { $meta.mod_desc = $Matches[1] }
        if ($t -match "mod_license\s*:\s*'([^']+)'") { $meta.mod_license = $Matches[1] }
        if ($t -match "mod_id\s*:\s*'([^']+)'") { $meta.mod_id = $Matches[1] }
    }
    $java = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -ErrorAction SilentlyContinue |
        Select-String -Pattern '@Mod\(' -List | Select-Object -First 1
    if ($java) {
        $pkg = Select-String -Path $java.Path -Pattern '^package\s+([\w\.]+);' | Select-Object -First 1
        if ($pkg) { $meta.mod_group = $pkg.Matches[0].Groups[1].Value }
    }
    return $meta
}

function Test-SourceNeedsLibrary {
    param([string]$Root, [string]$Pattern)
    $hit = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
        Select-String -Pattern $Pattern -SimpleMatch:$false -List | Select-Object -First 1
    return [bool]$hit
}

function Write-GradleScaffold {
    param(
        [string]$Root,
        [hashtable]$Meta,
        [string]$LocalLibs,
        [bool]$IncludeGeckoLib = $false,
        [bool]$IncludeSmartBrainLib = $false
    )

    $props = @"
# Generated by Convert-Forge1201-ToNeoForge262 (experimental)
org.gradle.jvmargs=-Xmx4G
org.gradle.daemon=true
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configuration-cache=false

minecraft_version=$MinecraftVersion
minecraft_version_range=[$MinecraftVersion]
neo_version=$NeoVersion

mod_id=$($Meta.mod_id)
mod_name=$($Meta.mod_name)
mod_license=$($Meta.mod_license)
mod_version=$($Meta.mod_version)+mc$MinecraftVersion-neoforge
mod_group_id=$($Meta.mod_group)
mod_authors=$($Meta.mod_authors)
mod_description=$($Meta.mod_desc)

geckolib_version=$GeckoLibVersion
smartbrainlib_version=$SmartBrainLibVersion
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'gradle.properties'), $props.Trim() + "`r`n")

    $settings = @"
pluginManagement {
    repositories {
        gradlePluginPortal()
        maven { url = 'https://maven.neoforged.net/releases' }
        mavenCentral()
    }
}

plugins {
    id 'org.gradle.toolchains.foojay-resolver-convention' version '1.0.0'
}

rootProject.name = '$($Meta.mod_id)-neoforge-$MinecraftVersion'
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'settings.gradle'), $settings.Trim() + "`r`n")

    $localRepoBlock = ''
    if ($LocalLibs -and (Test-Path $LocalLibs)) {
        $localPath = $LocalLibs.Replace('\', '/')
        $localRepoBlock = @"

    // Local pre-downloaded dependency jars (optional fallback)
    flatDir {
        dirs '$localPath'
    }
"@
    }

    # Build optional dep lines OUTSIDE the main here-string (nested @" "@ breaks PowerShell parsing)
    if ($IncludeGeckoLib) {
        $geckoDepLine = @'
    // GeckoLib 5 for NeoForge 26.2 (detected in sources)
    implementation "com.geckolib:geckolib-neoforge-${minecraft_version}:${geckolib_version}"
'@
        $geckoTomlBlock = @'

[[dependencies.${mod_id}]]
modId="geckolib"
type="required"
versionRange="[5.5,)"
ordering="AFTER"
side="BOTH"
'@
    }
    else {
        $geckoDepLine = '    // GeckoLib not detected in sources - skipped'
        $geckoTomlBlock = ''
    }

    if ($IncludeSmartBrainLib) {
        $sblDepLine = @'
    // SmartBrainLib (detected in sources). Prefer a local jar if Maven has no 26.2 artifact.
    implementation "net.tslat.smartbrainlib:SmartBrainLib-neoforge-${minecraft_version}:${smartbrainlib_version}"
'@
        $sblTomlBlock = @'

[[dependencies.${mod_id}]]
modId="smartbrainlib"
type="required"
versionRange="[2.0,)"
ordering="AFTER"
side="BOTH"
'@
    }
    else {
        $sblDepLine = '    // SmartBrainLib not detected in sources - skipped (avoids missing Maven artifact)'
        $sblTomlBlock = ''
    }

    $build = @"
plugins {
    id 'java-library'
    id 'maven-publish'
    id 'net.neoforged.moddev' version '$ModDevGradleVersion'
    id 'idea'
}

tasks.named('wrapper', Wrapper).configure {
    distributionType = Wrapper.DistributionType.BIN
}

version = mod_version
group = mod_group_id

base {
    archivesName = mod_id
}

java.toolchain.languageVersion = JavaLanguageVersion.of(25)

sourceSets.main.resources {
    srcDir('src/generated/resources')
}

neoForge {
    version = project.neo_version

    runs {
        client {
            client()
            systemProperty 'neoforge.enabledGameTestNamespaces', project.mod_id
        }
        server {
            server()
            programArgument '--nogui'
        }
        configureEach {
            systemProperty 'forge.logging.markers', 'REGISTRIES'
            logLevel = org.slf4j.event.Level.DEBUG
        }
    }

    mods {
        "`${mod_id}" {
            sourceSet(sourceSets.main)
        }
    }
}

repositories {
    mavenCentral()
    maven { url = 'https://maven.neoforged.net/releases' }
    maven {
        name = 'GeckoLib'
        url = 'https://dl.cloudsmith.io/public/geckolib3/geckolib/maven/'
        content { includeGroupAndSubgroups('com.geckolib') }
    }
    maven {
        name = 'Tslat'
        url = 'https://dl.cloudsmith.io/public/tslat/tslat/maven/'
    }
    maven {
        name = 'BlameJared'
        url = 'https://maven.blamejared.com'
    }
$localRepoBlock
}

dependencies {
$geckoDepLine
$sblDepLine
}

var generateModMetadata = tasks.register('generateModMetadata', ProcessResources) {
    var replaceProperties = [
            minecraft_version      : minecraft_version,
            minecraft_version_range: minecraft_version_range,
            neo_version            : neo_version,
            mod_id                 : mod_id,
            mod_name               : mod_name,
            mod_license            : mod_license,
            mod_version            : mod_version,
            mod_authors            : mod_authors,
            mod_description        : mod_description,
            geckolib_version       : geckolib_version,
            smartbrainlib_version  : smartbrainlib_version
    ]
    inputs.properties replaceProperties
    expand replaceProperties
    from 'src/main/templates'
    into 'build/generated/sources/modMetadata'
}

sourceSets.main.resources.srcDir generateModMetadata
neoForge.ideSyncTask generateModMetadata

tasks.withType(JavaCompile).configureEach {
    options.encoding = 'UTF-8'
    options.release = 25
}

idea {
    module {
        downloadSources = true
        downloadJavadoc = true
    }
}
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'build.gradle'), $build.Trim() + "`r`n")

    $tomlDir = Join-Path $Root 'src\main\templates\META-INF'
    New-Item -ItemType Directory -Path $tomlDir -Force | Out-Null
    $toml = @"
modLoader="javafml"
loaderVersion="[4,)"
license="`${mod_license}"

[[mods]]
modId="`${mod_id}"
version="`${mod_version}"
displayName="`${mod_name}"
authors="`${mod_authors}"
description='''`${mod_description}'''

[[dependencies.`${mod_id}]]
modId="neoforge"
type="required"
versionRange="[`${neo_version},)"
ordering="NONE"
side="BOTH"

[[dependencies.`${mod_id}]]
modId="minecraft"
type="required"
versionRange="`${minecraft_version_range}"
ordering="NONE"
side="BOTH"
$geckoTomlBlock
$sblTomlBlock
"@
    [System.IO.File]::WriteAllText((Join-Path $tomlDir 'neoforge.mods.toml'), $toml.Trim() + "`r`n")

    $pack = @"
{
  "pack": {
    "min_format": 107,
    "max_format": 107,
    "description": "$($Meta.mod_name) $MinecraftVersion"
  }
}
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'src\main\resources\pack.mcmeta'), $pack.Trim() + "`r`n")

    # Remove old Forge mods.toml if present (MDG uses templates)
    $oldToml = Join-Path $Root 'src\main\resources\META-INF\mods.toml'
    if (Test-Path $oldToml) {
        Remove-Item $oldToml -Force
        Write-Info 'Removed legacy META-INF/mods.toml (using templates/neoforge.mods.toml)'
    }
}

function Invoke-MechanicalJavaRewrites {
    param([string]$Root)

    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    $touched = 0
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # --- Forge packages -> NeoForge (order matters: specific before broad) ---
        $t = $t -replace 'net\.minecraftforge\.fml\.common\.Mod', 'net.neoforged.fml.common.Mod'
        $t = $t -replace 'net\.minecraftforge\.fml\.javafmlmod\.FMLJavaModLoadingContext', 'net.neoforged.fml.javafmlmod.FMLJavaModLoadingContext'
        $t = $t -replace 'net\.minecraftforge\.fml\.ModLoadingContext', 'net.neoforged.fml.ModLoadingContext'
        $t = $t -replace 'net\.minecraftforge\.fml\.config\.ModConfig', 'net.neoforged.fml.config.ModConfig'
        $t = $t -replace 'net\.minecraftforge\.common\.ForgeConfigSpec', 'net.neoforged.neoforge.common.ModConfigSpec'
        $t = $t -replace '\bForgeConfigSpec\b', 'ModConfigSpec'
        $t = $t -replace 'net\.minecraftforge\.api\.distmarker\.Dist', 'net.neoforged.api.distmarker.Dist'
        $t = $t -replace 'net\.minecraftforge\.eventbus\.api\.SubscribeEvent', 'net.neoforged.bus.api.SubscribeEvent'
        $t = $t -replace 'net\.minecraftforge\.eventbus\.api\.IEventBus', 'net.neoforged.bus.api.IEventBus'
        $t = $t -replace 'net\.minecraftforge\.event\.entity\.EntityAttributeCreationEvent', 'net.neoforged.neoforge.event.entity.EntityAttributeCreationEvent'
        $t = $t -replace 'net\.minecraftforge\.client\.event\.EntityRenderersEvent', 'net.neoforged.neoforge.client.event.EntityRenderersEvent'
        $t = $t -replace 'net\.minecraftforge\.client\.event\.ViewportEvent', 'net.neoforged.neoforge.client.event.ViewportEvent'
        $t = $t -replace 'net\.minecraftforge\.client\.event\.', 'net.neoforged.neoforge.client.event.'
        $t = $t -replace 'net\.minecraftforge\.event\.entity\.living\.', 'net.neoforged.neoforge.event.entity.living.'
        $t = $t -replace 'net\.minecraftforge\.event\.entity\.player\.', 'net.neoforged.neoforge.event.entity.player.'
        $t = $t -replace 'net\.minecraftforge\.event\.level\.', 'net.neoforged.neoforge.event.level.'
        $t = $t -replace 'net\.minecraftforge\.common\.MinecraftForge', 'net.neoforged.neoforge.common.NeoForge'
        $t = $t -replace 'MinecraftForge\.EVENT_BUS', 'NeoForge.EVENT_BUS'
        $t = $t -replace 'net\.minecraftforge\.registries\.DeferredRegister', 'net.neoforged.neoforge.registries.DeferredRegister'
        $t = $t -replace 'net\.minecraftforge\.registries\.RegistryObject', 'net.neoforged.neoforge.registries.DeferredHolder'
        $t = $t -replace 'net\.minecraftforge\.registries\.ForgeRegistries', 'net.minecraft.core.registries.BuiltInRegistries /* TODO Registries.* */'
        # leftover catch-all (after specifics)
        $t = $t -replace 'net\.minecraftforge\.', 'net.neoforged.neoforge.'
        # Fix over-prefix from catch-all (api/fml live under net.neoforged.* not neoforge.*)
        $t = $t -replace 'net\.neoforged\.neoforge\.api\.distmarker', 'net.neoforged.api.distmarker'
        $t = $t -replace 'net\.neoforged\.neoforge\.fml\.', 'net.neoforged.fml.'
        $t = $t -replace 'net\.neoforged\.neoforge\.bus\.', 'net.neoforged.bus.'

        # --- TickEvent (safe: do NOT map whole TickEvent package to ServerTickEvent) ---
        # Client
        $t = $t -replace 'import\s+net\.minecraftforge\.event\.TickEvent;', "import net.neoforged.neoforge.client.event.ClientTickEvent;`r`nimport net.neoforged.neoforge.event.tick.ServerTickEvent;"
        $t = $t -replace 'import\s+net\.neoforged\.neoforge\.event\.TickEvent;', "import net.neoforged.neoforge.client.event.ClientTickEvent;`r`nimport net.neoforged.neoforge.event.tick.ServerTickEvent;"
        $t = $t -replace 'TickEvent\.ClientTickEvent', 'ClientTickEvent'
        $t = $t -replace 'TickEvent\.ServerTickEvent', 'ServerTickEvent'
        # phase END handlers → Post events (common 1.20.1 pattern)
        $t = [regex]::Replace($t,
            '(?s)public\s+static\s+void\s+(\w+)\s*\(\s*ClientTickEvent\s+(\w+)\s*\)\s*\{\s*if\s*\(\s*\2\.phase\s*==\s*TickEvent\.Phase\.END\s*\)\s*\{(.*?)\}\s*\}',
            'public static void $1(ClientTickEvent.Post $2) {$3}')
        $t = [regex]::Replace($t,
            '(?s)public\s+static\s+void\s+(\w+)\s*\(\s*ServerTickEvent\s+(\w+)\s*\)\s*\{\s*if\s*\(\s*\2\.phase\s*==\s*TickEvent\.Phase\.END\s*\)\s*\{(.*?)\}\s*\}',
            'public static void $1(ServerTickEvent.Post $2) {$3}')
        # Remaining phase checks
        $t = $t -replace '(\w+)\.phase\s*==\s*TickEvent\.Phase\.END', '($1 instanceof ClientTickEvent.Post || $1 instanceof ServerTickEvent.Post)'
        $t = $t -replace '(\w+)\.phase\s*==\s*TickEvent\.Phase\.START', '($1 instanceof ClientTickEvent.Pre || $1 instanceof ServerTickEvent.Pre)'
        $t = $t -replace 'TickEvent\.Phase\.END', '/* END */ true'
        $t = $t -replace 'TickEvent\.Phase\.START', '/* START */ true'

        # Bus subscriber: FORGE bus -> GAME bus
        $t = $t -replace 'Mod\.EventBusSubscriber\.Bus\.FORGE', 'Mod.EventBusSubscriber.Bus.GAME'

        # --- Minecraft 26.x: ResourceLocation renamed to Identifier ---
        $t = $t -replace 'net\.minecraft\.resources\.ResourceLocation', 'net.minecraft.resources.Identifier'
        $t = $t -replace '\bResourceLocation\b', 'Identifier'
        # constructors already converted or: new Identifier(ns, path) / fromNamespaceAndPath
        $t = [regex]::Replace($t, 'new\s+Identifier\(\s*([^,]+)\s*,\s*([^\)]+)\)', 'Identifier.fromNamespaceAndPath($1, $2)')
        # undo double-fromNamespace if we already had fromNamespaceAndPath on Identifier
        $t = $t -replace 'Identifier\.fromNamespaceAndPath', 'Identifier.fromNamespaceAndPath'

        # --- Entity / level accessors (1.20.1 fields -> methods) ---
        # IMPORTANT: never rewrite package paths like net.minecraft.world.level.Level
        # Only rewrite Entity field access: this.level / entity.level
        $t = $t -replace '\bthis\.level\.isClientSide\b', 'this.level().isClientSide()'
        $t = $t -replace '\bthis\.level\.isClientSide\(\)', 'this.level().isClientSide()'
        $t = $t -replace '\bthis\.level\b(?!\s*[\.(])', 'this.level()'
        $t = $t -replace '\bthis\.level\(\)\.', 'this.level().'
        # friend.level. / entity.level. when not package (single simple identifier receiver)
        $t = [regex]::Replace($t, '(?<![\w.])(entity|friend|mob|living|player|target|owner|self)\.level\.isClientSide\b', '$1.level().isClientSide()', 'IgnoreCase')
        $t = [regex]::Replace($t, '(?<![\w.])(entity|friend|mob|living|player|target|owner|self)\.level\.(?!isClientSide)', '$1.level().', 'IgnoreCase')
        # setMaxUpStep removed - comment out whole statement line-ish
        $t = [regex]::Replace($t, '(?m)^(\s*)(.*)\.setMaxUpStep\s*\(([^;]*)\)\s*;\s*$', '$1// LEGACY: $2.setMaxUpStep($3); // removed in 26.x')
        # BlockPos.getCenter -> Vec3.atCenterOf (simple receivers; chained forms handled in 26.2 API pass)
        $t = [regex]::Replace($t, '(?<![\w.])([a-zA-Z_]\w*)\.getCenter\(\)', {
                param($m)
                $recv = $m.Groups[1].Value
                if ($recv -match '^(?i)(visualBox|box|aabb)$') { return $m.Value }
                "net.minecraft.world.phys.Vec3.atCenterOf($recv)"
            })
        # Common chained BlockPos centers: feet.relative(dir).getCenter()
        $t = [regex]::Replace($t,
            '([a-zA-Z_]\w*(?:\([^)]*\))?\.relative\([^)]+\))\.getCenter\(\)',
            'net.minecraft.world.phys.Vec3.atCenterOf($1)')

        # EntityType.Builder.build("id")
        $t = [regex]::Replace($t, '\.build\(\s*"[^"]*"\s*\)', '.build()')

        # --- GeckoLib 4 -> 5 packages ---
        $t = $t -replace 'software\.bernie\.geckolib', 'com.geckolib'
        $t = $t -replace 'com\.geckolib\.core\.animatable\.instance', 'com.geckolib.animatable.instance'
        $t = $t -replace 'com\.geckolib\.core\.animation', 'com.geckolib.animation'
        $t = $t -replace 'com\.geckolib\.animation\.AnimatableManager', 'com.geckolib.animatable.manager.AnimatableManager'
        # AnimationController no longer takes animatable as first constructor arg
        $t = $t -replace 'new\s+AnimationController<>\s*\(\s*this\s*,\s*', 'new AnimationController<>('
        $t = $t -replace 'new\s+AnimationController\s*\(\s*this\s*,\s*', 'new AnimationController('
        # GeoModel resource methods now often take GeoRenderState - leave signatures, mark TODO via comment once
        if ($t -match 'extends\s+GeoModel') {
            $t = $t -replace 'public\s+Identifier\s+getModelResource\s*\(\s*(\w+)\s+(\w+)\s*\)',
                'public Identifier getModelResource(com.geckolib.renderer.base.GeoRenderState $2) /* was $1 entity */'
            $t = $t -replace 'public\s+Identifier\s+getTextureResource\s*\(\s*(\w+)\s+(\w+)\s*\)',
                'public Identifier getTextureResource(com.geckolib.renderer.base.GeoRenderState $2) /* was $1 entity */'
        }

        # Annotations
        $t = $t -replace 'import javax\.annotation\.Nullable;', 'import org.jetbrains.annotations.Nullable;'
        $t = $t -replace 'import javax\.annotation\.Nonnull;', 'import org.jetbrains.annotations.NotNull;'

        # Mod constructor injection hint
        if ($t -match 'FMLJavaModLoadingContext') {
            $t = $t -replace 'FMLJavaModLoadingContext\.get\(\)\.getModEventBus\(\)',
                '/* TODO inject IEventBus */ FMLJavaModLoadingContext.get().getModEventBus()'
        }

        # RegistryObject residual type name (import already DeferredHolder)
        $t = $t -replace '\bRegistryObject\b', 'DeferredHolder'

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }
    return $touched
}

function Invoke-NeoForge26ApiRewritePass {
    <#
    .SYNOPSIS
      Second-pass Minecraft/NeoForge 26.2 API renames proven on Friend-26.2 (Forge 1.20.1 source).
      Safe mechanical transforms only - does not invent gameplay logic.
    #>
    param([string]$Root)

    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    $touched = 0
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # --- NBT 26.x ---
        # getList(key, type) / getListOrEmpty(key, type) -> single-arg list accessors
        $t = $t -replace '\.getListOrEmpty\(([^,]+),\s*Tag\.[A-Z_]+\)', '.getListOrEmpty($1)'
        $t = $t -replace '\.getList\(([^,]+),\s*Tag\.[A-Z_]+\)', '.getListOrEmpty($1)'
        # Prefer OrEmpty compound accessors (Optional-based getCompound in 26.x)
        # Negative lookahead avoids rewriting getCompoundOrEmpty itself
        $t = $t -replace '\.getCompound(?!OrEmpty)\(([^)]+)\)', '.getCompoundOrEmpty($1)'

        # --- BlockState ---
        $t = $t -replace '\.isSolidRender\([^)]*\)', '.isSolidRender()'

        # --- PathNavigation: NEVER rename navigation.moveTo to snapTo ---
        # Entity absolute placement often becomes snapTo; only convert bare entity moveTo with 5 args (x,y,z,yaw,pitch)
        $t = [regex]::Replace($t,
            '(?<!getNavigation\(\)\.)(?<!Navigation\.)\bmoveTo\((\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*[^)]+)\)',
            'snapTo($1)')
        # If a prior pass wrongly converted navigation to snapTo, restore
        $t = $t -replace '\.getNavigation\(\)\.snapTo\(', '.getNavigation().moveTo('

        # --- EntityType.create needs spawn reason ---
        $t = $t -replace '\.create\((\s*(?:level|serverLevel|world)\s*)\)',
            '.create($1, net.minecraft.world.entity.EntitySpawnReason.MOB_SUMMONED)'

        # --- Server access: player.server is private; use level().getServer() ---
        # Do NOT touch net.minecraft.server.* imports/packages
        $t = $t -replace '(?<![\w.])(player|serverPlayer|owner|self)\.server\.', '$1.level().getServer().'
        $t = $t -replace '(?<![\w.])(player|serverPlayer|owner|self)\.getServer\(\)', '$1.level().getServer()'

        # --- Spawn / respawn ---
        $t = $t -replace '\.getSharedSpawnPos\(\)', '.getRespawnData().pos()'
        # Player respawn: prefer RespawnConfig when present (manual polish often still needed)
        $t = $t -replace '(\w+)\.getRespawnPosition\(\)',
            '($1.getRespawnConfig() != null ? $1.getRespawnConfig().respawnData().pos() : null)'

        # --- Effects / entity packages ---
        $t = $t -replace 'MobEffects\.MOVEMENT_SPEED', 'MobEffects.SPEED'
        $t = $t -replace 'net\.minecraft\.world\.entity\.monster\.Zombie\b',
            'net.minecraft.world.entity.monster.zombie.Zombie'
        $t = $t -replace 'net\.minecraft\.world\.entity\.animal\.Cat\b',
            'net.minecraft.world.entity.animal.feline.Cat'
        $t = $t -replace 'net\.minecraft\.world\.entity\.animal\.Wolf\b',
            'net.minecraft.world.entity.animal.wolf.Wolf'

        # --- NeoForge break event package (26.2) ---
        $t = $t -replace 'net\.neoforged\.neoforge\.event\.level\.BlockEvent\.BreakEvent',
            'net.neoforged.neoforge.event.level.block.BreakBlockEvent'
        $t = $t -replace '\bBlockEvent\.BreakEvent\b', 'BreakBlockEvent'
        # Ensure import when BreakBlockEvent is used without FQN
        if ($t -match '\bBreakBlockEvent\b' -and $t -notmatch 'import\s+net\.neoforged\.neoforge\.event\.level\.block\.BreakBlockEvent') {
            if ($t -match 'import\s+net\.neoforged\.neoforge\.event\.level\.BlockEvent;') {
                $t = $t -replace 'import\s+net\.neoforged\.neoforge\.event\.level\.BlockEvent;',
                    "import net.neoforged.neoforge.event.level.BlockEvent;`r`nimport net.neoforged.neoforge.event.level.block.BreakBlockEvent;"
            }
            elseif ($t -match '(?m)^package\s+[^;]+;') {
                $t = [regex]::Replace($t, '(?m)^(package\s+[^;]+;\s*)',
                    "`$1`r`nimport net.neoforged.neoforge.event.level.block.BreakBlockEvent;`r`n", 1)
            }
        }

        # --- Commands: hasPermission(int) -> PermissionSet ---
        $t = $t -replace '\.hasPermission\(\s*2\s*\)',
            '.permissions().hasPermission(net.minecraft.server.permissions.Permissions.COMMANDS_GAMEMASTER)'
        $t = $t -replace '\.hasPermission\(\s*4\s*\)',
            '.permissions().hasPermission(net.minecraft.server.permissions.Permissions.COMMANDS_OWNER)'
        $t = $t -replace '\.hasPermission\(\s*3\s*\)',
            '.permissions().hasPermission(net.minecraft.server.permissions.Permissions.COMMANDS_ADMIN)'

        # --- ResourceKey: dimension().location() -> identifier() ---
        $t = $t -replace '\.dimension\(\)\.location\(\)', '.dimension().identifier()'

        # --- Camera only (avoid rewriting unrelated getPosition) ---
        $t = $t -replace '\bcamera\.getPosition\(\)', 'camera.position()'
        $t = $t -replace '\bevent\.getCamera\(\)\.getPosition\(\)', 'event.getCamera().position()'

        # --- DeferredHolder single type param (SoundEvent etc.) ---
        $t = $t -replace 'DeferredHolder<\s*SoundEvent\s*>(?!\s*,)', 'DeferredHolder<SoundEvent, SoundEvent>'

        # --- ClipContext null entity ambiguity ---
        $t = $t -replace 'ClipContext\.Fluid\.NONE\s*,\s*null\)',
            'ClipContext.Fluid.NONE, net.minecraft.world.phys.shapes.CollisionContext.empty())'

        # --- Colored blocks (ColorCollection) common literals ---
        $colorBlocks = [ordered]@{
            'Blocks.BLACK_CONCRETE'           = 'Blocks.CONCRETE.black()'
            'Blocks.WHITE_CONCRETE'           = 'Blocks.CONCRETE.white()'
            'Blocks.RED_CONCRETE'             = 'Blocks.CONCRETE.red()'
            'Blocks.LIGHT_BLUE_CONCRETE'      = 'Blocks.CONCRETE.lightBlue()'
            'Blocks.GRAY_CONCRETE'            = 'Blocks.CONCRETE.gray()'
            'Blocks.BLACK_STAINED_GLASS'      = 'Blocks.STAINED_GLASS.black()'
            'Blocks.WHITE_STAINED_GLASS'      = 'Blocks.STAINED_GLASS.white()'
            'Blocks.GRAY_STAINED_GLASS'       = 'Blocks.STAINED_GLASS.gray()'
            'Blocks.LIGHT_BLUE_STAINED_GLASS' = 'Blocks.STAINED_GLASS.lightBlue()'
            'Blocks.RED_STAINED_GLASS'        = 'Blocks.STAINED_GLASS.red()'
            'Blocks.WHITE_CARPET'             = 'Blocks.CARPET.white()'
            'Blocks.BLUE_CARPET'              = 'Blocks.CARPET.blue()'
            'Blocks.RED_CARPET'               = 'Blocks.CARPET.red()'
            'Blocks.BLACK_CARPET'             = 'Blocks.CARPET.black()'
            'Blocks.RED_BED'                  = 'Blocks.BED.red()'
            'Blocks.WHITE_BED'                = 'Blocks.BED.white()'
            'Blocks.CHAIN'                    = 'Blocks.IRON_CHAIN'
        }
        foreach ($k in $colorBlocks.Keys) {
            $t = $t.Replace($k, $colorBlocks[$k])
        }

        # --- Weather / day-time (best-effort; many dims fix time in data) ---
        $t = $t -replace '(\w+)\.setWeatherParameters\(\s*([^,]+)\s*,\s*([^,]+)\s*,\s*false\s*,\s*false\s*\)',
            '{ var __w = $1.getWeatherData(); __w.setClearWeatherTime((int)($2)); __w.setRainTime(0); __w.setThunderTime(0); __w.setRaining(false); __w.setThundering(false); }'
        $t = $t -replace '(\w+)\.setWeatherParameters\(\s*([^,]+)\s*,\s*([^,]+)\s*,\s*true\s*,\s*true\s*\)',
            '{ var __w = $1.getWeatherData(); __w.setClearWeatherTime(0); __w.setRainTime((int)($3)); __w.setThunderTime((int)($3)); __w.setRaining(true); __w.setThundering(true); }'
        $t = $t -replace '(\w+)\.setDayTime\((\d+L|[\w.]+)\)',
            '$1.dimensionType().defaultClock().ifPresent(__clock -> $1.clockManager().setTotalTicks(__clock, $2))'

        # --- Teleport cross-dimension 6-arg (level, x,y,z, yaw, pitch) ---
        # Avoid nested-paren receivers; only simple identifier first arg (level/world vars)
        $t = [regex]::Replace($t,
            '(\w+)\.teleportTo\(\s*([A-Za-z_][\w]*)\s*,\s*([^,]+)\s*,\s*([^,]+)\s*,\s*([^,]+)\s*,\s*([^,]+)\s*,\s*([^)]+)\)',
            {
                param($m)
                $recv = $m.Groups[1].Value
                $a1 = $m.Groups[2].Value
                $a2 = $m.Groups[3].Value.Trim()
                $a3 = $m.Groups[4].Value.Trim()
                $a4 = $m.Groups[5].Value.Trim()
                $a5 = $m.Groups[6].Value.Trim()
                $a6 = $m.Groups[7].Value.Trim()
                if ($a5 -match 'emptySet|Relative|Set\.') { return $m.Value }
                if ($a6 -match '^\s*(true|false)\s*$' -and $a5 -match 'emptySet|Set\.') { return $m.Value }
                # skip same-dimension 3-double style misparse (first arg looks numeric via var unlikely)
                if ($a1 -match '^(?i)(x|y|z|dx|dy|dz)$') { return $m.Value }
                "$recv.teleportTo($a1, $a2, $a3, $a4, java.util.Collections.emptySet(), $a5, $a6, true)"
            })

        # --- Advancement lookup ---
        $t = $t -replace '\.getAdvancements\(\)\.getAdvancement\(', '.getAdvancements().get('

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }
    return $touched
}

function Invoke-RegistryTemplatePass {
    <#
    .SYNOPSIS
      Rewrite simple DeferredRegister entity/sound patterns to NeoForge 26 createEntities / Registries forms.
    #>
    param([string]$Root)

    $fixed = 0
    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # DeferredRegister.create(ForgeRegistries/BuiltInRegistries.ENTITY_TYPE[S], modid)
        $t = [regex]::Replace($t,
            'DeferredRegister\.create\(\s*(?:ForgeRegistries\.ENTITY_TYPES|BuiltInRegistries\s*/\*[^*]*\*/\s*\.ENTITY_TYPE|BuiltInRegistries\.ENTITY_TYPE)\s*,\s*([^)]+)\)',
            'DeferredRegister.createEntities($1)')
        $t = [regex]::Replace($t,
            'DeferredRegister\.create\(\s*(?:ForgeRegistries\.SOUND_EVENTS|BuiltInRegistries\s*/\*[^*]*\*/\s*\.SOUND_EVENT|BuiltInRegistries\.SOUND_EVENT)\s*,\s*([^)]+)\)',
            'DeferredRegister.create(net.minecraft.core.registries.Registries.SOUND_EVENT, $1)')
        $t = [regex]::Replace($t,
            'DeferredRegister\.create\(\s*(?:ForgeRegistries\.ITEMS|BuiltInRegistries\.ITEM)\s*,\s*([^)]+)\)',
            'DeferredRegister.createItems($1)')
        $t = [regex]::Replace($t,
            'DeferredRegister\.create\(\s*(?:ForgeRegistries\.BLOCKS|BuiltInRegistries\.BLOCK)\s*,\s*([^)]+)\)',
            'DeferredRegister.createBlocks($1)')

        # Ensure imports for DeferredHolder when used
        if ($t -match 'DeferredHolder' -and $t -notmatch 'import net\.neoforged\.neoforge\.registries\.DeferredHolder') {
            $t = $t -replace '(package [^;]+;\s*)', "`$1`r`nimport net.neoforged.neoforge.registries.DeferredHolder;"
        }
        if ($t -match 'DeferredRegister\.createEntities' -and $t -notmatch 'import net\.neoforged\.neoforge\.registries\.DeferredRegister') {
            $t = $t -replace '(package [^;]+;\s*)', "`$1`r`nimport net.neoforged.neoforge.registries.DeferredRegister;"
        }

        # EntityType register lambda with Builder.of(...).build() - try registerEntityType when simple
        # public static final DeferredHolder<EntityType<X>, ...> NAME = REG.register("id", () -> EntityType.Builder.of(X::new, CAT)...build());
        # Too risky to auto-convert all forms; leave for compile errors.

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $fixed++
        }
    }
    return $fixed
}

function Invoke-ModEntryTemplatePass {
    param([string]$Root)

    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File |
        Where-Object { (Get-Content $_.FullName -Raw) -match '@Mod\(' }
    $n = 0
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t
        # Convert no-arg mod constructor using FMLJavaModLoadingContext to IEventBus + ModContainer
        if ($t -match 'FMLJavaModLoadingContext' -or $t -match 'ModLoadingContext\.get\(\)\.registerConfig') {
            if ($t -notmatch 'import net\.neoforged\.bus\.api\.IEventBus') {
                $t = $t -replace '(package [^;]+;\s*)', "`$1`r`nimport net.neoforged.bus.api.IEventBus;`r`nimport net.neoforged.fml.ModContainer;"
            }
            # Replace constructor signature public Foo() { ... getModEventBus ...}
            $t = [regex]::Replace($t,
                'public\s+(\w+)\s*\(\s*\)\s*\{',
                'public $1(IEventBus modBus, ModContainer container) {')
            $t = $t -replace '/\*\s*TODO:\s*inject IEventBus\s*\*/\s*', ''
            $t = $t -replace '/\*\s*TODO inject IEventBus\s*\*/\s*', ''
            $t = $t -replace 'FMLJavaModLoadingContext\.get\(\)\.getModEventBus\(\)', 'modBus'
            $t = $t -replace 'var\s+modBus\s*=\s*modBus\s*;', ''
            $t = $t -replace 'ModLoadingContext\.get\(\)\.registerConfig\(', 'container.registerConfig('
            # drop unused imports
            $t = $t -replace 'import\s+net\.neoforged\.fml\.javafmlmod\.FMLJavaModLoadingContext;\r?\n', ''
            $t = $t -replace 'import\s+net\.neoforged\.fml\.ModLoadingContext;\r?\n', ''
        }
        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $n++
        }
    }
    return $n
}

function Invoke-EventBusSubscriberPass {
    <#
    .SYNOPSIS
      NeoForge 26.x no longer exposes @Mod.EventBusSubscriber the same way.
      Convert annotated static @SubscribeEvent handlers into explicit
      modBus / NeoForge.EVENT_BUS addListener registrations.
    #>
    param([string]$Root, [hashtable]$Meta)

    $javaRoot = Join-Path $Root 'src\main\java'
    if (-not (Test-Path $javaRoot)) { return 0 }

    $modBusMethods = New-Object System.Collections.Generic.List[string]
    $gameBusMethods = New-Object System.Collections.Generic.List[string]
    $imports = New-Object System.Collections.Generic.HashSet[string]
    $filesTouched = 0

    $modBusEventHints = @(
        'EntityAttributeCreationEvent', 'EntityRenderersEvent', 'RegisterParticleProvidersEvent',
        'RegisterMenuScreensEvent', 'RegisterClientReloadListenersEvent', 'BuildCreativeModeTabContentsEvent',
        'RegisterCommandsEvent'  # sometimes mod bus in older; usually game - keep game for commands below
    )

    foreach ($f in Get-ChildItem $javaRoot -Recurse -Filter '*.java') {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        if ($t -notmatch 'EventBusSubscriber') { continue }

        $pkg = if ($t -match 'package\s+([\w\.]+)\s*;') { $Matches[1] } else { continue }
        $cls = if ($t -match 'public\s+(?:final\s+)?class\s+(\w+)') { $Matches[1] } else { continue }
        $fqcn = "$pkg.$cls"

        # Collect static subscribe methods: public static void name(EventType event)
        $methodMatches = [regex]::Matches($t, '(?s)@SubscribeEvent\s+public\s+static\s+void\s+(\w+)\s*\(\s*([\w\.]+)\s+\w+\s*\)')
        $isClientOnly = $t -match 'value\s*=\s*Dist\.CLIENT' -or $t -match 'Dist\.CLIENT'
        $busIsMod = $t -match 'Bus\.MOD'

        foreach ($mm in $methodMatches) {
            $method = $mm.Groups[1].Value
            $eventType = $mm.Groups[2].Value
            $ref = "${cls}::${method}"
            $imports.Add("import ${fqcn};") | Out-Null

            $useModBus = $busIsMod -or ($modBusEventHints | Where-Object { $eventType -match $_ })
            # Commands / ticks / living / viewport -> game bus
            if ($eventType -match 'TickEvent|ClientTick|ServerTick|Viewport|Living|Player|Level|Block|Command') {
                $useModBus = $false
            }
            if ($eventType -match 'EntityAttribute|EntityRenderers|RegisterParticle|CreativeModeTab|RegisterMenu') {
                $useModBus = $true
            }

            if ($useModBus) {
                $modBusMethods.Add("        modBus.addListener($ref);") | Out-Null
            }
            else {
                $gameBusMethods.Add("        NeoForge.EVENT_BUS.addListener($ref);") | Out-Null
            }
        }

        # Strip class-level EventBusSubscriber annotation (keep methods + SubscribeEvent for clarity optional)
        $t2 = [regex]::Replace($t, '@Mod\.EventBusSubscriber\s*\([^)]*\)\s*', "/* was EventBusSubscriber - registered via LegacyEventBootstrap */`r`n")
        $t2 = $t2 -replace '@OnlyIn\s*\(\s*Dist\.CLIENT\s*\)', '/* @OnlyIn(Dist.CLIENT) removed */'
        $t2 = $t2 -replace 'import\s+net\.neoforged\.neoforge\.api\.distmarker\.OnlyIn;\r?\n', ''
        $t2 = $t2 -replace 'import\s+net\.minecraftforge\.api\.distmarker\.OnlyIn;\r?\n', ''

        if ($t2 -ne $t) {
            [System.IO.File]::WriteAllText($f.FullName, $t2)
            $filesTouched++
        }
    }

    if ($modBusMethods.Count -eq 0 -and $gameBusMethods.Count -eq 0) {
        return $filesTouched
    }

    # Write bootstrap under primary package
    $pkg = $Meta.mod_group
    if (-not $pkg) { $pkg = 'com.example' }
    $dir = Join-Path $javaRoot ($pkg -replace '\.', [IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $importBlock = ($imports | Sort-Object) -join "`r`n"
    $modLines = if ($modBusMethods.Count) { ($modBusMethods | Select-Object -Unique) -join "`r`n" } else { '        // (none detected)' }
    $gameLines = if ($gameBusMethods.Count) { ($gameBusMethods | Select-Object -Unique) -join "`r`n" } else { '        // (none detected)' }

    $bootstrap = @"
package $pkg;

import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.common.NeoForge;
$importBlock

/**
 * Auto-generated by Convert-Forge1201-ToNeoForge262.
 * Replaces 1.20.1 @Mod.EventBusSubscriber automatic discovery.
 */
public final class LegacyEventBootstrap {
    public static void register(IEventBus modBus) {
$modLines
$gameLines
    }

    private LegacyEventBootstrap() {}
}
"@
    [System.IO.File]::WriteAllText((Join-Path $dir 'LegacyEventBootstrap.java'), $bootstrap.Trim() + "`r`n")

    # Wire into @Mod constructor if present
    foreach ($f in Get-ChildItem $javaRoot -Recurse -Filter '*.java') {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        if ($t -notmatch '@Mod\(') { continue }
        if ($t -match 'LegacyEventBootstrap') { break }
        if ($t -match 'public\s+\w+\s*\(\s*IEventBus\s+(\w+)') {
            $busParam = $Matches[1]
            $t = $t -replace '(package [^;]+;\s*)', "`$1`r`nimport $pkg.LegacyEventBootstrap;`r`n"
            # insert call after opening brace of constructor
            $t = [regex]::Replace($t,
                "(public\s+\w+\s*\(\s*IEventBus\s+$busParam\s*,\s*ModContainer\s+\w+\s*\)\s*\{)",
                "`$1`r`n        LegacyEventBootstrap.register($busParam);")
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $filesTouched++
        }
        break
    }

    return $filesTouched
}

function Ensure-ClientItems {
    param([string]$Root)
    $assets = Join-Path $Root 'src\main\resources\assets'
    if (-not (Test-Path $assets)) { return 0 }
    $n = 0
    foreach ($ns in Get-ChildItem $assets -Directory) {
        $modelsItem = Join-Path $ns.FullName 'models\item'
        if (-not (Test-Path $modelsItem)) { continue }
        $itemsDir = Join-Path $ns.FullName 'items'
        New-Item -ItemType Directory -Path $itemsDir -Force | Out-Null
        foreach ($m in Get-ChildItem $modelsItem -Filter '*.json') {
            $id = [IO.Path]::GetFileNameWithoutExtension($m.Name)
            $cp = Join-Path $itemsDir "$id.json"
            if (Test-Path $cp) { continue }
            $json = "{`r`n  `"model`": {`r`n    `"type`": `"minecraft:model`",`r`n    `"model`": `"$($ns.Name):item/$id`"`r`n  }`r`n}`r`n"
            [IO.File]::WriteAllText($cp, $json)
            $n++
        }
    }
    return $n
}

function Install-WrapperFromTowwOrMdk {
    param([string]$Root)
    $ref = 'F:\Grok Build Apps\TheOneWhoWatches-26.2'
    if ((Test-Path (Join-Path $ref 'gradlew.bat')) -and (Test-Path (Join-Path $ref 'gradle\wrapper'))) {
        Copy-Item (Join-Path $ref 'gradlew.bat') $Root -Force
        if (Test-Path (Join-Path $ref 'gradlew')) { Copy-Item (Join-Path $ref 'gradlew') $Root -Force }
        New-Item -ItemType Directory -Path (Join-Path $Root 'gradle\wrapper') -Force | Out-Null
        Copy-Item (Join-Path $ref 'gradle\wrapper\*') (Join-Path $Root 'gradle\wrapper') -Force
        Write-Ok 'Gradle wrapper copied from TheOneWhoWatches-26.2'
        return
    }
    Write-Warn2 'No wrapper reference found - run gradle wrapper manually'
}

# -------------------- main --------------------
$Source = (Resolve-Path -LiteralPath $Path).Path
if (-not (Test-Path (Join-Path $Source 'src'))) { throw "No src/ under $Source" }

if (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path (Get-Location) $OutputPath
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

Write-Host ''
Write-Host 'Legacy Java Converter - Forge 1.20.1 -> NeoForge 26.2 (EXPERIMENTAL)' -ForegroundColor White
Write-Host "  Source : $Source"
Write-Host "  Output : $OutputPath"
Write-Host "  Target : Minecraft $MinecraftVersion / NeoForge $NeoVersion"
if ($DryRun) {
    Write-Host '  DryRun : yes (preview only - no files written)' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Would perform:' -ForegroundColor Cyan
    Write-Host "  1. Copy project tree from source -> output (excluding build/.gradle/.git)"
    Write-Host "  2. Write ModDevGradle 26.2 scaffold (build.gradle, settings.gradle, gradle.properties, mods.toml)"
    Write-Host "  3. Mechanical Forge->NeoForge rewrites + 26.2 API pass + registry/event bootstrap"
    Write-Host "  4. Client item stubs + Gradle wrapper bootstrap when available"
    if ($Compile) { Write-Host "  5. Run compileJava (diagnostic)" }
    Write-Host ''
    Write-Host "Source has src/: $((Test-Path (Join-Path $Source 'src')))" -ForegroundColor Green
    $javaCount = @(Get-ChildItem (Join-Path $Source 'src') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue).Count
    Write-Host "Java files under src/: $javaCount" -ForegroundColor Green
    Write-Host ''
    Write-Host 'Dry run complete. Re-run without -DryRun to write files.' -ForegroundColor Yellow
    return
}

Write-Step 'Copying project (original preserved)'
$n = Copy-ProjectTree -Source $Source -Dest $OutputPath
Write-Ok "Copied $n files"

$meta = Get-ModMetaFromSource -Root $Source
Write-Info "mod_id=$($meta.mod_id) group=$($meta.mod_group) version=$($meta.mod_version)"

if (-not $LocalLibDir) {
    $guess = Join-Path (Split-Path $Source -Parent) ''
    if (Test-Path (Join-Path $guess 'geckolib-neoforge-26.2-5.5.3.jar')) {
        $LocalLibDir = $guess.TrimEnd('\')
    }
}

# Detect optional libraries from source (do not force SBL - Maven often has no 26.2 artifact)
$needGecko = Test-SourceNeedsLibrary -Root $OutputPath -Pattern 'geckolib|software\.bernie\.geckolib|GeoEntity|GeoModel|GeoAnimatable'
$needSbl = Test-SourceNeedsLibrary -Root $OutputPath -Pattern 'smartbrainlib|tslat\.smartbrain|SmartBrain'
Write-Info "Optional deps: GeckoLib=$needGecko SmartBrainLib=$needSbl"

Write-Step 'Writing NeoForge 26.2 Gradle scaffold + dependency map'
Write-GradleScaffold -Root $OutputPath -Meta $meta -LocalLibs $LocalLibDir -IncludeGeckoLib $needGecko -IncludeSmartBrainLib $needSbl
Write-Ok 'build.gradle / settings.gradle / gradle.properties / neoforge.mods.toml'

Write-Step 'Mechanical Java rewrites (Forge -> NeoForge, Identifier, ticks, GeckoLib5)'
$j = Invoke-MechanicalJavaRewrites -Root $OutputPath
Write-Ok "Touched $j Java file(s)"

Write-Step 'NeoForge/Minecraft 26.2 API pass (NBT, nav, teleport, weather, colors, permissions)'
$api = Invoke-NeoForge26ApiRewritePass -Root $OutputPath
Write-Ok "API-touched $api Java file(s)"

Write-Step 'Registry template pass (createEntities / Registries.SOUND_EVENT / items / blocks)'
$r = Invoke-RegistryTemplatePass -Root $OutputPath
Write-Ok "Registry-touched $r file(s)"

Write-Step 'Mod entry template pass (IEventBus + ModContainer injection)'
$m = Invoke-ModEntryTemplatePass -Root $OutputPath
Write-Ok "Mod-entry-touched $m file(s)"

Write-Step 'EventBusSubscriber -> explicit addListener bootstrap'
$e = Invoke-EventBusSubscriberPass -Root $OutputPath -Meta $meta
Write-Ok "Event-bus pass touched $e unit(s) (classes + LegacyEventBootstrap)"

Write-Step 'Client item stubs (if models/item exist)'
$ci = Ensure-ClientItems -Root $OutputPath
Write-Ok "Created $ci client item file(s)"

Write-Step 'Gradle wrapper'
Install-WrapperFromTowwOrMdk -Root $OutputPath

$reportPath = Join-Path $OutputPath 'LEGACY_MIGRATION_REPORT.md'
$report = @"
# Legacy migration report: $($meta.mod_id)

- Source: ``$Source``
- Output: ``$OutputPath``
- Target: Minecraft $MinecraftVersion / NeoForge $NeoVersion
- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')

## What was automated

1. Full project copy (original unchanged)
2. ModDevGradle 26.2 scaffold (Java 25)
3. Dependency map:
   - GeckoLib -> ``com.geckolib:geckolib-neoforge-26.2:$GeckoLibVersion``
   - SmartBrainLib -> ``net.tslat.smartbrainlib:SmartBrainLib-neoforge-26.2:$SmartBrainLibVersion``
4. Mechanical package renames Forge -> NeoForge
5. Safer TickEvent rewrite (ClientTickEvent.Post / ServerTickEvent.Post)
6. ``ResourceLocation`` -> ``Identifier`` (MC 26.x rename)
7. GeckoLib 4 packages -> GeckoLib 5 (``com.geckolib`` + AnimationController ctor)
8. **26.2 API pass** (proven on Friend): NBT OrEmpty, isSolidRender, PathNavigation.moveTo vs Entity.snapTo,
   EntitySpawnReason create, server via level().getServer(), BreakBlockEvent, permissions, ColorCollection blocks,
   weather/clock stubs, cross-dim teleport signature, Camera.position, ClipContext CollisionContext
9. Registry templates (createEntities / Registries.SOUND_EVENT / createItems / createBlocks)
10. ``@Mod`` constructor injection template (IEventBus + ModContainer)
11. ``@Mod.EventBusSubscriber`` -> ``LegacyEventBootstrap`` + ``addListener`` registrations
12. Entity level accessors (safe ``this.level()`` only), getCenter, setMaxUpStep comment-out
13. pack.mcmeta format 107 + neoforge.mods.toml template
14. Client item stubs where models/item existed

## What you must still fix manually

- GeckoLib 5 render/model method signatures (GeoRenderState)
- SmartBrainLib 1.x -> 2.x API if used
- Written books / dyed items (DataComponents) if used heavily
- Nested/multi-line teleportTo and complex expression rewrites
- Networking, capabilities, worldgen datapacks
- Mixins (if any)
- SynchedEntityData.define builder APIs, entity tags, remaining vanilla package moves

## Next commands

``````powershell
cd "$OutputPath"
.\gradlew.bat compileJava --stacktrace
.\gradlew.bat build
``````

Local jars (optional install into mods for runClient):
- ``$LocalLibDir\geckolib-neoforge-26.2-5.5.3.jar``
- ``$LocalLibDir\smartbrainlib-neoforge-26.2-2.0.0.jar``
"@
[System.IO.File]::WriteAllText($reportPath, $report)

Write-Ok "Wrote $reportPath"

$compileExit = 0
if ($Compile) {
    Write-Step 'Running compileJava (diagnostic only - conversion already succeeded)'
    Push-Location $OutputPath
    try {
        # Use cmd so PowerShell does not treat Gradle stderr as a terminating error
        cmd /c "gradlew.bat compileJava --no-daemon --stacktrace > compile-errors.log 2>&1"
        $compileExit = $LASTEXITCODE
        Write-Host "Gradle exit: $compileExit"
        if ($compileExit -ne 0) {
            Write-Warn2 "compileJava failed (exit $compileExit). Scaffold is still written."
            Write-Warn2 "See compile-errors.log in the output folder for details."
            if (Test-Path (Join-Path $OutputPath 'compile-errors.log')) {
                Get-Content (Join-Path $OutputPath 'compile-errors.log') -Tail 40 | ForEach-Object { Write-Host "    $_" }
            }
        } else {
            Write-Ok 'compileJava succeeded'
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host ''
Write-Host "Conversion scaffold complete: $OutputPath" -ForegroundColor Green
Write-Host 'Original unchanged.' -ForegroundColor Green
if ($Compile -and $compileExit -ne 0) {
    Write-Host "Note: optional compile failed with exit $compileExit (conversion still OK)." -ForegroundColor Yellow
}
# Always exit 0 after successful scaffold so GUI does not report hard failure for diagnostic compile
exit 0
