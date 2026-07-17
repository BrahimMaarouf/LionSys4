# WorldEngine Asset Pipeline

Pinned DCC: Blender `4.5.0 LTS`.

## Conventions

- One Blender unit equals one Roblox stud (`Unit System: None`, scale `1`).
- Blender Z is up; Studio import uses `World Forward: Front`, `World Up: Top`.
- Object origin is centered at ground contact; assets extend upward from `Z = 0`.
- Apply rotation and scale before export; outward normals and UVs are required.
- PBR textures use base color, tangent-space normal, and roughness PNG maps.
- Names end in `_LOD0`, `_LOD1`, `_LOD2`, or `_COL`.
- Vegetation branches and alpha-card foliage remain separate LOD0 meshes so
  Studio can assign opaque and transparent materials independently.
- `_COL` is a simplified collision proxy and is not rendered.
- Export is GLB with materials, textures, custom properties, Y-up conversion, and scale `1`.

## Rebuild

```powershell
tools\blender-4.5.0-windows-x64\blender.exe --background --python pipeline\blender\generate_m2_assets.py
```

The command recreates the committed `.blend`, `.glb`, and texture files deterministically.
The family GLBs preserve the DCC hierarchy. `assets/export/studio/` contains
one GLB per render or collision mesh for Studio's upload API.

Validate the exported hierarchy, transforms, bounds, LOD reduction, UVs, materials, and collisions:

```powershell
tools\blender-4.5.0-windows-x64\blender.exe --background --python pipeline\blender\validate_m2_assets.py
```

## Studio import

Use Studio `File > Import`, enable upload to Roblox, import as a model, set scale unit to `Stud`, forward to `Front`, and up to `Top`. Preserve the LOD and collision names. Save the complete `Templates` folder as `src/ServerStorage/WorldEngine/Assets/Rocks/Templates.rbxm`; Rojo then includes the binary template source in both live sync and clean builds.
