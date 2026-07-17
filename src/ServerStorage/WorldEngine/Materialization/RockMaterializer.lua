--!strict

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Catalog = require(WorldEngine.Assets.Rocks.RockCatalog)
local PropPlanner = require(WorldEngine.Planning.RockPlacementPlanner)

type Plan = PropPlanner.Plan
type Placement = PropPlanner.Placement

local PROP_TAG = "WorldEngineDesertProp"
local WIND_TAG = "WorldEngineWindVegetation"
local LOD_TAG = "WorldEngineCustomLOD"
local Materializer = {}

local function templateModel(templateName: string): Model
	local templates = WorldEngine.Assets.Rocks:WaitForChild("Templates")
	local template = templates:FindFirstChild(templateName)
	assert(template and template:IsA("Model"), "Missing owned DCC template model: " .. templateName)
	assert(template:FindFirstChild("LODVariants"), "Template is missing source LOD variants: " .. templateName)
	assert(template:FindFirstChild("Collision"), "Template is missing collision proxy: " .. templateName)
	return template
end

local function propsFolder(): Folder
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local existing = generated:FindFirstChild("DesertProps")
	if existing then
		assert(existing:IsA("Folder"), "WorldRoot.Generated.DesertProps must be a Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "DesertProps"
	folder.Parent = generated
	return folder
end

local function surfaceFrame(position: Vector3, normal: Vector3, yawRadians: number): CFrame
	local projected = Vector3.xAxis - normal * Vector3.xAxis:Dot(normal)
	if projected.Magnitude < 0.001 then
		projected = Vector3.zAxis - normal * Vector3.zAxis:Dot(normal)
	end
	local right = projected.Unit
	local back = right:Cross(normal).Unit
	return CFrame.fromMatrix(position, right, normal, back) * CFrame.Angles(0, yawRadians, 0)
end

local function copyAppearance(source: Instance?, target: MeshPart)
	if target:FindFirstChildOfClass("SurfaceAppearance") then
		return
	end
	local appearance = if source then source:FindFirstChildOfClass("SurfaceAppearance") else nil
	if appearance then
		local clone = appearance:Clone()
		clone.Parent = target
	end
end

local function prepareAuthoredLods(model: Model, asset)
	local archive = model:FindFirstChild("LODVariants")
	assert(archive and archive:IsA("Folder"), "Template is missing LODVariants")
	local appearanceSource = if asset.Kind == "Vegetation"
		then model:FindFirstChild("Foliage")
		else model:FindFirstChild("Render")

	for _, name in { "LOD1", "LOD2" } do
		local lod = archive:FindFirstChild(name)
		assert(lod and lod:IsA("MeshPart"), "Template is missing authored " .. name)
		lod.Parent = model
		lod.Name = name
		lod.Anchored = true
		lod.CanCollide = false
		lod.CanQuery = false
		lod.CanTouch = false
		lod.RenderFidelity = Enum.RenderFidelity.Precise
		copyAppearance(appearanceSource, lod)
	end
	archive:Destroy()
	model:SetAttribute("LODNearDistance", 180)
	model:SetAttribute("LODFarDistance", 360)
end

local function makeProp(placement: Placement): Model
	local asset = Catalog.ById[placement.AssetId]
	assert(asset, "Unknown desert asset: " .. placement.AssetId)
	local model = templateModel(asset.TemplateName):Clone()
	model.Name = string.format("%03d_%s", placement.Index, asset.Id)
	model.LevelOfDetail = Enum.ModelLevelOfDetail.Disabled
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("PlacementIndex", placement.Index)
	model:SetAttribute("SourceAsset", asset.Id)
	model:SetAttribute("AssetKind", asset.Kind)
	model:SetAttribute("CatalogVersion", Catalog.Version)
	model:SetAttribute("SlopeDegrees", placement.SlopeDegrees)
	model:SetAttribute("Scale", placement.Scale)
	model:SetAttribute("WindEnabled", asset.WindEnabled)

	prepareAuthoredLods(model, asset)
	model:ScaleTo(placement.Scale)
	model:PivotTo(surfaceFrame(
		Vector3.new(placement.WorldX, placement.GroundY - asset.SinkStuds * placement.Scale, placement.WorldZ),
		placement.Normal,
		placement.YawRadians
	))

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("MeshPart") then
			descendant.Anchored = true
			descendant.CanTouch = false
			if descendant.Name ~= "Collision" then
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.RenderFidelity = Enum.RenderFidelity.Precise
			end
		end
	end
	CollectionService:AddTag(model, PROP_TAG)
	CollectionService:AddTag(model, LOD_TAG)
	if asset.WindEnabled then
		CollectionService:AddTag(model, WIND_TAG)
	end
	return model
end

function Materializer.Clear()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local existing = generated:FindFirstChild("DesertProps")
	if existing then
		existing:Destroy()
	end
	local legacy = generated:FindFirstChild("Rocks")
	if legacy then
		legacy:Destroy()
	end
end

function Materializer.Materialize(plan: Plan)
	Materializer.Clear()
	local folder = propsFolder()
	for _, placement in plan.Placements do
		local model = makeProp(placement)
		model.Parent = folder
	end

	local worldRoot = Workspace:WaitForChild("WorldRoot")
	worldRoot:SetAttribute("DesertAssetCatalogVersion", Catalog.Version)
	worldRoot:SetAttribute("DesertPropPlacementSignature", plan.Signature)
	worldRoot:SetAttribute("DesertPropCount", #plan.Placements)
	return folder
end

return table.freeze(Materializer)
