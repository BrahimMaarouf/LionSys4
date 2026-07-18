--!strict

local ServerStorage = game:GetService("ServerStorage")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Catalog = require(WorldEngine.Assets.Rocks.RockCatalog)
local Checksum = require(WorldEngine.Core.Checksum)
local Hash32 = require(WorldEngine.Core.Hash32)
local Config = require(WorldEngine.Config.Composition.DesertWorldComposition)
local HeightfieldPlanner = require(WorldEngine.Planning.HeightfieldPlanner)
local BasePlanner = require(WorldEngine.Planning.DesertCompositionPlanner)
local VariationPlanner = require(WorldEngine.Planning.AssetVariationPlanner)

type WorldSpec = HeightfieldPlanner.WorldSpec
export type SurfacePoint = BasePlanner.SurfacePoint
type BasePlan = BasePlanner.Plan

export type Region = {
	Id: string,
	DisplayName: string,
	Kind: string,
	AnchorX: number,
	AnchorY: number,
	AnchorZ: number,
	InfluenceRadius: number,
	Bias: number,
}

export type Landmark = SurfacePoint & {
	Id: string,
	RegionId: string,
	ApproachX: number,
	ApproachZ: number,
	Primary: boolean,
	RouteId: string,
}

export type Route = {
	Id: string,
	Kind: string,
	LandmarkId: string,
	RegionId: string,
	Nodes: {SurfacePoint},
	Samples: {SurfacePoint},
	Length: number,
	Reachable: boolean,
}

export type Vista = {
	Id: string,
	LandmarkId: string,
	RouteId: string,
	WorldX: number,
	GroundY: number,
	WorldZ: number,
	TargetX: number,
	TargetY: number,
	TargetZ: number,
	Distance: number,
	Score: number,
	LineOfSightClear: boolean,
}

export type Placement = BasePlanner.Placement & {
	RegionId: string,
	LandmarkId: string,
	VistaId: string,
	CompositionLayer: string,
}

export type RepairStats = {
	Passes: number,
	RemovedByBounds: number,
	RemovedBySpawn: number,
	RemovedByRoute: number,
	RemovedByLandmark: number,
	RemovedBySlope: number,
	RemovedBySpacing: number,
}

export type Plan = {
	Version: string,
	WorldSeed: number,
	BaseComposition: BasePlan,
	CompositionInput: BasePlan,
	Variation: any,
	Regions: {Region},
	Landmarks: {Landmark},
	Routes: {Route},
	Vistas: {Vista},
	Placements: {Placement},
	RegionCellCounts: {[string]: number},
	RegionPlacementCounts: {[string]: {[string]: number}},
	RoleCounts: {[string]: number},
	Repair: RepairStats,
	RevalidationPassed: boolean,
	Signature: string,
}

local CHANNEL = 0x4D35434F
local Planner = {}

local function unit(seed: number, a: number, b: number, property: number): number
	return (Hash32.ToSignedUnit(Hash32.HashIntegers(seed, a, b, CHANNEL, property)) + 1) * 0.5
end

local function sampleSurface(spec: WorldSpec, worldX: number, worldZ: number): SurfacePoint
	local step = spec.Resolution * 2
	local left = HeightfieldPlanner.HeightAt(spec, worldX - step, worldZ)
	local right = HeightfieldPlanner.HeightAt(spec, worldX + step, worldZ)
	local back = HeightfieldPlanner.HeightAt(spec, worldX, worldZ - step)
	local front = HeightfieldPlanner.HeightAt(spec, worldX, worldZ + step)
	local center = HeightfieldPlanner.HeightAt(spec, worldX, worldZ)
	local dx = (right - left) / (step * 2)
	local dz = (front - back) / (step * 2)
	return {
		WorldX = worldX,
		GroundY = center + spec.Resolution * 0.5,
		WorldZ = worldZ,
		Normal = Vector3.new(-dx, 1, -dz).Unit,
		SlopeDegrees = math.deg(math.atan(math.sqrt(dx * dx + dz * dz))),
	}
end

local function insideWorld(spec: WorldSpec, worldX: number, worldZ: number): boolean
	local margin = Config.WorldEdgeMargin
	return worldX >= spec.OriginX + margin and worldZ >= spec.OriginZ + margin
		and worldX <= spec.OriginX + spec.WorldSize - margin
		and worldZ <= spec.OriginZ + spec.WorldSize - margin
end

