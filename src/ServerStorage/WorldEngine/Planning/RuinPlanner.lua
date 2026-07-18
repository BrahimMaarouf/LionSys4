--!strict

local ServerStorage = game:GetService("ServerStorage")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Checksum = require(WorldEngine.Core.Checksum)
local Config = require(WorldEngine.Config.Ruins.DesertRuins)
local Hash32 = require(WorldEngine.Core.Hash32)
local HeightfieldPlanner = require(WorldEngine.Planning.HeightfieldPlanner)
local WorldCompositionPlanner = require(WorldEngine.Planning.WorldCompositionPlanner)

type WorldSpec = HeightfieldPlanner.WorldSpec

export type RuinPiece = {
	Index: number,
	SiteId: string,
	PieceId: string, -- kit template name
	WorldX: number,
	WorldY: number, -- pivot ground height (site anchor)
	WorldZ: number,
	YawRadians: number,
	Socket: string, -- "EdgeN"/"EdgeS"/"EdgeE"/"EdgeW"/"Corner"/"Interior"/"Rubble"
}

export type RuinSite = {
	Id: string,
	CenterX: number,
	CenterZ: number,
	AnchorY: number,
	CellsX: number,
	CellsZ: number,
	DoorwayCount: number,
	PieceCount: number,
}

export type Plan = {
	Version: string,
	WorldSeed: number,
	Sites: {RuinSite},
	Pieces: {RuinPiece},
	Signature: string,
	RejectedSiteBearings: number,
}

local CHANNEL = 0x5255494E -- "RUIN"

local Planner = {}

local function unit(seed: number, a: number, b: number, c: number): number
	return (Hash32.ToSignedUnit(Hash32.HashIntegers(seed, a, b, c, CHANNEL)) + 1) * 0.5
end

local function insideWorld(spec: WorldSpec, x: number, z: number, margin: number): boolean
	local half = spec.WorldSize / 2
	return x > spec.OriginX + margin and x < spec.OriginX + spec.WorldSize - margin
		and z > spec.OriginZ + margin and z < spec.OriginZ + spec.WorldSize - margin
end

local function routeClear(routes, x: number, z: number): boolean
	for _, route in routes do
		if WorldCompositionPlanner.DistanceToRouteSquared(route, x, z) < Config.RouteClearance ^ 2 then
			return false
		end
	end
	return true
end

local function siteSlope(spec: WorldSpec, x: number, z: number, extent: number): number
	-- dense 3x3 sample: a mean-of-corners check lets a site straddle a gully
	-- and float; sampling the interior too rejects such sites outright.
	local minH, maxH = math.huge, -math.huge
	for gx = -1, 1 do
		for gz = -1, 1 do
			local h = HeightfieldPlanner.HeightAt(spec, x + gx * extent, z + gz * extent)
			minH = math.min(minH, h)
			maxH = math.max(maxH, h)
		end
	end
	return math.deg(math.atan((maxH - minH) / (extent * 2)))
end

local function footprintValid(spec: WorldSpec, routes, cx: number, cz: number, halfX: number, halfZ: number): boolean
	if not insideWorld(spec, cx, cz, math.max(halfX, halfZ) + 6) then
		return false
	end
	for _, corner in {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}, {0, 0}} do
		if not routeClear(routes, cx + corner[1] * halfX, cz + corner[2] * halfZ) then
			return false
		end
	end
	return siteSlope(spec, cx, cz, math.max(halfX, halfZ)) <= Config.MaximumSiteSlopeDegrees
end

local function anchorHeight(spec: WorldSpec, cx: number, cz: number, halfX: number, halfZ: number): number
	-- anchor the whole site at the LOWEST sampled height: pieces then sink
	-- into rises instead of floating over dips (ruins read as settled, never
	-- hovering). The dense slope gate keeps the total burial acceptable.
	local minH = math.huge
	for gx = -1, 1 do
		for gz = -1, 1 do
			minH = math.min(minH, HeightfieldPlanner.HeightAt(spec, cx + gx * halfX, cz + gz * halfZ))
		end
	end
	return minH
end

-- Chooses the perimeter piece for one edge socket. The route-facing edge is
-- guaranteed at least one doorway so every ruin remains enterable.
local function edgePiece(seed: number, siteIndex: number, socketIndex: number, ruination: number,
	isDoorwaySocket: boolean): string?
	if isDoorwaySocket then
		return "WallDoorway"
	end
	local roll = unit(seed, siteIndex, socketIndex, 1)
	if roll < ruination * 0.45 then
		return nil -- collapsed: gap plus rubble
	elseif roll < ruination then
		return "WallBroken"
	end
	return "WallSegment"
