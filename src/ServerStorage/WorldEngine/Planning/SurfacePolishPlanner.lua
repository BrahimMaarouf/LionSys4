--!strict

local ServerStorage = game:GetService("ServerStorage")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Checksum = require(WorldEngine.Core.Checksum)
local Hash32 = require(WorldEngine.Core.Hash32)
local Noise = require(WorldEngine.Core.DeterministicNoise)
local Config = require(WorldEngine.Config.Polish.DesertSurfacePolish)
local HeightfieldPlanner = require(WorldEngine.Planning.HeightfieldPlanner)
local CompositionPlanner = require(WorldEngine.Planning.WorldCompositionPlanner)

type WorldSpec = HeightfieldPlanner.WorldSpec
type CompositionPlan = CompositionPlanner.Plan

export type Detail = {
	Index: number,
	Kind: string,
	RegionId: string,
	WorldX: number,
	GroundY: number,
	WorldZ: number,
	Normal: Vector3,
	SlopeDegrees: number,
	YawRadians: number,
	Width: number,
	Height: number,
	Depth: number,
}

export type Plan = {
	Version: string,
	WorldSeed: number,
	Composition: CompositionPlan,
	Width: number,
	Depth: number,
	MaterialCodes: buffer,
	RegionCodes: buffer,
	MaterialCounts: {[string]: number},
	RegionMaterialCounts: {[string]: {[string]: number}},
	RegionCellCounts: {[string]: number},
	RouteSurfaceCellCount: number,
	Details: {Detail},
	DetailCounts: {[string]: number},
	RegionDetailCounts: {[string]: number},
	RejectedDetailCandidates: number,
	Signature: string,
}

local CHANNEL = 0x4D36504F
local Planner = {}

local MATERIAL_BY_CODE = Config.Materials
local CODE_BY_VALUE: {[number]: number} = {}
for code, material in MATERIAL_BY_CODE do CODE_BY_VALUE[material.Value] = code end

local function unit(seed: number, a: number, b: number, property: number): number
	return (Hash32.ToSignedUnit(Hash32.HashIntegers(seed, a, b, CHANNEL, property)) + 1) * 0.5
end

local function sampleSurface(spec: WorldSpec, worldX: number, worldZ: number)
	local step = spec.Resolution * 2
	local left = HeightfieldPlanner.HeightAt(spec, worldX - step, worldZ)
	local right = HeightfieldPlanner.HeightAt(spec, worldX + step, worldZ)
	local back = HeightfieldPlanner.HeightAt(spec, worldX, worldZ - step)
	local front = HeightfieldPlanner.HeightAt(spec, worldX, worldZ + step)
	local center = HeightfieldPlanner.HeightAt(spec, worldX, worldZ)
	local dx = (right - left) / (step * 2)
	local dz = (front - back) / (step * 2)
	return {
		WorldX = worldX, GroundY = center + spec.Resolution * 0.5, WorldZ = worldZ,
		Normal = Vector3.new(-dx, 1, -dz).Unit,
		SlopeDegrees = math.deg(math.atan(math.sqrt(dx * dx + dz * dz))),
	}
end

local function regionAt(composition: CompositionPlan, worldX: number, worldZ: number)
	local best = composition.Regions[1]
	local bestScore = math.huge
	for _, region in composition.Regions do
		local distance = math.sqrt((worldX - region.AnchorX) ^ 2 + (worldZ - region.AnchorZ) ^ 2)
		local score = distance / region.InfluenceRadius + region.Bias
		if score < bestScore then best, bestScore = region, score end
	end
	return best
end

local function routeDistanceSquared(composition: CompositionPlan, worldX: number, worldZ: number): number
	local best = math.huge
	for _, route in composition.Routes do
		best = math.min(best, CompositionPlanner.DistanceToRouteSquared(route, worldX, worldZ))
	end
	return best
end

