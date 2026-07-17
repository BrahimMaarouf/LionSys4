--!strict

-- Owned asset IDs uploaded from pipeline/blender/generate_m2_assets.py exports
-- via Roblox Studio 3D Importer on 2026-07-17 (GLB family imports, Scale Unit = Stud).
-- Texture IDs are the SurfaceAppearance maps embedded in the GLB imports.
-- Both rock templates share the WindBoulder-import texture set so the two rock
-- families batch against one PBR set; the LayeredMesa-import duplicates are unused.
local ids = {
	WindBoulder = {
		Meshes = {
			LOD0 = "rbxassetid://115461967748519",
			LOD1 = "rbxassetid://91058435912843",
			LOD2 = "rbxassetid://102545361988963",
			Collision = "rbxassetid://133467161337897",
		},
	},
	LayeredMesa = {
		Meshes = {
			LOD0 = "rbxassetid://108699430223825",
			LOD1 = "rbxassetid://92687806290914",
			LOD2 = "rbxassetid://113217484663274",
			Collision = "rbxassetid://102488412195279",
		},
	},
	DryShrub = {
		Meshes = {
			BranchesLOD0 = "rbxassetid://118063902636752",
			FoliageLOD0 = "rbxassetid://136932855938218",
			LOD1 = "rbxassetid://91947829689114",
			LOD2 = "rbxassetid://101956757833949",
			Collision = "rbxassetid://104143325120325",
		},
	},
	RockTextures = {
		BaseColor = "rbxassetid://99627186924749",
		Normal = "rbxassetid://95545128032354",
		Roughness = "rbxassetid://76026688651618",
	},
	ShrubTextures = {
		BaseColor = "rbxassetid://121972517941237",
		Normal = "rbxassetid://106728068097919",
		Roughness = "rbxassetid://95409404892910",
	},
}

return table.freeze(ids)
