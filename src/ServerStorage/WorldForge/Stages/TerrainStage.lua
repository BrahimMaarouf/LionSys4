--!strict

-- WorldForge Stage 1: Terrain.
--
-- A themeless heightfield. Every landform control from the schema feeds one
-- pure function of (x, z) — so the same recipe always produces the same land,
-- and nothing here knows what a desert, a mountain or a beach is.
--
-- Height composition, in order:
--   continent   large-scale mass, decides where high ground lives
--   hills       mid-scale rolling shape
--   ridged      sharp ridgelines (blended in by the "ridges" control)
--   detail      fine roughness
--   valleys     carves channels along a separate noise field
--   plateau     flattens the top of high ground into mesas
--
-- Domain warp displaces the sample point before all of the above, which is
-- what stops the result looking like plain noise.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldForge = script.Parent.Parent
local Checksum = require(WorldForge.Core.Checksum)
local Noise = require(WorldForge.Core.Noise)
local Recipe = require(WorldForge.Core.Recipe)

local Stage = {}

-- Roblox supports exactly one terrain voxel resolution.
local VOXEL_SIZE = 4
Stage.VoxelSize = VOXEL_SIZE

export type Field = {
	Seed: number,
	Size: number,
	Resolution: number,
	Origin: number,
	HeightAt: (number, number) -> number,
	MinHeight: number,
	MaxHeight: number,
	WaterLevel: number,
}

local CH_CONTINENT = 0x574F524C
local CH_HILL = 0x48494C4C
local CH_RIDGE = 0x52494447
local CH_DETAIL = 0x44455441
local CH_VALLEY = 0x56414C4C
local CH_WARP_X = 0x57415058
local CH_WARP_Z = 0x5741505A

local function fbm(seed: number, x: number, z: number, channel: number, octaves: number): number
	local total, amplitude, norm, frequency = 0, 1, 0, 1
	for octave = 1, octaves do
		total += Noise.Value2D(seed, x * frequency, z * frequency, channel + octave) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2
	end
	return total / norm
end

