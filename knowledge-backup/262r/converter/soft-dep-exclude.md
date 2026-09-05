# Converter — soft-dep integration exclude

**Pass:** `Invoke-OptionalIntegrationExcludePass`  
**IDs:** `mc-262r-soft-dep-exclude`, `mc-262r-soft-dep-keep-when-jar`  
**Related:** `INT-001-soft-dep-integration-exclude.md`

## Rule

Strip integration sources that hard-import missing companion APIs **only when** no matching 26.2 jar exists under `libs/`.

| libs/ has | Keep sources under |
|---|---|
| `*jei*` | `compat/jei/**`, `integration/jei/**` |
| `*carryon*` | `integration/carryon/**` |
| `*appleskin*` | `integration/appleskin/**` |
| `*sable*` | `integration/sable/**` |

Always safe to exclude: `**/gametest/**` (harness not on leaf classpath).

## Path markers

- `integration/{carryon,sable,jei,appleskin}/`
- `compat/jei/` (Easy Mob Farm shape)

## Proven

Easy Mob Farm: after dual-pull JEI 26.2 into `libs/`, remove `exclude '**/compat/jei/**'` and compile against the jar.
