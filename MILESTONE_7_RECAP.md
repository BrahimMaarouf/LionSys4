# WorldEngine Milestone 7 Recap

Date completed: 2026-07-18
Status: **PASSED** (`PASSED_M7_ASSET_QUALITY`)
Version: `7.0.0-m7-asset-quality`

## Delivered

- Complete texture-quality pass over all three owned asset families, authored as
  deterministic math (no DCC dependency) and swapped without any golden rebaseline.
- New rock set (384px): domain-warped strata banding, multi-octave grain, cavity
  shading, Sobel-derived normal map, variance-driven roughness — replacing the
  flat saturated orange criticized since M2.
- New shrub atlas (256px): per-cluster color variation (green→dry), vein detail,
  softer silhouette edges; identical cluster layout so existing foliage UVs are
  untouched.
- New dedicated seamless bark set (256px): fibrous dry wood with cracked plates —
  closes the M2 atlas bark gap without remapping mesh UVs, by giving branch
  meshes their own texture set instead of the shared atlas.
- Recipe contact-sheet tooling: `MilestoneSevenRunner.BuildContactSheet()` clones
  one live representative of each of the 15 (family, recipe) variants from the
  generated world into a labeled review grid; recorded human sign-off gate.
- Texture validation: all 10 template surfaces verified to carry exactly the M7
  sets from `AssetIds`; bark set verified distinct from the foliage atlas.
- Performance snapshot tooling (`CollectPerformanceSnapshot`).

## Signature-safety argument

Golden signatures hash mesh IDs and quantized positions — never SurfaceAppearance
maps. The full M1–M6 cumulative regression was run immediately after the texture
swap and passed unchanged (`PASSED_M1_M2_M3_M4_M5_M6_CUMULATIVE`), demonstrating
that texture upgrades are a rebaseline-free operation. This is now a documented
engine property.

## Upload pipeline

Because programmatic image upload is unavailable, textures ride the project's
proven 3D-Importer path: `build_m7_texture_carrier.py` packs the nine PNGs into
`M7TextureCarrier.glb` (three quads, three PBR materials); Studio's importer
uploads the images and wires SurfaceAppearances; asset IDs are harvested from
the import and the carrier is deleted. Scripts, PNGs, and carrier GLB are committed.

## Reproducible evidence

| Claim | Reproduction |
|---|---|
| Textures regenerate deterministically | `python3 pipeline/textures/generate_m7_textures.py` — byte-identical PNGs |
| Carrier rebuilds | `python3 pipeline/textures/build_m7_texture_carrier.py` |
| All 10 template surfaces carry M7 sets | `require(...MilestoneSevenValidator).ValidateTemplateTextures()` → `CheckedSurfaces = 10`, `WrongSurfaces = {}` |
| Cumulative unchanged after swap | `require(...WorldEngineRegressionRunner).Run()` → `PASSED_M1_M2_M3_M4_M5_M6_CUMULATIVE` |
| M7 gate | `require(...MilestoneSevenRunner).RunGoldenRegression()` → `PASSED_M7_ASSET_QUALITY` |
| Contact sheet | `require(...MilestoneSevenRunner).BuildContactSheet()` → 15 variants, 5×3 grid |

Performance snapshot (Studio, full generated world): 1,226 generated descendants,
484 MeshParts, 4 ParticleEmitters, 42.9 MB instance memory, 67.1 MB texture
memory, 2.2 MB mesh memory.

## Human sign-off

Recorded on `WorldRoot` (`Milestone7HumanVisualSignoff = true`, 2026-07-18):
owner reviewed the 15-recipe contact sheet and in-world vistas and approved.

## Open items (deferred, tracked)

- **Device profile** — deferred to M9 hardening by owner decision (2026-07-18);
  `MilestoneSevenEvidence.DeviceProfileRecorded = false` until performed.
- Blender `.blend` regeneration of textures (the Python generator is canonical
  for textures as of M7; `generate_m2_assets.py` texture functions are
  superseded and kept for mesh provenance).
- World-edge presentation and five-landmark scale-up → M9.
- Modular ruins → M8.

## Boundary

M7 upgrades surface quality of the existing kit. It does not add meshes, change
any plan or signature, or claim final production art. The require-cache gotcha
(see README) applies when Rojo-syncing these modules into an open Studio.
