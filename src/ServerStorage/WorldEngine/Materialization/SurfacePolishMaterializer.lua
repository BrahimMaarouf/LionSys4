--!strict

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Config = require(WorldEngine.Config.Polish.DesertSurfacePolish)
local Planner = require(WorldEngine.Planning.SurfacePolishPlanner)
local HeightfieldPlanner = require(WorldEngine.Planning.HeightfieldPlanner)

type Plan = Planner.Plan
type WorldSpec = HeightfieldPlanner.WorldSpec

local Materializer = {}

local function polishFolder(): Folder
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local existing = generated:FindFirstChild("EnvironmentPolish")
	if existing then existing:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "EnvironmentPolish"
	folder.Parent = generated
	return folder
end

local function childFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function terrainRegion(spec: WorldSpec, chunkX: number, chunkZ: number): Region3
	local minX = spec.OriginX + chunkX * spec.ChunkSize
	local minZ = spec.OriginZ + chunkZ * spec.ChunkSize
	return Region3.new(
		Vector3.new(minX, spec.MinY, minZ),
		Vector3.new(minX + spec.ChunkSize, spec.MaxY, minZ + spec.ChunkSize)
	)
end

local function applyTerrainPalette()
	for materialName, color in Config.MaterialColors do
		Workspace.Terrain:SetMaterialColor(Enum.Material[materialName], color)
	end
end

local function paintTerrain(spec: WorldSpec, plan: Plan): {[string]: number}
	local counts: {[string]: number} = {}
	local chunkCount = spec.WorldSize / spec.ChunkSize
	local chunkCells = spec.ChunkSize / spec.Resolution
	for chunkZ = 0, chunkCount - 1 do
		for chunkX = 0, chunkCount - 1 do
			local region = terrainRegion(spec, chunkX, chunkZ)
			local materials, occupancies = Workspace.Terrain:ReadVoxels(region, spec.Resolution)
			for localX = 1, #materials do
				for localZ = 1, #materials[localX][1] do
					local globalX = chunkX * chunkCells + localX - 1
					local globalZ = chunkZ * chunkCells + localZ - 1
					local code = buffer.readu8(plan.MaterialCodes, globalZ * plan.Width + globalX)
					local desired = Planner.MaterialForCode(code)
					local painted = 0
					for y = #materials[localX], 1, -1 do
						if occupancies[localX][y][localZ] > 0 and materials[localX][y][localZ] ~= Enum.Material.Air then
							if painted < Config.SurfaceThicknessCells then materials[localX][y][localZ] = desired end
							painted += 1
							if painted >= Config.SurfaceThicknessCells then break end
						end
					end
					counts[desired.Name] = (counts[desired.Name] or 0) + 1
				end
			end
			Workspace.Terrain:WriteVoxels(region, spec.Resolution, materials, occupancies)
		end
	end
	return counts
end

local function surfaceFrame(position: Vector3, normal: Vector3, yaw: number): CFrame
	local projected = Vector3.xAxis - normal * Vector3.xAxis:Dot(normal)
	if projected.Magnitude < 0.001 then projected = Vector3.zAxis - normal * Vector3.zAxis:Dot(normal) end
	local right = projected.Unit
	local back = right:Cross(normal).Unit
	return CFrame.fromMatrix(position, right, normal, back) * CFrame.Angles(0, yaw, 0)
end

local function makeDetail(detail): BasePart
	local style = Config.DetailStyle[detail.Kind]
	local part = Instance.new("Part")
	part.Name = string.format("Detail_%03d_%s", detail.Index, detail.Kind)
	part.Shape = if detail.Kind == "DuneRipple" or detail.Kind == "SandDrift" or detail.Kind == "PebbleField"
		then Enum.PartType.Ball else Enum.PartType.Block
	part.Size = Vector3.new(detail.Width, detail.Height, detail.Depth)
	part.CFrame = surfaceFrame(
		Vector3.new(detail.WorldX, detail.GroundY + detail.Height * 0.12, detail.WorldZ),
		detail.Normal,
		detail.YawRadians
	)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = detail.Kind == "PebbleField" or detail.Kind == "StrataAccent"
	part.Material = style.Material
	part.Color = style.Color
	part.Transparency = if detail.Kind == "DuneRipple" then 0.12 elseif detail.Kind == "WadiCrack" then 0.08 else 0
	part:SetAttribute("DetailIndex", detail.Index)
	part:SetAttribute("DetailKind", detail.Kind)
	part:SetAttribute("RegionId", detail.RegionId)
	part:SetAttribute("Milestone6Version", Config.Version)
	return part
