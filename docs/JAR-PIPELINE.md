# JAR pipeline (finished mods without Gradle)

Minecraft mod jars are **not encrypted**. This tool **decompiles** and **unpacks** them.

## Modes in the GUI

| Mode | Input | Output |
|------|--------|--------|
| **A: Project** | Forge 1.20.1 source folder | NeoForge 26.2 scaffold |
| **B: JAR** | Finished `.jar` | Decompiled project, or full pipeline to 26.2 |

## CLI

### Decompile only

```powershell
.\Convert-JarToProject.ps1 `
  -JarPath "D:\mods\oldmod-1.20.1.jar" `
  -OutputPath "D:\mods\oldmod-decompiled"
```

Produces:

- `src/main/java/...` (Vineflower)
- `src/main/resources/...` (assets/data/META-INF)
- `gradle.properties` stub
- `DECOMPILE_REPORT.md`

### Full pipeline (jar → 26.2)

```powershell
.\Convert-OldJarToNeoForge262.ps1 `
  -JarPath "D:\mods\oldmod-1.20.1.jar" `
  -OutputPath "D:\mods\oldmod-26.2" `
  -Compile
```

Steps:

1. Decompile to `<name>-decompiled` next to the output parent  
2. Run `Convert-Forge1201-ToNeoForge262.ps1` into your 26.2 output folder  

## Requirements

- **Java 17+** on PATH (for Vineflower)
- First run downloads Vineflower to `tools/lib/decompiler-cache/`

## After conversion

1. Open the **26.2 output project** (not the intermediate decompile only).
2. Run:

```powershell
cd "D:\mods\oldmod-26.2"
.\gradlew.bat compileJava --stacktrace
.\gradlew.bat build
```

3. Install **only** `build\libs\*-mc26.2-neoforge.jar` (or similar) into your Minecraft 26.2 mods folder.

### Common pitfall (fixed in v1.2.0)

If an old `META-INF/neoforge.mods.toml` from a 1.21.x jar is left in `src/main/resources`, NeoForge may still require Minecraft `1.21.8` (or similar) even though the Gradle scaffold targets 26.2.  
v1.2.0 **deletes** resource-side mod toml files and regenerates from `src/main/templates`.

**Never** rename the original input jar and put it in a 26.2 mods folder.

## Limits

- Decompiled code is imperfect
- Mixins often need heavy hand work
- Fabric/Quilt jars extract, but rewrites target Forge/NeoForge
- Always keep the original jar; never overwrite it
- Scaffold success ≠ compile success; expect manual fixes on large mods
