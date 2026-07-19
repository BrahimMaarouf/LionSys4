# WorldForge — build any world from your own assets

WorldForge is the authoring tool layer of this project. **You supply the assets
and the seeds; the system arranges them.** It never creates a mesh or a texture
of its own, and it knows nothing about deserts, forests or any other theme —
every landform, rule and palette is data you control.

Open the panel (Studio command bar):

```lua
require(game.ServerStorage.WorldForge.UI.Panel).Open()
```

---

## The seven stages

The panel has one tab per stage, in build order.

| # | Stage | What you do |
|---|---|---|
| 1 | **Terrain** | Set the terrain seed and 14 landform controls, generate, roll or lock |
| 2 | **Library** | Import your meshes + textures; the system organises and validates them |
| 3 | **Zones** | Define regions by rule and say which assets may live in each |
| 4 | **Scatter** | Density, clustering, spacing, jitter — placement of your library assets |
| 5 | **Structures** | Socket-grammar assembly from your own kit pieces |
| 6 | **Surface & Light** | Material rules by slope/height/shore, atmosphere, time of day |
| 7 | **Save** | Name the world, save it, load it back, build everything |

Every control shows its own help text, its range is enforced, and the status bar
always shows which layers have gone stale.

---

## Per-stage seeds — lock what you like

Four independent seeds: `terrain`, `zones`, `scatter`, `structures`. Each has a
🎲 roll button.

Roll terrain until the land is right → leave it alone → roll only `scatter`
until the planting is right. **Your landscape never changes while you tune the
vegetation.** That single split is what makes this feel like an instrument
instead of a slot machine.

---

## The Asset Library

You give it asset IDs; it does the organising:

```lua
local WF = require(game.ServerStorage.WorldForge.WorldForge)

WF.Library.Import({
  Id = "pine_a", Kind = "Tree",
  MeshId = "rbxassetid://…",           -- required
  CollisionMeshId = "rbxassetid://…",  -- optional, falls back to the render mesh
  Lod1MeshId = "…", Lod2MeshId = "…",  -- optional
  ColorMap = "…", NormalMap = "…", RoughnessMap = "…",
  AlphaMode = "Transparency",          -- for cutout foliage
  Spacing = 9, MaxSlope = 28, Sink = 0.4, Weight = 3, Wind = true,
  Tags = {"conifer"},
})
```

Each import becomes a uniform template under
`ServerStorage.WorldForge.Library.<Kind>.<Id>` containing `Render`,
`Collision` and optional `LODVariants` — bottom-aligned at the origin so
everything grounds identically. Placement rules live on the template as
attributes, so the library persists with the place.

Kinds: `Rock · Tree · Bush · Plant · Prop · Debris · Structure`

Other library calls: `List()`, `SetRules(id, {...})`, `Remove(id)`,
`BuildPreview()` (lays the whole kit out on a labelled grid), `Export()` /
`ImportFromJson()`.

---

## Zones — where things are allowed

Zones are matched top to bottom; first match wins.

| Rule | Meaning |
|---|---|
| `everywhere` | the whole world |
| `altitude` | height band, `Min`/`Max` as 0–1 fractions of the world's relief |
| `slope` | ground steepness in degrees |
| `nearWater` | within `Max` studs of the water line |
| `patch` | organic noise blobs, `Min` is the threshold |

`Allow` accepts `"*"`, a `kind:Tree` filter, or explicit asset ids.

```lua
WF.AddZone("Highlands", "altitude", 0.55, 1.0, {"kind:Rock"}, 0.8)
WF.AddZone("Lowlands",  "altitude", 0.0, 0.55, {"kind:Bush", "kind:Plant"}, 1.0)
```

---

## Structures from your kit

Tag library assets with a role — `wall`, `door`, `corner`, `floor`, `pillar`,
`rubble` — then nominate them as the kit:

```lua
WF.SetStructureKit({"wall", "doorway", "corner_post", "floor_slab", "rubble"})
WF.Set("structures.enabled", true)
```

The planner walks each site's perimeter sockets, degrades them by the
`degradation` control, guarantees at least one entrance, and grounds every
piece on the baked terrain. It has no idea whether your kit is stone, wood or
steel.

