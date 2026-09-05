# GokuAI Fix-in-Grok workspace overlay

This tree is synced into `C:\gokuai\projects\RB-Legacy-Java-Converter` so **Fix in Grok** sessions get the same skills, agents, workflows, and standing orders developed for migration repair.

## Contents

- `.grok/skills/` — `repair-failed-262-output`, `migrate-neoforge-262`, `encode-262r-remap`, `validate-destination-build`, `minecraft-knowledge`
- `.grok/agents/` — `mc-research`, `mc-fast`, `mc-code`, `mc-reviewer`
- `.grok/workflows/` — `repair-neoforge-262.rhai`
- `.grok/rules/` — knowledge pointers
- `Agents.md` — slim standing orders
- `tools/` — `Build-WithDestinationJava.ps1`, `Lint-MigrationSkills.ps1`

## Sync

```powershell
.\scripts\Sync-GokuaiConverterWorkspace.ps1
```

`Build-Release.ps1` also runs this sync on the build machine after packaging.
