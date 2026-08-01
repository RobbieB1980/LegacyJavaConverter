# Changelog

## 1.2.5 — 2026-08-01

### Networking forEach type-inference fix (MOAdecor GARDEN)
- **Fix:** MCreator main class pattern  
  `MESSAGES.forEach((id, msg) -> registrar.playBidirectional(...))`  
  fails to compile under Java generics wildcards  
  (`no suitable method found for playBidirectional` / CAP# constraints).
- Converter rewrites that form to a typed `registerOne` helper loop.
- Prefer registering `MenuStateUpdateMessage` on `RegisterPayloadHandlersEvent`  
  with 4-arg handlers (not `FMLCommonSetupEvent`).

Proven: **MOAdecor GARDEN 1.21.8.A** → `gradlew build`.

### Packaging
- GUI / Setup / portable package **1.2.5**

## 1.2.4 — 2026-08-01

### Converter rewrite safety (MOAdecor ELECTRONICS)
- **Fix:** naive `playBidirectional` 3→4-arg expansion could mangle
  `networkMessage.handler()` into invalid Java  
  `handler(, handler(), handler())` (compile failure).
- Now only rewrites the exact MCreator form  
  `playBidirectional(id, msg.reader(), msg.handler())`  
  and can repair the previously corrupted form.
- **Fix:** `registerItem` rewrite no longer treats nested  
  `new BlockItem(..., prop)` as the third argument; repairs  
  `BlockItem(..., () -> prop)` and wraps only the final  
  `properties` variable as `() -> properties`.

Proven: **MOAdecor ELECTRONICS 1.21.8.A** → `gradlew build` after re-apply.

### Packaging
- GUI / Setup / portable package **1.2.4**

## 1.2.3 — 2026-08-01

### MCreator / NeoForge 1.21.x → 26.2 pass (MOAdecor BATH)
New rewrite pass for decompiled **1.21.8 NeoForge / MCreator** jars (in addition to Forge 1.20.1). Not a separate converter product — same Legacy pipeline + extra pass:
- Remove `shouldDisplayFluidOverlay` + old `BlockAndTintGetter` import (method gone from Block)
- `.noCollission()` → `.noCollision()`
- `GuiGraphics` → `GuiGraphicsExtractor`; `renderBg` → `extractBackground`; tooltip/label extract renames
- Final `imageWidth`/`imageHeight` → `super(menu, inv, title, w, h)` (including delayed field assigns)
- `keyPressed(int,int,int)` → `keyPressed(KeyEvent)` (ESC close pattern)
- `.isClientSide` field → `.isClientSide()`
- `net.minecraft.util.Tuple` delayed work queue → `Object[]` holders
- Stub MCreator `ItemHandler.ITEM` / `ItemHandler.ENTITY` capability binds (transfer API is manual)
- `Minecraft.getInstance().screen` → `gui.screen()`
- `registerItem(name, fn, Properties)` → supplier form `() -> properties`
- Payload `StreamCodec<? extends FriendlyByteBuf` → `? super RegistryFriendlyByteBuf`
- **Critical networking:** use 4-arg `playBidirectional(type, codec, handler, handler)` — 3-arg leaves client handler null and crashes with `missing client-side handlers`

Proven: **MOAdecor BATH 1.21.8.A** → compile, `gradlew build`, and **client load on NeoForge 26.2.0.32-beta**.

### Packaging
- GUI / Setup / portable package **1.2.3**

## 1.2.2 — 2026-08-01

### 26.2 API rewrite expansions (BuildPaste / decompile lessons)
- `EntityType.VANILLA_FIELD` → `EntityTypes.VANILLA_FIELD` (+ import)
- Full **ColorCollection** grid for `Items`/`Blocks` (`WHITE_WOOL` → `WOOL.white()`, glazed terracotta, beds, carpets, …)
- `getMainCamera()` → `mainCamera()`
- `Minecraft.getInstance().renderBuffers()` → `gameRenderer.renderBuffers()`
- Note: `MultiBufferSource` / `.bufferSource()` world drawing still needs manual `SubmitCustomGeometryEvent` + `submitShapeOutline` (naive renames are not enough)

### Packaging
- Bump GUI / portable package when releasing **1.2.2**

## 1.2.1 — 2026-07-25

### Critical fix (The Knocker world-join disconnect)
- **ModConfigSpec define-before-build pass:** decompiled MCreator configs that call `BUILDER.build()` before `.define(...)` caused  
  `Cannot get config value before spec is built` on player spawn → **Connection lost / Disconnected**.
- Converter now reorders SPEC construction after config value definitions.

### Packaging
- GUI + Setup version **1.2.1**
- Rebuild installer / portable package

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

## 1.1.x and earlier
See git history for initial GUI, jar pipeline, and Forge 1.20.1 scaffold support.
