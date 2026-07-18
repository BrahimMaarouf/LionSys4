# WorldEngine Milestone 8 Recap

Date completed: 2026-07-18
Status: **PASSED** (`PASSED_GOLDEN_MODULAR_RUINS`, cumulative `PASSED_M1_M2_M3_M4_M5_M6_M8_CUMULATIVE`)
Version: `8.0.0-m8-modular-ruins`

## Delivered

- Math-authored modular ruin kit — 8 pieces (WallSegment, WallDoorway, WallBroken,
  CornerPost, Pillar, PillarBroken, RubblePile, FloorSlab) generated as
  deterministic geometry with seeded jagged break-lines, packed to GLB and
  uploaded via the proven 3D-Importer path. Stone-block PBR set (courses,
  mortar, per-block tint) from the same generator. No DCC dependency.
- Socket-grammar ruin planner: three sites (SanctuaryRuin 5×4 at SentinelCrown,
  WadiGardenRuin 3×3 at WadiGate, RouteWatchPost 2×2 on the longest route),
  each with perimeter sockets degraded by a seeded ruination weight, guaranteed
  route-facing doorway, corner piers, floor slabs, colonnades, and rubble
  outside collapsed sockets.
- Deterministic site selection: candidate compass bearings filtered by bounds,
  route clearance (14 studs), and a dense 3×3 flatness gate (≤7°).
- Terrain-snapped materialization (per piece), extending the M2-era fix; zero
  buried, zero floating across all 77 pieces.
- `RuinTemplateBuilder`: templates reproducible from committed code alone via
  `AssetService:CreateMeshPartAsync` — Studio-side template loss is now
  recoverable in one call.
- Explicit cumulative state machine in `WorldEngineRegressionRunner`: ruins
  cleared before M1–M6 regressions (their captures predate ruins), M8 runs
  last and leaves the complete world standing. Ordering is documented in code.

## Final evidence

| Measurement | Value |
|---|---|
| Seed / version | `271828` / `8.0.0-m8-modular-ruins` |
| Plan signature | `fnv1a32:f5412a23` |
| Materialized signature | `fnv1a32:3d52e8e5` |
| Pieces | 77 across 3 sites (44 sanctuary / 21 wadi / 12 watch post) |
| Doorways | ≥1 per site (validated: EveryRuinEnterable) |
| Route violations / bounds violations | 0 / 0 |
| Grounding | 77/77 within ±1.5 studs of baked surface |
| Generation time | ~0.26 s (Studio) |

Reproduction: `require(...MilestoneEightRunner).RegenerateAndVerify()` →
`M8_RUNTIME_VALIDATED`; `require(...WorldEngineRegressionRunner).Run()` →
`PASSED_M1_M2_M3_M4_M5_M6_M8_CUMULATIVE`; kit rebuild:
`python3 pipeline/ruins/generate_m8_ruinkit.py`; template rebuild:
`require(...RuinTemplateBuilder).Build()`.

## Human sign-off

Recorded (`Milestone8HumanVisualSignoff = true`, 2026-07-18): owner reviewed all
three ruins in Studio and approved.

## Incidents during development (documented deliberately)

1. **Heightfield-vs-baked-surface burial** (same class as the M2 bug): initial
   flat-platform anchoring left 11 pieces floating, then a min-anchor attempt
   buried all 44 sanctuary pieces ~3.5 studs. Resolved with per-piece terrain
   snap at materialization; the planner keeps pure heightfield data.
2. **Studio-side state rollback**: mid-milestone, the Ruins template folder
   vanished and the M7 template SurfaceAppearances reverted to M2 texture IDs —
   consistent with Studio undo history rewinding plugin edits. Recovered via
   `RuinTemplateBuilder` and re-applying the M7 sets; the cumulative suite
   caught both regressions exactly as designed. Mitigations: templates now
   rebuildable from code; place saved immediately after every green cumulative.

## Open items (tracked)

- Device performance profile — deferred to M9 (owner decision, M7).
- Ruin interiors are sparse (no props inside); ruin-interior dressing could
  join a later content pass.
- World-edge presentation, five-landmark scale-up, seed browser → M9.

## Boundary

M8 proves structural generation from a modular kit with grammar, degradation,
and safety repair. It does not add NPCs, loot, or interior gameplay, and the
kit remains stylized first-pass art consistent with the M7 texture pass.
