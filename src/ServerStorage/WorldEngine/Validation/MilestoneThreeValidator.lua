--!strict

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Catalog = require(WorldEngine.Assets.Rocks.RockCatalog)
local Checksum = require(WorldEngine.Core.Checksum)
local Config = require(WorldEngine.Config.Composition.DesertPilgrimage)
local Planner = require(WorldEngine.Planning.DesertCompositionPlanner)

type Plan = Planner.Plan
type Placement = Planner.Placement

local Validator = {}

local function overlap(left: Placement, right: Placement): boolean
	local dx = left.WorldX - right.WorldX
	local dz = left.WorldZ - right.WorldZ
	local minimum = left.SpacingRadius + right.SpacingRadius
	return dx * dx + dz * dz < minimum * minimum
end

function Validator.ValidatePlan(spec, plan: Plan)
	local pathSlopeViolations = 0
	local pathStepViolations = 0
	for index, node in plan.RouteNodes do
		if node.SlopeDegrees > Config.PathMaxSlopeDegrees and index ~= #plan.RouteNodes then
			pathSlopeViolations += 1
		end
		if index > 1 and math.abs(node.GroundY - plan.RouteNodes[index - 1].GroundY) > Config.PathMaxStepHeight then
			pathStepViolations += 1
		end
	end

	local spawnViolations = 0
	local pathBlockers = 0
	local landmarkClearViolations = 0
	local slopeViolations = 0
	local boundsViolations = 0
	local overlapViolations = 0
	for index, placement in plan.Placements do
		local asset = Catalog.ById[placement.AssetId]
		if placement.Role ~= "Landmark"
			and placement.WorldX * placement.WorldX + placement.WorldZ * placement.WorldZ < Config.SpawnSafeRadius ^ 2 then
			spawnViolations += 1
		end
		if placement.Role ~= "Landmark"
			and Planner.DistanceToRouteSquared(plan.RouteNodes, placement.WorldX, placement.WorldZ) < Config.PathCorridorRadius ^ 2 then
			pathBlockers += 1
		end
		local dxLandmark = placement.WorldX - plan.Landmark.WorldX
		local dzLandmark = placement.WorldZ - plan.Landmark.WorldZ
		if placement.Role ~= "Landmark"
			and dxLandmark * dxLandmark + dzLandmark * dzLandmark < Config.LandmarkClearRadius ^ 2 then
			landmarkClearViolations += 1
		end
		if placement.Role ~= "Landmark" and placement.SlopeDegrees > asset.MaxSlopeDegrees then
			slopeViolations += 1
		end
		if placement.WorldX < spec.OriginX + Config.WorldEdgeMargin
			or placement.WorldZ < spec.OriginZ + Config.WorldEdgeMargin
			or placement.WorldX > spec.OriginX + spec.WorldSize - Config.WorldEdgeMargin
			or placement.WorldZ > spec.OriginZ + spec.WorldSize - Config.WorldEdgeMargin then
			boundsViolations += 1
		end
		for otherIndex = index + 1, #plan.Placements do
			local other = plan.Placements[otherIndex]
			if not (placement.Role == "Landmark" and other.Role == "Landmark") and overlap(placement, other) then
				overlapViolations += 1
			end
		end
	end

	local start = plan.RouteNodes[1]
	local finish = plan.RouteNodes[#plan.RouteNodes]
	local startDistance = math.sqrt(start.WorldX ^ 2 + start.WorldZ ^ 2)
	local endDx = finish.WorldX - plan.Landmark.ApproachX
	local endDz = finish.WorldZ - plan.Landmark.ApproachZ
	local endDistance = math.sqrt(endDx * endDx + endDz * endDz)
	local landmarkRadius = math.sqrt(plan.Landmark.WorldX ^ 2 + plan.Landmark.WorldZ ^ 2)
	local roleCoverage = (plan.RoleCounts.Landmark or 0) >= 8
		and (plan.RoleCounts.TrailMarker or 0) >= 3
		and (plan.RoleCounts.Ecology or 0) >= 3
		and (plan.RoleCounts.Scatter or 0) >= 8

	local assertions = {
		VersionMatches = plan.Version == Config.Version,
		SeedMatches = plan.WorldSeed == spec.WorldSeed,
		RouteHasUsefulLength = #plan.RouteNodes >= 6,
		PathSamplesCoverRoute = #plan.PathSamples > #plan.RouteNodes,
		PathSlopeSafe = pathSlopeViolations == 0,
		PathStepSafe = pathStepViolations == 0,
		SpawnConnectsToRoute = startDistance <= Config.PathGridSize,
		RouteReachesLandmarkApproach = endDistance <= Config.PathGridSize,
		LandmarkInTargetRing = landmarkRadius >= Config.LandmarkMinRadius and landmarkRadius <= Config.LandmarkMaxRadius,
		RoleCoverage = roleCoverage,
		NoSpawnViolations = spawnViolations == 0,
		NoPathBlockers = pathBlockers == 0,
		LandmarkPlazaClear = landmarkClearViolations == 0,
		NoSlopeViolations = slopeViolations == 0,
		NoBoundsViolations = boundsViolations == 0,
		NoSpacingViolations = overlapViolations == 0,
		RepairConverged = plan.RevalidationPassed and plan.Repair.Passes <= Config.RepairPassLimit,
		WithinPropBudget = #plan.Placements <= Config.PropBudget,
	}
	local passed = true
	for _, assertion in assertions do
		passed = passed and assertion
	end
	return {
		Passed = passed,
		Assertions = assertions,
		Signature = plan.Signature,
		PropCount = #plan.Placements,
		RoleCounts = plan.RoleCounts,
		RouteNodeCount = #plan.RouteNodes,
		PathSampleCount = #plan.PathSamples,
		PathSlopeViolations = pathSlopeViolations,
		PathStepViolations = pathStepViolations,
		PathBlockers = pathBlockers,
		SpawnViolations = spawnViolations,
		LandmarkClearViolations = landmarkClearViolations,
		SlopeViolations = slopeViolations,
		BoundsViolations = boundsViolations,
		OverlapViolations = overlapViolations,
		Repair = plan.Repair,
		StartDistance = startDistance,
		EndDistance = endDistance,
	}
end

function Validator.CaptureMaterialized()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local props = generated:FindFirstChild("DesertProps")
	local paths = generated:FindFirstChild("Paths")
	if not props or not paths then
		return {
			Signature = "missing",
			Passed = false,
			ModelCount = 0,
			PathPatchCount = 0,
			InvalidModels = 1,
			InvalidPathPatches = 1,
			CollisionProxyCount = 0,
			GeneratedDescendantCount = #generated:GetDescendants(),
		}
	end

	local models = props:GetChildren()
	table.sort(models, function(left, right)
		return (left:GetAttribute("PlacementIndex") or 0) < (right:GetAttribute("PlacementIndex") or 0)
	end)
	local patches = paths:GetChildren()
	table.sort(patches, function(left, right)
		return (left:GetAttribute("PathIndex") or 0) < (right:GetAttribute("PathIndex") or 0)
	end)
	local state = Checksum.New()
	Checksum.UpdateString(state, Config.Version)
	Checksum.UpdateUInt32(state, #models)
	local invalidModels = 0
	local collisionProxyCount = 0
	local roleCounts: {[string]: number} = {}
	for index, instance in models do
		if not instance:IsA("Model") then
			invalidModels += 1
			continue
		end
		local assetId = instance:GetAttribute("SourceAsset")
		local role = instance:GetAttribute("CompositionRole")
		local zone = instance:GetAttribute("CompositionZone")
		if type(assetId) ~= "string" or not Catalog.ById[assetId]
			or type(role) ~= "string" or type(zone) ~= "string"
			or instance:GetAttribute("CompositionVersion") ~= Config.Version then
			invalidModels += 1
			continue
		end
		roleCounts[role] = (roleCounts[role] or 0) + 1
		local collision = instance:FindFirstChild("Collision")
		if collision and collision:IsA("BasePart") and collision.Anchored and collision.CanCollide then
			collisionProxyCount += 1
		else
			invalidModels += 1
		end
		local pivot = instance:GetPivot()
		Checksum.UpdateIndexedUInt32(state, index, instance:GetAttribute("PlacementIndex") or 0)
		Checksum.UpdateString(state, assetId)
		Checksum.UpdateString(state, role)
		Checksum.UpdateString(state, zone)
		Checksum.UpdateUInt32(state, math.floor(pivot.Position.X * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(pivot.Position.Y * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(pivot.Position.Z * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(instance:GetScale() * 65536 + 0.5))
	end

	Checksum.UpdateUInt32(state, #patches)
	local invalidPathPatches = 0
	for index, instance in patches do
		if not instance:IsA("BasePart") or not instance.Anchored or instance.CanCollide
			or instance:GetAttribute("PathIndex") ~= index
			or instance:GetAttribute("CompositionVersion") ~= Config.Version then
			invalidPathPatches += 1
			continue
		end
		Checksum.UpdateIndexedUInt32(state, index, math.floor(instance.Position.X * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(instance.Position.Y * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(instance.Position.Z * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(instance.Size.X * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(instance.Size.Z * 1024 + 0.5))
	end
	local descendantCount = #generated:GetDescendants()
	local baseplateAbsent = Workspace:FindFirstChild("Baseplate") == nil
	local passed = invalidModels == 0
		and invalidPathPatches == 0
		and collisionProxyCount == #models
		and descendantCount <= Config.GeneratedDescendantBudget
		and baseplateAbsent
	return {
		Passed = passed,
		Signature = Checksum.Digest(state),
		ModelCount = #models,
		PathPatchCount = #patches,
		InvalidModels = invalidModels,
		InvalidPathPatches = invalidPathPatches,
		CollisionProxyCount = collisionProxyCount,
		RoleCounts = roleCounts,
		GeneratedDescendantCount = descendantCount,
		WithinInstanceBudget = descendantCount <= Config.GeneratedDescendantBudget,
		BaseplateAbsent = baseplateAbsent,
	}
end

function Validator.ValidateMaterializedAgainstPlan(plan: Plan)
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local props = generated:FindFirstChild("DesertProps")
	local paths = generated:FindFirstChild("Paths")
	local positionMismatches = 0
	local metadataMismatches = 0
	if not props or not paths then
		return {Passed = false, PositionMismatches = #plan.Placements, MetadataMismatches = #plan.Placements}
	end
	for _, placement in plan.Placements do
		local asset = Catalog.ById[placement.AssetId]
		local model = props:FindFirstChild(string.format("%03d_%s", placement.Index, placement.AssetId))
		if not model or not model:IsA("Model") then
			positionMismatches += 1
			metadataMismatches += 1
			continue
		end
		local expected = Vector3.new(
			placement.WorldX,
			placement.GroundY - asset.SinkStuds * placement.Scale,
			placement.WorldZ
		)
		if (model:GetPivot().Position - expected).Magnitude > 0.001 then
			positionMismatches += 1
		end
		if model:GetAttribute("CompositionRole") ~= placement.Role
			or model:GetAttribute("CompositionZone") ~= placement.ZoneId then
			metadataMismatches += 1
		end
	end
	local start = plan.RouteNodes[1]
	local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
	local spawnPassed = spawn ~= nil
		and not spawn.CanCollide
		and spawn.Transparency == 1
		and Vector2.new(spawn.Position.X - start.WorldX, spawn.Position.Z - start.WorldZ).Magnitude <= 0.001
		and spawn:FindFirstChildOfClass("Decal") == nil
	local pathCountMatches = #paths:GetChildren() == #plan.PathSamples
	return {
		Passed = positionMismatches == 0 and metadataMismatches == 0 and spawnPassed and pathCountMatches,
		PositionMismatches = positionMismatches,
		MetadataMismatches = metadataMismatches,
		SpawnPassed = spawnPassed,
		PathCountMatches = pathCountMatches,
	}
end

return table.freeze(Validator)
