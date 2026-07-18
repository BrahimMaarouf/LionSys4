--!strict

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Config = require(WorldEngine.Config.Composition.DesertWorldComposition)
local Planner = require(WorldEngine.Planning.WorldCompositionPlanner)

type Plan = Planner.Plan
type SurfacePoint = Planner.SurfacePoint

local Materializer = {}

local function compositionFolder(): Folder
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local existing = generated:FindFirstChild("WorldComposition")
	if existing then existing:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "WorldComposition"
	folder.Parent = generated
	return folder
end

local function childFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function hiddenAnchor(name: string, position: Vector3, kind: string): Part
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Size = Vector3.new(0.25, 0.25, 0.25)
	anchor.Position = position
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor:SetAttribute("CompositionAnchorKind", kind)
	anchor:SetAttribute("Milestone5Version", Config.Version)
	return anchor
end

local function tangentAt(samples: {SurfacePoint}, index: number): Vector3
	local first = samples[math.max(1, index - 1)]
	local second = samples[math.min(#samples, index + 1)]
	local tangent = Vector3.new(second.WorldX - first.WorldX, second.GroundY - first.GroundY, second.WorldZ - first.WorldZ)
	return if tangent.Magnitude > 0.001 then tangent.Unit else Vector3.zAxis
end

local function makePathPatch(samples: {SurfacePoint}, index: number, route, regionDefinition): BasePart
	local sample = samples[index]
	local tangent = tangentAt(samples, index)
	local projected = tangent - sample.Normal * tangent:Dot(sample.Normal)
	if projected.Magnitude < 0.001 then projected = Vector3.zAxis - sample.Normal * Vector3.zAxis:Dot(sample.Normal) end
	projected = projected.Unit
	local back = -projected
	local right = sample.Normal:Cross(back).Unit
	local patch = Instance.new("Part")
	patch.Name = string.format("%s_%03d", route.Id, index)
	patch.Shape = Enum.PartType.Ball
	patch.Size = Vector3.new(8.5, 0.30, Config.RouteSampleSpacing * 1.28)
	patch.CFrame = CFrame.fromMatrix(Vector3.new(sample.WorldX, sample.GroundY + 0.05, sample.WorldZ), right, sample.Normal, back)
	patch.Anchored = true
	patch.CanCollide = false
	patch.CanQuery = false
	patch.CanTouch = false
	patch.CastShadow = false
	patch.Material = Enum.Material.Sandstone
	patch.Color = regionDefinition.PathColor
	patch.Transparency = 0.12
	patch:SetAttribute("RouteId", route.Id)
	patch:SetAttribute("RouteKind", route.Kind)
	patch:SetAttribute("RouteSampleIndex", index)
	patch:SetAttribute("RegionId", route.RegionId)
	patch:SetAttribute("Milestone5Version", Config.Version)
	return patch
end

local function multiplyColor(first: Color3, second: Color3): Color3
	return Color3.new(first.R * second.R, first.G * second.G, first.B * second.B)
end

local function annotateAndTint(plan: Plan)
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local props = generated:WaitForChild("DesertProps")
	for _, variant in plan.Variation.Variants do
		local name = string.format("%03d_%s_%s", variant.Index, variant.AssetId, variant.RecipeId)
		local model = props:FindFirstChild(name)
		assert(model and model:IsA("Model"), "M5 could not find an M4 variant")
		local placement = plan.Placements[variant.BasePlacementIndex]
		assert(placement, "M5 variation points to a missing placement")
		model:SetAttribute("RegionId", placement.RegionId)
		model:SetAttribute("LandmarkId", placement.LandmarkId)
		model:SetAttribute("VistaId", placement.VistaId)
		model:SetAttribute("CompositionLayer", placement.CompositionLayer)
		model:SetAttribute("Milestone5Version", Config.Version)
		local definition = Config.ById[placement.RegionId]
		assert(definition, "Unknown region definition")
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("MeshPart") and descendant:GetAttribute("WorldEngineLODLevel") ~= nil then
				local tint = if model:GetAttribute("AssetKind") == "Rock" then definition.RockTint
					elseif descendant.Name == "Branches" then definition.BranchTint else definition.FoliageTint
				descendant.Color = multiplyColor(descendant.Color, tint)
			end
		end
	end
end

function Materializer.Clear()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local existing = generated:FindFirstChild("WorldComposition")
	if existing then existing:Destroy() end
end

function Materializer.Materialize(plan: Plan)
	local root = compositionFolder()
	local branchRoutes = childFolder(root, "BranchRoutes")
	local regionAnchors = childFolder(root, "RegionAnchors")
	local landmarkAnchors = childFolder(root, "LandmarkAnchors")
	local vistaAnchors = childFolder(root, "VistaAnchors")

	local branchPatchCount = 0
	for _, route in plan.Routes do
		if route.Kind == "Primary" then continue end
		local folder = childFolder(branchRoutes, route.Id)
		local definition = Config.ById[route.RegionId]
		for index = 1, #route.Samples do
			makePathPatch(route.Samples, index, route, definition).Parent = folder
			branchPatchCount += 1
		end
	end
	for _, region in plan.Regions do
		local anchor = hiddenAnchor(region.Id, Vector3.new(region.AnchorX, region.AnchorY + 1, region.AnchorZ), "Region")
		anchor:SetAttribute("RegionId", region.Id)
		anchor:SetAttribute("RegionKind", region.Kind)
		anchor:SetAttribute("CoverageCellCount", plan.RegionCellCounts[region.Id] or 0)
		anchor.Parent = regionAnchors
	end
	for _, landmark in plan.Landmarks do
		local anchor = hiddenAnchor(landmark.Id, Vector3.new(landmark.WorldX, landmark.GroundY + 1, landmark.WorldZ), "Landmark")
		anchor:SetAttribute("LandmarkId", landmark.Id)
		anchor:SetAttribute("RegionId", landmark.RegionId)
		anchor:SetAttribute("RouteId", landmark.RouteId)
		anchor:SetAttribute("PrimaryLandmark", landmark.Primary)
		anchor.Parent = landmarkAnchors
	end
	for _, vista in plan.Vistas do
		local anchor = hiddenAnchor(vista.Id, Vector3.new(vista.WorldX, vista.GroundY + Config.VistaEyeHeight, vista.WorldZ), "Vista")
		anchor:SetAttribute("VistaId", vista.Id)
		anchor:SetAttribute("LandmarkId", vista.LandmarkId)
		anchor:SetAttribute("RouteId", vista.RouteId)
		anchor:SetAttribute("TargetX", vista.TargetX)
		anchor:SetAttribute("TargetY", vista.TargetY)
		anchor:SetAttribute("TargetZ", vista.TargetZ)
		anchor:SetAttribute("VistaScore", vista.Score)
		anchor:SetAttribute("LineOfSightClear", vista.LineOfSightClear)
		anchor.Parent = vistaAnchors
	end
	annotateAndTint(plan)

	local worldRoot = Workspace:WaitForChild("WorldRoot")
	worldRoot:SetAttribute("GeneratorVersion", Config.Version)
	worldRoot:SetAttribute("Milestone5CompositionVersion", Config.Version)
	worldRoot:SetAttribute("Milestone5PlanSignature", plan.Signature)
	worldRoot:SetAttribute("Milestone5RegionCount", #plan.Regions)
	worldRoot:SetAttribute("Milestone5RouteCount", #plan.Routes)
	worldRoot:SetAttribute("Milestone5LandmarkCount", #plan.Landmarks)
	worldRoot:SetAttribute("Milestone5VistaCount", #plan.Vistas)
	worldRoot:SetAttribute("Milestone5PlacementCount", #plan.Placements)
	worldRoot:SetAttribute("Milestone5VariantCount", #plan.Variation.Variants)
	return {
		Folder = root,
		BranchPatchCount = branchPatchCount,
		RegionAnchorCount = #plan.Regions,
		LandmarkAnchorCount = #plan.Landmarks,
		VistaAnchorCount = #plan.Vistas,
	}
end

return table.freeze(Materializer)
