# WorldForge — Staged World Authoring Tool

Status: **plan**
Date: 2026-07-19
Supersedes: `WEB_UI_INTEGRATION_PLAN.md`

---

## 0. The goal, in your words

> "My system shouldn't create any object by himself. We give him rock, trees,
> leaves, etc. — textures we want to use in our world design, and the seed or
> seeds for terrain. Using the system we create, stage by stage, our dream
> world. First thing is uploading the seed(s) and generating terrain with all
> options available to create anything we want."

So the system is a **composer, not a creator**. You supply the material and the
seeds; the system arranges them under your control, one stage at a time, and
saves anything good.

Two rules that follow, and that everything below obeys:

1. **The engine never authors content.** No generated meshes, no generated
   textures. It positions, orients, scales, groups and tints *your* assets.
   (The Blender/Python generators in `pipeline/` become optional *sample kits*
   you can delete — they are not part of the engine.)
2. **Nothing is themed.** No "desert" in the engine. Words like wadi, dune and
   sanctuary become data you type, not logic that ships.

---

## 1. What exists today vs what's needed

Nine milestones already built the hard machinery — deterministic planning,
grounding, spacing, repair loops, LODs, validation, save/verify. What's missing
is that it's all wired to one hardcoded desert.

| Capability | Today | Needed |
|---|---|---|
| Terrain generation | works, fixed parameters, 1 seed | all options exposed, multi-seed |
| Asset source | 3 hardcoded IDs in `AssetIds.lua` | your library, any number, tagged |
| Placement rules | desert logic in planners (23 refs) | rules you define per asset/zone |
| Structures | 8-piece kit hardcoded | your kit, your socket rules |
| Surface/atmosphere | 5 desert materials | your palette |
| Control | Lua command bar | staged panel in Studio |
| Save | one golden world | unlimited saved worlds |

**The engine is ~85% reusable.** The work is unbinding it from the desert and
putting a face on it.

---

## 2. Architecture

### 2.1 Two documents define everything

**`AssetLibrary`** — your material, registered once, reused across worlds:

```jsonc
{
  "assets": [
    { "id": "pine_a", "name": "Pine A", "kind": "Tree",
      "mesh":    { "lod0": "rbxassetid://...", "lod1": "...", "collision": "..." },
      "texture": { "color": "rbxassetid://...", "normal": "...", "roughness": "...",
                   "alpha": "Transparency" },
      "footprint": 6.5, "height": 22, "spacing": 9,
      "maxSlope": 28, "sink": 0.4, "windEnabled": true,
      "tags": ["conifer", "cold", "forest"] }
  ]
}
```

**`WorldRecipe`** — one saved world, layer by layer:

```jsonc
{
  "name": "Frozen Pass",
  "seeds": { "terrain": 8814, "zones": 22, "scatter": 7, "structures": 91 },
  "terrain": { "size": 1024, "amplitude": 1.4, "ridges": 0.7, "warp": 0.3,
               "valleys": 0.5, "waterLevel": 12, "material": "Snow" },
  "zones":   [ { "name": "Treeline", "shape": "altitude", "min": 40, "max": 90,
                 "allow": ["pine_a", "pine_b", "boulder_*"], "density": 0.6 } ],
  "scatter": { "clustering": 0.7, "jitter": 0.3 },
  "structures": { "kit": "stone_ruin", "sites": 4, "degradation": 0.6 },
  "surface": { "palette": "alpine" },
  "lighting": { "clockTime": 8.2, "fog": 0.4 }
}
```

Both are plain data — saveable, diffable, shareable, hashable.

### 2.2 Per-stage seeds (the feature that makes it a tool)

Today one seed drives everything, so rerolling trees also destroys your
mountains. Splitting seeds per stage means:

- Roll terrain until the land is right → **lock it**
- Roll zones/scatter until vegetation is right → **lock it**
- Roll structures until the ruins land well → **lock it**

Each stage has its own dice, its own lock. This is the difference between a
generator and an instrument. The engine already derives seeds hierarchically,
so this is a natural extension, not a rewrite.

### 2.3 Stage dependency & rebuild cost

| Stage | Rebuilds | Cost |
|---|---|---|
| Lighting / palette | apply only | instant |
| Structures | structures | ~0.3 s |
| Scatter / zones | props | ~1–2 s |
| Terrain | everything downstream | ~8 s |

Changing an upstream stage marks downstream ones dirty; the panel shows which
layers will regenerate before you press the button. Nothing silently vanishes.

---

## 3. The tool — a Studio plugin, staged

A docked panel with one tab per stage. The viewport is the preview; no web
bridge, no relay server, no HTTP.

