# WorldEngine Milestone 9 Recap

Date completed: 2026-07-19
Status: **PASSED** (`PASSED_CROSS_SESSION_GOLDEN_WORLD_HARDENING`; cumulative
`PASSED_M1_M2_M3_M4_M5_M6_M8_M9_CUMULATIVE`)
Version: `9.0.0-m9-world-hardening`

## Scope decision (documented)

The original roadmap sketch said "five-landmark scale-up." The approved M5
grammar authored four landmarks plus three ruin destinations (seven authored
goals). Changing landmark count would cascade rebaselines through M5/M6/M8 for
no gameplay gain, so M9 keeps the composition and hardens the world instead.

## Delivered

- **World-edge presentation**: deterministic 128-stud dune skirt continuing the
  edge height profile and easing down to a low rim — the slab no longer ends in
  a bare cliff. Lives entirely outside the M1 golden capture region (M1
  signatures untouched). Four invisible boundary walls keep players inside.
  Skirt has its own FNV-1a signature and version attribute.
- **Seed browser** (`MilestoneNineRunner.BrowseSeeds`): plan-only, zero
  instances created — per-seed metrics (landmarks, routes, vistas, placements,
  ruin sites/pieces, composition + ruin signatures, plan time). This is the
  data backbone for the settings UI.
- **Full-world validation** (`ValidateFullWorld`): cross-layer checks no single
  milestone owns — spawn grounded; every prop grounded within 6 studs (with a
  documented exemption for Landmark-role variants, which stack on other rocks
  by design); every ruin piece grounded within 3 studs; boundary walls valid;
  skirt signature + version match; instance/memory census.
- **Self-healing cumulative suite**: Rojo sync-in deletes Studio-owned
  instances it does not manage (ruin template Models, template
  SurfaceAppearances — the "phantom rollback" finally root-caused this
  session, confirmed by Rojo's own confirm-sync diff). The suite now rebuilds
  ruin templates via `RuinTemplateBuilder` and re-applies M7 sets via
  `MilestoneSevenTextureApplier` before validating. Loss of Studio-side state
  is no longer possible to ship silently.
- **M9 golden** with session-boundary gate, seed-browser signatures, and
  full-world census; M9 wired into the cumulative runner (runs last, after M8).

## Final evidence

| Measurement | Value |
|---|---|
| Skirt signature | `fnv1a32:6d0de742` (deterministic across regenerations) |
| Composition / ruin signatures (golden seed) | `fnv1a32:9357cc40` / `fnv1a32:f5412a23` |
| Props grounded | 56/56 (54 terrain-grounded + 2 landmark-stack exempt) |
| Ruin pieces grounded | 77/77 |
| Boundary walls | 4/4 valid |
| Alternate seeds differ | yes (271827/271829 vs 271828) |
| Edge generation time | ~0.46 s |
| Cross-session | baselined in session `b809059c…`, verified after place reload in a fresh session |

Reproduction: `require(...MilestoneNineRunner).RegenerateAndVerify()` →
`M9_RUNTIME_VALIDATED`; `require(...WorldEngineRegressionRunner).Run()` →
`PASSED_M1_M2_M3_M4_M5_M6_M8_M9_CUMULATIVE`.

## Sign-off & profiling

- Owner visual sign-off recorded in `MilestoneNineEvidence` (2026-07-18, Studio
  play-mode inspection of the dune skirt and full world).
- Studio performance snapshot captured per evidence notes. **Real-device
  profiling remains release QA** — publish the place and run 10–15 min on a
  mid-range phone with MicroProfiler; not a golden-regression substitute.

## Boundary

M9 completes the desert vertical slice: deterministic terrain, owned assets,
variation, composition, surfacing, ruins, edge presentation, and a
self-healing nine-milestone regression suite. It does not add new biomes,
runtime per-server generation, or final production art. Next planned work is
the per-milestone settings UI (seed playground) on top of `BrowseSeeds`.
