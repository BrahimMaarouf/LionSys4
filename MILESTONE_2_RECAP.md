# WorldEngine Milestone 2 Recap

Date completed: 2026-07-17
Status: **PASSED**

## Delivered

- Reproducible Blender 4.5 pipeline with two owned rocks and one owned shrub.
- PBR textures, alpha foliage, collision proxies, and authored LOD0/LOD1/LOD2 meshes.
- Binary Roblox templates are Rojo-owned source, not hidden place-only objects.
- Seeded clustered placement uses heightfield data only; no placement raycasts.
- Client distance switching exercises the authored LOD meshes; shrub wind is active.
- Exact lighting, template, catalog, spacing, grounding, normal, and signature assertions.

## Final evidence

- Seed: `271828`; catalog: `2.1.0-m2-owned-dcc-lod`.
- Props: `32` (`16` WindBoulder, `10` LayeredMesa, `6` DryShrub).
- Placement signature: `fnv1a32:4308cf52`.
- Materialized signature: `fnv1a32:e1310853`.
- Invalid models: `0`; custom LOD sets: `32`.
- Blender validation: passed for transforms, pivots, UVs, materials, triangle descent, and collision simplification.
- Separate Studio Session A/B cumulative regression: `PASSED_M1_AND_M2_CUMULATIVE`.
- M2 Session B verified a different session ID, both golden signatures, lighting, source templates, grounding, and visual sign-off.

## Reproduce

Run the Blender validator, build a clean place with Rojo 7.7.0, then execute `pipeline/studio/cumulative_regression.luau` using Roblox Studio's `RunScript` command-line task. `pipeline/verify_m2_source.ps1` verifies that the pinned source artifacts are tracked and hash-identical.

Milestone 2 proves the complete asset-to-world vertical slice. More asset families and production-level scene composition belong to Milestone 3 and later.