--[[
	Builds the height function for a recipe. Pure data in, pure function out —
	no instances touched, so this is safe to call for previews.
]]
function Stage.BuildField(recipe: Recipe.Data): Field
	local p = Recipe.Resolve(recipe)
	local seed = Recipe.GetSeed(recipe, "terrain")

	-- Roblox terrain voxels are a fixed 4-stud grid and WriteVoxels rejects any
	-- other resolution. Every coordinate we hand to it must land exactly on
	-- that grid, so the world size is snapped to a multiple of 2 voxels: that
	-- keeps the centred origin (-size/2) on a voxel boundary for ANY size the
	-- user types. Without this, an odd size shifts every tile off-grid and
	-- Roblox silently expands the region, producing the classic
	-- "17x17x17 array expected" mismatch.
	local resolution = VOXEL_SIZE
	local size = math.max(resolution * 2,
		math.floor(p["terrain.size"] / (resolution * 2) + 0.5) * (resolution * 2))
	local baseHeight = p["terrain.baseHeight"]
	local amplitude = p["terrain.amplitude"]
	local featureScale = p["terrain.featureScale"]
	local ridges = p["terrain.ridges"]
	local warp = p["terrain.warp"]
	local valleys = p["terrain.valleys"]
	local detail = p["terrain.detail"]
	local plateau = p["terrain.plateau"]
	local waterLevel = p["terrain.waterLevel"]

	-- Feature wavelengths in studs, scaled by the Feature Scale control.
	local continentScale = 640 * featureScale
	local hillScale = 210 * featureScale
	local ridgeScale = 150 * featureScale
	local detailScale = 38 * featureScale
	local valleyScale = 320 * featureScale
	local warpScale = 260 * featureScale
	local warpStrength = warp * 110

	local heightRange = 60 * amplitude

	local function heightAt(worldX: number, worldZ: number): number
		local wx, wz = worldX, worldZ
		if warpStrength > 0.01 then
			local dx = Noise.Value2D(seed, worldX / warpScale, worldZ / warpScale, CH_WARP_X)
			local dz = Noise.Value2D(seed, worldX / warpScale, worldZ / warpScale, CH_WARP_Z)
			wx += dx * warpStrength
			wz += dz * warpStrength
		end

		local continent = fbm(seed, wx / continentScale, wz / continentScale, CH_CONTINENT, 3)
		local hills = fbm(seed, wx / hillScale, wz / hillScale, CH_HILL, 4)

		-- ridged noise: fold the signal to make sharp crests
		local ridgeRaw = fbm(seed, wx / ridgeScale, wz / ridgeScale, CH_RIDGE, 4)
		local ridged = 1 - math.abs(ridgeRaw) * 2
		ridged = ridged * ridged

		local fine = fbm(seed, wx / detailScale, wz / detailScale, CH_DETAIL, 3)

		-- blend rounded hills toward sharp ridges
		local shape = hills * (1 - ridges) + ridged * ridges
		local height = baseHeight
			+ continent * heightRange * 0.85
			+ shape * heightRange * 0.55
			+ fine * heightRange * 0.12 * detail

		if valleys > 0.01 then
			local channel = math.abs(fbm(seed, wx / valleyScale, wz / valleyScale, CH_VALLEY, 3))
			local carve = math.clamp(1 - channel * 3.2, 0, 1)
			height -= carve * heightRange * 0.55 * valleys
		end

		if plateau > 0.01 then
			local top = baseHeight + heightRange * 0.55
			if height > top then
				height = top + (height - top) * (1 - plateau * 0.92)
			end
		end

		return height
	end

	-- sample the range so downstream stages can normalise altitude
	local minHeight, maxHeight = math.huge, -math.huge
	local step = math.max(resolution * 4, size / 48)
	for x = 0, size, step do
		for z = 0, size, step do
			local h = heightAt(x - size / 2, z - size / 2)
			minHeight = math.min(minHeight, h)
			maxHeight = math.max(maxHeight, h)
		end
	end

	return {
		Seed = seed,
		Size = size,
		Resolution = resolution,
		Origin = -size / 2,
		HeightAt = heightAt,
		MinHeight = minHeight,
		MaxHeight = maxHeight,
		WaterLevel = waterLevel,
	}
end

function Stage.Signature(recipe: Recipe.Data): string
	local field = Stage.BuildField(recipe)
	local state = Checksum.New()
	Checksum.UpdateString(state, "worldforge-terrain-v1")
	Checksum.UpdateUInt32(state, field.Seed)
	Checksum.UpdateUInt32(state, field.Size)
	local samples = 24
	local step = field.Size / samples
	for ix = 0, samples do
		for iz = 0, samples do
			local x = field.Origin + ix * step
			local z = field.Origin + iz * step
			Checksum.UpdateIndexedUInt32(state, ix * 100 + iz,
				math.floor(field.HeightAt(x, z) * 256 + 0.5) % 4294967296)
		end
	end
	return Checksum.Digest(state)
end

local function worldRoot(): Folder
	local root = Workspace:FindFirstChild("WorldForgeWorld")
	if not root then
		root = Instance.new("Folder")
		root.Name = "WorldForgeWorld"
		root.Parent = Workspace
	end
	return root :: Folder
end

Stage.WorldRoot = worldRoot

function Stage.Clear(recipe: Recipe.Data)
	local p = Recipe.Resolve(recipe)
	local size = p["terrain.size"]
	local resolution = p["terrain.resolution"]
	local skirt = if p["terrain.edgeSkirt"] then 128 else 0
	local half = size / 2 + skirt
	local region = Region3.new(
		Vector3.new(-half, -256, -half),
		Vector3.new(half, 512, half)
	):ExpandToGrid(resolution)
	Workspace.Terrain:FillRegion(region, resolution, Enum.Material.Air)

	local walls = worldRoot():FindFirstChild("BoundaryWalls")
	if walls then walls:Destroy() end
