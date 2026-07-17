# WorldEngine

Rojo-compatible source mirror for the procedural world system in the active Roblox `Engine` experience.

## Current status

Milestones 1 and 2 are complete. The owned Blender-to-Roblox asset slice, deterministic placement, authored runtime LODs, and independent-session cumulative regression all pass. See `MILESTONE_2_RECAP.md`.

## Layout

- `default.project.json`: Rojo DataModel mapping.
- `src/ServerStorage/WorldEngine`: generator, planning, materialization, validation, and golden seed modules.
- `src/ServerScriptService/WorldEngineRunners`: callable Studio runner.

## Rojo workflow

Rojo `7.7.0` is pinned through `rokit.toml`. Run `rojo serve` from this repository and connect the matching Studio plugin. Review the initial diff carefully because the active place also contains Studio-managed mesh templates and diagnostics.

Milestone 1 and Milestone 2 cross-session golden regressions pass. Milestone 3 can now build composition and additional desert asset families on this foundation.
