--!strict

local AssetIds = require(script.Parent.AssetIds)

export type DesertAsset = {
	Id: string,
	Kind: "Rock" | "Vegetation",
	DisplayName: string,
	TemplateName: string,
	SourceGlb: string,
	MeshIds: {[string]: string},
	TextureIds: {[string]: string},
	Weight: number,
	ScaleMin: number,
	ScaleMax: number,
	MaxSlopeDegrees: number,
	SpacingRadius: number,
	SinkStuds: number,
	UsesAlphaCards: boolean,
	WindEnabled: boolean,
}

local assets: {DesertAsset} = {
	{
		Id = "WindBoulder",
		Kind = "Rock",
		DisplayName = "Wind-eroded Boulder",
		TemplateName = "WindBoulder",
		SourceGlb = "assets/export/WindBoulder.glb",
		MeshIds = AssetIds.WindBoulder.Meshes,
		TextureIds = AssetIds.RockTextures,
		Weight = 0.36,
		ScaleMin = 0.62,
		ScaleMax = 1.38,
		MaxSlopeDegrees = 25,
		SpacingRadius = 8.5,
		SinkStuds = 0.45,
		UsesAlphaCards = false,
		WindEnabled = false,
	},
	{
		Id = "LayeredMesa",
		Kind = "Rock",
		DisplayName = "Layered Mesa Rock",
		TemplateName = "LayeredMesa",
		SourceGlb = "assets/export/LayeredMesa.glb",
		MeshIds = AssetIds.LayeredMesa.Meshes,
		TextureIds = AssetIds.RockTextures,
		Weight = 0.27,
		ScaleMin = 0.70,
		ScaleMax = 1.28,
		MaxSlopeDegrees = 20,
		SpacingRadius = 10,
		SinkStuds = 0.35,
		UsesAlphaCards = false,
		WindEnabled = false,
	},
	{
		Id = "DryShrub",
		Kind = "Vegetation",
		DisplayName = "Dry Desert Shrub",
		TemplateName = "DryShrub",
		SourceGlb = "assets/export/DryShrub.glb",
		MeshIds = AssetIds.DryShrub.Meshes,
		TextureIds = AssetIds.ShrubTextures,
		Weight = 0.37,
		ScaleMin = 0.58,
		ScaleMax = 1.18,
		MaxSlopeDegrees = 18,
		SpacingRadius = 4.5,
		SinkStuds = 0.12,
		UsesAlphaCards = true,
		WindEnabled = true,
	},
}

local byId: {[string]: DesertAsset} = {}
for _, asset in assets do
	byId[asset.Id] = asset
	-- MeshIds/TextureIds tables can be shared between assets (both rocks share
	-- one PBR set), so guard against double-freezing a shared table.
	if not table.isfrozen(asset.MeshIds) then
		table.freeze(asset.MeshIds)
	end
	if not table.isfrozen(asset.TextureIds) then
		table.freeze(asset.TextureIds)
	end
	table.freeze(asset)
end

local Catalog = {
	Version = "2.1.0-m2-owned-dcc-lod",
	Family = "DesertFoundationProps",
	Dcc = "Blender 4.5.0 LTS",
	SourceBlend = "assets/blender/M2_DesertAssetSlice.blend",
	Assets = table.freeze(assets),
	ById = table.freeze(byId),
}

return table.freeze(Catalog)
