--!strict

local ServerStorage = game:GetService("ServerStorage")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Catalog = require(WorldEngine.Assets.Rocks.RockCatalog)
local Checksum = require(WorldEngine.Core.Checksum)
local Hash32 = require(WorldEngine.Core.Hash32)
local Config = require(WorldEngine.Config.Composition.DesertPilgrimage)
local HeightfieldPlanner = require(WorldEngine.Planning.HeightfieldPlanner)
local ScatterPlanner = require(WorldEngine.Planning.RockPlacementPlanner)

type WorldSpec = HeightfieldPlanner.WorldSpec
type ScatterPlacement = ScatterPlanner.Placement

export type SurfacePoint = {
	WorldX: number,
	GroundY: number,
	WorldZ: number,
	Normal: Vector3,
	SlopeDegrees: number,
}

export type Placement = ScatterPlacement & {
	Role: string,
	ZoneId: string,
}

export type Landmark = SurfacePoint & {
	Id: string,
	ApproachX: number,
	ApproachZ: number,
}

export type RepairStats = {
	Passes: number,
	RemovedByBounds: number,
	RemovedBySpawn: number,
	RemovedByPath: number,
	RemovedByLandmark: number,
	RemovedBySlope: number,
	RemovedBySpacing: number,
}

export type Plan = {
	Version: string,
	WorldSeed: number,
	Landmark: Landmark,
	RouteNodes: {SurfacePoint},
	PathSamples: {SurfacePoint},
	Placements: {Placement},
	RoleCounts: {[string]: number},
	Repair: RepairStats,
	RevalidationPassed: boolean,
	BaseScatterCount: number,
	Signature: string,
}

local CHANNEL = 0x4D33434F
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
	local normal = Vector3.new(-dx, 1, -dz).Unit
	return {
		WorldX = worldX,
		GroundY = center + spec.Resolution * 0.5,
		WorldZ = worldZ,
		Normal = normal,
		SlopeDegrees = math.deg(math.atan(math.sqrt(dx * dx + dz * dz))),
	}
end

local function insideWorld(spec: WorldSpec, worldX: number, worldZ: number): boolean
	local margin = Config.WorldEdgeMargin
	return worldX >= spec.OriginX + margin
		and worldZ >= spec.OriginZ + margin
		and worldX <= spec.OriginX + spec.WorldSize - margin
		and worldZ <= spec.OriginZ + spec.WorldSize - margin
end

local function chooseLandmark(spec: WorldSpec): Landmark
	local bestPoint: SurfacePoint? = nil
	local bestScore = -math.huge
	for candidate = 0, 15 do
		local baseAngle = candidate / 16 * math.pi * 2
		local angle = baseAngle + (unit(spec.WorldSeed, candidate, 0, 1) - 0.5) * 0.24
		local radius = Config.LandmarkMinRadius
			+ (Config.LandmarkMaxRadius - Config.LandmarkMinRadius) * unit(spec.WorldSeed, candidate, 0, 2)
		local worldX = math.cos(angle) * radius
		local worldZ = math.sin(angle) * radius
		local surface = sampleSurface(spec, worldX, worldZ)
		if insideWorld(spec, worldX, worldZ) and surface.SlopeDegrees <= Config.LandmarkMaxSlopeDegrees then
			local prominence = surface.GroundY * 0.06
			local score = prominence + unit(spec.WorldSeed, candidate, 0, 3) * 3 - surface.SlopeDegrees * 0.08
			if score > bestScore then
				bestScore = score
				bestPoint = surface
			end
		end
	end
	assert(bestPoint, "No valid deterministic landmark site was found")
	local center = Vector3.new(bestPoint.WorldX, 0, bestPoint.WorldZ)
	local towardSpawn = -center.Unit
	local approachDistance = Config.LandmarkPlazaRadius + 18
	return {
		Id = "SentinelCrown",
		WorldX = bestPoint.WorldX,
		GroundY = bestPoint.GroundY,
		WorldZ = bestPoint.WorldZ,
		Normal = bestPoint.Normal,
		SlopeDegrees = bestPoint.SlopeDegrees,
		ApproachX = bestPoint.WorldX + towardSpawn.X * approachDistance,
		ApproachZ = bestPoint.WorldZ + towardSpawn.Z * approachDistance,
	}