local function routeDirection(samples: {SurfacePoint}, index: number): Vector3
	local first = samples[math.max(1, index - 1)]
	local second = samples[math.min(#samples, index + 1)]
	local direction = Vector3.new(second.WorldX - first.WorldX, 0, second.WorldZ - first.WorldZ)
	return if direction.Magnitude > 0.001 then direction.Unit else Vector3.zAxis
end

local function chooseSite(spec: WorldSpec, desiredX: number, desiredZ: number, preferHigh: boolean, ordinal: number): SurfacePoint
	local best: SurfacePoint? = nil
	local bestScore = -math.huge
	for candidate = 0, 23 do
		local angle = candidate / 24 * math.pi * 2 + unit(spec.WorldSeed, ordinal, candidate, 1) * 0.18
		local radius = if candidate == 0 then 0 else 7 + math.floor((candidate - 1) / 8) * 11
		local worldX = desiredX + math.cos(angle) * radius
		local worldZ = desiredZ + math.sin(angle) * radius
		if insideWorld(spec, worldX, worldZ) then
			local surface = sampleSurface(spec, worldX, worldZ)
			if surface.SlopeDegrees <= 17 then
				local elevation = surface.GroundY * (if preferHigh then 0.16 else -0.10)
				local score = elevation - surface.SlopeDegrees * 0.32 - radius * 0.015
					+ unit(spec.WorldSeed, ordinal, candidate, 2)
				if score > bestScore then
					bestScore = score
					best = surface
				end
			end
		end
	end
	assert(best, "No deterministic composition site was found")
	return best
end

local function makeLandmark(
	spec: WorldSpec,
	id: string,
	regionId: string,
	site: SurfacePoint,
	towardX: number,
	towardZ: number,
	primary: boolean,
	routeId: string
): Landmark
	local toward = Vector3.new(towardX - site.WorldX, 0, towardZ - site.WorldZ)
	if toward.Magnitude < 0.001 then toward = Vector3.zAxis end
	toward = toward.Unit
	return {
		Id = id,
		RegionId = regionId,
		WorldX = site.WorldX,
		GroundY = site.GroundY,
		WorldZ = site.WorldZ,
		Normal = site.Normal,
		SlopeDegrees = site.SlopeDegrees,
		ApproachX = site.WorldX + toward.X * 36,
		ApproachZ = site.WorldZ + toward.Z * 36,
		Primary = primary,
		RouteId = routeId,
	}
end

local function routeLength(samples: {SurfacePoint}): number
	local total = 0
	for index = 1, #samples - 1 do
		local first = samples[index]
		local second = samples[index + 1]
		total += (Vector3.new(second.WorldX, second.GroundY, second.WorldZ)
			- Vector3.new(first.WorldX, first.GroundY, first.WorldZ)).Magnitude
	end
	return total
end

local function nodeKey(x: number, z: number, width: number): number
	return z * width + x
end

local function sampleRoute(spec: WorldSpec, nodes: {SurfacePoint}): {SurfacePoint}
	local samples: {SurfacePoint} = {}
	for index = 1, #nodes - 1 do
		local first = nodes[index]
		local second = nodes[index + 1]
		local dx = second.WorldX - first.WorldX
		local dz = second.WorldZ - first.WorldZ
		local length = math.sqrt(dx * dx + dz * dz)
		local steps = math.max(1, math.ceil(length / Config.RouteSampleSpacing))
		for step = 0, steps - 1 do
			local alpha = step / steps
			table.insert(samples, sampleSurface(spec, first.WorldX + dx * alpha, first.WorldZ + dz * alpha))
		end
	end
	table.insert(samples, nodes[#nodes])
	return samples
end

local function buildRoute(spec: WorldSpec, start: SurfacePoint, goalX: number, goalZ: number): {SurfacePoint}
	local grid = Config.RouteGridSize
	local minX = spec.OriginX + Config.WorldEdgeMargin
	local minZ = spec.OriginZ + Config.WorldEdgeMargin
	local maxX = spec.OriginX + spec.WorldSize - Config.WorldEdgeMargin
	local maxZ = spec.OriginZ + spec.WorldSize - Config.WorldEdgeMargin
	local width = math.floor((maxX - minX) / grid) + 1
	local depth = math.floor((maxZ - minZ) / grid) + 1
	local function cell(value: number, origin: number, count: number): number
		return math.clamp(math.floor((value - origin) / grid + 0.5), 0, count - 1)
	end
	local sx, sz = cell(start.WorldX, minX, width), cell(start.WorldZ, minZ, depth)
	local gx, gz = cell(goalX, minX, width), cell(goalZ, minZ, depth)
	local startKey, goalKey = nodeKey(sx, sz, width), nodeKey(gx, gz, width)
	local open: {[number]: boolean} = {[startKey] = true}
	local gScore: {[number]: number} = {[startKey] = 0}
	local fScore: {[number]: number} = {}
	local cameFrom: {[number]: number} = {}
	local coordinates: {[number]: {X: number, Z: number}} = {[startKey] = {X = sx, Z = sz}}
	local function heuristic(x: number, z: number): number
		return math.sqrt((gx - x) ^ 2 + (gz - z) ^ 2) * grid
	end
	fScore[startKey] = heuristic(sx, sz)
	local offsets = {
		{X = -1, Z = 0}, {X = 1, Z = 0}, {X = 0, Z = -1}, {X = 0, Z = 1},
		{X = -1, Z = -1}, {X = 1, Z = -1}, {X = -1, Z = 1}, {X = 1, Z = 1},
	}
	local found = false
	for _ = 1, width * depth do
		local currentKey: number? = nil
		local currentF = math.huge
		for key in open do
			local score = fScore[key] or math.huge
			if score < currentF or (score == currentF and (currentKey == nil or key < currentKey)) then
				currentKey, currentF = key, score
			end
		end
		if currentKey == nil then break end
		if currentKey == goalKey then found = true break end
		open[currentKey] = nil
		local current = coordinates[currentKey]
		local currentSurface = sampleSurface(spec, minX + current.X * grid, minZ + current.Z * grid)
		for _, offset in offsets do
			local nx, nz = current.X + offset.X, current.Z + offset.Z
			if nx < 0 or nz < 0 or nx >= width or nz >= depth then continue end
			local surface = sampleSurface(spec, minX + nx * grid, minZ + nz * grid)
			local step = math.abs(surface.GroundY - currentSurface.GroundY)
			local endpoint = nx == gx and nz == gz
			if not endpoint and (surface.SlopeDegrees > Config.RouteMaxSlopeDegrees or step > Config.RouteMaxStepHeight) then continue end
			local diagonal = offset.X ~= 0 and offset.Z ~= 0
			local travel = grid * (if diagonal then 1.41421356237 else 1)
			local tentative = (gScore[currentKey] or math.huge) + travel + step * 2.25
				+ surface.SlopeDegrees * 0.18 + unit(spec.WorldSeed, nx, nz, 17) * 1.1
			local key = nodeKey(nx, nz, width)
			if tentative < (gScore[key] or math.huge) then
				cameFrom[key] = currentKey
				gScore[key] = tentative
				fScore[key] = tentative + heuristic(nx, nz)
				coordinates[key] = {X = nx, Z = nz}
				open[key] = true
			end
		end
	end
	assert(found, "Composition route solver could not reach a landmark")
	local reverse = {goalKey}
	local current = goalKey
	while current ~= startKey do
		current = cameFrom[current]
		assert(current, "Composition route reconstruction failed")
		table.insert(reverse, current)
	end
	local route: {SurfacePoint} = {}
	for index = #reverse, 1, -1 do
		local coordinate = coordinates[reverse[index]]
		table.insert(route, sampleSurface(spec, minX + coordinate.X * grid, minZ + coordinate.Z * grid))
	end
	return route
end

local function createWorldStructure(spec: WorldSpec, base: BasePlan): ({Region}, {Landmark}, {Route})
	local primarySamples = base.PathSamples
	local wadiIndex = math.clamp(math.floor(#primarySamples * 0.38), 3, #primarySamples - 2)
	local hamadaIndex = math.clamp(math.floor(#primarySamples * 0.64), 3, #primarySamples - 2)
	local wadiNode, hamadaNode = primarySamples[wadiIndex], primarySamples[hamadaIndex]
	local wadiSide = Vector3.new(-routeDirection(primarySamples, wadiIndex).Z, 0, routeDirection(primarySamples, wadiIndex).X)
	local hamadaSide = Vector3.new(-routeDirection(primarySamples, hamadaIndex).Z, 0, routeDirection(primarySamples, hamadaIndex).X) * -1
	local wadiSite = chooseSite(spec, wadiNode.WorldX + wadiSide.X * 92, wadiNode.WorldZ + wadiSide.Z * 92, false, 2)
	local hamadaSite = chooseSite(spec, hamadaNode.WorldX + hamadaSide.X * 98, hamadaNode.WorldZ + hamadaSide.Z * 98, true, 3)
	local duneDirection = -Vector3.new(base.Landmark.WorldX, 0, base.Landmark.WorldZ).Unit
	local duneSite = chooseSite(spec, duneDirection.X * 112, duneDirection.Z * 112, true, 1)
	local primarySite = sampleSurface(spec, base.Landmark.WorldX, base.Landmark.WorldZ)
	local landmarks: {Landmark} = {
		makeLandmark(spec, "SentinelCrown", "CrownHighlands", primarySite, base.Landmark.ApproachX, base.Landmark.ApproachZ, true, "PilgrimRoad"),
		makeLandmark(spec, "DuneNeedle", "ErgDunes", duneSite, 0, 0, false, "DuneSpur"),
		makeLandmark(spec, "WadiGate", "WadiGardens", wadiSite, wadiNode.WorldX, wadiNode.WorldZ, false, "WadiSpur"),
		makeLandmark(spec, "HamadaWatch", "HamadaShelf", hamadaSite, hamadaNode.WorldX, hamadaNode.WorldZ, false, "HamadaSpur"),
	}
	local regions: {Region} = {}
	local anchors = {
		ErgDunes = sampleSurface(spec, 0, 0),
		WadiGardens = wadiSite,
		HamadaShelf = hamadaSite,
		CrownHighlands = primarySite,
	}
	for _, definition in Config.Regions do
		local anchor = anchors[definition.Id]
		table.insert(regions, {
			Id = definition.Id, DisplayName = definition.DisplayName, Kind = definition.Kind,
			AnchorX = anchor.WorldX, AnchorY = anchor.GroundY, AnchorZ = anchor.WorldZ,
			InfluenceRadius = definition.InfluenceRadius, Bias = definition.Bias,
		})
	end
	local routes: {Route} = {{
		Id = "PilgrimRoad", Kind = "Primary", LandmarkId = "SentinelCrown", RegionId = "CrownHighlands",
		Nodes = base.RouteNodes, Samples = base.PathSamples, Length = routeLength(base.PathSamples), Reachable = true,
	}}
	local branchStarts = {
		DuneSpur = primarySamples[math.clamp(math.floor(#primarySamples * 0.15), 2, #primarySamples - 1)],
		WadiSpur = wadiNode,
		HamadaSpur = hamadaNode,
	}
	for index = 2, #landmarks do
		local landmark = landmarks[index]
		local start = branchStarts[landmark.RouteId]
		local nodes = buildRoute(spec, start, landmark.ApproachX, landmark.ApproachZ)
		local samples = sampleRoute(spec, nodes)
		table.insert(routes, {
			Id = landmark.RouteId, Kind = "Spur", LandmarkId = landmark.Id, RegionId = landmark.RegionId,
			Nodes = nodes, Samples = samples, Length = routeLength(samples), Reachable = true,
		})
	end
	return regions, landmarks, routes
end

local function regionAt(regions: {Region}, worldX: number, worldZ: number): Region
	local best = regions[1]
	local bestScore = math.huge
	for _, region in regions do
		local distance = math.sqrt((worldX - region.AnchorX) ^ 2 + (worldZ - region.AnchorZ) ^ 2)
		local score = distance / region.InfluenceRadius + region.Bias
		if score < bestScore then best, bestScore = region, score end
	end
	return best
end

local function countRegionCells(spec: WorldSpec, regions: {Region}): {[string]: number}
	local counts: {[string]: number} = {}
	local minX, minZ = spec.OriginX + Config.WorldEdgeMargin, spec.OriginZ + Config.WorldEdgeMargin
	local maxX, maxZ = spec.OriginX + spec.WorldSize - Config.WorldEdgeMargin, spec.OriginZ + spec.WorldSize - Config.WorldEdgeMargin
	local z = minZ
	while z <= maxZ do
		local x = minX
		while x <= maxX do
			local id = regionAt(regions, x, z).Id
			counts[id] = (counts[id] or 0) + 1
			x += Config.RegionGridSize
		end
		z += Config.RegionGridSize
	end
	return counts
end

local function assetIndex(assetId: string): number
	for index, asset in Catalog.Assets do if asset.Id == assetId then return index end end
	error("Unknown asset " .. assetId)
end

local function makePlacement(
	spec: WorldSpec, regions: {Region}, assetId: string, worldX: number, worldZ: number,
	scale: number, yaw: number, role: string, zoneId: string, landmarkId: string?, vistaId: string?, layer: string?
): Placement
	local surface = sampleSurface(spec, worldX, worldZ)
	local asset = Catalog.ById[assetId]
	assert(asset, "Unknown asset " .. assetId)
	return {
		Index = 0, AssetId = assetId, AssetIndex = assetIndex(assetId), WorldX = worldX,
		GroundY = surface.GroundY, WorldZ = worldZ, Normal = surface.Normal, YawRadians = yaw,
		Scale = scale, SlopeDegrees = surface.SlopeDegrees, SpacingRadius = asset.SpacingRadius * scale,
		Role = role, ZoneId = zoneId, RegionId = regionAt(regions, worldX, worldZ).Id,
		LandmarkId = landmarkId or "", VistaId = vistaId or "", CompositionLayer = layer or "RegionalGrammar",
	}
end

local function copyBasePlacement(regions: {Region}, basePlacement): Placement
	local regionId = regionAt(regions, basePlacement.WorldX, basePlacement.WorldZ).Id
	return {
		Index = 0, AssetId = basePlacement.AssetId, AssetIndex = basePlacement.AssetIndex,
		WorldX = basePlacement.WorldX, GroundY = basePlacement.GroundY, WorldZ = basePlacement.WorldZ,
		Normal = basePlacement.Normal, YawRadians = basePlacement.YawRadians, Scale = basePlacement.Scale,
		SlopeDegrees = basePlacement.SlopeDegrees, SpacingRadius = basePlacement.SpacingRadius,
		Role = basePlacement.Role, ZoneId = basePlacement.ZoneId, RegionId = regionId,
		LandmarkId = if basePlacement.Role == "Landmark" then "SentinelCrown" else "",
		VistaId = "", CompositionLayer = "Milestone3Backbone",
	}
end

local function addRegionalGrammar(spec: WorldSpec, regions: {Region}, placements: {Placement})
	for regionIndex, region in regions do
		local definition = Config.ById[region.Id]
		local ordinal = 0
		for _, assetId in {"WindBoulder", "LayeredMesa", "DryShrub"} do
			local target = definition.Targets[assetId] or 0
			local generated = 0
			local attempts = 0
			while generated < target and attempts < target * 8 do
				attempts += 1
				ordinal += 1
				local angle = unit(spec.WorldSeed, regionIndex, ordinal, 31) * math.pi * 2
				local radius = 30 + math.sqrt(unit(spec.WorldSeed, regionIndex, ordinal, 32)) * (region.InfluenceRadius * 0.52)
				local worldX = region.AnchorX + math.cos(angle) * radius
				local worldZ = region.AnchorZ + math.sin(angle) * radius
				if insideWorld(spec, worldX, worldZ) and regionAt(regions, worldX, worldZ).Id == region.Id then
					table.insert(placements, makePlacement(spec, regions, assetId, worldX, worldZ,
						(if assetId == "DryShrub" then 0.56 else 0.72) + unit(spec.WorldSeed, regionIndex, ordinal, 33) * 0.55,
						angle + unit(spec.WorldSeed, regionIndex, ordinal, 34), "Regional", region.Id, nil, nil, "RegionalGrammar"))
					generated += 1
				end
			end
		end
	end
end

local function addSecondaryLandmarks(spec: WorldSpec, regions: {Region}, landmarks: {Landmark}, placements: {Placement})
	for landmarkIndex = 2, #landmarks do
		local landmark = landmarks[landmarkIndex]
		local recipe = if landmark.Id == "WadiGate"
			then {{"LayeredMesa", -9, 0, 1.12}, {"LayeredMesa", 9, 0, 1.12}, {"WindBoulder", 0, 2, 0.88}}
			else {{"LayeredMesa", 0, 0, 1.38}, {"WindBoulder", -7, 4, 0.96}, {"WindBoulder", 7, -3, 0.72}}
		local toward = Vector3.new(landmark.ApproachX - landmark.WorldX, 0, landmark.ApproachZ - landmark.WorldZ).Unit
		local side = Vector3.new(-toward.Z, 0, toward.X)
		for member, item in recipe do
			local worldX = landmark.WorldX + side.X * item[2] + toward.X * item[3]
			local worldZ = landmark.WorldZ + side.Z * item[2] + toward.Z * item[3]
			table.insert(placements, makePlacement(spec, regions, item[1], worldX, worldZ, item[4],
				math.atan2(toward.X, toward.Z) + member * 0.2, "Landmark", landmark.RegionId,
				landmark.Id, nil, "SecondaryLandmark"))
		end
	end
end

local function lineOfSight(spec: WorldSpec, view: SurfacePoint, landmark: Landmark): boolean
	local eyeY = view.GroundY + Config.VistaEyeHeight
	local targetY = landmark.GroundY + Config.VistaTargetHeight
	for step = 1, 15 do
		local alpha = step / 16
		local x = view.WorldX + (landmark.WorldX - view.WorldX) * alpha
		local z = view.WorldZ + (landmark.WorldZ - view.WorldZ) * alpha
		local sightY = eyeY + (targetY - eyeY) * alpha
		if HeightfieldPlanner.HeightAt(spec, x, z) + spec.Resolution * 0.5 > sightY - 1.2 then return false end
	end
	return true
end

local function addVistas(spec: WorldSpec, regions: {Region}, landmarks: {Landmark}, routes: {Route}, placements: {Placement}): {Vista}
	local routesById: {[string]: Route} = {}
	for _, route in routes do routesById[route.Id] = route end
	local vistas: {Vista} = {}
	for landmarkIndex, landmark in landmarks do
		local route = routesById[landmark.RouteId]
		local best: SurfacePoint? = nil
		local bestScore = -math.huge
		for sampleIndex, sample in route.Samples do
			local distance = math.sqrt((sample.WorldX - landmark.WorldX) ^ 2 + (sample.WorldZ - landmark.WorldZ) ^ 2)
			if distance >= Config.VistaMinimumDistance and distance <= Config.VistaMaximumDistance and lineOfSight(spec, sample, landmark) then
				local ideal = 102 + landmarkIndex * 8
				local score = 100 - math.abs(distance - ideal) * 0.24 - sample.SlopeDegrees * 0.3
					+ unit(spec.WorldSeed, landmarkIndex, sampleIndex, 61) * 2
				if score > bestScore then best, bestScore = sample, score end
			end
		end
		assert(best, "No clear deterministic vista for " .. landmark.Id)
		local vistaId = landmark.Id .. "Vista"
		table.insert(vistas, {
			Id = vistaId, LandmarkId = landmark.Id, RouteId = route.Id,
			WorldX = best.WorldX, GroundY = best.GroundY, WorldZ = best.WorldZ,
			TargetX = landmark.WorldX, TargetY = landmark.GroundY + Config.VistaTargetHeight, TargetZ = landmark.WorldZ,
			Distance = math.sqrt((best.WorldX - landmark.WorldX) ^ 2 + (best.WorldZ - landmark.WorldZ) ^ 2),
			Score = bestScore, LineOfSightClear = true,
		})
		local forward = Vector3.new(landmark.WorldX - best.WorldX, 0, landmark.WorldZ - best.WorldZ).Unit
		local side = Vector3.new(-forward.Z, 0, forward.X)
		for frame = 1, 2 do
			local sign = if frame == 1 then -1 else 1
			local worldX = best.WorldX + side.X * Config.VistaFrameOffset * sign + forward.X * 8
			local worldZ = best.WorldZ + side.Z * Config.VistaFrameOffset * sign + forward.Z * 8
			local fromSpawn = Vector3.new(worldX, 0, worldZ)
			if fromSpawn.Magnitude < Config.SpawnSafeRadius + 18 then
				local sector = math.atan2(landmark.WorldZ, landmark.WorldX) + sign * 0.33
				worldX = math.cos(sector) * (Config.SpawnSafeRadius + 18)
				worldZ = math.sin(sector) * (Config.SpawnSafeRadius + 18)
			end
			table.insert(placements, makePlacement(spec, regions, "WindBoulder", worldX, worldZ,
				0.58 + unit(spec.WorldSeed, landmarkIndex, frame, 62) * 0.25,
				math.atan2(forward.X, forward.Z), "VistaFrame", landmark.RegionId, landmark.Id, vistaId, "VistaFraming"))
		end
	end
	return vistas
end

local function distanceToSegmentSquared(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local abx, abz = bx - ax, bz - az
	local lengthSquared = abx * abx + abz * abz
	local alpha = if lengthSquared > 0 then math.clamp(((px - ax) * abx + (pz - az) * abz) / lengthSquared, 0, 1) else 0
	local dx, dz = px - (ax + abx * alpha), pz - (az + abz * alpha)
	return dx * dx + dz * dz
end

function Planner.DistanceToRouteSquared(route: Route, worldX: number, worldZ: number): number
	local best = math.huge
	for index = 1, #route.Nodes - 1 do
		local first, second = route.Nodes[index], route.Nodes[index + 1]
		best = math.min(best, distanceToSegmentSquared(worldX, worldZ, first.WorldX, first.WorldZ, second.WorldX, second.WorldZ))
	end
	return best
end

local function overlaps(accepted: {Placement}, candidate: Placement): boolean
	for _, other in accepted do
		if candidate.Role == "Landmark" and other.Role == "Landmark" then continue end
		local minimum = candidate.SpacingRadius + other.SpacingRadius
		if (candidate.WorldX - other.WorldX) ^ 2 + (candidate.WorldZ - other.WorldZ) ^ 2 < minimum ^ 2 then return true end
	end
	return false
end

local function repairPlan(spec: WorldSpec, landmarks: {Landmark}, routes: {Route}, candidates: {Placement}): ({Placement}, RepairStats, boolean)
	local stats: RepairStats = {Passes = 0, RemovedByBounds = 0, RemovedBySpawn = 0, RemovedByRoute = 0,
		RemovedByLandmark = 0, RemovedBySlope = 0, RemovedBySpacing = 0}
	local current = candidates
	local revalidated = false
	for pass = 1, 3 do
		stats.Passes = pass
		local accepted: {Placement} = {}
		local removed = 0
		for _, placement in current do
			local reason = ""
			if not insideWorld(spec, placement.WorldX, placement.WorldZ) then reason = "Bounds"
			elseif placement.Role ~= "Landmark" and placement.WorldX ^ 2 + placement.WorldZ ^ 2 < Config.SpawnSafeRadius ^ 2 then reason = "Spawn"
			elseif placement.Role ~= "Landmark" and placement.SlopeDegrees > Catalog.ById[placement.AssetId].MaxSlopeDegrees then reason = "Slope"
			elseif placement.Role ~= "Landmark" then
				for _, route in routes do
					if Planner.DistanceToRouteSquared(route, placement.WorldX, placement.WorldZ) < Config.RouteCorridorRadius ^ 2 then reason = "Route" break end
				end
				if reason == "" then
					for _, landmark in landmarks do
						if placement.LandmarkId ~= landmark.Id and (placement.WorldX - landmark.WorldX) ^ 2
							+ (placement.WorldZ - landmark.WorldZ) ^ 2 < Config.LandmarkClearRadius ^ 2 then reason = "Landmark" break end
					end
				end
			end
			if reason == "" and overlaps(accepted, placement) then reason = "Spacing" end
			if reason == "" then table.insert(accepted, placement) else
				removed += 1
				if reason == "Bounds" then stats.RemovedByBounds += 1
				elseif reason == "Spawn" then stats.RemovedBySpawn += 1
				elseif reason == "Route" then stats.RemovedByRoute += 1
				elseif reason == "Landmark" then stats.RemovedByLandmark += 1
				elseif reason == "Slope" then stats.RemovedBySlope += 1
				elseif reason == "Spacing" then stats.RemovedBySpacing += 1 end
			end
		end
		current = accepted
		if removed == 0 then revalidated = true break end
	end
	for index, placement in current do placement.Index = index end
	return current, stats, revalidated
end

local function countPlacements(placements: {Placement}): ({[string]: {[string]: number}}, {[string]: number})
	local regions: {[string]: {[string]: number}} = {}
	local roles: {[string]: number} = {}
	for _, placement in placements do
		local counts = regions[placement.RegionId] or {Total = 0, Rock = 0, Vegetation = 0}
		counts.Total += 1
		counts[Catalog.ById[placement.AssetId].Kind] = (counts[Catalog.ById[placement.AssetId].Kind] or 0) + 1
		regions[placement.RegionId] = counts
		roles[placement.Role] = (roles[placement.Role] or 0) + 1
	end
	return regions, roles
end

local function signature(plan: Plan): string
	local state = Checksum.New()
	Checksum.UpdateString(state, plan.Version)
	Checksum.UpdateUInt32(state, plan.WorldSeed)
	for index, region in plan.Regions do
		Checksum.UpdateIndexedUInt32(state, index, math.floor(region.AnchorX * 1024 + 0.5))
		Checksum.UpdateString(state, region.Id)
		Checksum.UpdateUInt32(state, math.floor(region.AnchorY * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(region.AnchorZ * 1024 + 0.5))
		Checksum.UpdateUInt32(state, plan.RegionCellCounts[region.Id] or 0)
	end
	for index, landmark in plan.Landmarks do
		Checksum.UpdateIndexedUInt32(state, index, math.floor(landmark.WorldX * 1024 + 0.5))
		Checksum.UpdateString(state, landmark.Id)
		Checksum.UpdateUInt32(state, math.floor(landmark.WorldZ * 1024 + 0.5))
	end
	for index, route in plan.Routes do
		Checksum.UpdateIndexedUInt32(state, index, #route.Nodes)
		Checksum.UpdateString(state, route.Id)
		for nodeIndex, node in route.Nodes do
			Checksum.UpdateIndexedUInt32(state, nodeIndex, math.floor(node.WorldX * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(node.GroundY * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(node.WorldZ * 1024 + 0.5))
		end
	end
	for index, vista in plan.Vistas do
		Checksum.UpdateIndexedUInt32(state, index, math.floor(vista.WorldX * 1024 + 0.5))
		Checksum.UpdateString(state, vista.Id)
		Checksum.UpdateUInt32(state, math.floor(vista.WorldZ * 1024 + 0.5))
	end
	for index, placement in plan.Placements do
		Checksum.UpdateIndexedUInt32(state, index, placement.AssetIndex)
		Checksum.UpdateString(state, placement.RegionId)
		Checksum.UpdateString(state, placement.Role)
		Checksum.UpdateString(state, placement.LandmarkId)
		Checksum.UpdateString(state, placement.VistaId)
		Checksum.UpdateUInt32(state, math.floor(placement.WorldX * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(placement.WorldZ * 1024 + 0.5))
	end
	Checksum.UpdateString(state, if plan.Variation then plan.Variation.Signature else "composition-input")
	return Checksum.Digest(state)
end

function Planner.Plan(spec: WorldSpec): Plan
	local base = BasePlanner.Plan(spec)
	local regions, landmarks, routes = createWorldStructure(spec, base)
	local candidates: {Placement} = {}
	-- Composition-critical silhouettes and views own priority over decoration.
	for _, placement in base.Placements do
		if placement.Role == "Landmark" then table.insert(candidates, copyBasePlacement(regions, placement)) end
	end
	addSecondaryLandmarks(spec, regions, landmarks, candidates)
	local vistas = addVistas(spec, regions, landmarks, routes, candidates)
	addRegionalGrammar(spec, regions, candidates)
	for _, placement in base.Placements do
		if placement.Role == "Landmark" then continue end
		local regionId = regionAt(regions, placement.WorldX, placement.WorldZ).Id
		local supportsGrammar = not (regionId == "WadiGardens" and placement.AssetId ~= "DryShrub")
			and not ((regionId == "ErgDunes" or regionId == "HamadaShelf") and placement.AssetId == "DryShrub")
		local keep = placement.Role ~= "Scatter" or unit(spec.WorldSeed, placement.Index, 0, 21) > 0.76
		if supportsGrammar and keep then table.insert(candidates, copyBasePlacement(regions, placement)) end
	end
	local placements, repair, revalidated = repairPlan(spec, landmarks, routes, candidates)
	assert(#placements <= Config.MaximumPlacements, "World composition exceeded placement budget")
	local regionPlacementCounts, roleCounts = countPlacements(placements)
	local compositionInput: BasePlan = {
		Version = Config.Version, WorldSeed = spec.WorldSeed, Landmark = base.Landmark,
		RouteNodes = base.RouteNodes, PathSamples = base.PathSamples, Placements = placements :: any,
		RoleCounts = roleCounts, Repair = base.Repair, RevalidationPassed = revalidated,
		BaseScatterCount = base.BaseScatterCount, Signature = "",
	}
	local provisional: Plan = {
		Version = Config.Version, WorldSeed = spec.WorldSeed, BaseComposition = base,
		CompositionInput = compositionInput, Variation = nil, Regions = regions, Landmarks = landmarks,
		Routes = routes, Vistas = vistas, Placements = placements,
		RegionCellCounts = countRegionCells(spec, regions), RegionPlacementCounts = regionPlacementCounts,
		RoleCounts = roleCounts, Repair = repair, RevalidationPassed = revalidated, Signature = "",
	}
	-- M4 consumes this position-mixed composition signature and stays the final
	-- asset-variation authority. The full M5 signature also includes its output.
	compositionInput.Signature = signature(provisional)
	provisional.Variation = VariationPlanner.Plan(spec, compositionInput)
	provisional.Signature = signature(provisional)
	return provisional
end

return table.freeze(Planner)