end

-- Height of the skirt (or nil when outside a disabled skirt).
local function surfaceHeight(field: Field, x: number, z: number, skirtWidth: number): number?
	local origin = field.Origin
	local size = field.Size
	local inside = x >= origin and x < origin + size and z >= origin and z < origin + size
	if inside then
		return field.HeightAt(x, z)
	end
	if skirtWidth <= 0 then
		return nil
	end
	-- continue the edge profile outward, easing down to a low rim
	local clampedX = math.clamp(x, origin, origin + size)
	local clampedZ = math.clamp(z, origin, origin + size)
	local edgeHeight = field.HeightAt(clampedX, clampedZ)
	local dx = math.max(0, math.max(origin - x, x - (origin + size)))
	local dz = math.max(0, math.max(origin - z, z - (origin + size)))
	local distance = math.sqrt(dx * dx + dz * dz)
	local t = math.clamp(distance / skirtWidth, 0, 1)
	local fade = t * t * (3 - 2 * t)
	return edgeHeight * (1 - fade) + (field.MinHeight - 12) * fade
end

--[[
	Writes the terrain with WriteVoxels in tiles.

	Occupancy is the fraction of each voxel that sits below the surface, which
	is what gives smooth slopes instead of 4-stud stairs. Tiles keep the voxel
	arrays small and let us yield between them so Studio stays responsive.
]]
function Stage.Materialize(recipe: Recipe.Data)
	local started = os.clock()
	local p = Recipe.Resolve(recipe)
	local field = Stage.BuildField(recipe)
	local terrain = Workspace.Terrain

	Stage.Clear(recipe)

	local size = field.Size
	local resolution = field.Resolution
	local origin = field.Origin
	local material = (Enum.Material :: any)[p["terrain.material"]] or Enum.Material.Sand
	local waterLevel = field.WaterLevel
	local useWater = waterLevel > field.MinHeight
	local skirtEnabled = p["terrain.edgeSkirt"]
	local skirtWidth = if skirtEnabled then 128 else 0   -- 32 voxels

	local floor = math.floor((field.MinHeight - 32) / resolution) * resolution

	-- Tile and skirt are whole numbers of voxels, so every region corner below
	-- is already grid-aligned and ExpandToGrid can never resize it.
	local cellsPerTile = 16
	local tile = cellsPerTile * resolution            -- 64 studs
	local outerMin = -skirtWidth
	local outerMax = size + skirtWidth
	local tiles = 0
	assert(origin % resolution == 0, "world origin is not voxel-aligned")

	for gx = outerMin, outerMax - 1, tile do
		for gz = outerMin, outerMax - 1, tile do
			local baseX = origin + gx
			local baseZ = origin + gz

			-- Per-tile height band. Writing voxels only where the surface
			-- actually is — and bulk-filling the solid rock below it — keeps
			-- generation fast even on tall worlds.
			local heights = table.create(cellsPerTile)
			local tileMin, tileMax = math.huge, -math.huge
			local anySurface = false
			for ix = 1, cellsPerTile do
				heights[ix] = table.create(cellsPerTile)
				local worldX = baseX + (ix - 0.5) * resolution
				for iz = 1, cellsPerTile do
					local worldZ = baseZ + (iz - 0.5) * resolution
					local height = surfaceHeight(field, worldX, worldZ, skirtWidth)
					heights[ix][iz] = height
					if height then
						anySurface = true
						tileMin = math.min(tileMin, height)
						tileMax = math.max(tileMax, height)
					end
				end
			end

			if anySurface then
				if useWater then
					tileMax = math.max(tileMax, waterLevel)
					tileMin = math.min(tileMin, waterLevel)
				end
				local bandBottom = math.floor((tileMin - resolution * 2) / resolution) * resolution
				local bandTop = math.ceil((tileMax + resolution * 2) / resolution) * resolution
				bandBottom = math.max(bandBottom, floor)
				local bandCells = math.max(1, math.floor((bandTop - bandBottom) / resolution))

				-- solid base below the band, written in one cheap call
				if bandBottom > floor then
					terrain:FillBlock(
						CFrame.new(
							baseX + cellsPerTile * resolution / 2,
							(floor + bandBottom) / 2,
							baseZ + cellsPerTile * resolution / 2),
						Vector3.new(cellsPerTile * resolution, bandBottom - floor, cellsPerTile * resolution),
						material)
				end

				local materials = table.create(cellsPerTile)
				local occupancies = table.create(cellsPerTile)
				for ix = 1, cellsPerTile do
					materials[ix] = table.create(bandCells)
					occupancies[ix] = table.create(bandCells)
					for iy = 1, bandCells do
						materials[ix][iy] = table.create(cellsPerTile)
						occupancies[ix][iy] = table.create(cellsPerTile)
						local cellBottom = bandBottom + (iy - 1) * resolution
						for iz = 1, cellsPerTile do
							local height = heights[ix][iz]
							local occupancy, cellMaterial = 0, Enum.Material.Air
							if height then
								occupancy = math.clamp((height - cellBottom) / resolution, 0, 1)
								if occupancy > 0 then
									cellMaterial = material
								elseif useWater then
									local waterFill = math.clamp((waterLevel - cellBottom) / resolution, 0, 1)
									if waterFill > 0 then
										occupancy = waterFill
										cellMaterial = Enum.Material.Water
									end
								end
							end
							materials[ix][iy][iz] = cellMaterial
							occupancies[ix][iy][iz] = occupancy
						end
					end
				end

				local region = Region3.new(
					Vector3.new(baseX, bandBottom, baseZ),
					Vector3.new(baseX + cellsPerTile * resolution, bandBottom + bandCells * resolution,
						baseZ + cellsPerTile * resolution)
				):ExpandToGrid(resolution)
				terrain:WriteVoxels(region, resolution, materials, occupancies)
			end

			tiles += 1
			if tiles % 8 == 0 then
				task.wait()
			end
		end
	end
	local columns = tiles

	-- boundary walls
	if p["terrain.boundaryWalls"] then
		local walls = Instance.new("Folder")
		walls.Name = "BoundaryWalls"
		local height = (field.MaxHeight - field.MinHeight) + 80
		local mid = (field.MaxHeight + field.MinHeight) / 2
		local half = size / 2
		local definitions = {
			{Vector3.new(0, mid, -half), Vector3.new(size, height, 2)},
			{Vector3.new(0, mid, half), Vector3.new(size, height, 2)},
			{Vector3.new(-half, mid, 0), Vector3.new(2, height, size)},
			{Vector3.new(half, mid, 0), Vector3.new(2, height, size)},
		}
		for index, definition in definitions do
			local wall = Instance.new("Part")
			wall.Name = "BoundaryWall" .. index
			wall.Anchored = true
			wall.Transparency = 1
			wall.CanCollide = true
			wall.CanQuery = false
			wall.CanTouch = false
			wall.CastShadow = false
			wall.Position = definition[1]
			wall.Size = definition[2]
			wall.Parent = walls
		end
		walls.Parent = worldRoot()
	end

	local root = worldRoot()
	root:SetAttribute("TerrainSeed", field.Seed)
	root:SetAttribute("TerrainSignature", Stage.Signature(recipe))
	root:SetAttribute("WorldSize", size)
	root:SetAttribute("MinHeight", field.MinHeight)
	root:SetAttribute("MaxHeight", field.MaxHeight)

	return {
		Seed = field.Seed,
		Size = size,
		Tiles = columns,
		MinHeight = math.floor(field.MinHeight * 10) / 10,
		MaxHeight = math.floor(field.MaxHeight * 10) / 10,
		WaterLevel = if useWater then waterLevel else nil,
		Signature = Stage.Signature(recipe),
		Seconds = os.clock() - started,
	}
end

return table.freeze(Stage)
