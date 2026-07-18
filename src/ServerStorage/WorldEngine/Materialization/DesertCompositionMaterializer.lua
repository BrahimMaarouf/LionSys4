--!strict

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Config = require(WorldEngine.Config.Composition.DesertPilgrimage)
local PropMaterializer = require(WorldEngine.Materialization.RockMaterializer)
local CompositionPlanner = require(WorldEngine.Planning.DesertCompositionPlanner)

type Plan = CompositionPlanner.Plan
type SurfacePoint = CompositionPlanner.SurfacePoint

local Materializer = {}

local function pathFolder(): Folder
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local existing = generated:FindFirstChild("Paths")
	if existing then
		assert(existing:IsA("Folder"), "WorldRoot.Generated.Paths must be a Folder")
		existing:ClearAllChildren()
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Paths"
	folder.Parent = generated
	return folder
end

local function tangentAt(samples: {SurfacePoint}, index: number): Vector3
	local first = samples[math.max(1, index - 1)]
	local second = samples[math.min(#samples, index + 1)]
	local tangent = Vector3.new(
		second.WorldX - first.WorldX,
		second.GroundY - first.GroundY,
		second.WorldZ - first.WorldZ
	)
	if tangent.Magnitude < 0.001 then
		return Vector3.zAxis
	end
	return tangent.Unit
end

local function makePathPatch(samples: {SurfacePoint}, index: number): BasePart
	local sample = samples[index]
	local tangent = tangentAt(samples, index)
	local projected = tangent - sample.Normal * tangent:Dot(sample.Normal)
	if projected.Magnitude < 0.001 then
		projected = Vector3.zAxis - sample.Normal * Vector3.zAxis:Dot(sample.Normal)
	end
	projected = projected.Unit
	local back = -projected
	local right = sample.Normal:Cross(back).Unit

	local patch = Instance.new("Part")
	patch.Name = string.format("PathPatch_%03d", index)
	patch.Shape = Enum.PartType.Ball
	patch.Size = Vector3.new(Config.PathPatchWidth, 0.34, Config.PathPatchSpacing * 1.35)
	patch.CFrame = CFrame.fromMatrix(
		Vector3.new(sample.WorldX, sample.GroundY + 0.06, sample.WorldZ),
		right,
		sample.Normal,
		back
	)
	patch.Anchored = true
	patch.CanCollide = false
	patch.CanQuery = false
	patch.CanTouch = false
	patch.CastShadow = false
	patch.Material = Enum.Material.Sandstone
	patch.Color = Color3.fromRGB(163, 103, 58)
	patch.Transparency = 0.10
	patch:SetAttribute("PathIndex", index)
	patch:SetAttribute("CompositionVersion", Config.Version)
	return patch
end

local function configureSpawn(start: SurfacePoint)
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
	if not spawn then
		spawn = Instance.new("SpawnLocation")
		spawn.Name = "SpawnLocation"
		spawn.Parent = Workspace
	end
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.CastShadow = false
	spawn.Transparency = 1
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(start.WorldX, start.GroundY + 3, start.WorldZ)
	spawn.Neutral = true
	spawn.Duration = 0
	for _, child in spawn:GetChildren() do
		if child:IsA("Decal") then
			child:Destroy()
		end
	end
end

function Materializer.Clear()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local paths = generated:FindFirstChild("Paths")
	if paths then
		paths:ClearAllChildren()
	end
	PropMaterializer.Clear()
end

function Materializer.Materialize(plan: Plan)
	PropMaterializer.Materialize(plan :: any)
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local props = generated:WaitForChild("DesertProps")
	for _, placement in plan.Placements do
		local model = props:FindFirstChild(string.format("%03d_%s", placement.Index, placement.AssetId))
		assert(model and model:IsA("Model"), "Materialized prop is missing for composition placement")
		model:SetAttribute("CompositionRole", placement.Role)
		model:SetAttribute("CompositionZone", placement.ZoneId)
		model:SetAttribute("CompositionVersion", Config.Version)
	end

	local paths = pathFolder()
	for index = 1, #plan.PathSamples do
		makePathPatch(plan.PathSamples, index).Parent = paths
	end
	configureSpawn(plan.RouteNodes[1])

	local worldRoot = Workspace:WaitForChild("WorldRoot")
	worldRoot:SetAttribute("GeneratorVersion", Config.Version)
	worldRoot:SetAttribute("Milestone3CompositionVersion", Config.Version)
	worldRoot:SetAttribute("Milestone3PlanSignature", plan.Signature)
	worldRoot:SetAttribute("Milestone3PropCount", #plan.Placements)
	worldRoot:SetAttribute("Milestone3PathNodeCount", #plan.RouteNodes)
	worldRoot:SetAttribute("Milestone3PathPatchCount", #plan.PathSamples)
	worldRoot:SetAttribute("Milestone3Landmark", plan.Landmark.Id)
	return {
		PropFolder = props,
		PathFolder = paths,
		PropCount = #plan.Placements,
		PathPatchCount = #plan.PathSamples,
	}
end

return table.freeze(Materializer)