end

local function makeAtmosphereAnchor(region): Part
	local definition = Config.RegionAtmosphere[region.Id]
	local anchor = Instance.new("Part")
	anchor.Name = region.Id .. "Atmosphere"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = Vector3.new(region.AnchorX, region.AnchorY + Config.AtmosphereAnchorHeight, region.AnchorZ)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor:SetAttribute("RegionId", region.Id)
	anchor:SetAttribute("Milestone6Version", Config.Version)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RegionalDust"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = definition.Rate
	emitter.Lifetime = NumberRange.new(5.5, 9)
	emitter.Speed = NumberRange.new(definition.Speed * 0.65, definition.Speed)
	emitter.Drag = 0.18
	emitter.Acceleration = Vector3.new(0.8, 0.25, -0.35)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(180, 18)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-7, 7)
	emitter.Color = ColorSequence.new(definition.Color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.55, 1.5),
		NumberSequenceKeypoint.new(1, 2.2),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.84),
		NumberSequenceKeypoint.new(0.75, 0.90),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = 0.08
	emitter.LightInfluence = 0
	emitter:SetAttribute("Milestone6Version", Config.Version)
	emitter.Parent = anchor
	return anchor
end

local function getOrCreateLighting(className: string, name: string, parent: Instance): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then return existing end
	if existing then existing:Destroy() end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function applyCinematicLighting()
	local bloom = getOrCreateLighting("BloomEffect", "WorldEngineBloom", Lighting) :: BloomEffect
	bloom.Intensity = Config.Bloom.Intensity
	bloom.Size = Config.Bloom.Size
	bloom.Threshold = Config.Bloom.Threshold
	local depth = getOrCreateLighting("DepthOfFieldEffect", "WorldEngineDepthOfField", Lighting) :: DepthOfFieldEffect
	depth.FarIntensity = Config.DepthOfField.FarIntensity
	depth.FocusDistance = Config.DepthOfField.FocusDistance
	depth.InFocusRadius = Config.DepthOfField.InFocusRadius
	depth.NearIntensity = Config.DepthOfField.NearIntensity
	local atmosphere = Lighting:FindFirstChild("WorldEngineAtmosphere")
	assert(atmosphere and atmosphere:IsA("Atmosphere"), "Base desert atmosphere is missing")
	atmosphere.Density = Config.Atmosphere.Density
	atmosphere.Offset = Config.Atmosphere.Offset
	atmosphere.Glare = Config.Atmosphere.Glare
	atmosphere.Haze = Config.Atmosphere.Haze
	local clouds = getOrCreateLighting("Clouds", "WorldEngineClouds", Workspace.Terrain) :: Clouds
	clouds.Cover = Config.Clouds.Cover
	clouds.Density = Config.Clouds.Density
	clouds.Color = Config.Clouds.Color
end

function Materializer.Clear()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local existing = generated:FindFirstChild("EnvironmentPolish")
	if existing then existing:Destroy() end
	for _, name in {"WorldEngineBloom", "WorldEngineDepthOfField"} do
		local effect = Lighting:FindFirstChild(name)
		if effect then effect:Destroy() end
	end
	local clouds = Workspace.Terrain:FindFirstChild("WorldEngineClouds")
	if clouds then clouds:Destroy() end
end

function Materializer.Materialize(spec: WorldSpec, plan: Plan)
	applyTerrainPalette()
	local surfaceCounts = paintTerrain(spec, plan)
	local folder = polishFolder()
	local details = childFolder(folder, "SurfaceDetails")
	local atmosphere = childFolder(folder, "AtmosphereAnchors")
	for _, detail in plan.Details do makeDetail(detail).Parent = details end
	for _, region in plan.Composition.Regions do makeAtmosphereAnchor(region).Parent = atmosphere end
	applyCinematicLighting()
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("GeneratorVersion", Config.Version)
	root:SetAttribute("Milestone6PolishVersion", Config.Version)
	root:SetAttribute("Milestone6PlanSignature", plan.Signature)
	root:SetAttribute("Milestone6SurfaceCellCount", plan.Width * plan.Depth)
	root:SetAttribute("Milestone6DetailCount", #plan.Details)
	root:SetAttribute("Milestone6AtmosphereEmitterCount", #plan.Composition.Regions)
	return {
		Folder = folder, SurfaceCounts = surfaceCounts, DetailCount = #plan.Details,
		AtmosphereEmitterCount = #plan.Composition.Regions, PostEffectCount = 5,
	}
end

return table.freeze(Materializer)
