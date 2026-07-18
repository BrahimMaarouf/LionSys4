# WorldEngine

Rojo-compatible source mirror for the procedural world system in the active Roblox `Engine` experience.

## Current status

Milestones 1 through 5 are complete. The engine now covers deterministic terrain, an owned Blender-to-Roblox asset slice, art-directed asset-family variation, and deterministic multi-region world composition with connected routes, landmarks, and vistas. Composite collisions, authored runtime LODs, and vegetation wind remain validated. The independent-process cumulative regression passes. See `MILESTONE_5_RECAP.md`.

## Layout

- `default.project.json`: Rojo DataModel mapping.
- `src/ServerStorage/WorldEngine`: generator, planning, materialization, validation, and golden seed modules.
- `src/ServerScriptService/WorldEngineRunners`: callable Studio runner.

## Rojo workflow

Rojo `7.7.0` is pinned through `rokit.toml`. Run `rojo serve` from this repository and connect the matching Studio plugin. Review the initial diff carefully because the active place also contains Studio-managed mesh templates and diagnostics.

Milestones 1 through 5 pass cross-session golden regressions. Milestone 5 demonstrates controlled world composition from the deliberately small owned kit; terrain-detail rendering, atmospheric polish, and production-scale content remain future work.
