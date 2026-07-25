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

## Pin NeoForge version

```powershell
.\Convert-Forge1201-ToNeoForge262.ps1 `
  -Path "C:\mods\legacy\mymod" `
  -OutputPath "C:\mods\mymod-26.2" `
  -NeoVersion "26.2.0.32-beta" `
  -ModDevGradleVersion "2.0.141"
```
