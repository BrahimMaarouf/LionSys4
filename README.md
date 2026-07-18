# WorldEngine

A deterministic, offline-first procedural world engine for Roblox, built as a Rojo-compatible source mirror of the active `Engine` experience. Worlds are planned as pure data from a seed, materialized into Roblox terrain and instances, validated against golden baselines, and regenerated bit-identically across sessions and machines.

## Milestones

| Milestone | Tag | Delivers | Recap |
|---|---|---|---|
| 1 — Terrain foundation | `m1` | Owned deterministic noise, seeded heightfield, seam-safe chunked voxel terrain, FNV-1a signatures, cross-session golden regression | `MILESTONE_1_RECAP.md` |
| 2 — Owned asset pipeline | `m2` | Blender→GLB→Studio pipeline (2 rocks + 1 shrub), PBR + alpha foliage, templates, data-only placement, terrain-surface grounding, runtime LODs | `MILESTONE_2_RECAP.md` |
| 3 — Composition | `m3` | Trail from spawn to landmark, SentinelCrown composition, repair/revalidation loop, instance budgets | `MILESTONE_3_RECAP.md` |
| 4 — Asset variation | `m4` | 15 art-directed recipes, bounded morphology/palette variation, identity audit, composite collisions, client LOD registration | `MILESTONE_4_RECAP.md` |
| 5 — World composition | `m5` | Four named regions, four landmarks + routes + vistas, regional grammar, role-aware repair | `MILESTONE_5_RECAP.md` |
| 6 — Surface & atmosphere | `m6` | Five-material route-aware surfacing, detail grammar (ripples, drifts, wadi cracks), dust systems, restrained post-FX | `MILESTONE_6_RECAP.md` |
| 7 — Asset quality | `m7` | Math-authored texture pass (strata rock, varied foliage, dedicated bark set), 15-recipe contact-sheet review, signature-safe swap proof | `MILESTONE_7_RECAP.md` |
| 8 — Modular ruins | `m8` | Math-authored 8-piece ruin kit, socket-grammar sites with seeded degradation and guaranteed doorways, terrain-snapped grounding, code-rebuildable templates | `MILESTONE_8_RECAP.md` |
| 9 — World hardening | `m9` | Dune-skirt world edge, boundary walls, plan-only seed browser, full-world cross-layer validation, self-healing regression suite | `MILESTONE_9_RECAP.md` |

All milestones pass a cumulative cross-session golden regression (`PASSED_M1_M2_M3_M4_M5_M6_M8_M9_CUMULATIVE`), verified both in the active Studio and in a clean Rojo-built Studio process.

## Layout

- `default.project.json` — Rojo DataModel mapping.
- `src/ServerStorage/WorldEngine` — planning (pure data), materialization (Roblox instances/terrain), validation, config, and golden-seed baselines, organized per subsystem.
- `src/ServerScriptService/WorldEngineRunners` — Studio entry points. One runner per milestone plus `WorldEngineRegressionRunner.Run()` for the cumulative suite.
- `pipeline/blender` — reproducible asset-source generation (pinned Blender 4.5 LTS scripts).
- `assets/` — GLB exports, PBR textures, template `.rbxm` artifacts, DCC validation reports.

## Workflow

Rojo `7.7.0` is pinned via `rokit.toml`. Run `rojo serve` from the repository root and connect the Studio plugin.

Verification entry point (Studio command bar):

```lua
require(game.ServerScriptService.WorldEngineRunners.WorldEngineRegressionRunner).Run()
```

Expected: `PASSED_M1_M2_M3_M4_M5_M6_M8_M9_CUMULATIVE`. Reports are stored under `Workspace.WorldRoot.Diagnostics`.

### Known gotcha: module require-cache staleness

If Rojo syncs sources while Studio is open, previously required ModuleScripts keep their old compiled code in the require cache and regressions may report false failures. After any sync, force fresh compilation (clone-replace the module instances, or restart Studio) before trusting regression output.


## Control panel (seed playground)

`ui/worldengine-panel.html` — open it in any browser. One zone per milestone
group with seed inputs and buttons; each button copies a ready-to-paste Studio
command-bar snippet driving `WorldEngineRunners.WorldEngineConsole`:

- `Preview({seeds})` — plan-only metrics for any seeds (no instances created)
- `BuildWorld(seed)` — the complete world (terrain → props → variation →
  composition → surfacing → ruins → edge) for any seed, ~8 s
- `RestoreGoldenWorld()` — rebuild + verify the golden baseline after experiments
- Layer tools: regenerate/clear ruins and world edge, recipe contact sheet

Building a non-golden seed is a sandbox operation; the cumulative regression
restores and re-verifies the golden world afterwards.

## Principles

- **Data plans the world; final geometry verifies it.** Planners never read live instances; validators and materializers may.
- **Golden baselines are immutable evidence.** A mismatch is investigated, never auto-rebaselined.
- **Every milestone must reproduce cross-session** — same seed, same signatures, after a full Studio restart and from a clean Rojo build.
- **Repair loops revalidate.** Any repair pass re-runs the constraints it may have disturbed.

## Roadmap

- Real-device performance profile — release QA (publish + MicroProfiler on a mid-range phone).
- Later — forest biome, hydrology-driven biome placement, optional runtime per-server generation.
