# Native Codex repair workspace overlay

This directory is the versioned repair environment installed into a failed
LegacyJavaConverter output before GokuCodexAI opens.

- `AGENTS.md` — durable Codex orchestration and validation policy.
- `.agents/skills/` — reusable migration, repair, knowledge, validation, and
  write-back workflows.
- `.codex/config.toml` — project-scoped local Minecraft knowledge MCP template.
- `tools/` — deterministic destination-Java build and skill-lint tools.

The overlay is native to Codex. It does not require a Grok executable,
account, service, environment variable, or project configuration.

`legacy-java-converter-vnext` is the top-level workflow. It keeps deterministic
conversion, known solutions, AST repair, preservation checks, Gradle build,
and runtime correctness as ordered and separately reported stages.
