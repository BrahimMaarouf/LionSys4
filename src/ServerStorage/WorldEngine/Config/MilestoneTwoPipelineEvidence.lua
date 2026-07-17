--!strict

local evidence = {
	PinnedBlenderVersion = "4.5.0 LTS",
	DccValidationPassed = true,
	DccValidationReport = "assets/M2_DCC_VALIDATION.json",
	DccValidationSha256 = "14060c97fee07457a255ad8ec3e58678c06d9a5af5fdc2caa5d69d08cfd87619",
	OwnedSourceBlend = "assets/blender/M2_DesertAssetSlice.blend",
	OwnedFamilyExports = {
		"assets/export/WindBoulder.glb",
		"assets/export/LayeredMesa.glb",
		"assets/export/DryShrub.glb",
	},
	CreatorStoreAssetCount = 0,
	TemplateArtifact = "src/ServerStorage/WorldEngine/Assets/Rocks/Templates.rbxm",
	TemplateArtifactSha256 = "0c8fe1aa8663bf0fa6895db9875f0f8b150e7c7ce76b51fd09e16155e222450d",
	SourceBlendSha256 = "6d5db5c6500875ef2ae1ce53de9c22f7e38e7f7a907bfcd67c9bf293f6f351c2",
	SourceManifestSchema = 2,
	HumanVisualSignoffPassed = true,
	HumanVisualSignoffDate = "2026-07-17",
	HumanVisualSignoffNotes = "Grounding, silhouettes, clustered composition, alpha foliage, lighting, wind, and near/mid/far authored LOD switching inspected in Studio play mode.",
}

return table.freeze(evidence)