end

local function nodeKey(x: number, z: number, width: number): number
	return z * width + x
end

local function buildRoute(spec: WorldSpec, landmark: Landmark): {SurfacePoint}
	local grid = Config.PathGridSize
	local minX = spec.OriginX + Config.WorldEdgeMargin
	local minZ = spec.OriginZ + Config.WorldEdgeMargin
	local maxX = spec.OriginX + spec.WorldSize - Config.WorldEdgeMargin
	local maxZ = spec.OriginZ + spec.WorldSize - Config.WorldEdgeMargin
	local width = math.floor((maxX - minX) / grid) + 1
	local depth = math.floor((maxZ - minZ) / grid) + 1

	local function clampCell(value: number, origin: number, count: number): number
		return math.clamp(math.floor((value - origin) / grid + 0.5), 0, count - 1)
	end
	local startX = clampCell(0, minX, width)
	local startZ = clampCell(0, minZ, depth)
	local goalX = clampCell(landmark.ApproachX, minX, width)
	local goalZ = clampCell(landmark.ApproachZ, minZ, depth)
	local startKey = nodeKey(startX, startZ, width)
	local goalKey = nodeKey(goalX, goalZ, width)

	local open: {[number]: boolean} = {[startKey] = true}
	local gScore: {[number]: number} = {[startKey] = 0}
	local fScore: {[number]: number} = {}
	local cameFrom: {[number]: number} = {}
	local coordinates: {[number]: {X: number, Z: number}} = {[startKey] = {X = startX, Z = startZ}}
	local function heuristic(x: number, z: number): number
		local dx = goalX - x
		local dz = goalZ - z
		return math.sqrt(dx * dx + dz * dz) * grid
	end
	fScore[startKey] = heuristic(startX, startZ)

	local neighbors = {
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
				currentKey = key
				currentF = score
			end
		end
		if currentKey == nil then
			break
		end
		if currentKey == goalKey then
			found = true
			break
		end
		open[currentKey] = nil
		local current = coordinates[currentKey]
		local currentWorldX = minX + current.X * grid
		local currentWorldZ = minZ + current.Z * grid
		local currentSurface = sampleSurface(spec, currentWorldX, currentWorldZ)
		for _, offset in neighbors do
			local nx = current.X + offset.X
			local nz = current.Z + offset.Z
			if nx < 0 or nz < 0 or nx >= width or nz >= depth then
				continue
			end
			local worldX = minX + nx * grid
			local worldZ = minZ + nz * grid
			local surface = sampleSurface(spec, worldX, worldZ)
			local heightStep = math.abs(surface.GroundY - currentSurface.GroundY)
			local isEndpoint = nx == goalX and nz == goalZ
			if not isEndpoint and (surface.SlopeDegrees > Config.PathMaxSlopeDegrees or heightStep > Config.PathMaxStepHeight) then
				continue
			end
			local diagonal = offset.X ~= 0 and offset.Z ~= 0
			local travel = grid * (if diagonal then 1.41421356237 else 1)
			local scenic = unit(spec.WorldSeed, nx, nz, 11) * 1.25
			local tentative = (gScore[currentKey] or math.huge)
				+ travel + heightStep * 2.2 + surface.SlopeDegrees * 0.18 + scenic
			local neighborKey = nodeKey(nx, nz, width)
			if tentative < (gScore[neighborKey] or math.huge) then
				cameFrom[neighborKey] = currentKey
				gScore[neighborKey] = tentative
				fScore[neighborKey] = tentative + heuristic(nx, nz)
				coordinates[neighborKey] = {X = nx, Z = nz}
				open[neighborKey] = true
			end
		end
	end
	assert(found, "Deterministic path solver could not reach the landmark approach")

	local reverseKeys = {goalKey}
	local current = goalKey
	while current ~= startKey do
		current = cameFrom[current]
		assert(current, "Path reconstruction failed")
		table.insert(reverseKeys, current)
	end
	local route: {SurfacePoint} = {}
	for index = #reverseKeys, 1, -1 do
		local coordinate = coordinates[reverseKeys[index]]
		local worldX = minX + coordinate.X * grid
		local worldZ = minZ + coordinate.Z * grid
		table.insert(route, sampleSurface(spec, worldX, worldZ))
	end
	return route
end

local function sampleRoute(spec: WorldSpec, route: {SurfacePoint}): {SurfacePoint}
	local samples: {SurfacePoint} = {}
	for index = 1, #route - 1 do
		local first = route[index]
		local second = route[index + 1]
		local dx = second.WorldX - first.WorldX
		local dz = second.WorldZ - first.WorldZ
		local length = math.sqrt(dx * dx + dz * dz)
		local steps = math.max(1, math.ceil(length / Config.PathPatchSpacing))
		for step = 0, steps - 1 do
			local alpha = step / steps
			table.insert(samples, sampleSurface(spec, first.WorldX + dx * alpha, first.WorldZ + dz * alpha))
		end
	end
	table.insert(samples, route[#route])
	return samples
end

local function distanceToSegmentSquared(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local abx = bx - ax
	local abz = bz - az
	local lengthSquared = abx * abx + abz * abz
	local alpha = if lengthSquared > 0 then math.clamp(((px - ax) * abx + (pz - az) * abz) / lengthSquared, 0, 1) else 0
	local dx = px - (ax + abx * alpha)
	local dz = pz - (az + abz * alpha)
	return dx * dx + dz * dz
end

local function distanceToRouteSquared(route: {SurfacePoint}, worldX: number, worldZ: number): number
	local best = math.huge
	for index = 1, #route - 1 do
		local first = route[index]
		local second = route[index + 1]
		best = math.min(best, distanceToSegmentSquared(
			worldX, worldZ, first.WorldX, first.WorldZ, second.WorldX, second.WorldZ
		))
	end
	return best
end

local function assetIndex(assetId: string): number
	for index, asset in Catalog.Assets do
		if asset.Id == assetId then
			return index
		end
	end
	error("Unknown asset: " .. assetId)
end

local function makePlacement(
	spec: WorldSpec,
	assetId: string,
	worldX: number,
	worldZ: number,
	scale: number,
	yaw: number,
	role: string,
	zoneId: string
): Placement
	local asset = Catalog.ById[assetId]
	assert(asset, "Unknown asset: " .. assetId)
	local surface = sampleSurface(spec, worldX, worldZ)
	return {
		Index = 0,
		AssetId = assetId,
		AssetIndex = assetIndex(assetId),
		WorldX = worldX,
		GroundY = surface.GroundY,
		WorldZ = worldZ,
		Normal = surface.Normal,
		YawRadians = yaw,
		Scale = scale,
		SlopeDegrees = surface.SlopeDegrees,
		SpacingRadius = asset.SpacingRadius * scale,
		Role = role,
		ZoneId = zoneId,
	}
end

local function copyScatter(placement: ScatterPlacement): Placement
	return {
		Index = 0,
		AssetId = placement.AssetId,
		AssetIndex = placement.AssetIndex,
		WorldX = placement.WorldX,
		GroundY = placement.GroundY,
		WorldZ = placement.WorldZ,
		Normal = placement.Normal,
		YawRadians = placement.YawRadians,
		Scale = placement.Scale,
		SlopeDegrees = placement.SlopeDegrees,
		SpacingRadius = placement.SpacingRadius,
		Role = "Scatter",
		ZoneId = "OpenDesert",
	}
end

local function addLandmark(spec: WorldSpec, landmark: Landmark, placements: {Placement})
	for index = 0, 6 do
		local angle = index / 7 * math.pi * 2 + (unit(spec.WorldSeed, index, 1, 21) - 0.5) * 0.12
		local radius = 31 + unit(spec.WorldSeed, index, 1, 22) * 7
		local assetId = if index % 3 == 0 then "WindBoulder" else "LayeredMesa"
		local scale = 1.00 + unit(spec.WorldSeed, index, 1, 23) * 0.48
		table.insert(placements, makePlacement(
			spec,
			assetId,
			landmark.WorldX + math.cos(angle) * radius,
			landmark.WorldZ + math.sin(angle) * radius,
			scale,
			angle + math.pi * 0.5,
			"Landmark",
			landmark.Id
		))
	end
	local base = makePlacement(spec, "LayeredMesa", landmark.WorldX, landmark.WorldZ, 1.82, 0.35, "Landmark", landmark.Id)
	table.insert(placements, base)
	local middle = makePlacement(spec, "WindBoulder", landmark.WorldX + 1.5, landmark.WorldZ - 1, 1.30, 1.8, "Landmark", landmark.Id)
	middle.GroundY += 9.5
	table.insert(placements, middle)
	local cap = makePlacement(spec, "WindBoulder", landmark.WorldX - 1, landmark.WorldZ + 0.5, 0.84, 4.2, "Landmark", landmark.Id)
	cap.GroundY += 18
	table.insert(placements, cap)
end

local function routeDirection(route: {SurfacePoint}, index: number): Vector3
	local first = route[math.max(1, index - 1)]
	local second = route[math.min(#route, index + 1)]
	return Vector3.new(second.WorldX - first.WorldX, 0, second.WorldZ - first.WorldZ).Unit
end

local function addTrailMarkers(spec: WorldSpec, route: {SurfacePoint}, placements: {Placement})
	for markerOrdinal = 1, 3 do
		local index = math.clamp(math.floor(#route * (0.42 + markerOrdinal * 0.13) + 0.5), 3, #route - 2)
		local node = route[index]
		local direction = routeDirection(route, index)
		local side = Vector3.new(-direction.Z, 0, direction.X) * (if markerOrdinal % 2 == 1 then 1 else -1)
		local offset = 22 + unit(spec.WorldSeed, index, 2, 31) * 4
		local worldX = node.WorldX + side.X * offset
		local worldZ = node.WorldZ + side.Z * offset
		if insideWorld(spec, worldX, worldZ) then
			table.insert(placements, makePlacement(
				spec,
				"WindBoulder",
				worldX,
				worldZ,
				0.42 + unit(spec.WorldSeed, index, 2, 32) * 0.28,
				unit(spec.WorldSeed, index, 2, 33) * math.pi * 2,
				"TrailMarker",
				"PilgrimTrail"
			))
		end
	end
end

local function addEcology(spec: WorldSpec, route: {SurfacePoint}, placements: {Placement})
	for cluster = 1, 3 do
		local routeIndex = math.clamp(math.floor(#route * (cluster / 4)), 2, #route - 1)
		local node = route[routeIndex]
		local direction = routeDirection(route, routeIndex)
		local side = Vector3.new(-direction.Z, 0, direction.X) * (if cluster % 2 == 0 then -1 else 1)
		local anchorX = node.WorldX + side.X * (28 + cluster * 3)
		local anchorZ = node.WorldZ + side.Z * (28 + cluster * 3)
		for member = 1, 4 do
			local angle = unit(spec.WorldSeed, cluster, member, 41) * math.pi * 2
			local radius = 3 + unit(spec.WorldSeed, cluster, member, 42) * 13
			local worldX = anchorX + math.cos(angle) * radius
			local worldZ = anchorZ + math.sin(angle) * radius
			if insideWorld(spec, worldX, worldZ) then
				local placement = makePlacement(
					spec,
					"DryShrub",
					worldX,
					worldZ,
					0.48 + unit(spec.WorldSeed, cluster, member, 43) * 0.56,
					angle,
					"Ecology",
					"ShrubPatch" .. cluster
				)
				if placement.SlopeDegrees <= Catalog.ById.DryShrub.MaxSlopeDegrees then
					table.insert(placements, placement)
				end
			end
		end
	end
end

local function addOutcrops(spec: WorldSpec, route: {SurfacePoint}, placements: {Placement})
	for group = 1, 2 do
		local routeIndex = math.clamp(math.floor(#route * (0.32 + group * 0.21)), 2, #route - 1)
		local node = route[routeIndex]
		local direction = routeDirection(route, routeIndex)
		local side = Vector3.new(-direction.Z, 0, direction.X) * (if group == 1 then -1 else 1)
		local anchorX = node.WorldX + side.X * 49
		local anchorZ = node.WorldZ + side.Z * 49
		for member = 1, 3 do
			local angle = (member - 1) / 3 * math.pi * 2 + unit(spec.WorldSeed, group, member, 51) * 0.4
			local radius = 4 + member * 3
			local worldX = anchorX + math.cos(angle) * radius
			local worldZ = anchorZ + math.sin(angle) * radius
			if insideWorld(spec, worldX, worldZ) then
				table.insert(placements, makePlacement(
					spec,
					if member == 1 then "LayeredMesa" else "WindBoulder",
					worldX,
					worldZ,
					0.72 + unit(spec.WorldSeed, group, member, 52) * 0.52,
					angle,
					"Outcrop",
					"RockOutcrop" .. group
				))
			end
		end
	end
end

local function overlapsAccepted(accepted: {Placement}, candidate: Placement): boolean
	for _, other in accepted do
		if candidate.Role == "Landmark" and other.Role == "Landmark" then
			continue
		end
		local dx = candidate.WorldX - other.WorldX
		local dz = candidate.WorldZ - other.WorldZ
		local minimum = candidate.SpacingRadius + other.SpacingRadius
		if dx * dx + dz * dz < minimum * minimum then
			return true
		end
	end
	return false
end

local function repairPlan(spec: WorldSpec, landmark: Landmark, route: {SurfacePoint}, candidates: {Placement}): ({Placement}, RepairStats, boolean)
	local stats: RepairStats = {
		Passes = 0,
		RemovedByBounds = 0,
		RemovedBySpawn = 0,
		RemovedByPath = 0,
		RemovedByLandmark = 0,
		RemovedBySlope = 0,
		RemovedBySpacing = 0,
	}
	local current = candidates
	local revalidated = false
	for pass = 1, Config.RepairPassLimit do
		stats.Passes = pass
		local accepted: {Placement} = {}
		local removed = 0
		for _, placement in current do
			local asset = Catalog.ById[placement.AssetId]
			local dxSpawn = placement.WorldX
			local dzSpawn = placement.WorldZ
			local dxLandmark = placement.WorldX - landmark.WorldX
			local dzLandmark = placement.WorldZ - landmark.WorldZ
			if not insideWorld(spec, placement.WorldX, placement.WorldZ) then
				stats.RemovedByBounds += 1
				removed += 1
			elseif placement.Role ~= "Landmark" and dxSpawn * dxSpawn + dzSpawn * dzSpawn < Config.SpawnSafeRadius ^ 2 then
				stats.RemovedBySpawn += 1
				removed += 1
			elseif placement.Role ~= "Landmark"
				and distanceToRouteSquared(route, placement.WorldX, placement.WorldZ) < Config.PathCorridorRadius ^ 2 then
				stats.RemovedByPath += 1
				removed += 1
			elseif placement.Role ~= "Landmark"
				and dxLandmark * dxLandmark + dzLandmark * dzLandmark < Config.LandmarkClearRadius ^ 2 then
				stats.RemovedByLandmark += 1
				removed += 1
			elseif placement.SlopeDegrees > asset.MaxSlopeDegrees and placement.Role ~= "Landmark" then
				stats.RemovedBySlope += 1
				removed += 1
			elseif overlapsAccepted(accepted, placement) then
				stats.RemovedBySpacing += 1
				removed += 1
			else
				table.insert(accepted, placement)
			end
		end
		current = accepted
		if removed == 0 then
			revalidated = true
			break
		end
	end
	for index, placement in current do
		placement.Index = index
	end
	return current, stats, revalidated
end

local function roleCounts(placements: {Placement}): {[string]: number}
	local counts: {[string]: number} = {}
	for _, placement in placements do
		counts[placement.Role] = (counts[placement.Role] or 0) + 1
	end
	return counts
end

local function signature(spec: WorldSpec, landmark: Landmark, route: {SurfacePoint}, placements: {Placement}, repair: RepairStats): string
	local state = Checksum.New()
	Checksum.UpdateString(state, Config.Version)
	Checksum.UpdateUInt32(state, spec.WorldSeed)
	Checksum.UpdateString(state, landmark.Id)
	Checksum.UpdateUInt32(state, math.floor(landmark.WorldX * 1024 + 0.5))
	Checksum.UpdateUInt32(state, math.floor(landmark.WorldZ * 1024 + 0.5))
	Checksum.UpdateUInt32(state, #route)
	for index, node in route do
		Checksum.UpdateIndexedUInt32(state, index, math.floor(node.WorldX * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(node.GroundY * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(node.WorldZ * 1024 + 0.5))
	end
	Checksum.UpdateUInt32(state, #placements)
	for index, placement in placements do
		Checksum.UpdateIndexedUInt32(state, index, placement.AssetIndex)
		Checksum.UpdateString(state, placement.Role)
		Checksum.UpdateString(state, placement.ZoneId)
		Checksum.UpdateUInt32(state, math.floor(placement.WorldX * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(placement.GroundY * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(placement.WorldZ * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(placement.YawRadians * 65536 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(placement.Scale * 65536 + 0.5))
	end
	Checksum.UpdateUInt32(state, repair.Passes)
	Checksum.UpdateUInt32(state, repair.RemovedByPath)
	Checksum.UpdateUInt32(state, repair.RemovedBySpacing)
	return Checksum.Digest(state)
end

function Planner.DistanceToRouteSquared(route: {SurfacePoint}, worldX: number, worldZ: number): number
	return distanceToRouteSquared(route, worldX, worldZ)
end

function Planner.Plan(spec: WorldSpec): Plan
	local landmark = chooseLandmark(spec)
	local route = buildRoute(spec, landmark)
	local samples = sampleRoute(spec, route)
	local baseScatter = ScatterPlanner.Plan(spec)
	local candidates: {Placement} = {}

	-- Composition-critical placements own priority. Generic scatter is repaired last.
	addLandmark(spec, landmark, candidates)
	addTrailMarkers(spec, samples, candidates)
	addEcology(spec, route, candidates)
	addOutcrops(spec, route, candidates)
	for _, placement in baseScatter.Placements do
		table.insert(candidates, copyScatter(placement))
	end

	local placements, repair, revalidationPassed = repairPlan(spec, landmark, route, candidates)
	assert(#placements <= Config.PropBudget, "Composition exceeded the prop budget")
	local plan: Plan = {
		Version = Config.Version,
		WorldSeed = spec.WorldSeed,
		Landmark = landmark,
		RouteNodes = route,
		PathSamples = samples,
		Placements = placements,
		RoleCounts = roleCounts(placements),
		Repair = repair,
		RevalidationPassed = revalidationPassed,
		BaseScatterCount = #baseScatter.Placements,
		Signature = "",
	}
	plan.Signature = signature(spec, landmark, route, placements, repair)
	return plan
end

return table.freeze(Planner)