---

## Saving worlds

A saved world is a **recipe**: per-stage seeds plus only the parameters that
differ from default, plus zones and kit. Small, readable, diffable.

```lua
WF.Save("Frozen Pass")     -- stored in ServerStorage.WorldForge.Recipes
WF.Load("Frozen Pass")
WF.SavedWorlds()
WF.Export()                -- JSON, paste anywhere
```

Every recipe carries an FNV-1a hash. Same recipe → same hash → same world, on
any machine. Verified: save, mutate, reload, hash returns identical.

---

## Coexisting with the WorldEngine milestones

WorldForge and the original M1–M9 WorldEngine both own `Workspace.Terrain`, so
only one can be materialized at a time. This is handled explicitly:

- Building a WorldForge world **parks** the legacy world as
  `ServerStorage._ParkedWorldRoot` (nothing is lost).
- `WF.ReleaseToWorldEngine()` — or the panel's **Release to WorldEngine**
  button — clears WorldForge and restores the legacy world, ready for
  `WorldEngineRegressionRunner.Run()`.

Never let two `WorldRoot` folders exist at once; the release path enforces this.


## Using WorldForge in a different (or brand-new) place

WorldForge is self-contained — it needs nothing from the WorldEngine milestone
folders. To use it in any other experience:

**Option A — Rojo (recommended)**

```
rojo serve worldforge.project.json
```

Then open your new place, connect the Rojo plugin, Accept. Only
`ServerStorage.WorldForge` is synced; no desert, no milestone code.

**Option B — copy/paste**

In the Engine place, right-click `ServerStorage.WorldForge` → Copy. In the new
place, right-click `ServerStorage` → Paste.

Then in the new place:

```lua
require(game.ServerStorage.WorldForge.UI.Panel).Open()
```

The Library starts empty — import your own asset IDs on tab 2. Everything else
works immediately.

---

## Verified behaviour (2026-07-19)

| Check | Result |
|---|---|
| Flat plains (amplitude 0.25, ridges 0) | 8 studs of relief, smooth |
| Sharp peaks + water (amplitude 2.2, ridges 0.85) | 137 studs of relief, water at 18 |
| Terrain generation, 384² world | 1.8 s (was 57 s before per-tile banding) |
| Full world 512², terrain→scatter→structures→surface→light | 11 s |
| Library import, 11 assets incl. alpha foliage and a structure kit | all organised, 0 failures |
| Zoned scatter (rock highlands / plants lowlands) | 66 objects, correctly separated |
| Structures from tagged kit | 85 pieces across 3 sites |
| Save → mutate → load | hash restored exactly (`fnv1a32:a291fb1a`) |
| M1–M9 cumulative after a WorldForge build + release | `PASSED_M1_M2_M3_M4_M5_M6_M8_M9_CUMULATIVE` |

---

## API quick reference

```lua
local WF = require(game.ServerStorage.WorldForge.WorldForge)

WF.Help()                       -- prints this cheat sheet
WF.NewRecipe("My World")
WF.Set("terrain.amplitude", 1.8)
WF.RollSeed("terrain")          -- or WF.SetSeed("terrain", 1234)
WF.Preview()                    -- plan only, creates nothing
WF.Build("terrain")             -- one layer
WF.Build()                      -- everything
WF.Status()                     -- recipe, hash, seeds, stale layers
WF.Clear()
WF.ReleaseToWorldEngine()
```

Layer names for `Build`: `terrain`, `surface`, `scatter`, `structures`,
`lighting`.

---

## Known limits

- The panel lives in `CoreGui` and is opened with one command per Studio
  session; it is not yet a `.rbxmx` plugin (that is a packaging step, not new
  functionality).
- Rojo sync-in proposes deleting Studio-owned instances (library templates,
  ruin templates, applied SurfaceAppearances). Abort the sync, or accept and
  then run the regression, which self-heals. Same caveat as the M9 note.
- Structures use one kit at a time; multiple named kits per world is future work.
- The library holds asset IDs, not files — upload meshes/textures to Roblox
  first (3D Importer or the web), then register the IDs here.
