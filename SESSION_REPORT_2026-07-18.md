# WorldEngine — Session Report (2026-07-18)

Scope of this report: everything done in the current Claude session, from taking
over the project through Milestone 7, Milestone 8, and the start of Milestone 9.

---

## 1. Baseline verification (before any new work)

- Reconnected to Roblox Studio (`Engine`, place `83952086450444`) and the repo.
- Ran the cumulative regression in a fresh session. Found **M5 and M6 failing**
  (`FAILED_OR_GATES_OPEN`) despite their recaps claiming PASSED.
- Root-caused it to **stale module require-cache**: Rojo had synced sources
  mid-session, but Studio's require cache still held old compiled modules.
  After force-recompiling all 48 ModuleScripts, the true result was
  `PASSED_M1_M2_M3_M4_M5_M6_CUMULATIVE` — the codebase was healthy.
- Documented the gotcha in the README ("require-cache staleness").

## 2. Publishing / repository

**Added**
- Expanded `README.md`: milestone table with tags, verification workflow,
  engine principles, roadmap.
- Git tags `m1` … `m8` (one per milestone commit).
- Commits: `Complete Milestone 6`, `README expansion`, `Complete Milestone 7`,
  `Complete Milestone 8` (M6 work was sitting uncommitted in the tree).

**Changed**
- Cleared stale `.git` lock files (a crashed git process had blocked commits;
  file-delete permission was granted for the folder to fix this).

**Still needs you**
- `git push origin main --tags` — pushing requires your GitHub credentials,
  which I don't handle. Run it once in Git Bash from the repo folder.

## 3. Milestone 7 — Asset quality pass (**PASSED**, tag `m7`)

**Added**
- `pipeline/textures/generate_m7_textures.py` — deterministic, math-authored
  PBR texture sets (no Blender needed): strata rock (384px), varied shrub
  atlas, and a **new dedicated bark set** fixing the M2 "white branches" gap
  without touching mesh UVs.
