# Usage examples

## Convert without compile

```powershell
.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "C:\mods\legacy\mymod" `
  -OutputPath "C:\mods\mymod-26.2"
```

## Convert and capture compile errors

```powershell
.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "C:\mods\legacy\mymod" `
  -OutputPath "C:\mods\mymod-26.2" `
  -Compile
# See C:\mods\mymod-26.2\compile-errors.log and LEGACY_MIGRATION_REPORT.md
```

## Finished NeoForge 1.21.x jar → 26.2 scaffold

```powershell
.\Convert-OldJarToNeoForge262.ps1 `
  -JarPath "C:\mods\the_knocker-1.5.2-neoforge-1.21.8.jar" `
  -OutputPath "C:\mods\the_knocker-26.2" `
  -Compile
```

Then fix remaining compile errors if needed and:

```powershell
cd "C:\mods\the_knocker-26.2"
.\gradlew.bat build
# Install build\libs\*.jar only — not the original 1.21.8 jar
```

## Pin NeoForge version

```powershell
.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "C:\mods\legacy\mymod" `
  -OutputPath "C:\mods\mymod-26.2" `
  -NeoVersion "26.2.0.32-beta" `
  -ModDevGradleVersion "2.0.141"
```

