--!strict

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Planner = require(WorldEngine.Planning.HeightfieldPlanner)

type WorldSpec = Planner.WorldSpec
type Heightfield = Planner.Heightfield

local Materializer = {}

local function makeChunkOrder(chunkCount: number, orderName: string): {{X: number, Z: number}}
	local result = {}
	for z = 0, chunkCount - 1 do
		for x = 0, chunkCount - 1 do
			table.insert(result, {X = x, Z = z})
		end
	end

	if orderName == "Reverse" then
		local left = 1
		local right = #result
		while left < right do
			result[left], result[right] = result[right], result[left]
			left += 1
			right -= 1
		end
	else
		assert(orderName == "Forward", "Unknown chunk order: " .. orderName)
	end

	return result
end

local function buildVoxelArrays(spec: WorldSpec, field: Heightfield)
	local horizontalCells = field.Width
	local verticalCells = (spec.MaxY - spec.MinY) / spec.Resolution
	local materials = table.create(horizontalCells)
	local occupancies = table.create(horizontalCells)

	for x = 1, horizontalCells do
		materials[x] = table.create(verticalCells)
		occupancies[x] = table.create(verticalCells)
		for y = 1, verticalCells do
			materials[x][y] = table.create(horizontalCells)
			occupancies[x][y] = table.create(horizontalCells)
			local cellBottom = spec.MinY + (y - 1) * spec.Resolution
			for z = 1, horizontalCells do
				local height = Planner.GetHeight(field, x - 1, z - 1)
				local occupancy = math.clamp((height - cellBottom) / spec.Resolution, 0, 1)
				occupancies[x][y][z] = occupancy
				materials[x][y][z] = if occupancy > 0 then spec.TerrainMaterial else Enum.Material.Air
			end
		end
	end

	return materials, occupancies
end

function Materializer.Clear(spec: WorldSpec)
	local centerX = spec.OriginX + spec.WorldSize / 2
	local centerY = spec.MinY + (spec.MaxY - spec.MinY) / 2
	local centerZ = spec.OriginZ + spec.WorldSize / 2
	Workspace.Terrain:FillBlock(
		CFrame.new(centerX, centerY, centerZ),
		Vector3.new(spec.WorldSize, spec.MaxY - spec.MinY, spec.WorldSize),
		Enum.Material.Air
	)
end

function Materializer.MaterializeChunk(spec: WorldSpec, chunkX: number, chunkZ: number)
	local field = Planner.PlanChunk(spec, chunkX, chunkZ)
	local materials, occupancies = buildVoxelArrays(spec, field)
	local minX = spec.OriginX + chunkX * spec.ChunkSize
	local minZ = spec.OriginZ + chunkZ * spec.ChunkSize
	local region = Region3.new(
		Vector3.new(minX, spec.MinY, minZ),
		Vector3.new(minX + spec.ChunkSize, spec.MaxY, minZ + spec.ChunkSize)
	)
	Workspace.Terrain:WriteVoxels(region, spec.Resolution, materials, occupancies)
end

function Materializer.Materialize(spec: WorldSpec, orderName: string)
	Materializer.Clear(spec)
	local worldPlan = Planner.PlanWorld(spec)
	local planSignature = Planner.Signature(spec, worldPlan)
	local chunkCount = Planner.GetChunkCount(spec)
	local chunkOrder = makeChunkOrder(chunkCount, orderName)
	for _, coordinate in chunkOrder do
		Materializer.MaterializeChunk(spec, coordinate.X, coordinate.Z)
	end

	local worldRoot = Workspace:FindFirstChild("WorldRoot")
	if worldRoot then
		worldRoot:SetAttribute("GeneratorVersion", spec.GeneratorVersion)
		worldRoot:SetAttribute("WorldSeed", spec.WorldSeed)
		worldRoot:SetAttribute("WorldSpec", spec.Name)
		worldRoot:SetAttribute("PlanSignature", planSignature)
		worldRoot:SetAttribute("LastChunkOrder", orderName)
	end

	return {
		ChunkCount = #chunkOrder,
		PlanSignature = planSignature,
		Order = orderName,
	}
end

return table.freeze(Materializer)
