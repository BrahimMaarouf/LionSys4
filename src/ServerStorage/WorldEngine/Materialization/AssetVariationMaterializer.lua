--!strict

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Catalog = require(WorldEngine.Assets.Rocks.RockCatalog)
local Config = require(WorldEngine.Config.Variation.DesertAssetFamilies)
local Planner = require(WorldEngine.Planning.AssetVariationPlanner)

type Plan = Planner.Plan
type Variant = Planner.Variant
type VariationComponent = Planner.VariationComponent

local PROP_TAG = "WorldEngineDesertProp"
local WIND_TAG = "WorldEngineWindVegetation"
local LOD_TAG = "WorldEngineCustomLOD"
local VARIANT_TAG = "WorldEngineAssetVariant"
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
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "DesertProps"
	folder.Parent = generated
	return folder
end

local function surfaceFrame(position: Vector3, normal: Vector3, yawRadians: number, pitchRadians: number, rollRadians: number): CFrame
	local projected = Vector3.xAxis - normal * Vector3.xAxis:Dot(normal)
	if projected.Magnitude < 0.001 then
		projected = Vector3.zAxis - normal * Vector3.zAxis:Dot(normal)
	end
	local right = projected.Unit
	local back = right:Cross(normal).Unit
	return CFrame.fromMatrix(position, right, normal, back)
		* CFrame.Angles(0, yawRadians, 0)
		* CFrame.Angles(pitchRadians, 0, rollRadians)
end

local function copyAppearance(source: Instance?, target: MeshPart)
	if target:FindFirstChildOfClass("SurfaceAppearance") then
		return
	end
	local appearance = if source then source:FindFirstChildOfClass("SurfaceAppearance") else nil
	if appearance then
		appearance:Clone().Parent = target
	end
end

local function prepareAuthoredLods(model: Model, asset)
	local archive = model:FindFirstChild("LODVariants")
	assert(archive and archive:IsA("Folder"), "Template is missing LODVariants")
	local appearanceSource = if asset.Kind == "Vegetation"
		then model:FindFirstChild("Foliage")
		else model:FindFirstChild("Render")
	for _, name in {"LOD1", "LOD2"} do
		local lod = archive:FindFirstChild(name)
		assert(lod and lod:IsA("MeshPart"), "Template is missing authored " .. name)
		lod.Parent = model
		lod.Name = name
		lod.Anchored = true
		lod.CanCollide = false
		lod.CanQuery = false
		lod.CanTouch = false
		lod.RenderFidelity = Enum.RenderFidelity.Precise
		lod:SetAttribute("WorldEngineLODLevel", if name == "LOD1" then 1 else 2)
		copyAppearance(appearanceSource, lod)
	end
	archive:Destroy()
	for _, name in if asset.Kind == "Vegetation" then {"Branches", "Foliage"} else {"Render"} do
		local part = model:FindFirstChild(name)
		assert(part and part:IsA("MeshPart"), "Template is missing LOD0 render part " .. name)
		part:SetAttribute("WorldEngineLODLevel", 0)
	end
	local collision = model:FindFirstChild("Collision")
	assert(collision and collision:IsA("MeshPart"), "Template is missing collision")
	collision:SetAttribute("WorldEngineVariationCollision", true)
end

local function stretchModel(model: Model, stretch: Vector3)
	local pivot = model:GetPivot()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local localFrame = pivot:ToObjectSpace(descendant.CFrame)
			local localPosition = localFrame.Position
			descendant.Size = Vector3.new(
				descendant.Size.X * stretch.X,
				descendant.Size.Y * stretch.Y,
				descendant.Size.Z * stretch.Z
			)
			descendant.CFrame = pivot
				* CFrame.new(localPosition.X * stretch.X, localPosition.Y * stretch.Y, localPosition.Z * stretch.Z)
				* localFrame.Rotation
		end
	end
end

local function tintPart(part: MeshPart, assetKind: string, tintIndex: number)
	if part:GetAttribute("WorldEngineVariationCollision") then
		return
	end
	if assetKind == "Rock" then
		part.Color = Config.Palettes.Rock[tintIndex]
	elseif part.Name == "Branches" then
		part.Color = Config.Palettes.Branch[tintIndex]
	else
		part.Color = Config.Palettes.Foliage[tintIndex]
	end
end

