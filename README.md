# Legacy Java Converter


**Current release: [v2.0.4](https://github.com/RobbieB1980/LegacyJavaConverter/releases/tag/v2.0.4)**

## Learnings (2.0.x)

- [Hand-written NeoForge learnings](docs/LEARNINGS-HANDWRITTEN-NEOFORGE.md) — for Java modders
- [Solved notes mirror](docs/solved/README.md) — CASE-003/004, DFU/overlay/soft-dep
- [Release 2.0.4 notes](docs/RELEASE-2.0.4.md)


Windows GUI and PowerShell migration assistant for **Forge/NeoForge 1.20.1 through 26.1** â†’ **NeoForge 26.2** ModDevGradle projects.

The converter detects the source version and API features, decompiles finished JARs, migrates known Java/resource patterns, resolves dependencies, generates the 26.2 project and optionally runs a complete Gradle build. Project-specific code can still require manual repair. The rewrite stack was proven on:

- **Friend** â€” compile, world creation, in-game entity spawn
- **The Knocker** â€” NeoForge 1.21.8 jar â†’ 26.2 compile + in-game spawn
- **The One Who Watches** â€” Forge 1.20.1 â†’ 26.2 jar loads (GeckoLib 5 geo/anim, spawn egg, world data)
- **MOAdecor BATH 1.21.8.A** â€” MCreator NeoForge 1.21.8 jar â†’ 26.2 **compile + `gradlew build`**
- **NextGen Furniture 1.21.11** â€” finished NeoForge jar â†’ 26.2 **full build and installable jar**
- **NextGen Furniture 1.21.1** â€” exact-version primer path â†’ 26.2 **full build and installable jar**
- **Mel's DeCo 1.21.4** — MCreator NeoForge → 26.2 full build + in-game (converter 2.0.2)
- **MedSystem 1.21.1** — hand-written NeoForge → 26.2 full build + in-game (converter 2.0.4)

Related product: [RB-Mcreator-Version-Updater](https://github.com/RobbieB1980/RB-Mcreator-Version-Updater) (26.1 â†’ 26.2 NeoForge/MCreator updater).

## Downloads (Windows)

From [GitHub Releases](https://github.com/RobbieB1980/LegacyJavaConverter/releases):

| Artifact | Description |
|----------|-------------|
| `RB-Legacy-Java-Converter-Setup.exe` | GUI installer (self-contained, embeds portable package) |
| `RB-Legacy-Java-Converter-Portable.zip` | Portable folder â€” unzip and run `RB-Legacy-Java-Converter.exe` |

Build locally:

```powershell
.\scripts\Build-Release.ps1
```

Outputs land in `dist\`. See [CHANGELOG.md](CHANGELOG.md) for version history.

## GUI app

1. Install via Setup.exe **or** extract the portable zip.
2. Run **RB Legacy Java Converter**.
3. Choose a mode:
   - **Mode A â€” Project folder:** Forge 1.20.1 (or decompiled) source with `src/`
   - **Mode B â€” Finished `.jar`:** Vineflower decompile â†’ optional NeoForge 26.2 scaffold
4. Choose **Input** and empty **Output** folder.
5. Optionally enable **Compile after convert** to run the full Gradle build and produce the versioned JAR (needs JDK 25; jar mode also needs Java 17+ for Vineflower).
6. Click **Convert** / **Jar â†’ 26.2**. Original input is never modified.

See [docs/JAR-PIPELINE.md](docs/JAR-PIPELINE.md) for the jar workflow.

See [docs/SUPPORTED-VERSIONS.md](docs/SUPPORTED-VERSIONS.md) for the routing matrix and completion criteria, and [docs/RELEASE-1.5.1.md](docs/RELEASE-1.5.1.md) for this release's verified build.

The converter now auto-detects the source loader/version and inventories legacy API usage before selecting rewrite passes. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the executable cumulative 1.20.1-through-26.2 migration graph. Every final scaffold also receives `PRIMER_CHANGE_INDEX.md`, a source-specific quick reference generated from `lib/PrimerChangeIndex.json`.

## CLI (PowerShell)

### Project â†’ 26.2

```powershell
.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "D:\mods\MyForgeMod-1.20.1" `
  -OutputPath "D:\mods\MyForgeMod-26.2" `
  -Compile
```

### Finished JAR â†’ decompiled project

```powershell
.\Convert-JarToProject.ps1 `
  -JarPath "D:\mods\oldmod.jar" `
  -OutputPath "D:\mods\oldmod-decompiled"
```

### Finished JAR â†’ NeoForge 26.2 (full pipeline)

```powershell
.\Convert-OldJarToNeoForge262.ps1 `
  -JarPath "D:\mods\oldmod.jar" `
  -OutputPath "D:\mods\oldmod-26.2" `
  -Compile
```

| Parameter | Description |
|-----------|-------------|
| `-Path` | Source Forge 1.20.1 project (required) |
| `-OutputPath` | Empty output folder (required) |
| `-Compile` | Run the complete `gradlew build`; success requires an installable JAR in `build/libs` |
| `-DryRun` | Preview only â€” no files written |
| `-NeoVersion` | Default `26.2.0.72` |
| `-GeckoLibVersion` | Default `5.5.3` |

After conversion:

```powershell
cd "D:\mods\MyForgeMod-26.2"
.\gradlew.bat compileJava --stacktrace
.\gradlew.bat build
```

Converter regression checks:

```powershell
.\tests\Run-RegressionTests.ps1
dotnet build RB.LegacyJavaConverter.slnx
```

A `LEGACY_MIGRATION_REPORT.md` is written in the output folder.

## What is automated

1. Full project copy (excludes `build/`, `.gradle/`, etc.)
2. Evidence-based source profiling (`SOURCE_PROFILE.json`) and route-aware rule selection
3. ModDevGradle **26.2** scaffold
4. Dependency map (GeckoLib 5 / SmartBrainLib 2 for 26.2)
4. Forge â†’ NeoForge package renames
5. Tick event rewrites, `ResourceLocation` â†’ `Identifier`
6. GeckoLib 4 â†’ 5 package paths + controller constructor shape
7. **26.2 API pass** (Friend + Knocker + BuildPaste lessons): NBT OrEmpty, navigation, spawn reason, permissions, full ColorCollection grid (`Items`/`Blocks`), `EntityTypes` registry fields, weather/clock stubs, teleport signature, `sendSystemMessage`, respawn/`getSpawnPos`, `CommandSourceStack` PermissionSet, `FMLEnvironment.getDist()`, spawn eggs / `registerItem`, client `RenderTypes`/`ArmorModelSet`, `mainCamera` / `gameRenderer.renderBuffers()`, â€¦
8. Registry templates + `@Mod.EventBusSubscriber` â†’ bootstrap
9. **Removes leftover `resources/META-INF/neoforge.mods.toml`** so templates pin Minecraft **`[26.2]`** (prevents â€œwrong MC versionâ€ load errors from 1.21.x jars)
10. Gradle wrapper bootstrap when a local reference exists

## What you must still fix manually

- Remaining compile errors after scaffold (especially complex client render / networking)
- World-space custom geometry still on `MultiBufferSource` / `.bufferSource()` â€” port to `SubmitCustomGeometryEvent` + `submitShapeOutline`
- Datapacks (biomes / dimension types often need 26.2 JSON shape)
- GeckoLib assets under `assets/<mod>/geckolib/models|animations/` with bare resource IDs
- Written books / dyed items (data components)
- Mixins, transfer/capabilities API, complex gameplay
- Runtime testing (`runClient`)
- New or project-specific API changes that do not yet have a tested rule; use `SOURCE_PROFILE.json` and `COMPILE_REPORT.md` to add these incrementally
- **Always `gradlew build` and install `build/libs` only** â€” never the original input jar

## Requirements

- Windows 10/11 (GUI installer + app)
- PowerShell 5.1+ (bundled with Windows)
- Java **25** for compile/build of converted projects
- Internet for first Gradle resolve of NeoForge

## License

MIT â€” see [LICENSE](LICENSE).

## Disclaimer

Provided as-is for migration assistance. Always keep backups of original projects. Review generated code before shipping.


