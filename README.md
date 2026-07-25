# Legacy Java Converter

**Experimental** PowerShell converter: **Minecraft Forge 1.20.1** workspaces → **NeoForge 26.2** (ModDevGradle) scaffolds.

This is a first-pass automation tool. It is **not** a complete port. Large mods (for example Friend) still need manual follow-up after the scaffold, but the rewrite stack is proven enough to reach **green `compileJava` / `build`** on that project after additional API fixes.

Related product: [RB-Mcreator-Version-Updater](https://github.com/RobbieB1980/RB-Mcreator-Version-Updater) (26.1 → 26.2 NeoForge/MCreator updater).

## Requirements

- Windows + PowerShell 5.1+ (or PowerShell 7+)
- Java **25** toolchain for NeoForge 26.2 builds
- A Forge **1.20.1** source tree with `src/`
- Internet access the first time Gradle resolves NeoForge / ModDevGradle

## Quick start

```powershell
git clone https://github.com/RobbieB1980/LegacyJavaConverter.git
cd LegacyJavaConverter

.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "D:\mods\MyForgeMod-1.20.1" `
  -OutputPath "D:\mods\MyForgeMod-26.2" `
  -Compile
```

| Parameter | Description |
|-----------|-------------|
| `-Path` | Source Forge 1.20.1 project (required) |
| `-OutputPath` | Empty output folder for the 26.2 copy (required) |
| `-Compile` | Run `gradlew compileJava` after conversion (diagnostic) |
| `-NeoVersion` | Default `26.2.0.32-beta` |
| `-GeckoLibVersion` | Default `5.5.3` |
| `-SmartBrainLibVersion` | Default `2.0.0` |
| `-LocalLibDir` | Optional folder with local dependency jars |

The **original project is not modified** — conversion works on a copy.

After conversion:

```powershell
cd "D:\mods\MyForgeMod-26.2"
.\gradlew.bat compileJava --stacktrace
.\gradlew.bat build
```

A `LEGACY_MIGRATION_REPORT.md` is written in the output folder.

## What is automated

1. Full project copy (excludes `build/`, `.gradle/`, etc.)
2. ModDevGradle **26.2** scaffold (`build.gradle`, `settings.gradle`, `gradle.properties`, `neoforge.mods.toml`)
3. Dependency map (GeckoLib 5 / SmartBrainLib 2 for 26.2)
4. Forge → NeoForge package renames
5. Safer tick event rewrites (`ClientTickEvent.Post` / `ServerTickEvent.Post`)
6. `ResourceLocation` → `Identifier`
7. GeckoLib 4 → 5 package paths + `AnimationController` constructor shape
8. **26.2 API pass** (NBT OrEmpty, `isSolidRender`, navigation `moveTo` vs entity `snapTo`, `EntitySpawnReason`, server access, `BreakBlockEvent`, permissions, ColorCollection blocks, weather/clock stubs, cross-dim teleport, Camera, ClipContext, …)
9. Registry templates (`createEntities` / sound / items / blocks)
10. `@Mod` constructor injection template
11. `@Mod.EventBusSubscriber` → `LegacyEventBootstrap` + `addListener`
12. Gradle wrapper bootstrap (from a local TOWW reference when available)
13. Client item stubs when item models exist

## What you must still fix manually

- Complex gameplay / AI / networking still on 1.20.1 APIs
- Written books and dyed items (data components) if heavily used
- Nested multi-line `teleportTo` expressions
- GeckoLib render/model `GeoRenderState` signatures
- Mixins, capabilities, datapack worldgen edge cases
- Runtime testing (`runClient`, commands, dimensions)

## Validation note (Friend)

The Friend mod (Forge 1.20.1 → NeoForge 26.2) was used as a large real-world driver:

- Scaffold + multi-pass rewrites + manual/API follow-up → **`gradlew build` SUCCESS**
- Artifact shape: `friend-*-mc26.2-neoforge.jar` with GeckoLib 26.2 as a runtime dependency

Expect other mods to need different residual fixes; Friend was a stretch goal, not a guarantee for every codebase.

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

Provided as-is for migration assistance. Always keep backups of original projects. Review generated code before shipping.