- `pipeline/textures/build_m7_texture_carrier.py` + `assets/export/M7TextureCarrier.glb`
  — packs the 9 PNGs into a 3-quad GLB so Studio's 3D Importer uploads them
  (programmatic image upload isn't available). IDs harvested, carrier deleted.
- `MilestoneSevenValidator` — verifies all 10 template surfaces carry exactly
  the M7 sets; performance snapshot tooling (instance/mesh/texture memory).
- `MilestoneSevenRunner` — recipe **contact sheet** (clones one live
  representative of each of the 15 recipes into a labeled review grid),
  visual sign-off recording, M7 gate.
- `MilestoneSevenEvidence`, `MILESTONE_7_RECAP.md`.

**Changed**
- `AssetIds.lua` — texture IDs swapped to the M7 uploads, `BarkTextures` added.
- All template SurfaceAppearances (2 rocks × 3 surfaces, shrub × 4 surfaces).

**Proved**
- Texture swaps are **signature-safe**: the full M1–M6 cumulative passed
  unchanged immediately after the swap. Zero golden rebaselines.

**Deferred (your decision)**
- Real-device performance profile → M9.

## 4. Milestone 8 — Modular ruins (**PASSED**, tag `m8`)

**Added**
- `pipeline/ruins/generate_m8_ruinkit.py` — math-authored 8-piece ruin kit
  (WallSegment, WallDoorway, WallBroken, CornerPost, Pillar, PillarBroken,
  RubblePile, FloorSlab) with seeded jagged break-lines, plus the
  `M8_Stone_*` block-masonry PBR set. Exported as `M8RuinKit.glb`, imported,
  IDs harvested.
- `RuinAssetIds`, `Config/Ruins/DesertRuins` (3 site definitions),
  `RuinPlanner` (socket grammar: perimeter sockets with seeded degradation,
  guaranteed route-facing doorway, corners, floor slabs, colonnades, rubble
  outside collapsed sockets; deterministic bearing-based siting with bounds /
  route-clearance / flatness gates), `RuinMaterializer`,
  `MilestoneEightValidator`, `MilestoneEightRunner`, `MilestoneEightGolden`,
  `MILESTONE_8_RECAP.md`.
- **`RuinTemplateBuilder`** — rebuilds Studio templates from committed code
  (`CreateMeshPartAsync`), so template loss is recoverable in one call.

**Changed**
- `WorldEngineRegressionRunner` — now an **explicit state machine**: clears
  ruins → runs M1–M6 golden regressions (their captures predate ruins) → runs
  M8 last, leaving the full world standing. Order documented in code.
  This resolved the cross-milestone capture pollution found during testing.
- `RuinMaterializer` — per-piece terrain snap (extends the M2-era fix) after
  the first two grounding attempts left pieces floating / buried.

**Result**: 3 ruins, 77 pieces, every ruin enterable, 0 route violations,
77/77 grounded, ~0.26 s generation. Your visual sign-off recorded. Cumulative:
`PASSED_M1_M2_M3_M4_M5_M6_M8_CUMULATIVE`.

## 5. Incidents caught & fixed (worth knowing about)

1. **Ruin burial / floating** — heightfield vs voxel-smoothed surface (same
   class as the M2 bug). Fixed via per-piece raycast snap at materialization.
2. **Studio-side rollback** — mid-milestone, the ruin Templates folder
   vanished and M7 template textures reverted to M2 IDs, consistent with
   Studio **undo** rewinding plugin edits (avoid Ctrl+Z in Studio during
   generation work). The regression suite caught both. Recovered via
   `RuinTemplateBuilder` + re-applying M7 sets; the place is saved after every
   green cumulative now.

**Removed** (this session): nothing from the repo; deleted from the *place*:
the imported carrier/kit staging models (`M7TextureCarrier`, `M8RuinKit`) after
harvesting IDs, and the stale duplicate of an old milestone runner.

## 6. Milestone 9 — in progress (NOT yet in Studio, NOT committed)

**Scope decision (documented)**: keep the 4-landmark composition (their M5
design; 4 landmarks + 3 ruin destinations). Changing landmark count would
force rebaselining M5/M6/M8 for no gameplay gain. M9 = world-edge
presentation + seed browser + full-world validation + profiling.

**Written locally so far**
- `WorldEdgeMaterializer` — deterministic dune skirt (128 studs) around the
  slab so the horizon reads as endless desert; lives outside the M1 capture
  region (M1 golden untouched); invisible boundary walls; skirt signature.
- `MilestoneNineRunner` — `BrowseSeeds` (plan-only seed browser with per-seed
  metrics), `ValidateFullWorld` (cross-layer checks: spawn grounded, every
  prop/ruin grounded, walls present, skirt signature, budget census, memory),
  sign-off + golden regression.
- `MilestoneNineGolden` placeholder (`Pending = true`).

**Remaining for M9**
- Mirror the three files into Studio, generate the skirt, visual check,
  your sign-off, baseline the golden, add M9 to the cumulative runner,
  recap, commit + tag `m9`.
- Optional: your phone profile of the published place (still the one gate I
  can't do from here).

## 7. After M9

- The per-milestone **settings UI** you asked for (seed playground: per-
  milestone settings, generate / preview / remove / regenerate) — kept last
  per your instruction. The M9 seed browser is its data backbone.

## 8. Current workflow state (quick reference)

| Item | State |
|---|---|
| Cumulative regression | `PASSED_M1_M2_M3_M4_M5_M6_M8_CUMULATIVE` (green) |
| Place saved | Yes, after the green cumulative |
| Git | 4 new commits, tags `m1`–`m8`, **unpushed** (needs your `git push origin main --tags`) |
| Rojo | `rojo serve` NOT running — I mirror files manually; start it to simplify future sync |
| Studio update | A "Restart to update" is pending in Studio; after any restart, re-run the cumulative before trusting anything |
| M9 | ~60 % built locally, not yet applied to Studio |

**Verification one-liner** (Studio command bar):
```lua
require(game.ServerScriptService.WorldEngineRunners.WorldEngineRegressionRunner).Run()
```
