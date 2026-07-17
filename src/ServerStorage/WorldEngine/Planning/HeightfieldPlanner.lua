--!strict

local ServerStorage = game:GetService("ServerStorage")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Checksum = require(WorldEngine.Core.Checksum)
local Noise = require(WorldEngine.Core.DeterministicNoise)

export type WorldSpec = {
	Name: string,
	GeneratorVersion: string,
	WorldSeed: number,
	Resolution: number,
	WorldSize: number,
	ChunkSize: number,
	OriginX: number,
	OriginZ: number,
	MinY: number,
	MaxY: number,
	BaseHeight: number,
	MacroScale: number,
	MacroAmplitude: number,
	RidgeScale: number,
	RidgeAmplitude: number,
	DuneScale: number,
	DuneAmplitude: number,
	DetailScale: number,
	DetailAmplitude: number,
	TerrainMaterial: Enum.Material,
}

export type Heightfield = {
	Data: buffer,
	Width: number,
	Depth: number,
	OriginX: number,
	OriginZ: number,
	Resolution: number,
}

local Planner = {}

local function validateSpec(spec: WorldSpec)
	assert(spec.Resolution > 0, "Resolution must be positive")
	assert(spec.WorldSize > 0, "WorldSize must be positive")
	assert(spec.ChunkSize > 0, "ChunkSize must be positive")
	assert(spec.WorldSize % spec.ChunkSize == 0, "WorldSize must be divisible by ChunkSize")
	assert(spec.ChunkSize % spec.Resolution == 0, "ChunkSize must be divisible by Resolution")
	assert(spec.WorldSize % spec.Resolution == 0, "WorldSize must be divisible by Resolution")
	assert(spec.MaxY > spec.MinY, "MaxY must be greater than MinY")
	assert((spec.MaxY - spec.MinY) % spec.Resolution == 0, "Vertical range must align to Resolution")
end

function Planner.HeightAt(spec: WorldSpec, worldX: number, worldZ: number): number
	local seed = spec.WorldSeed

	local macro = Noise.Value2D(seed, worldX / spec.MacroScale, worldZ / spec.MacroScale, 1)
	local ridgeNoise = Noise.Value2D(seed, worldX / spec.RidgeScale, worldZ / spec.RidgeScale, 2)
	local ridge = (1 - math.abs(ridgeNoise)) * 0.5

	local warpedX = worldX + Noise.Value2D(seed, worldX / 180, worldZ / 180, 3) * 34
	local warpedZ = worldZ + Noise.Value2D(seed, worldX / 180, worldZ / 180, 4) * 34
	local dunes = Noise.Value2D(seed, warpedX / spec.DuneScale, warpedZ / spec.DuneScale, 5)
	local detail = Noise.Value2D(seed, worldX / spec.DetailScale, worldZ / spec.DetailScale, 6)

	local height = spec.BaseHeight
		+ macro * spec.MacroAmplitude
		+ ridge * spec.RidgeAmplitude
		+ dunes * spec.DuneAmplitude
		+ detail * spec.DetailAmplitude

	return math.clamp(height, spec.MinY + spec.Resolution, spec.MaxY - spec.Resolution)
end

local function allocate(width: number, depth: number): buffer
	return buffer.create(width * depth * 4)
end

local function writeHeight(field: Heightfield, x: number, z: number, height: number)
	local index = z * field.Width + x
	buffer.writef32(field.Data, index * 4, height)
end

function Planner.GetHeight(field: Heightfield, x: number, z: number): number
	assert(x >= 0 and x < field.Width, "Heightfield x is out of bounds")
	assert(z >= 0 and z < field.Depth, "Heightfield z is out of bounds")
	local index = z * field.Width + x
	return buffer.readf32(field.Data, index * 4)
end

function Planner.PlanWorld(spec: WorldSpec): Heightfield
	validateSpec(spec)

	local cells = spec.WorldSize / spec.Resolution
	local field: Heightfield = {
		Data = allocate(cells, cells),
		Width = cells,
		Depth = cells,
		OriginX = spec.OriginX,
		OriginZ = spec.OriginZ,
		Resolution = spec.Resolution,
	}

	for z = 0, cells - 1 do
		local worldZ = spec.OriginZ + (z + 0.5) * spec.Resolution
		for x = 0, cells - 1 do
			local worldX = spec.OriginX + (x + 0.5) * spec.Resolution
			writeHeight(field, x, z, Planner.HeightAt(spec, worldX, worldZ))
		end
	end

	return field
end

function Planner.PlanChunk(spec: WorldSpec, chunkX: number, chunkZ: number): Heightfield
	validateSpec(spec)

	local chunkCount = spec.WorldSize / spec.ChunkSize
	assert(chunkX >= 0 and chunkX < chunkCount, "chunkX is out of bounds")
	assert(chunkZ >= 0 and chunkZ < chunkCount, "chunkZ is out of bounds")

	local cells = spec.ChunkSize / spec.Resolution
	local originX = spec.OriginX + chunkX * spec.ChunkSize
	local originZ = spec.OriginZ + chunkZ * spec.ChunkSize
	local field: Heightfield = {
		Data = allocate(cells, cells),
		Width = cells,
		Depth = cells,
		OriginX = originX,
		OriginZ = originZ,
		Resolution = spec.Resolution,
	}

	for z = 0, cells - 1 do
		local worldZ = originZ + (z + 0.5) * spec.Resolution
		for x = 0, cells - 1 do
			local worldX = originX + (x + 0.5) * spec.Resolution
			writeHeight(field, x, z, Planner.HeightAt(spec, worldX, worldZ))
		end
	end

	return field
end

function Planner.Signature(spec: WorldSpec, field: Heightfield): string
	local state = Checksum.New()
	Checksum.UpdateString(state, spec.Name)
	Checksum.UpdateUInt32(state, spec.WorldSeed)
	Checksum.UpdateUInt32(state, field.Width)
	Checksum.UpdateUInt32(state, field.Depth)

	for z = 0, field.Depth - 1 do
		for x = 0, field.Width - 1 do
			local height = Planner.GetHeight(field, x, z)
			local index = z * field.Width + x
			local quantized = math.floor((height - spec.MinY) * 4096 + 0.5)
			Checksum.UpdateIndexedUInt32(state, index, quantized)
		end
	end

	return Checksum.Digest(state)
end

function Planner.GetChunkCount(spec: WorldSpec): number
	validateSpec(spec)
	return spec.WorldSize / spec.ChunkSize
end

return table.freeze(Planner)
