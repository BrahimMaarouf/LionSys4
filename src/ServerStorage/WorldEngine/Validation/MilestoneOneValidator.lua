--!strict

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Checksum = require(WorldEngine.Core.Checksum)
local Planner = require(WorldEngine.Planning.HeightfieldPlanner)

type WorldSpec = Planner.WorldSpec

local Validator = {}

local function chunkRegion(spec: WorldSpec, chunkX: number, chunkZ: number): Region3
	local minX = spec.OriginX + chunkX * spec.ChunkSize
	local minZ = spec.OriginZ + chunkZ * spec.ChunkSize
	return Region3.new(
		Vector3.new(minX, spec.MinY, minZ),
		Vector3.new(minX + spec.ChunkSize, spec.MaxY, minZ + spec.ChunkSize)
	)
end

function Validator.ValidatePlan(spec: WorldSpec)
	local world = Planner.PlanWorld(spec)
	local chunkCount = Planner.GetChunkCount(spec)
	local chunkCells = spec.ChunkSize / spec.Resolution
	local mismatchCount = 0
	local checkedCells = 0
	local minimumHeight = math.huge
	local maximumHeight = -math.huge

	for worldZ = 0, world.Depth - 1 do
		for worldX = 0, world.Width - 1 do
			local height = Planner.GetHeight(world, worldX, worldZ)
			minimumHeight = math.min(minimumHeight, height)
			maximumHeight = math.max(maximumHeight, height)
		end
	end

	for chunkZ = 0, chunkCount - 1 do
		for chunkX = 0, chunkCount - 1 do
			local chunk = Planner.PlanChunk(spec, chunkX, chunkZ)
			for localZ = 0, chunkCells - 1 do
				for localX = 0, chunkCells - 1 do
					local worldX = chunkX * chunkCells + localX
					local worldZ = chunkZ * chunkCells + localZ
					local worldHeight = Planner.GetHeight(world, worldX, worldZ)
					local chunkHeight = Planner.GetHeight(chunk, localX, localZ)
					checkedCells += 1
					if worldHeight ~= chunkHeight then
						mismatchCount += 1
					end
				end
			end
		end
	end

	local signature = Planner.Signature(spec, world)
	local passed = mismatchCount == 0
		and minimumHeight >= spec.MinY
		and maximumHeight <= spec.MaxY
		and checkedCells == world.Width * world.Depth

	return {
		Passed = passed,
		PlanSignature = signature,
		CheckedCells = checkedCells,
		ChunkMismatchCount = mismatchCount,
		MinimumHeight = minimumHeight,
		MaximumHeight = maximumHeight,
		ChunkCount = chunkCount * chunkCount,
	}
end

local function capture(spec: WorldSpec, onlyChunkX: number?, onlyChunkZ: number?)
	local state = Checksum.New()
	local filledCells = 0
	local totalCells = 0
	local chunkCount = Planner.GetChunkCount(spec)
	local chunkCells = spec.ChunkSize / spec.Resolution
	local worldCells = spec.WorldSize / spec.Resolution

	Checksum.UpdateString(state, spec.Name)
	Checksum.UpdateString(state, spec.GeneratorVersion)
	Checksum.UpdateUInt32(state, spec.WorldSeed)
	Checksum.UpdateUInt32(state, worldCells)
	Checksum.UpdateUInt32(state, (spec.MaxY - spec.MinY) / spec.Resolution)

	for chunkZ = 0, chunkCount - 1 do
		for chunkX = 0, chunkCount - 1 do
			if onlyChunkX == nil or (chunkX == onlyChunkX and chunkZ == onlyChunkZ) then
				local materials, occupancies = Workspace.Terrain:ReadVoxels(
					chunkRegion(spec, chunkX, chunkZ),
					spec.Resolution
				)
				for x = 1, #materials do
					for y = 1, #materials[x] do
						for z = 1, #materials[x][y] do
							local material = materials[x][y][z]
							local occupancy = occupancies[x][y][z]
							local quantizedOccupancy = math.floor(occupancy * 65535 + 0.5)
							local globalX = chunkX * chunkCells + (x - 1)
							local globalY = y - 1
							local globalZ = chunkZ * chunkCells + (z - 1)
							local globalIndex = (globalY * worldCells + globalZ) * worldCells + globalX

							Checksum.UpdateUInt32(state, globalIndex)
							Checksum.UpdateUInt32(state, material.Value)
							Checksum.UpdateUInt32(state, quantizedOccupancy)
							totalCells += 1
							if occupancy > 0 then
								filledCells += 1
							end
						end
					end
				end
			end
		end
	end

	return {
		Signature = Checksum.Digest(state),
		FilledCells = filledCells,
		TotalCells = totalCells,
	}
end

function Validator.CaptureTerrain(spec: WorldSpec)
	return capture(spec, nil, nil)
end

function Validator.CaptureChunk(spec: WorldSpec, chunkX: number, chunkZ: number)
	local chunkCount = Planner.GetChunkCount(spec)
	assert(chunkX >= 0 and chunkX < chunkCount, "chunkX is out of bounds")
	assert(chunkZ >= 0 and chunkZ < chunkCount, "chunkZ is out of bounds")
	return capture(spec, chunkX, chunkZ)
end

return table.freeze(Validator)
