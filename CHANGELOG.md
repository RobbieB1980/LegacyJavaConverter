# Changelog

## 1.2.0 — 2026-07-25

Proven on **Friend** (runtime) and **The Knocker** (NeoForge 1.21.8 jar → 26.2 compile/build).

### Critical fixes
- **Strip leftover `src/main/resources/META-INF/neoforge.mods.toml`** (and `mods.toml` / `MANIFEST.MF`) so generated templates control Minecraft/NeoForge `versionRange`.
  - Fixes loader rejection still asking for old versions such as **1.21.8**.
- Clearer docs: conversion success ≠ loadable mod; only install `gradlew build` output jars; never rename the input jar as 26.2.

### API rewrite expansions (26.2)
- `displayClientMessage` → `sendSystemMessage`
- `getLevelData().getSpawnPos()` → `getRespawnData().pos()`
- `getRespawnConfig().pos()/dimension()` → `respawnData()...`
- Broader `entity.getServer()` → `level().getServer()` receivers
- `CommandSourceStack` permission int → `LevelBasedPermissionSet`
- `FMLEnvironment.dist` → `FMLEnvironment.getDist()`
- `registerItem(name, fn, new Properties())` → two-arg form
- `SpawnEggItem(EntityType, Properties)` → entity data component form
- Client: `MultiBufferSource`/`RenderType` → `SubmitNodeCollector`/`RenderTypes`
- Humanoid armor: `PLAYER_INNER/OUTER_ARMOR` → `ArmorModelSet` + `PLAYER_ARMOR`
- `PlayerSkin.texture()` → `body().texturePath()`
- Comment out obsolete `Capabilities.ItemHandler` block-entity registration

### Metadata
- Prefer `modId` / display name / authors from existing NeoForge/Forge toml when present

### Packaging
- GUI + Setup version **1.2.0**

## 1.1.1
- Fix Mode B hard-fail on diagnostic compile

## 1.1.0
- Finished-JAR decompile pipeline and dual-mode GUI

## 1.0.0
- Initial Windows GUI app, installer, and Forge 1.20.1 → NeoForge 26.2 scaffold