end

local function planSite(spec: WorldSpec, composition, siteConfig, siteIndex: number,
	pieces: {RuinPiece}, rejectedBearings: {number}): RuinSite?
	local cell = Config.CellSize
	local halfX = siteConfig.CellsX * cell / 2
	local halfZ = siteConfig.CellsZ * cell / 2

	-- resolve site center
	local baseX, baseZ
	if siteConfig.LandmarkId then
		for _, landmark in composition.Landmarks do
			if landmark.Id == siteConfig.LandmarkId then
				baseX, baseZ = landmark.WorldX, landmark.WorldZ
				break
			end
		end
	else
		local longest, length = nil, -1
		for _, route in composition.Routes do
			local nodes = route.Nodes
			local total = 0
			for i = 1, #nodes - 1 do
				total += math.sqrt((nodes[i + 1].WorldX - nodes[i].WorldX) ^ 2
					+ (nodes[i + 1].WorldZ - nodes[i].WorldZ) ^ 2)
			end
			if total > length then longest, length = route, total end
		end
		if longest then
			local nodes = longest.Nodes
			local index = math.clamp(math.floor(#nodes * siteConfig.RouteFraction), 1, #nodes)
			baseX, baseZ = nodes[index].WorldX, nodes[index].WorldZ
		end
	end
	if not baseX then
		return nil
	end

	local centerX, centerZ
	for _, bearing in siteConfig.OffsetDirections do
		local radians = math.rad(bearing)
		local cx = baseX + math.cos(radians) * siteConfig.OffsetDistance
		local cz = baseZ + math.sin(radians) * siteConfig.OffsetDistance
		if footprintValid(spec, composition.Routes, cx, cz, halfX, halfZ) then
			centerX, centerZ = cx, cz
			break
		end
		table.insert(rejectedBearings, bearing)
	end
	if not centerX then
		return nil
	end

	local anchorY = anchorHeight(spec, centerX, centerZ, halfX, halfZ)
	local doorways = 0
	local pieceCount = 0

	local function addPiece(pieceId: string, x: number, z: number, yaw: number, socket: string)
		pieceCount += 1
		table.insert(pieces, {
			Index = #pieces + 1, SiteId = siteConfig.Id, PieceId = pieceId,
			WorldX = x, WorldY = anchorY, WorldZ = z, YawRadians = yaw, Socket = socket,
		})
	end

	local function addRubbleNear(x: number, z: number, socketIndex: number, socket: string)
		local angle = unit(spec.WorldSeed, siteIndex, socketIndex, 5) * math.pi * 2
		local dist = 2.0 + unit(spec.WorldSeed, siteIndex, socketIndex, 6) * 2.5
		addPiece("RubblePile", x + math.cos(angle) * dist, z + math.sin(angle) * dist,
			unit(spec.WorldSeed, siteIndex, socketIndex, 7) * math.pi * 2, socket)
	end

	-- doorway socket: route-facing edge (edge whose center is closest to base landmark/route point)
	local edges = {
		{Name = "EdgeS", Dx = 0, Dz = -halfZ, Yaw = 0, Count = siteConfig.CellsX, Axis = "X"},
		{Name = "EdgeN", Dx = 0, Dz = halfZ, Yaw = 0, Count = siteConfig.CellsX, Axis = "X"},
		{Name = "EdgeW", Dx = -halfX, Dz = 0, Yaw = math.pi / 2, Count = siteConfig.CellsZ, Axis = "Z"},
		{Name = "EdgeE", Dx = halfX, Dz = 0, Yaw = math.pi / 2, Count = siteConfig.CellsZ, Axis = "Z"},
	}
	local doorEdge, doorDistance = 1, math.huge
	for index, edge in edges do
		local ex, ez = centerX + edge.Dx, centerZ + edge.Dz
		local d = (ex - baseX) ^ 2 + (ez - baseZ) ^ 2
		if d < doorDistance then doorEdge, doorDistance = index, d end
	end

	local socketIndex = 0
	for edgeIndex, edge in edges do
		local doorSocket = math.floor(edge.Count / 2) + 1
		for i = 1, edge.Count do
			socketIndex += 1
			local along = (i - 0.5 - edge.Count / 2) * cell
			local x = centerX + (if edge.Axis == "X" then along else edge.Dx)
			local z = centerZ + (if edge.Axis == "Z" then along else edge.Dz)
			local isDoor = edgeIndex == doorEdge and i == doorSocket
			local pieceId = edgePiece(spec.WorldSeed, siteIndex, socketIndex, siteConfig.Ruination, isDoor)
			if pieceId then
				addPiece(pieceId, x, z, edge.Yaw, edge.Name)
				if pieceId == "WallDoorway" then doorways += 1 end
				if pieceId == "WallBroken" and unit(spec.WorldSeed, siteIndex, socketIndex, 4) < 0.6 then
					addRubbleNear(x, z, socketIndex, "Rubble")
				end
			else
				addRubbleNear(x, z, socketIndex, "Rubble")
			end
		end
	end

	-- corners
	for cornerIndex, corner in {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}} do
		socketIndex += 1
		if unit(spec.WorldSeed, siteIndex, socketIndex, 2) > siteConfig.Ruination * 0.5 then
			addPiece("CornerPost", centerX + corner[1] * halfX, centerZ + corner[2] * halfZ,
				0, "Corner")
		end
	end

	-- interior: floor slabs and colonnade
	for gx = 1, siteConfig.CellsX do
		for gz = 1, siteConfig.CellsZ do
			socketIndex += 1
			local x = centerX + (gx - 0.5 - siteConfig.CellsX / 2) * cell
			local z = centerZ + (gz - 0.5 - siteConfig.CellsZ / 2) * cell
			if unit(spec.WorldSeed, siteIndex, socketIndex, 3) < siteConfig.FloorCoverage then
				addPiece("FloorSlab", x + (unit(spec.WorldSeed, siteIndex, socketIndex, 8) - 0.5) * 2,
					z + (unit(spec.WorldSeed, siteIndex, socketIndex, 9) - 0.5) * 2,
					math.floor(unit(spec.WorldSeed, siteIndex, socketIndex, 10) * 4) * math.pi / 2, "Interior")
			end
		end
	end
	if siteConfig.Colonnade then
		local rowZ = {centerZ - halfZ + cell, centerZ + halfZ - cell}
		for rowIndex, z in rowZ do
			for i = 1, siteConfig.CellsX - 1 do
				socketIndex += 1
				local x = centerX + (i - siteConfig.CellsX / 2) * cell
				local broken = unit(spec.WorldSeed, siteIndex, socketIndex, 11) < siteConfig.Ruination
				addPiece(if broken then "PillarBroken" else "Pillar", x, z, 0, "Interior")
			end
		end
	end

	return {
		Id = siteConfig.Id, CenterX = centerX, CenterZ = centerZ, AnchorY = anchorY,
		CellsX = siteConfig.CellsX, CellsZ = siteConfig.CellsZ,
		DoorwayCount = doorways, PieceCount = pieceCount,
	}
end

local function signature(plan: Plan): string
	local state = Checksum.New()
	Checksum.UpdateString(state, plan.Version)
	Checksum.UpdateUInt32(state, plan.WorldSeed)
	Checksum.UpdateUInt32(state, #plan.Pieces)
	for index, piece in plan.Pieces do
		Checksum.UpdateIndexedUInt32(state, index, math.floor(piece.WorldX * 1024 + 0.5))
		Checksum.UpdateString(state, piece.PieceId)
		Checksum.UpdateString(state, piece.SiteId)
		Checksum.UpdateUInt32(state, math.floor(piece.WorldY * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(piece.WorldZ * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(piece.YawRadians * 65536 + 0.5))
	end
	return Checksum.Digest(state)
end

function Planner.Plan(spec: WorldSpec): Plan
	local composition = WorldCompositionPlanner.Plan(spec)
	local pieces: {RuinPiece} = {}
	local sites: {RuinSite} = {}
	local rejectedBearings: {number} = {}
	for siteIndex, siteConfig in Config.Sites do
		local site = planSite(spec, composition, siteConfig, siteIndex, pieces, rejectedBearings)
		if site then
			table.insert(sites, site)
		end
	end
	local plan: Plan = {
		Version = Config.Version,
		WorldSeed = spec.WorldSeed,
		Sites = sites,
		Pieces = pieces,
		Signature = "",
		RejectedSiteBearings = #rejectedBearings,
	}
	plan.Signature = signature(plan)
	return plan
end

return table.freeze(Planner)
