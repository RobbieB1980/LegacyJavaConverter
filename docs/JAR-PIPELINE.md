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

## Limits

- Decompiled code is imperfect
- Mixins often need heavy hand work
- Fabric/Quilt jars extract, but rewrites target Forge/NeoForge
- Always keep the original jar; never overwrite it
