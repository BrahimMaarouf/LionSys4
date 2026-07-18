--!strict

-- Templates.rbxm is a binary import artifact. This source-owned applicator
-- makes the M7 PBR assignment reproducible even if Studio undo or a template
-- re-import restores the older M2 SurfaceAppearances. It is safe to call
-- repeatedly and deliberately does not affect any geometry signature.
local ServerStorage = game:GetService("ServerStorage")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local AssetIds = require(script.Parent.AssetIds)

local Applier = {}

local function applySurface(part: Instance?, textureSet, alphaMode: Enum.AlphaMode)
	assert(part and part:IsA("MeshPart"), "Expected M7 template MeshPart")
	local surface = part:FindFirstChildOfClass("SurfaceAppearance") or Instance.new("SurfaceAppearance")
	surface.ColorMap = textureSet.BaseColor
	surface.NormalMap = textureSet.Normal
	surface.RoughnessMap = textureSet.Roughness
	surface.AlphaMode = alphaMode
	surface.Parent = part
end

function Applier.Apply()
	local templates = WorldEngine.Assets.Rocks:WaitForChild("Templates")
	for _, name in {"WindBoulder", "LayeredMesa"} do
		local template = templates:FindFirstChild(name)
		assert(template and template:IsA("Model"), "Missing rock template: " .. name)
		applySurface(template:FindFirstChild("Render"), AssetIds.RockTextures, Enum.AlphaMode.Overlay)
		local lods = template:FindFirstChild("LODVariants")
		assert(lods and lods:IsA("Folder"), "Missing LOD variants: " .. name)
		applySurface(lods:FindFirstChild("LOD1"), AssetIds.RockTextures, Enum.AlphaMode.Overlay)
		applySurface(lods:FindFirstChild("LOD2"), AssetIds.RockTextures, Enum.AlphaMode.Overlay)
	end

	local shrub = templates:FindFirstChild("DryShrub")
	assert(shrub and shrub:IsA("Model"), "Missing vegetation template: DryShrub")
	applySurface(shrub:FindFirstChild("Foliage"), AssetIds.ShrubTextures, Enum.AlphaMode.Transparency)
	applySurface(shrub:FindFirstChild("Branches"), AssetIds.BarkTextures, Enum.AlphaMode.Overlay)
	local shrubLods = shrub:FindFirstChild("LODVariants")
	assert(shrubLods and shrubLods:IsA("Folder"), "Missing shrub LOD variants")
	applySurface(shrubLods:FindFirstChild("LOD1"), AssetIds.ShrubTextures, Enum.AlphaMode.Transparency)
	applySurface(shrubLods:FindFirstChild("LOD2"), AssetIds.ShrubTextures, Enum.AlphaMode.Transparency)
	return {Templates = 3, Surfaces = 10}
end

return table.freeze(Applier)