local function makeComponent(componentPlan: VariationComponent, variant: Variant): Model
	local asset = Catalog.ById[componentPlan.AssetId]
	assert(asset, "Unknown component asset: " .. componentPlan.AssetId)
	local component = templateModel(asset.TemplateName):Clone()
	component.Name = string.format("Component_%02d_%s", componentPlan.Index, componentPlan.AssetId)
	component.LevelOfDetail = Enum.ModelLevelOfDetail.Disabled
	component.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	component:SetAttribute("ComponentIndex", componentPlan.Index)
	component:SetAttribute("SourceAsset", componentPlan.AssetId)
	component:SetAttribute("RecipeId", variant.RecipeId)
	component:SetAttribute("UniformScale", componentPlan.UniformScale)
	component:SetAttribute("StretchX", componentPlan.StretchX)
	component:SetAttribute("StretchY", componentPlan.StretchY)
	component:SetAttribute("StretchZ", componentPlan.StretchZ)
	component:SetAttribute("TintIndex", componentPlan.TintIndex)

	prepareAuthoredLods(component, asset)
	component:ScaleTo(componentPlan.UniformScale)
	stretchModel(component, Vector3.new(componentPlan.StretchX, componentPlan.StretchY, componentPlan.StretchZ))
	component:PivotTo(surfaceFrame(
		Vector3.new(componentPlan.WorldX, componentPlan.PivotY, componentPlan.WorldZ),
		componentPlan.Normal,
		componentPlan.YawRadians,
		componentPlan.PitchRadians,
		componentPlan.RollRadians
	))

	for _, descendant in component:GetDescendants() do
		if descendant:IsA("MeshPart") then
			descendant.Anchored = true
			descendant.CanTouch = false
			if descendant:GetAttribute("WorldEngineVariationCollision") then
				descendant.Transparency = 1
				descendant.CanCollide = true
				descendant.CanQuery = true
				descendant.CastShadow = false
			else
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.RenderFidelity = Enum.RenderFidelity.Precise
				tintPart(descendant, asset.Kind, componentPlan.TintIndex)
			end
		end
	end
	return component
end

local function makeAnchor(variant: Variant): Part
	local anchor = Instance.new("Part")
	anchor.Name = "VariantAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = surfaceFrame(
		Vector3.new(variant.WorldX, variant.GroundY, variant.WorldZ),
		variant.Normal,
		variant.YawRadians,
		0,
		0
	)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	return anchor
end

local function makeVariant(variant: Variant): Model
	local root = Instance.new("Model")
	root.Name = string.format("%03d_%s_%s", variant.Index, variant.AssetId, variant.RecipeId)
	root.LevelOfDetail = Enum.ModelLevelOfDetail.Disabled
	root.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	root:SetAttribute("VariantIndex", variant.Index)
	root:SetAttribute("BasePlacementIndex", variant.BasePlacementIndex)
	root:SetAttribute("SourceAsset", variant.AssetId)
	root:SetAttribute("AssetKind", variant.AssetKind)
	root:SetAttribute("RecipeId", variant.RecipeId)
	root:SetAttribute("IdentityKey", variant.IdentityKey)
	root:SetAttribute("VariantSeed", variant.VariantSeed)
	root:SetAttribute("CompositionRole", variant.Role)
	root:SetAttribute("CompositionZone", variant.ZoneId)
	root:SetAttribute("VariationVersion", Config.Version)
	root:SetAttribute("ComponentCount", #variant.Components)
	root:SetAttribute("LODNearDistance", 180)
	root:SetAttribute("LODFarDistance", 360)
	root:SetAttribute("WindEnabled", variant.AssetKind == "Vegetation")

	local anchor = makeAnchor(variant)
	anchor.Parent = root
	root.PrimaryPart = anchor
	for _, componentPlan in variant.Components do
		makeComponent(componentPlan, variant).Parent = root
	end

	return root
end

function Materializer.Clear()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local existing = generated:FindFirstChild("DesertProps")
	if existing then
		existing:Destroy()
	end
end

function Materializer.Materialize(plan: Plan)
	local folder = propsFolder()
	for _, variant in plan.Variants do
		local model = makeVariant(variant)
		model.Parent = folder
		-- Publish tags only after the complete descendant hierarchy is in the
		-- DataModel. Clients can otherwise observe the tag before streamed LOD
		-- parts and permanently reject the incomplete entry.
		CollectionService:AddTag(model, PROP_TAG)
		CollectionService:AddTag(model, LOD_TAG)
		CollectionService:AddTag(model, VARIANT_TAG)
		if variant.AssetKind == "Vegetation" then
			CollectionService:AddTag(model, WIND_TAG)
		end
	end
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("GeneratorVersion", Config.Version)
	root:SetAttribute("Milestone4VariationVersion", Config.Version)
	root:SetAttribute("Milestone4PlanSignature", plan.Signature)
	root:SetAttribute("Milestone4VariantCount", #plan.Variants)
	root:SetAttribute("Milestone4ComponentCount", plan.ComponentCount)
	root:SetAttribute("Milestone4UniqueIdentityCount", plan.UniqueIdentityCount)
	return folder
end

return table.freeze(Materializer)
