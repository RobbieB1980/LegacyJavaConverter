# Learnings for Java modders — NeoForge 1.21.x → 26.2

This document is for **human Java Minecraft / NeoForge modders** and for AI assistants helping them. It summarizes what we encoded into **RB Legacy Java Converter 2.0.4** after converting Mel's DeCo (MCreator) and TarkovCraft MedSystem (hand-written).

Converter releases: https://github.com/RobbieB1980/LegacyJavaConverter/releases

## Prefer official 26.2 builds when they exist

If CurseForge/Modrinth already ships a NeoForge **26.2** jar for your mod, install that for play. Use this converter when you need to uplift an older jar/workspace yourself.

## Two failure bands

### 1) MCreator / GUI-heavy mods

Symptoms: `RenderSystem`, old armor/tool constructors, ValueInput, permission `_level*`, Optional NBT, item model `ItemOwner`, PacketDistributor oddities.

Converter encodes these mechanically (ExactPrimer + NeoForge 26 API + MCreator 1.21.x passes). Proven: Mel's DeCo 1.21.4 → 26.2.

### 2) Hand-written DFU / records / mixins

Symptoms after Vineflower decompile:

- `RecordCodecBuilder` / `Kind1.group` inference collapsing to `Object`
- Record **field** access inside `.validate(...)` (`config.limbs` instead of `config.limbs()`)
- Mixin `(LivingEntity)this` rejected by javac → need `(LivingEntity)(Object)this`
- Optional integrations (Carry On / Sable) still on the compile classpath

**Manual Java fixes (if you are not using the converter):**

```java
// Type witness
public static final Codec<LimbConfiguration> CODEC = RecordCodecBuilder.<LimbConfiguration>create(
    instance -> instance.group(/* ... */).apply(instance, LimbConfiguration::new)
).validate(config -> !config.limbs().containsKey(config.rootLimb())
    ? DataResult.error(() -> "...")
    : DataResult.success(config));

// Mixin
LivingEntity self = (LivingEntity)(Object)this;
```

Soft optional integrations: delete or Gradle-exclude `integration/carryon/**` and `integration/sable/**` when those mods are not dependencies.

Proven: MedSystem 1.21.1 → 26.2 (`medsystem-2.12.1+mc26.2-neoforge.jar`).

## Overlay / patch pack hygiene

If you maintain a “known-good patch zip” applied after automated rewrites:

- Build it from a tree that **already compiles**, not from a raw decompile of someone else’s jar.
- Include a delete-list for files that must not remain.
- Keep `*.mixins.json` in sync with deleted mixin classes.

A bad overlay applied last will silently undo good automated DFU repairs.

## JPMS note

Do not ship a shared `rb.legacy.converter.compat` helper package in multiple converted jars — NeoForge module layers will conflict. Scope helpers per mod id.

## Verification

Claim success only when:

1. `gradlew build` succeeds
2. You have an installable `build/libs/*.jar`
3. Ideally the jar loads in-game on NeoForge **26.2.0.72** with required deps

## Further reading in this repo

- `CHANGELOG.md` (2.0.0–2.0.4)
- `docs/RELEASE-2.0.4.md`
- `docs/JAR-PIPELINE.md`, `docs/USAGE.md`
