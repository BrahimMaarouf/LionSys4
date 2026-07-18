# WorldEngine

Rojo-compatible source mirror for the procedural world system in the active Roblox `Engine` experience.

## Current status

Milestones 1 through 4 are complete. The engine now covers deterministic terrain, an owned Blender-to-Roblox asset slice, deterministic desert composition, and art-directed asset-family variation with composite collisions, authored runtime LODs, and wind. The independent-process cumulative regression passes. See `MILESTONE_4_RECAP.md`.

## Layout

- `default.project.json`: Rojo DataModel mapping.
- `src/ServerStorage/WorldEngine`: generator, planning, materialization, validation, and golden seed modules.
- `src/ServerScriptService/WorldEngineRunners`: callable Studio runner.

## Rojo workflow

Rojo `7.7.0` is pinned through `rokit.toml`. Run `rojo serve` from this repository and connect the matching Studio plugin. Review the initial diff carefully because the active place also contains Studio-managed mesh templates and diagnostics.

Milestone 1 through 4 cross-session golden regressions pass. Milestone 4 demonstrates controlled variation from the deliberately small owned kit; production-scale content and further biome scope remain future work.
