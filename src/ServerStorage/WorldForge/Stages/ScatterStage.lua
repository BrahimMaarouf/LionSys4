--!strict

-- WorldForge Stages 3 & 4: Zones and Scatter.
--
-- Zones divide the world by RULE, not by theme. A zone says "here" (altitude
-- band, slope range, noise patch, near water, everywhere) and "these assets
-- may live here". The engine has no opinion about what those assets are.
--
-- Scatter then places library assets on a jittered grid, respecting each
-- asset's own spacing/slope/sink rules plus the global density and clustering
-- controls, and grounds every object on the baked terrain surface.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldForge = script.Parent.Parent
local Checksum = require(WorldForge.Core.Checksum)
local Hash32 = require(WorldForge.Core.Hash32)
local Noise = require(WorldForge.Core.Noise)
local Library = require(WorldForge.Core.AssetLibrary)
local Recipe = require(WorldForge.Core.Recipe)
local TerrainStage = require(WorldForge.Stages.TerrainStage)

local Stage = {}

local CHANNEL = 0x53434154 -- "SCAT"
local CH_ZONE = 0x5A4F4E45
local CH_PATCH = 0x50415443
local PROP_TAG = "WorldForgeProp"

export type Placement = {
	Index: number,
	AssetId: string,
	Zone: string,
	X: number,
	Y: number,
	Z: number,
	Yaw: number,
	Scale: number,
	Normal: Vector3,
	Slope: number,
	Spacing: number,
}

local function unit(seed: number, a: number, b: number, c: number): number
	return (Hash32.ToSignedUnit(Hash32.HashIntegers(seed, a, b, c, CHANNEL)) + 1) * 0.5
end

local function surfaceAt(field, x: number, z: number): (number, Vector3, number)
	local step = field.Resolution
	local left = field.HeightAt(x - step, z)
	local right = field.HeightAt(x + step, z)
	local back = field.HeightAt(x, z - step)
	local front = field.HeightAt(x, z + step)
	local center = field.HeightAt(x, z)
	local dx = (right - left) / (step * 2)
	local dz = (front - back) / (step * 2)
	local normal = Vector3.new(-dx, 1, -dz).Unit
	local slope = math.deg(math.atan(math.sqrt(dx * dx + dz * dz)))
	return center, normal, slope
end

-- Does this zone claim this point?
local function zoneMatches(zone, field, x: number, z: number, height: number, slope: number, seed: number): boolean
	local rule = zone.Rule
	if rule == "everywhere" then
		return true
	elseif rule == "altitude" then
		local range = math.max(0.001, field.MaxHeight - field.MinHeight)
		local t = (height - field.MinHeight) / range
		return t >= (zone.Min or 0) and t <= (zone.Max or 1)
	elseif rule == "slope" then
		return slope >= (zone.Min or 0) and slope <= (zone.Max or 90)
	elseif rule == "nearWater" then
		local water = field.WaterLevel
		if water <= field.MinHeight then return false end
		return height >= water - (zone.Max or 8) and height <= water + (zone.Max or 8)
	elseif rule == "patch" then
		local value = Noise.Value2D(seed, x / 220, z / 220, CH_PATCH + (zone.PatchIndex or 0))
		local normalized = (value + 1) * 0.5
		return normalized >= (zone.Min or 0.5)
	end
	return false
end

-- Is this asset allowed in this zone?
local function zoneAllows(zone, assetId: string, assetKind: string): boolean
	for _, entry in zone.Allow do
		if entry == "*" then
			return true
		elseif entry == assetId then
			return true
		elseif string.sub(entry, 1, 5) == "kind:" and string.sub(entry, 6) == assetKind then
			return true
		end
	end
	return false
end

