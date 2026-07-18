# WorldEngine

Rojo-compatible source mirror for the procedural world system in the active Roblox `Engine` experience.

## Current status

Milestones 1 through 6 are complete. The engine now covers deterministic terrain, an owned Blender-to-Roblox asset slice, art-directed asset-family variation, deterministic multi-region composition, and a biome-specific surface/atmosphere layer. Connected routes, landmarks, vistas, collisions, runtime LODs, and vegetation wind remain validated. The independent-process cumulative regression passes. See `MILESTONE_6_RECAP.md`.

## Layout

- `default.project.json`: Rojo DataModel mapping.
- `src/ServerStorage/WorldEngine`: generator, planning, materialization, validation, and golden seed modules.
- `src/ServerScriptService/WorldEngineRunners`: callable Studio runner.

## Rojo workflow

Rojo `7.7.0` is pinned through `rokit.toml`. Run `rojo serve` from this repository and connect the matching Studio plugin. Review the initial diff carefully because the active place also contains Studio-managed mesh templates and diagnostics.

Milestones 1 through 6 pass cross-session golden regressions. Milestone 6 demonstrates reusable terrain surfacing, detail grammar, and atmospheric presentation from the deliberately small owned kit; custom terrain PBR, mesh-terrain features, and production-scale content remain future work.