```
┌─ WorldForge ───────────────┐
│ [1 Terrain]  ← you are here│
│  2 Library                 │
│  3 Zones                   │
│  4 Scatter                 │
│  5 Structures              │
│  6 Surface & Light         │
│  7 Save                    │
├────────────────────────────┤
│ Seed   8814      [🎲][🔒]  │
│ Size   1024 ▾              │
│ Amplitude  ▓▓▓▓▓▓░░  1.4   │
│ Ridges     ▓▓▓▓▓▓▓░  0.7   │
│ Warp       ▓▓▓░░░░░  0.3   │
│ Valleys    ▓▓▓▓▓░░░  0.5   │
│ Water      ▓▓░░░░░░  12    │
│ Material   Snow ▾          │
│                            │
│ [ Generate Terrain ]       │
│ ⚠ regenerates: all stages  │
└────────────────────────────┘
```

**Stage 1 — Terrain**: seeds, size, resolution, amplitude, ridges, domain warp,
valley carving, water level, base material, plateau/flatten controls. Generate,
look at it, reroll or lock.

**Stage 2 — Library**: paste Roblox asset IDs (or pick from a folder in the
place), set kind/footprint/spacing/slope/sink/LODs/wind per asset. Live preview
row showing each asset on a test plot. Your library persists across worlds.

**Stage 3 — Zones**: define regions by rule (altitude band, slope, distance from
water, noise patch) or by name, and say which library assets are allowed, denied
or targeted in each. This is where "in the wadi only shrubs" becomes something
*you* type instead of something the engine believes.

**Stage 4 — Scatter**: density, clustering, jitter, spacing multipliers, edge
margins, spawn-clear radius — placement of your library assets under your zone
rules, with the existing grounding/spacing/repair machinery.

**Stage 5 — Structures**: register your modular kit (your meshes, your socket
tags), set site count, size, degradation, doorway guarantees. Same socket
grammar as M8, but the pieces are yours.

**Stage 6 — Surface & Light**: terrain material palette by rule (slope,
altitude, zone), detail scatter, lighting preset, atmosphere, post-FX.

**Stage 7 — Save**: name the world, save the recipe, list/load/duplicate/export
saved worlds. Rebuild any saved world and verify its hash.

---

## 4. Milestones

### **M10 — Unbind the engine** *(foundation, no visible UI)*
Extract every desert-specific value and rule out of the planners into
`AssetLibrary` + `WorldRecipe` documents. Introduce the parameter schema
(id, label, type, default, range, group, rebuild-scope) that the panel will
render itself from. Split seeds per stage.

**Gate:** the desert recipe + default library reproduces every M1–M9 golden
signature bit-identically. *(If the extraction changed nothing, it was correct.)*

### **M11 — Terrain stage, live**
Plugin skeleton + Stage 1 fully working: all terrain options, seed roll/lock,
generate, undo-safe, dirty-layer warnings.

**Gate:** produce three visually distinct landscapes (flat plain / rolling hills
/ sharp ridges) without touching code.

### **M12 — Asset Library**
Stage 2: register assets by ID, full metadata, per-asset test preview, library
persists in the place and exports to JSON. Placement stages read the library
instead of `AssetIds.lua`.

**Gate:** import a set of assets you supply (not the sample kit) and scatter
them into a world.

### **M13 — Zones & Scatter**
Stages 3–4: rule-based zones, allow/deny/target lists, density and clustering,
grounding + spacing + repair against your library.

**Gate:** two zones with different vegetation, correctly separated, nothing
floating or buried.

### **M14 — Structures**
Stage 5: your modular kit, socket definitions, degradation, enterability rules.

**Gate:** a structure built from a kit that isn't the sample ruin kit.

### **M15 — Surface, Light & Save**
Stages 6–7: rule-driven material palette, lighting, and the saved-world library
with load/duplicate/export and per-world hash verification.

**Gate:** save a world, restart Studio, reload it, identical hash.

### **M16 — Proof: a world that isn't a desert**
Using only the tool and assets you supply, build and save something with no
desert in it. No code written during this milestone — that's the point.

**Gate:** a saved recipe + screenshots of a non-desert world, produced entirely
through the panel.

---

## 5. Risks & guardrails

- **Determinism.** Parameters must scale/threshold values, never add or remove
  hash draws, or downstream stages shift. The M10 gate catches this.
- **"Golden" changes meaning.** After M10 golden = sample recipe + sample
  library. Every saved world then carries its own hash (M15).
- **Undo.** Each generate is one `ChangeHistoryService` waypoint — we already
  lost Studio state to Ctrl+Z once on this project.
- **Rojo sync-in wipes Studio-owned instances.** The M9 self-heal must run on
  the panel path too, or the first build after a sync fails confusingly.
- **Bad assets.** A mesh with a wrong pivot or missing collision will look
  broken however good the placement is. Stage 2 validates each asset on import
  (pivot at base, sane bounds, LODs present) and flags problems immediately.
- **Scope discipline.** The panel exposes parameters. Node graphs, spline roads,
  hand-painting and in-panel 3D are separate products, not this one.

---

## 6. What to build first

**M10, and specifically its gate.** It's the only step carrying real risk: is
this engine separable from the desert, or did the desert grow into it? A day or
two of careful refactoring with a binary pass/fail answer at the end. Everything
after it is mechanical, and every stage afterwards ships something you can see
and use.
