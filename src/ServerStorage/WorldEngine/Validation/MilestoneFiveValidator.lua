--!strict

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Catalog = require(WorldEngine.Assets.Rocks.RockCatalog)
local Checksum = require(WorldEngine.Core.Checksum)
local Config = require(WorldEngine.Config.Composition.DesertWorldComposition)
local M4Validator = require(WorldEngine.Validation.MilestoneFourValidator)
local Planner = require(WorldEngine.Planning.WorldCompositionPlanner)

type Plan = Planner.Plan

local Validator = {}

local function countKeys(values): number
	local count = 0
	for _ in values do count += 1 end
	return count
end

local function routeViolations(plan: Plan): (number, number, number)
	local slope, step, blockers = 0, 0, 0
	for _, route in plan.Routes do
		for index, node in route.Nodes do
			if node.SlopeDegrees > Config.RouteMaxSlopeDegrees then slope += 1 end
			if index > 1 and math.abs(node.GroundY - route.Nodes[index - 1].GroundY) > Config.RouteMaxStepHeight then step += 1 end
		end
		for _, placement in plan.Placements do
			if placement.Role ~= "Landmark" and Planner.DistanceToRouteSquared(route, placement.WorldX, placement.WorldZ)
				< Config.RouteCorridorRadius ^ 2 then blockers += 1 end
		end
	end
	return slope, step, blockers
end

function Validator.ValidatePlan(plan: Plan, identityAudit)
	local m4 = M4Validator.ValidatePlan(plan.CompositionInput, plan.Variation, identityAudit)
	local totalCells = 0
	for _, count in plan.RegionCellCounts do totalCells += count end
	local undercovered, dominant = 0, 0
	for _, region in plan.Regions do
		local count = plan.RegionCellCounts[region.Id] or 0
		if count < Config.MinimumRegionCoverageCells then undercovered += 1 end
		if totalCells > 0 and count / totalCells > Config.MaximumRegionCoverageFraction then dominant += 1 end
	end
	local missingRegionGrammar = 0
	for _, region in plan.Regions do
		local counts = plan.RegionPlacementCounts[region.Id]
		if not counts or (counts.Total or 0) < 2 then missingRegionGrammar += 1 end
	end
	local wadi = plan.RegionPlacementCounts.WadiGardens or {}
	local hamada = plan.RegionPlacementCounts.HamadaShelf or {}
	local routeSlopeViolations, routeStepViolations, routeBlockers = routeViolations(plan)
	local invalidVistas = 0
	for _, vista in plan.Vistas do
		if not vista.LineOfSightClear or vista.Distance < Config.VistaMinimumDistance
			or vista.Distance > Config.VistaMaximumDistance or vista.Score <= 0 then invalidVistas += 1 end
	end
	local landmarkIds: {[string]: boolean} = {}
	for _, landmark in plan.Landmarks do landmarkIds[landmark.Id] = true end
	local connectedLandmarks = 0
	for _, route in plan.Routes do
		if route.Reachable and landmarkIds[route.LandmarkId] and #route.Nodes >= 2 and #route.Samples >= #route.Nodes then
			connectedLandmarks += 1
		end
	end
	local assertions = {
		VersionMatches = plan.Version == Config.Version,
		SeedMatches = plan.WorldSeed == plan.BaseComposition.WorldSeed,
		FourDistinctRegions = #plan.Regions == 4 and countKeys(plan.RegionCellCounts) == 4,
		RegionCoverageBalanced = undercovered == 0 and dominant == 0,
		FourLandmarks = #plan.Landmarks == 4 and countKeys(landmarkIds) == 4,
		AllLandmarksConnected = #plan.Routes == 4 and connectedLandmarks == 4,
		RoutesWalkableOnPlan = routeSlopeViolations == 0 and routeStepViolations == 0 and routeBlockers == 0,
		OneClearVistaPerLandmark = #plan.Vistas == #plan.Landmarks and invalidVistas == 0,
		RegionalGrammarPopulated = missingRegionGrammar == 0,
		WadiReadsAsVegetation = (wadi.Vegetation or 0) > (wadi.Rock or 0),
		HamadaReadsAsRockShelf = (hamada.Rock or 0) >= 5 and (hamada.Rock or 0) > (hamada.Vegetation or 0),
		VistaFramingPresent = (plan.RoleCounts.VistaFrame or 0) >= 4,
		RepairRevalidated = plan.RevalidationPassed,
		WithinPlacementBudget = #plan.Placements <= Config.MaximumPlacements,
		WithinVariationBudget = #plan.Variation.Variants <= Config.MaximumVariants,
		WithinComponentBudget = plan.Variation.ComponentCount <= Config.MaximumComponents,
		MilestoneFourVariationStillPasses = m4.Passed,
	}
	local passed = true
	for _, assertion in assertions do passed = passed and assertion end
	return {
		Passed = passed, Assertions = assertions, M4Validation = m4,
		RegionCount = #plan.Regions, LandmarkCount = #plan.Landmarks, RouteCount = #plan.Routes,
		VistaCount = #plan.Vistas, PlacementCount = #plan.Placements,
		VariantCount = #plan.Variation.Variants, ComponentCount = plan.Variation.ComponentCount,
		TotalRegionCells = totalCells, UndercoveredRegions = undercovered, DominantRegions = dominant,
		MissingRegionGrammar = missingRegionGrammar, InvalidVistas = invalidVistas,
		RouteSlopeViolations = routeSlopeViolations, RouteStepViolations = routeStepViolations,
		RouteBlockers = routeBlockers, RegionCellCounts = plan.RegionCellCounts,
		RegionPlacementCounts = plan.RegionPlacementCounts, RoleCounts = plan.RoleCounts,
		Signature = plan.Signature,
	}
