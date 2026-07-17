# WorldEngine

Rojo-compatible source mirror for the procedural world system in the active Roblox `Engine` experience.

## Current status

Milestone 1 is complete. Its full current-session suite and post-restart golden regression both pass, as recorded in `MILESTONE_1_RECAP.md`.

## Layout

- `default.project.json`: Rojo DataModel mapping.
- `src/ServerStorage/WorldEngine`: generator, planning, materialization, validation, and golden seed modules.
- `src/ServerScriptService/WorldEngineRunners`: callable Studio runner.

## Rojo workflow

Rojo is not currently installed on this machine. Once installed, run `rojo serve` from this repository and connect the Rojo Studio plugin. Review the initial diff carefully before syncing because the active place currently contains the authoritative scene folders and diagnostics in addition to these scripts.

The post-restart golden regression passes. Commit this mirror before beginning Milestone 2.
