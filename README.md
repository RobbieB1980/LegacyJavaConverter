# Legacy Java Converter

**Current release: v1.2.1**

**Experimental** PowerShell + Windows GUI converter: **Minecraft Forge 1.20.1** (and decompiled NeoForge 1.21.x jars) → **NeoForge 26.2** (ModDevGradle) scaffolds.

This is a first-pass automation tool. It is **not** a complete port. Large mods still need manual follow-up after the scaffold. The rewrite stack was proven on:

- **Friend** — compile, world creation, in-game entity spawn
- **The Knocker** — NeoForge 1.21.8 jar → 26.2 compile + loadable metadata (`[26.2]`)

Related product: [RB-Mcreator-Version-Updater](https://github.com/RobbieB1980/RB-Mcreator-Version-Updater) (26.1 → 26.2 NeoForge/MCreator updater).

## Downloads (Windows)

From [GitHub Releases](https://github.com/RobbieB1980/LegacyJavaConverter/releases):

| Artifact | Description |
|----------|-------------|
| `RB-Legacy-Java-Converter-Setup.exe` | GUI installer (self-contained, embeds portable package) |
| `RB-Legacy-Java-Converter-Portable.zip` | Portable folder — unzip and run `RB-Legacy-Java-Converter.exe` |

Build locally:

```powershell
.\scripts\Build-Release.ps1
```

Outputs land in `dist\`. See [CHANGELOG.md](CHANGELOG.md) for version history.

## GUI app

1. Install via Setup.exe **or** extract the portable zip.
2. Run **RB Legacy Java Converter**.
3. Choose a mode:
   - **Mode A — Project folder:** Forge 1.20.1 (or decompiled) source with `src/`
   - **Mode B — Finished `.jar`:** Vineflower decompile → optional NeoForge 26.2 scaffold
4. Choose **Input** and empty **Output** folder.
5. Optionally enable **Compile after convert** (needs JDK 25; jar mode also needs Java 17+ for Vineflower).
6. Click **Convert** / **Jar → 26.2**. Original input is never modified.

See [docs/JAR-PIPELINE.md](docs/JAR-PIPELINE.md) for the jar workflow.

## CLI (PowerShell)

### Project → 26.2

```powershell
.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "D:\mods\MyForgeMod-1.20.1" `
  -OutputPath "D:\mods\MyForgeMod-26.2" `
  -Compile
```

### Finished JAR → decompiled project

```powershell
.\Convert-JarToProject.ps1 `
  -JarPath "D:\mods\oldmod.jar" `
  -OutputPath "D:\mods\oldmod-decompiled"
```

### Finished JAR → NeoForge 26.2 (full pipeline)

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
| `-Compile` | Run `gradlew compileJava` after conversion |
| `-DryRun` | Preview only — no files written |
| `-NeoVersion` | Default `26.2.0.32-beta` |
| `-GeckoLibVersion` | Default `5.5.3` |

After conversion:

```powershell
cd "D:\mods\MyForgeMod-26.2"
.\gradlew.bat compileJava --stacktrace
.\gradlew.bat build
```

A `LEGACY_MIGRATION_REPORT.md` is written in the output folder.

## What is automated

1. Full project copy (excludes `build/`, `.gradle/`, etc.)
2. ModDevGradle **26.2** scaffold
3. Dependency map (GeckoLib 5 / SmartBrainLib 2 for 26.2)
4. Forge → NeoForge package renames
5. Tick event rewrites, `ResourceLocation` → `Identifier`
6. GeckoLib 4 → 5 package paths + controller constructor shape
7. **26.2 API pass** (Friend + Knocker + BuildPaste lessons): NBT OrEmpty, navigation, spawn reason, permissions, full ColorCollection grid (`Items`/`Blocks`), `EntityTypes` registry fields, weather/clock stubs, teleport signature, `sendSystemMessage`, respawn/`getSpawnPos`, `CommandSourceStack` PermissionSet, `FMLEnvironment.getDist()`, spawn eggs / `registerItem`, client `RenderTypes`/`ArmorModelSet`, `mainCamera` / `gameRenderer.renderBuffers()`, …
8. Registry templates + `@Mod.EventBusSubscriber` → bootstrap
9. **Removes leftover `resources/META-INF/neoforge.mods.toml`** so templates pin Minecraft **`[26.2]`** (prevents “wrong MC version” load errors from 1.21.x jars)
10. Gradle wrapper bootstrap when a local reference exists

## What you must still fix manually

- Remaining compile errors after scaffold (especially complex client render / networking)
- World-space custom geometry still on `MultiBufferSource` / `.bufferSource()` — port to `SubmitCustomGeometryEvent` + `submitShapeOutline`
- Datapacks (biomes / dimension types often need 26.2 JSON shape)
- GeckoLib assets under `assets/<mod>/geckolib/models|animations/` with bare resource IDs
- Written books / dyed items (data components)
- Mixins, transfer/capabilities API, complex gameplay
- Runtime testing (`runClient`)
- **Always `gradlew build` and install `build/libs` only** — never the original input jar

## Requirements

- Windows 10/11 (GUI installer + app)
- PowerShell 5.1+ (bundled with Windows)
- Java **25** for compile/build of converted projects
- Internet for first Gradle resolve of NeoForge

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

Provided as-is for migration assistance. Always keep backups of original projects. Review generated code before shipping.