end

local function colorByte(value: number): number
	return math.floor(math.clamp(value, 0, 1) * 255 + 0.5)
end

function Validator.CaptureMaterialized()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local composition = generated:FindFirstChild("WorldComposition")
	local props = generated:FindFirstChild("DesertProps")
	if not composition or not composition:IsA("Folder") or not props or not props:IsA("Folder") then
		return {Passed = false, Signature = "missing", InvalidInstances = 1}
	end
	local branches = composition:FindFirstChild("BranchRoutes")
	local regions = composition:FindFirstChild("RegionAnchors")
	local landmarks = composition:FindFirstChild("LandmarkAnchors")
	local vistas = composition:FindFirstChild("VistaAnchors")
	if not branches or not regions or not landmarks or not vistas then
		return {Passed = false, Signature = "missing-structure", InvalidInstances = 1}
	end
	local state = Checksum.New()
	Checksum.UpdateString(state, Config.Version)
	local invalid = 0
	local branchPatchCount = 0
	local branchFolders = branches:GetChildren()
	table.sort(branchFolders, function(a, b) return a.Name < b.Name end)
	for folderIndex, folder in branchFolders do
		Checksum.UpdateIndexedUInt32(state, folderIndex, #folder:GetChildren())
		Checksum.UpdateString(state, folder.Name)
		local patches = folder:GetChildren()
		table.sort(patches, function(a, b) return (a:GetAttribute("RouteSampleIndex") or 0) < (b:GetAttribute("RouteSampleIndex") or 0) end)
		for patchIndex, patch in patches do
			branchPatchCount += 1
			if not patch:IsA("BasePart") or not patch.Anchored or patch.CanCollide or patch.CanQuery
				or patch:GetAttribute("Milestone5Version") ~= Config.Version
				or patch:GetAttribute("RouteSampleIndex") ~= patchIndex then invalid += 1 continue end
			Checksum.UpdateIndexedUInt32(state, patchIndex, math.floor(patch.Position.X * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(patch.Position.Y * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(patch.Position.Z * 1024 + 0.5))
			Checksum.UpdateString(state, patch:GetAttribute("RouteId") or "")
		end
	end
	local function captureAnchors(folder: Instance, idAttribute: string): number
		local children = folder:GetChildren()
		table.sort(children, function(a, b) return a.Name < b.Name end)
		for index, anchor in children do
			if not anchor:IsA("BasePart") or anchor.Transparency ~= 1 or not anchor.Anchored
				or anchor.CanCollide or anchor.CanQuery or anchor:GetAttribute("Milestone5Version") ~= Config.Version
				or type(anchor:GetAttribute(idAttribute)) ~= "string" then invalid += 1 continue end
			Checksum.UpdateIndexedUInt32(state, index, math.floor(anchor.Position.X * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(anchor.Position.Y * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(anchor.Position.Z * 1024 + 0.5))
			Checksum.UpdateString(state, anchor:GetAttribute(idAttribute))
		end
		return #children
	end
	local regionAnchorCount = captureAnchors(regions, "RegionId")
	local landmarkAnchorCount = captureAnchors(landmarks, "LandmarkId")
	local vistaAnchorCount = captureAnchors(vistas, "VistaId")
	local variantCount = 0
	for _, instance in props:GetChildren() do
		if not instance:IsA("Model") then invalid += 1 continue end
		variantCount += 1
		if instance:GetAttribute("Milestone5Version") ~= Config.Version
			or type(instance:GetAttribute("RegionId")) ~= "string"
			or type(instance:GetAttribute("CompositionLayer")) ~= "string" then invalid += 1 end
		Checksum.UpdateString(state, instance:GetAttribute("RegionId") or "")
		Checksum.UpdateString(state, instance:GetAttribute("LandmarkId") or "")
		Checksum.UpdateString(state, instance:GetAttribute("VistaId") or "")
		local descendants = instance:GetDescendants()
		table.sort(descendants, function(a, b) return a:GetFullName() < b:GetFullName() end)
		for _, descendant in descendants do
			if descendant:IsA("MeshPart") and descendant:GetAttribute("WorldEngineLODLevel") ~= nil then
				Checksum.UpdateByte(state, colorByte(descendant.Color.R))
				Checksum.UpdateByte(state, colorByte(descendant.Color.G))
				Checksum.UpdateByte(state, colorByte(descendant.Color.B))
			end
		end
	end
	local descendants = #generated:GetDescendants()
	local passed = invalid == 0 and regionAnchorCount == 4 and landmarkAnchorCount == 4 and vistaAnchorCount == 4
		and #branchFolders == 3 and branchPatchCount > 15 and descendants <= Config.GeneratedDescendantBudget
	return {
		Passed = passed, Signature = Checksum.Digest(state), InvalidInstances = invalid,
		BranchRouteCount = #branchFolders, BranchPatchCount = branchPatchCount,
		RegionAnchorCount = regionAnchorCount, LandmarkAnchorCount = landmarkAnchorCount,
		VistaAnchorCount = vistaAnchorCount, VariantCount = variantCount,
		GeneratedDescendantCount = descendants, WithinInstanceBudget = descendants <= Config.GeneratedDescendantBudget,
	}
end

function Validator.ValidateMaterializedAgainstPlan(plan: Plan)
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local composition = generated:FindFirstChild("WorldComposition")
	local props = generated:FindFirstChild("DesertProps")
	if not composition or not props then return {Passed = false, Mismatches = 1} end
	local mismatches = 0
	local expectedPatches = 0
	for _, route in plan.Routes do if route.Kind ~= "Primary" then expectedPatches += #route.Samples end end
	local branches = composition:FindFirstChild("BranchRoutes")
	local actualPatches = if branches then #branches:GetDescendants() - #branches:GetChildren() else 0
	if actualPatches ~= expectedPatches then mismatches += 1 end
	for _, variant in plan.Variation.Variants do
		local placement = plan.Placements[variant.BasePlacementIndex]
		local model = props:FindFirstChild(string.format("%03d_%s_%s", variant.Index, variant.AssetId, variant.RecipeId))
		if not placement or not model or model:GetAttribute("RegionId") ~= placement.RegionId
			or model:GetAttribute("LandmarkId") ~= placement.LandmarkId
			or model:GetAttribute("VistaId") ~= placement.VistaId
			or model:GetAttribute("CompositionLayer") ~= placement.CompositionLayer then mismatches += 1 end
	end
	return {Passed = mismatches == 0, Mismatches = mismatches, ExpectedBranchPatches = expectedPatches, ActualBranchPatches = actualPatches}
end

return table.freeze(Validator)
