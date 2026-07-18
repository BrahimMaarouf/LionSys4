--!strict

-- Milestone 9 world-edge presentation. The finite 512-stud slab previously
-- ended in a bare vertical cliff. This materializer surrounds it with a
-- deterministic dune skirt: a ring of terrain whose height continues the edge
-- profile and falls away smoothly, so the horizon reads as endless desert.
-- The skirt lives entirely OUTSIDE the M1 golden capture region, so M1
-- signatures are untouched. An invisible boundary wall keeps players inside
-- the authored world.
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Checksum = require(WorldEngine.Core.Checksum)
local HeightfieldPlanner = require(WorldEngine.Planning.HeightfieldPlanner)

type WorldSpec = HeightfieldPlanner.WorldSpec

local SKIRT_WIDTH = 128
local RESOLUTION = 4
local FLOOR_DROP = 14 -- outer rim ends this far below the lowest edge height
local WALL_HEIGHT = 60
local WALL_TAG = "WorldEngineBoundaryWall"
local VERSION = "9.0.0-m9-world-hardening"

local Materializer = {}

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Height for a skirt cell: continue the clamped edge height inward, ease down
-- to a low outer rim. Deterministic pure function of the heightfield.
local function skirtHeight(spec: WorldSpec, x: number, z: number): number
	local clampedX = math.clamp(x, spec.OriginX, spec.OriginX + spec.WorldSize)
	local clampedZ = math.clamp(z, spec.OriginZ, spec.OriginZ + spec.WorldSize)
	local edgeHeight = HeightfieldPlanner.HeightAt(spec, clampedX, clampedZ)
	local dx = math.max(0, math.max(spec.OriginX - x, x - (spec.OriginX + spec.WorldSize)))
	local dz = math.max(0, math.max(spec.OriginZ - z, z - (spec.OriginZ + spec.WorldSize)))
	local distance = math.sqrt(dx * dx + dz * dz)
	local fade = smoothstep(distance / SKIRT_WIDTH)
	return edgeHeight * (1 - fade) + (edgeHeight - FLOOR_DROP) * fade
end

function Materializer.SkirtSignature(spec: WorldSpec): string
	local state = Checksum.New()
	Checksum.UpdateString(state, "M9WorldEdgeSkirt")
	Checksum.UpdateUInt32(state, spec.WorldSeed)
	local index = 0
	local outerMin = -SKIRT_WIDTH
	local outerMax = spec.WorldSize + SKIRT_WIDTH
	for x = outerMin, outerMax, RESOLUTION * 4 do
		for z = outerMin, outerMax, RESOLUTION * 4 do
			local wx, wz = spec.OriginX + x, spec.OriginZ + z
			local inside = x >= 0 and x <= spec.WorldSize and z >= 0 and z <= spec.WorldSize
			if not inside then
				index += 1
				Checksum.UpdateIndexedUInt32(state, index,
					math.floor(skirtHeight(spec, wx, wz) * 1024 + 0.5))
			end
		end
	end
	return Checksum.Digest(state)
end

function Materializer.Clear(spec: WorldSpec)
	local terrain = Workspace.Terrain
	local outerMin = -SKIRT_WIDTH
	local size = spec.WorldSize
	-- clear the four ring rectangles (not the play region)
	local rects = {
		{outerMin, -SKIRT_WIDTH, size + SKIRT_WIDTH, 0},           -- south strip
		{outerMin, size, size + SKIRT_WIDTH, size + SKIRT_WIDTH},  -- north strip
		{-SKIRT_WIDTH, 0, 0, size},                                 -- west strip
		{size, 0, size + SKIRT_WIDTH, size},                        -- east strip
	}
	for _, r in rects do
		local region = Region3.new(
			Vector3.new(spec.OriginX + r[1], -64, spec.OriginZ + r[2]),
			Vector3.new(spec.OriginX + r[3], 64, spec.OriginZ + r[4])
		):ExpandToGrid(RESOLUTION)
		terrain:FillRegion(region, RESOLUTION, Enum.Material.Air)
	end
	local walls = Workspace.WorldRoot:FindFirstChild("BoundaryWalls")
	if walls then
		walls:Destroy()
	end
end

function Materializer.Materialize(spec: WorldSpec)
	Materializer.Clear(spec)
	local terrain = Workspace.Terrain

	-- fill skirt columns (8-stud columns at 4-stud voxel resolution keeps the
	-- FillRegion count low enough for interactive regeneration)
	local step = RESOLUTION * 2
	local outerMin = -SKIRT_WIDTH
	local outerMax = spec.WorldSize + SKIRT_WIDTH
	for x = outerMin, outerMax - step, step do
		for z = outerMin, outerMax - step, step do
			local inside = x >= 0 and x < spec.WorldSize and z >= 0 and z < spec.WorldSize
			if not inside then
				local wx = spec.OriginX + x + step / 2
				local wz = spec.OriginZ + z + step / 2
				local height = skirtHeight(spec, wx, wz)
				if height > -40 then
					local region = Region3.new(
						Vector3.new(spec.OriginX + x, -60, spec.OriginZ + z),
						Vector3.new(spec.OriginX + x + step, math.max(-56, height), spec.OriginZ + z + step)
					):ExpandToGrid(RESOLUTION)
					terrain:FillRegion(region, RESOLUTION, Enum.Material.Sand)
				end
			end
		end
	end

	-- invisible boundary walls at the play-region edge
	local walls = Instance.new("Folder")
	walls.Name = "BoundaryWalls"
	walls.Parent = Workspace.WorldRoot
	local size = spec.WorldSize
	local cx = spec.OriginX + size / 2
	local cz = spec.OriginZ + size / 2
	local definitions = {
		{Vector3.new(cx, WALL_HEIGHT / 2, spec.OriginZ), Vector3.new(size, WALL_HEIGHT, 2)},
		{Vector3.new(cx, WALL_HEIGHT / 2, spec.OriginZ + size), Vector3.new(size, WALL_HEIGHT, 2)},
		{Vector3.new(spec.OriginX, WALL_HEIGHT / 2, cz), Vector3.new(2, WALL_HEIGHT, size)},
		{Vector3.new(spec.OriginX + size, WALL_HEIGHT / 2, cz), Vector3.new(2, WALL_HEIGHT, size)},
	}
	for index, def in definitions do
		local wall = Instance.new("Part")
		wall.Name = "BoundaryWall" .. index
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanCollide = true
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
		wall:SetAttribute("WorldEngineBoundaryWall", WALL_TAG)
		wall.Position = def[1]
		wall.Size = def[2]
		wall.Parent = walls
	end

	local root = Workspace.WorldRoot
	root:SetAttribute("WorldEdgeVersion", VERSION)
	root:SetAttribute("WorldEdgeSkirtWidth", SKIRT_WIDTH)
	root:SetAttribute("WorldEdgeSignature", Materializer.SkirtSignature(spec))
	return walls
end

Materializer.Version = VERSION
Materializer.SkirtWidth = SKIRT_WIDTH

return table.freeze(Materializer)