--[[
	Plans placements. Pure data: no instances are created or read, so this is
	safe to call for previews and cheap enough to run per keystroke.
]]
function Stage.Plan(recipe: Recipe.Data)
	local p = Recipe.Resolve(recipe)
	local seed = Recipe.GetSeed(recipe, "scatter")
	local zoneSeed = Recipe.GetSeed(recipe, "zones")
	local field = TerrainStage.BuildField(recipe)

	local assets = Library.List()
	if #assets == 0 then
		return {Placements = {}, Signature = "empty", AssetCount = 0, Rejected = {}}
	end

	local byId: {[string]: any} = {}
	for _, asset in assets do
		byId[asset.Id] = asset
	end

	local density = p["scatter.density"]
	local clustering = p["scatter.clustering"]
	local jitterAmount = p["scatter.jitter"]
	local spacingScale = p["scatter.spacingScale"]
	local cellSize = p["scatter.cellSize"]
	local edgeMargin = p["scatter.edgeMargin"]
	local spawnClear = p["scatter.spawnClear"]
	local maxObjects = p["scatter.maxObjects"]
	local scaleVariation = p["scatter.scaleVariation"]

	local size = field.Size
	local origin = field.Origin
	local available = size - edgeMargin * 2
	local cells = math.max(1, math.floor(available / cellSize))

	local placements: {Placement} = {}
	local rejected = {Density = 0, Spawn = 0, Slope = 0, Spacing = 0, NoZone = 0, Water = 0}

	-- spatial buckets keep spacing checks near-constant time
	local buckets: {[string]: {Placement}} = {}
	local bucketSize = math.max(cellSize, 24)
	local function bucketKey(x: number, z: number): string
		return string.format("%d:%d", math.floor(x / bucketSize), math.floor(z / bucketSize))
	end
	local function overlaps(x: number, z: number, radius: number): boolean
		local bx = math.floor(x / bucketSize)
		local bz = math.floor(z / bucketSize)
		for ox = -1, 1 do
			for oz = -1, 1 do
				local bucket = buckets[string.format("%d:%d", bx + ox, bz + oz)]
				if bucket then
					for _, other in bucket do
						local dx = other.X - x
						local dz = other.Z - z
						local minimum = other.Spacing + radius
						if dx * dx + dz * dz < minimum * minimum then
							return true
						end
					end
				end
			end
		end
		return false
	end

	for cz = 0, cells - 1 do
		for cx = 0, cells - 1 do
			if #placements >= maxObjects then break end

			local jitterRange = cellSize * jitterAmount
			local x = origin + edgeMargin + (cx + 0.5) * cellSize
				+ (unit(seed, cx, cz, 2) * 2 - 1) * jitterRange
			local z = origin + edgeMargin + (cz + 0.5) * cellSize
				+ (unit(seed, cx, cz, 3) * 2 - 1) * jitterRange

			-- clustering: a low-frequency field pushes density up in some
			-- places and down in others, so objects clump instead of spreading
			-- evenly. clustering = 0 makes this field flat.
			local patch = Noise.Value2D(seed, x / 160, z / 160, CHANNEL)
			local localDensity = math.clamp(density + patch * clustering * 0.9, 0, 1)
			if unit(seed, cx, cz, 1) > localDensity then
				rejected.Density += 1
				continue
			end

			if x * x + z * z < spawnClear * spawnClear then
				rejected.Spawn += 1
				continue
			end

			local height, normal, slope = surfaceAt(field, x, z)

			if field.WaterLevel > field.MinHeight and height < field.WaterLevel then
				rejected.Water += 1
				continue
			end

			-- which zone claims this point?
			local zone
			for _, candidate in recipe.Zones do
				if zoneMatches(candidate, field, x, z, height, slope, zoneSeed) then
					zone = candidate
					break
				end
			end
			if not zone then
				rejected.NoZone += 1
				continue
			end
			if unit(seed, cx, cz, 8) > (zone.Density or 1) then
				rejected.Density += 1
				continue
			end

			-- weighted pick among assets this zone allows
			local candidates = {}
			local totalWeight = 0
			for _, asset in assets do
				if zoneAllows(zone, asset.Id, asset.Kind) and slope <= (asset.MaxSlope or 35) then
					totalWeight += (asset.Weight or 1)
					table.insert(candidates, asset)
				end
			end
			if #candidates == 0 then
				rejected.Slope += 1
				continue
			end
			local roll = unit(seed, cx, cz, 4) * totalWeight
			local chosen = candidates[#candidates]
			local cumulative = 0
			for _, asset in candidates do
				cumulative += (asset.Weight or 1)
				if roll <= cumulative then
					chosen = asset
					break
				end
			end

			local scale = (chosen.Scale or 1)
				* (1 + (unit(seed, cx, cz, 5) * 2 - 1) * scaleVariation)
			scale = math.max(0.05, scale)
			local spacing = (chosen.Spacing or 6) * scale * spacingScale

			if overlaps(x, z, spacing) then
				rejected.Spacing += 1
				continue
			end

			local placement: Placement = {
				Index = #placements + 1,
				AssetId = chosen.Id,
				Zone = zone.Name,
				X = x,
				Y = height,
				Z = z,
				Yaw = unit(seed, cx, cz, 6) * math.pi * 2,
				Scale = scale,
				Normal = normal,
				Slope = slope,
				Spacing = spacing,
			}
			table.insert(placements, placement)
			local key = bucketKey(x, z)
			local bucket = buckets[key]
			if not bucket then
				bucket = {}
				buckets[key] = bucket
			end
			table.insert(bucket, placement)
		end
	end

	local state = Checksum.New()
	Checksum.UpdateString(state, "worldforge-scatter-v1")
	Checksum.UpdateUInt32(state, seed)
	Checksum.UpdateUInt32(state, #placements)
	for index, placement in placements do
		Checksum.UpdateIndexedUInt32(state, index, math.floor(placement.X * 512 + 0.5) % 4294967296)
		Checksum.UpdateString(state, placement.AssetId)
		Checksum.UpdateUInt32(state, math.floor(placement.Z * 512 + 0.5) % 4294967296)
		Checksum.UpdateUInt32(state, math.floor(placement.Scale * 4096 + 0.5) % 4294967296)
	end

	local counts: {[string]: number} = {}
	for _, placement in placements do
		counts[placement.AssetId] = (counts[placement.AssetId] or 0) + 1
	end

	return {
		Placements = placements,
		Signature = Checksum.Digest(state),
		AssetCount = #assets,
		Counts = counts,
		Rejected = rejected,
	}
end

function Stage.Clear()
	local root = TerrainStage.WorldRoot()
	local existing = root:FindFirstChild("Scatter")
	if existing then
		existing:Destroy()
	end
end

local function surfaceFrame(position: Vector3, normal: Vector3, yaw: number, align: boolean): CFrame
	if not align then
		return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	end
	local projected = Vector3.xAxis - normal * Vector3.xAxis:Dot(normal)
	if projected.Magnitude < 0.001 then
		projected = Vector3.zAxis - normal * Vector3.zAxis:Dot(normal)
	end
	local right = projected.Unit
	local back = right:Cross(normal).Unit
	return CFrame.fromMatrix(position, right, normal, back) * CFrame.Angles(0, yaw, 0)
end

--[[
	Materializes a plan. Objects are snapped to the BAKED terrain surface via
	raycast (the planned height comes from the heightfield, which sits a little
	below the voxel-smoothed surface) — the same fix the older engine needed.
]]
function Stage.Materialize(recipe: Recipe.Data, plan)
	local started = os.clock()
	plan = plan or Stage.Plan(recipe)
	Stage.Clear()

	local p = Recipe.Resolve(recipe)
	local align = p["scatter.alignToSlope"]

	local root = TerrainStage.WorldRoot()
	local folder = Instance.new("Folder")
	folder.Name = "Scatter"
	folder.Parent = root

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {Workspace.Terrain}

	local built = 0
	for _, placement in plan.Placements do
		local template = Library.Get(placement.AssetId)
		if template then
			local model = template:Clone()
			model.Name = string.format("%04d_%s", placement.Index, placement.AssetId)
			model:SetAttribute("PlacementIndex", placement.Index)
			model:SetAttribute("AssetId", placement.AssetId)
			model:SetAttribute("Zone", placement.Zone)
			model:SetAttribute("Scale", placement.Scale)
			model.LevelOfDetail = Enum.ModelLevelOfDetail.Automatic
			model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

			local lods = model:FindFirstChild("LODVariants")
			if lods then lods:Destroy() end

			model:ScaleTo(placement.Scale)

			local hit = Workspace:Raycast(
				Vector3.new(placement.X, placement.Y + 96, placement.Z),
				Vector3.new(0, -256, 0), params)
			local groundY = if hit then hit.Position.Y else placement.Y
			local sink = (template:GetAttribute("Sink") or 0.3) * placement.Scale

			model:PivotTo(surfaceFrame(
				Vector3.new(placement.X, groundY - sink, placement.Z),
				if hit then hit.Normal else placement.Normal,
				placement.Yaw, align))

			for _, descendant in model:GetDescendants() do
				if descendant:IsA("MeshPart") then
					descendant.Anchored = true
					descendant.CanTouch = false
					descendant.RenderFidelity = Enum.RenderFidelity.Automatic
				end
			end
			CollectionService:AddTag(model, PROP_TAG)
			model.Parent = folder
			built += 1
			if built % 120 == 0 then
				task.wait()
			end
		end
	end

	root:SetAttribute("ScatterSignature", plan.Signature)
	root:SetAttribute("ScatterCount", built)

	return {
		Built = built,
		Planned = #plan.Placements,
		Signature = plan.Signature,
		Counts = plan.Counts,
		Rejected = plan.Rejected,
		Seconds = os.clock() - started,
	}
end

return table.freeze(Stage)
