# WorldEngine

Rojo-compatible source mirror for the procedural world system in the active Roblox `Engine` experience.

## Current status

Milestones 1, 2, and 3 are complete. The engine now covers deterministic terrain, an owned Blender-to-Roblox asset slice, authored runtime LODs, and deterministic desert composition with a validated trail and landmark. The independent-process cumulative regression passes. See `MILESTONE_3_RECAP.md`.

## Layout

- `default.project.json`: Rojo DataModel mapping.
- `src/ServerStorage/WorldEngine`: generator, planning, materialization, validation, and golden seed modules.
- `src/ServerScriptService/WorldEngineRunners`: callable Studio runner.

## Rojo workflow

Rojo `7.7.0` is pinned through `rokit.toml`. Run `rojo serve` from this repository and connect the matching Studio plugin. Review the initial diff carefully because the active place also contains Studio-managed mesh templates and diagnostics.

Milestone 1, 2, and 3 cross-session golden regressions pass. Milestone 3 demonstrates composition from the small owned kit; production-scale content and further biome scope remain future work.