local function classifyMaterial(spec: WorldSpec, composition: CompositionPlan, regionId: string, worldX: number, worldZ: number, slope: number): (Enum.Material, boolean)
	local routeSurface = routeDistanceSquared(composition, worldX, worldZ) <= Config.RouteSurfaceRadius ^ 2
	local broad = Noise.Value2D(spec.WorldSeed, worldX / 58, worldZ / 58, 61)
	local fine = Noise.Value2D(spec.WorldSeed, worldX / 21, worldZ / 21, 62)
	if routeSurface then
		return if regionId == "WadiGardens" then Enum.Material.Ground else Enum.Material.Sandstone, true
	elseif regionId == "ErgDunes" then
		return if slope > 16 or broad > 0.72 then Enum.Material.Sandstone else Enum.Material.Sand, false
	elseif regionId == "WadiGardens" then
		if slope < 7 and fine < -0.48 then return Enum.Material.Mud, false end
		return if broad < 0.58 then Enum.Material.Ground else Enum.Material.Sand, false
	elseif regionId == "HamadaShelf" then
		if slope > 12 or broad > -0.08 then return Enum.Material.Rock, false end
		return if fine < 0.68 then Enum.Material.Sandstone else Enum.Material.Sand, false
	else
		if slope > 14 or fine > 0.48 then return Enum.Material.Rock, false end
		return if broad > -0.38 then Enum.Material.Sandstone else Enum.Material.Sand, false
	end
end

local function insideDetailBounds(spec: WorldSpec, worldX: number, worldZ: number): boolean
	local margin = Config.DetailWorldMargin
	return worldX >= spec.OriginX + margin and worldZ >= spec.OriginZ + margin
		and worldX <= spec.OriginX + spec.WorldSize - margin
		and worldZ <= spec.OriginZ + spec.WorldSize - margin
end

local function detailOverlaps(details: {Detail}, worldX: number, worldZ: number): boolean
	for _, detail in details do
		if (detail.WorldX - worldX) ^ 2 + (detail.WorldZ - worldZ) ^ 2 < Config.DetailMinimumSpacing ^ 2 then return true end
	end
	return false
end

local function planDetails(spec: WorldSpec, composition: CompositionPlan): ({Detail}, {[string]: number}, {[string]: number}, number)
	local details: {Detail} = {}
	local kindCounts: {[string]: number} = {}
	local regionCounts: {[string]: number} = {}
	local rejected = 0
	for regionIndex, region in composition.Regions do
		local targets = Config.RegionDetails[region.Id]
		for kindIndex, kind in Config.DetailOrder do
			local target = targets[kind] or 0
			local accepted = 0
			local attempt = 0
			while accepted < target and attempt < target * 18 do
				attempt += 1
				local angle = unit(spec.WorldSeed, regionIndex * 17 + kindIndex, attempt, 71) * math.pi * 2
				local radius = 30 + math.sqrt(unit(spec.WorldSeed, regionIndex * 17 + kindIndex, attempt, 72)) * region.InfluenceRadius * 0.70
				local worldX = region.AnchorX + math.cos(angle) * radius
				local worldZ = region.AnchorZ + math.sin(angle) * radius
				local valid = insideDetailBounds(spec, worldX, worldZ)
					and worldX ^ 2 + worldZ ^ 2 >= Config.DetailSpawnRadius ^ 2
					and regionAt(composition, worldX, worldZ).Id == region.Id
					and routeDistanceSquared(composition, worldX, worldZ) >= Config.DetailRouteClearance ^ 2
					and not detailOverlaps(details, worldX, worldZ)
				local surface = if valid then sampleSurface(spec, worldX, worldZ) else nil
				if surface and surface.SlopeDegrees <= Config.DetailMaximumSlope then
					local style = Config.DetailStyle[kind]
					local scale = 0.82 + unit(spec.WorldSeed, regionIndex * 17 + kindIndex, attempt, 73) * 0.42
					accepted += 1
					table.insert(details, {
						Index = 0, Kind = kind, RegionId = region.Id,
						WorldX = worldX, GroundY = surface.GroundY, WorldZ = worldZ,
						Normal = surface.Normal, SlopeDegrees = surface.SlopeDegrees,
						YawRadians = angle + unit(spec.WorldSeed, regionIndex, attempt, 74) * math.pi,
						Width = style.Width * scale, Height = style.Height * scale, Depth = style.Depth * scale,
					})
				else
					rejected += 1
				end
			end
		end
	end
	for index, detail in details do
		detail.Index = index
		kindCounts[detail.Kind] = (kindCounts[detail.Kind] or 0) + 1
		regionCounts[detail.RegionId] = (regionCounts[detail.RegionId] or 0) + 1
	end
	return details, kindCounts, regionCounts, rejected
