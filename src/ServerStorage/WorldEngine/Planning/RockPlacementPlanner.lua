--!strict

local ServerStorage = game:GetService("ServerStorage")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Catalog = require(WorldEngine.Assets.Rocks.RockCatalog)
local Checksum = require(WorldEngine.Core.Checksum)
local Noise = require(WorldEngine.Core.DeterministicNoise)
local Hash32 = require(WorldEngine.Core.Hash32)
local HeightfieldPlanner = require(WorldEngine.Planning.HeightfieldPlanner)

type WorldSpec = HeightfieldPlanner.WorldSpec
type DesertAsset = Catalog.DesertAsset

export type Placement = {
	Index: number,
	AssetId: string,
	AssetIndex: number,
	WorldX: number,
	GroundY: number,
	WorldZ: number,
	Normal: Vector3,
	YawRadians: number,
	Scale: number,
	SlopeDegrees: number,
	SpacingRadius: number,
}

export type Plan = {
	Placements: {Placement},
	Signature: string,
	CandidateCount: number,
	RejectedByDensity: number,
	RejectedBySpawn: number,
	RejectedBySlope: number,
	RejectedBySpacing: number,
}

local CELL_SIZE = 30
local EDGE_MARGIN = 24
local CLUSTER_FLOOR = 0.42
local CLUSTER_RANGE = 0.50
local SPAWN_SAFE_RADIUS = 52
local CHANNEL = 0x524F434B

local Planner = {}

local function unit(hash: number): number
	return (Hash32.ToSignedUnit(hash) + 1) * 0.5
end

local function hashUnit(seed: number, cellX: number, cellZ: number, property: number): number
	return unit(Hash32.HashIntegers(seed, cellX, cellZ, CHANNEL, property))
end

local function chooseAsset(value: number): (DesertAsset, number)
	local cumulative = 0
	for index, asset in Catalog.Assets do
		cumulative += asset.Weight
		if value <= cumulative then
			return asset, index
		end
	end
	return Catalog.Assets[#Catalog.Assets], #Catalog.Assets
end

local function sampleSurface(spec: WorldSpec, worldX: number, worldZ: number): (number, Vector3, number)
	local step = spec.Resolution * 2
	local left = HeightfieldPlanner.HeightAt(spec, worldX - step, worldZ)
	local right = HeightfieldPlanner.HeightAt(spec, worldX + step, worldZ)
	local back = HeightfieldPlanner.HeightAt(spec, worldX, worldZ - step)
	local front = HeightfieldPlanner.HeightAt(spec, worldX, worldZ + step)
	local center = HeightfieldPlanner.HeightAt(spec, worldX, worldZ)
	local dx = (right - left) / (step * 2)
	local dz = (front - back) / (step * 2)
	local normal = Vector3.new(-dx, 1, -dz).Unit
	local slopeDegrees = math.deg(math.atan(math.sqrt(dx * dx + dz * dz)))
	-- WriteVoxels represents a partially occupied top cell around its center.
	-- The rendered/collision surface is therefore half a voxel above the raw
	-- heightfield sample. Keep that conversion in data so placement never needs
	-- a streaming- or engine-state-dependent raycast.
	local deterministicSurfaceY = center + spec.Resolution * 0.5
	return deterministicSurfaceY, normal, slopeDegrees
end

local function overlaps(accepted: {Placement}, worldX: number, worldZ: number, radius: number): boolean
	for _, placement in accepted do
		local dx = placement.WorldX - worldX
		local dz = placement.WorldZ - worldZ
		local minimum = placement.SpacingRadius + radius
		if dx * dx + dz * dz < minimum * minimum then
			return true
		end
	end
	return false
end

local function signature(spec: WorldSpec, placements: {Placement}): string
	local state = Checksum.New()
	Checksum.UpdateString(state, Catalog.Version)
	Checksum.UpdateUInt32(state, spec.WorldSeed)
	Checksum.UpdateUInt32(state, #placements)
	for index, placement in placements do
		Checksum.UpdateUInt32(state, index)
		Checksum.UpdateUInt32(state, placement.AssetIndex)
		Checksum.UpdateUInt32(state, math.floor(placement.WorldX * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(placement.GroundY * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(placement.WorldZ * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(placement.YawRadians * 65536 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(placement.Scale * 65536 + 0.5))
	end
	return Checksum.Digest(state)
end

function Planner.Plan(spec: WorldSpec): Plan
	local placements: {Placement} = {}
	local available = spec.WorldSize - EDGE_MARGIN * 2
	local cellsPerAxis = math.floor(available / CELL_SIZE)
	local candidateCount = 0
	local rejectedByDensity = 0
	local rejectedBySpawn = 0
	local rejectedBySlope = 0
	local rejectedBySpacing = 0

	for cellZ = 0, cellsPerAxis - 1 do
		for cellX = 0, cellsPerAxis - 1 do
			candidateCount += 1
			local jitterRange = CELL_SIZE * 0.28
			local worldX = spec.OriginX + EDGE_MARGIN + (cellX + 0.5) * CELL_SIZE
				+ (hashUnit(spec.WorldSeed, cellX, cellZ, 2) * 2 - 1) * jitterRange
			local worldZ = spec.OriginZ + EDGE_MARGIN + (cellZ + 0.5) * CELL_SIZE
				+ (hashUnit(spec.WorldSeed, cellX, cellZ, 3) * 2 - 1) * jitterRange
			local patch = Noise.Value2D(spec.WorldSeed, worldX / 118, worldZ / 118, 0x50524F50)
			local cluster = math.clamp((patch + 1) * 0.5, 0, 1)
			local clusterStrength = math.clamp((cluster - CLUSTER_FLOOR) / CLUSTER_RANGE, 0, 1)
			local localDensity = math.pow(clusterStrength, 1.6) * 0.92
			if hashUnit(spec.WorldSeed, cellX, cellZ, 1) > localDensity then
				rejectedByDensity += 1
				continue
			end

			if worldX * worldX + worldZ * worldZ < SPAWN_SAFE_RADIUS * SPAWN_SAFE_RADIUS then
				rejectedBySpawn += 1
				continue
			end

			local asset, assetIndex = chooseAsset(hashUnit(spec.WorldSeed, cellX, cellZ, 4))
			local scale = asset.ScaleMin
				+ (asset.ScaleMax - asset.ScaleMin) * hashUnit(spec.WorldSeed, cellX, cellZ, 5)
			local groundY, normal, slopeDegrees = sampleSurface(spec, worldX, worldZ)
			if slopeDegrees > asset.MaxSlopeDegrees then
				rejectedBySlope += 1
				continue
			end

			local spacingRadius = asset.SpacingRadius * scale
			if overlaps(placements, worldX, worldZ, spacingRadius) then
				rejectedBySpacing += 1
				continue
			end

			table.insert(placements, {
				Index = #placements + 1,
				AssetId = asset.Id,
				AssetIndex = assetIndex,
				WorldX = worldX,
				GroundY = groundY,
				WorldZ = worldZ,
				Normal = normal,
				YawRadians = hashUnit(spec.WorldSeed, cellX, cellZ, 6) * math.pi * 2,
				Scale = scale,
				SlopeDegrees = slopeDegrees,
				SpacingRadius = spacingRadius,
			})
		end
	end

	return {
		Placements = placements,
		Signature = signature(spec, placements),
		CandidateCount = candidateCount,
		RejectedByDensity = rejectedByDensity,
		RejectedBySpawn = rejectedBySpawn,
		RejectedBySlope = rejectedBySlope,
		RejectedBySpacing = rejectedBySpacing,
	}
end

return table.freeze(Planner)
