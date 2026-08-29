# Release 2.0.4 — 2026-08-30

## Highlights

- GUI/Setup product version **2.0.4** (window titles no longer stuck on 1.5.5).
- MedSystem CASE-004 Mode B green reconvert: rebuilt `lib/overlays/medsystem/1.21.1.zip` from the proven green tree; filled `DELETE.txt`; synced mixins.json.
- Soft-dep exclude matches `integration/carryon|sable|jei|appleskin` paths as well as hard imports.
- Includes Mel 2.0.0–2.0.3 API/DFU bands.

## Downloads

GitHub: https://github.com/RobbieB1980/LegacyJavaConverter/releases/tag/v2.0.4

| Asset | Use |
|---|---|
| `RB-Legacy-Java-Converter-Setup.exe` | Installer (embeds portable toolset) |
| `RB-Legacy-Java-Converter-Portable.zip` | Extract and run |

## Learnings for the next coder / agent

See [LEARNINGS-HANDWRITTEN-NEOFORGE.md](LEARNINGS-HANDWRITTEN-NEOFORGE.md).

## Verify install

1. GUI title shows **v2.0.4**
2. `%LOCALAPPDATA%\RB-Legacy-Java-Converter\version.txt` is `2.0.4`
3. Mode B MedSystem 1.21.1 jar → `gradlew build` produces `medsystem-2.12.1+mc26.2-neoforge.jar`