end

local function planSignature(plan: Plan): string
	local state = Checksum.New()
	Checksum.UpdateString(state, plan.Version)
	Checksum.UpdateUInt32(state, plan.WorldSeed)
	Checksum.UpdateString(state, plan.Composition.Signature)
	for index = 0, plan.Width * plan.Depth - 1 do
		Checksum.UpdateIndexedUInt32(state, index, buffer.readu8(plan.MaterialCodes, index))
		Checksum.UpdateUInt32(state, buffer.readu8(plan.RegionCodes, index))
	end
	for index, detail in plan.Details do
		Checksum.UpdateIndexedUInt32(state, index, math.floor(detail.WorldX * 1024 + 0.5))
		Checksum.UpdateString(state, detail.Kind)
		Checksum.UpdateString(state, detail.RegionId)
		Checksum.UpdateUInt32(state, math.floor(detail.GroundY * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(detail.WorldZ * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(detail.YawRadians * 65536 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(detail.Width * 4096 + 0.5))
	end
	return Checksum.Digest(state)
end

function Planner.MaterialForCode(code: number): Enum.Material
	local material = MATERIAL_BY_CODE[code]
	assert(material, "Unknown M6 material code")
	return material
end

function Planner.CodeForMaterial(material: Enum.Material): number
	local code = CODE_BY_VALUE[material.Value]
	assert(code, "Material is not in the M6 palette")
	return code
end

function Planner.Plan(spec: WorldSpec): Plan
	local composition = CompositionPlanner.Plan(spec)
	local width = spec.WorldSize / spec.Resolution
	local depth = width
	local materialCodes = buffer.create(width * depth)
	local regionCodes = buffer.create(width * depth)
	local materialCounts: {[string]: number} = {}
	local regionMaterialCounts: {[string]: {[string]: number}} = {}
	local regionCellCounts: {[string]: number} = {}
	local routeCells = 0
	local regionIndexById: {[string]: number} = {}
	for index, region in composition.Regions do regionIndexById[region.Id] = index end
	for z = 0, depth - 1 do
		local worldZ = spec.OriginZ + (z + 0.5) * spec.Resolution
		for x = 0, width - 1 do
			local worldX = spec.OriginX + (x + 0.5) * spec.Resolution
			local region = regionAt(composition, worldX, worldZ)
			local surface = sampleSurface(spec, worldX, worldZ)
			local material, routeSurface = classifyMaterial(spec, composition, region.Id, worldX, worldZ, surface.SlopeDegrees)
			local code = Planner.CodeForMaterial(material)
			local index = z * width + x
			buffer.writeu8(materialCodes, index, code)
			buffer.writeu8(regionCodes, index, regionIndexById[region.Id])
			local name = material.Name
			materialCounts[name] = (materialCounts[name] or 0) + 1
			local regionCounts = regionMaterialCounts[region.Id] or {}
			regionCounts[name] = (regionCounts[name] or 0) + 1
			regionMaterialCounts[region.Id] = regionCounts
			regionCellCounts[region.Id] = (regionCellCounts[region.Id] or 0) + 1
			if routeSurface then routeCells += 1 end
		end
	end
	local details, detailCounts, regionDetailCounts, rejected = planDetails(spec, composition)
	assert(#details <= Config.MaximumDetails, "Surface polish exceeded detail budget")
	local plan: Plan = {
		Version = Config.Version, WorldSeed = spec.WorldSeed, Composition = composition,
		Width = width, Depth = depth, MaterialCodes = materialCodes, RegionCodes = regionCodes,
		MaterialCounts = materialCounts, RegionMaterialCounts = regionMaterialCounts,
		RegionCellCounts = regionCellCounts, RouteSurfaceCellCount = routeCells,
		Details = details, DetailCounts = detailCounts, RegionDetailCounts = regionDetailCounts,
		RejectedDetailCandidates = rejected, Signature = "",
	}
	plan.Signature = planSignature(plan)
	return plan
end

return table.freeze(Planner)
