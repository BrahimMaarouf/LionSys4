--!strict

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Checksum = require(WorldEngine.Core.Checksum)
local Config = require(WorldEngine.Config.Polish.DesertSurfacePolish)
local HeightfieldPlanner = require(WorldEngine.Planning.HeightfieldPlanner)
local CompositionPlanner = require(WorldEngine.Planning.WorldCompositionPlanner)
local Planner = require(WorldEngine.Planning.SurfacePolishPlanner)
local M5Validator = require(WorldEngine.Validation.MilestoneFiveValidator)

type WorldSpec = HeightfieldPlanner.WorldSpec
type Plan = Planner.Plan

local Validator = {}

local function near(left: number, right: number, epsilon: number?): boolean
	return math.abs(left - right) <= (epsilon or 0.0001)
end

local function countKeys(values): number
	local count = 0
	for _ in values do count += 1 end
	return count
end

local function detailSafetyViolations(spec: WorldSpec, plan: Plan): number
	local violations = 0
	for index, detail in plan.Details do
		if detail.Index ~= index or detail.Width <= 0 or detail.Height <= 0 or detail.Depth <= 0
			or detail.SlopeDegrees > Config.DetailMaximumSlope
			or detail.WorldX ^ 2 + detail.WorldZ ^ 2 < Config.DetailSpawnRadius ^ 2 then
			violations += 1
		end
		for _, route in plan.Composition.Routes do
			if CompositionPlanner.DistanceToRouteSquared(route, detail.WorldX, detail.WorldZ) < Config.DetailRouteClearance ^ 2 then
				violations += 1
				break
			end
		end
		for otherIndex = 1, index - 1 do
			local other = plan.Details[otherIndex]
			if (detail.WorldX - other.WorldX) ^ 2 + (detail.WorldZ - other.WorldZ) ^ 2 < Config.DetailMinimumSpacing ^ 2 then
				violations += 1
				break
			end
		end
	end
	return violations
end

function Validator.ValidatePlan(spec: WorldSpec, plan: Plan, identityAudit)
	local m5 = M5Validator.ValidatePlan(plan.Composition, identityAudit)
	local totalCells = 0
	for _, count in plan.MaterialCounts do totalCells += count end
	local regionDetailCoverage = true
	for _, region in plan.Composition.Regions do
		regionDetailCoverage = regionDetailCoverage and (plan.RegionDetailCounts[region.Id] or 0) >= Config.MinimumDetailsPerRegion
	end
	local erg = plan.RegionMaterialCounts.ErgDunes or {}
	local wadi = plan.RegionMaterialCounts.WadiGardens or {}
	local hamada = plan.RegionMaterialCounts.HamadaShelf or {}
	local crown = plan.RegionMaterialCounts.CrownHighlands or {}
	local detailViolations = detailSafetyViolations(spec, plan)
	local assertions = {
		VersionMatches = plan.Version == Config.Version,
		SeedMatches = plan.WorldSeed == spec.WorldSeed,
		CompositionPreserved = plan.Composition.Signature ~= "" and m5.Passed,
		EverySurfaceCellPlanned = totalCells == plan.Width * plan.Depth and totalCells == (spec.WorldSize / spec.Resolution) ^ 2,
		FiveMaterialPaletteUsed = countKeys(plan.MaterialCounts) == #Config.Materials
			and (plan.MaterialCounts.Mud or 0) >= 100,
		ErgReadsAsSand = (erg.Sand or 0) > (erg.Sandstone or 0) * 3,
		WadiReadsAsDryBed = (wadi.Ground or 0) + (wadi.Mud or 0) > (wadi.Sand or 0) * 5,
		HamadaReadsAsStone = (hamada.Rock or 0) + (hamada.Sandstone or 0) > (hamada.Sand or 0) * 20,
		HighlandsReadAsStrata = (crown.Rock or 0) + (crown.Sandstone or 0) > (crown.Sand or 0) * 3,
		RoutesReceiveSurfaceTreatment = plan.RouteSurfaceCellCount >= 150,
		DetailGrammarComplete = #plan.Details >= 60 and #plan.Details <= Config.MaximumDetails
			and countKeys(plan.DetailCounts) == #Config.DetailOrder,
		EveryRegionHasDetail = regionDetailCoverage,
		DetailsAreSafe = detailViolations == 0,
	}
	local passed = true
	for _, assertion in assertions do passed = passed and assertion end
	return {
		Passed = passed, Assertions = assertions, M5Validation = m5,
		SurfaceCellCount = totalCells, MaterialCounts = plan.MaterialCounts,
		RegionMaterialCounts = plan.RegionMaterialCounts, RouteSurfaceCellCount = plan.RouteSurfaceCellCount,
		DetailCount = #plan.Details, DetailCounts = plan.DetailCounts,
		RegionDetailCounts = plan.RegionDetailCounts, DetailSafetyViolations = detailViolations,
		RejectedDetailCandidates = plan.RejectedDetailCandidates, Signature = plan.Signature,
	}
end

local function terrainRegion(spec: WorldSpec, chunkX: number, chunkZ: number): Region3
	local minX = spec.OriginX + chunkX * spec.ChunkSize
	local minZ = spec.OriginZ + chunkZ * spec.ChunkSize
	return Region3.new(Vector3.new(minX, spec.MinY, minZ), Vector3.new(minX + spec.ChunkSize, spec.MaxY, minZ + spec.ChunkSize))
end

local function expectedSurfaceSignature(spec: WorldSpec, plan: Plan): string
	local state = Checksum.New()
	Checksum.UpdateString(state, Config.Version)
	Checksum.UpdateString(state, spec.Name)
	Checksum.UpdateUInt32(state, spec.WorldSeed)
	Checksum.UpdateUInt32(state, plan.Width)
	for index = 0, plan.Width * plan.Depth - 1 do
		local material = Planner.MaterialForCode(buffer.readu8(plan.MaterialCodes, index))
		Checksum.UpdateIndexedUInt32(state, index, material.Value)
	end
	return Checksum.Digest(state)
end

local function captureSurface(spec: WorldSpec)
	local state = Checksum.New()
	local width = spec.WorldSize / spec.Resolution
	Checksum.UpdateString(state, Config.Version)
	Checksum.UpdateString(state, spec.Name)
	Checksum.UpdateUInt32(state, spec.WorldSeed)
	Checksum.UpdateUInt32(state, width)
	local counts: {[string]: number} = {}
	local missingColumns = 0
	local capturedValues = buffer.create(width * width * 2)
	local chunkCount = spec.WorldSize / spec.ChunkSize
	local chunkCells = spec.ChunkSize / spec.Resolution
	for chunkZ = 0, chunkCount - 1 do
		for chunkX = 0, chunkCount - 1 do
			local materials, occupancies = Workspace.Terrain:ReadVoxels(terrainRegion(spec, chunkX, chunkZ), spec.Resolution)
			for x = 1, #materials do
				for z = 1, #materials[x][1] do
					local surfaceMaterial = Enum.Material.Air
					for y = #materials[x], 1, -1 do
						if occupancies[x][y][z] > 0 and materials[x][y][z] ~= Enum.Material.Air then
							surfaceMaterial = materials[x][y][z]
							break
						end
					end
					local globalX = chunkX * chunkCells + x - 1
					local globalZ = chunkZ * chunkCells + z - 1
					local index = globalZ * width + globalX
					buffer.writeu16(capturedValues, index * 2, surfaceMaterial.Value)
					counts[surfaceMaterial.Name] = (counts[surfaceMaterial.Name] or 0) + 1
					if surfaceMaterial == Enum.Material.Air then missingColumns += 1 end
				end
			end
		end
	end
	for index = 0, width * width - 1 do
		Checksum.UpdateIndexedUInt32(state, index, buffer.readu16(capturedValues, index * 2))
	end
	return {Signature = Checksum.Digest(state), MaterialCounts = counts, MissingColumns = missingColumns}
end

local function captureDetails(folder: Instance)
	local children = folder:GetChildren()
	table.sort(children, function(a, b) return (a:GetAttribute("DetailIndex") or 0) < (b:GetAttribute("DetailIndex") or 0) end)
	local state = Checksum.New()
	local invalid = 0
	local kinds: {[string]: number} = {}
	for index, instance in children do
		if not instance:IsA("BasePart") then invalid += 1 continue end
		local kind = instance:GetAttribute("DetailKind")
		if instance:GetAttribute("DetailIndex") ~= index or type(kind) ~= "string"
			or type(instance:GetAttribute("RegionId")) ~= "string"
			or instance:GetAttribute("Milestone6Version") ~= Config.Version
			or not instance.Anchored or instance.CanCollide or instance.CanQuery or instance.CanTouch then
			invalid += 1
		end
		kinds[kind or "missing"] = (kinds[kind or "missing"] or 0) + 1
		Checksum.UpdateIndexedUInt32(state, index, math.floor(instance.Position.X * 1024 + 0.5))
		Checksum.UpdateString(state, kind or "")
		Checksum.UpdateString(state, instance:GetAttribute("RegionId") or "")
		Checksum.UpdateUInt32(state, math.floor(instance.Position.Y * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(instance.Position.Z * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(instance.Size.X * 4096 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(instance.Size.Y * 4096 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(instance.Size.Z * 4096 + 0.5))
	end
	return {Signature = Checksum.Digest(state), Count = #children, Invalid = invalid, KindCounts = kinds}
end

local function validateLighting(): boolean
	local bloom = Lighting:FindFirstChild("WorldEngineBloom")
	local depth = Lighting:FindFirstChild("WorldEngineDepthOfField")
	local atmosphere = Lighting:FindFirstChild("WorldEngineAtmosphere")
	local clouds = Workspace.Terrain:FindFirstChild("WorldEngineClouds")
	return bloom ~= nil and bloom:IsA("BloomEffect") and near(bloom.Intensity, Config.Bloom.Intensity)
		and near(bloom.Size, Config.Bloom.Size) and near(bloom.Threshold, Config.Bloom.Threshold)
		and depth ~= nil and depth:IsA("DepthOfFieldEffect")
		and near(depth.FarIntensity, Config.DepthOfField.FarIntensity)
		and near(depth.FocusDistance, Config.DepthOfField.FocusDistance)
		and near(depth.InFocusRadius, Config.DepthOfField.InFocusRadius)
		and atmosphere ~= nil and atmosphere:IsA("Atmosphere")
		and near(atmosphere.Density, Config.Atmosphere.Density) and near(atmosphere.Haze, Config.Atmosphere.Haze)
		and clouds ~= nil and clouds:IsA("Clouds") and near(clouds.Cover, Config.Clouds.Cover)
		and near(clouds.Density, Config.Clouds.Density)
end

function Validator.CaptureMaterialized(spec: WorldSpec)
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local polish = generated:FindFirstChild("EnvironmentPolish")
	if not polish or not polish:IsA("Folder") then return {Passed = false, Signature = "missing", InvalidInstances = 1} end
	local detailFolder = polish:FindFirstChild("SurfaceDetails")
	local atmosphereFolder = polish:FindFirstChild("AtmosphereAnchors")
	if not detailFolder or not atmosphereFolder then return {Passed = false, Signature = "missing-structure", InvalidInstances = 1} end
	local surface = captureSurface(spec)
	local details = captureDetails(detailFolder)
	local invalidAtmosphere = 0
	local emitterCount = 0
	for _, anchor in atmosphereFolder:GetChildren() do
		if not anchor:IsA("BasePart") or not anchor.Anchored or anchor.Transparency ~= 1
			or anchor.CanCollide or anchor.CanQuery or type(anchor:GetAttribute("RegionId")) ~= "string"
			or anchor:GetAttribute("Milestone6Version") ~= Config.Version then invalidAtmosphere += 1 end
		local emitter = anchor:FindFirstChild("RegionalDust")
		if emitter and emitter:IsA("ParticleEmitter") and emitter:GetAttribute("Milestone6Version") == Config.Version then
			emitterCount += 1
		else
			invalidAtmosphere += 1
		end
	end
	local lightingPassed = validateLighting()
	local descendants = #generated:GetDescendants()
	local state = Checksum.New()
	Checksum.UpdateString(state, Config.Version)
	Checksum.UpdateString(state, surface.Signature)
	Checksum.UpdateString(state, details.Signature)
	Checksum.UpdateUInt32(state, emitterCount)
	Checksum.UpdateUInt32(state, if lightingPassed then 1 else 0)
	local passed = surface.MissingColumns == 0 and details.Invalid == 0
		and invalidAtmosphere == 0 and emitterCount == Config.AtmosphereEmitterCount
		and lightingPassed and descendants <= Config.GeneratedDescendantBudget
	return {
		Passed = passed, Signature = Checksum.Digest(state), SurfaceSignature = surface.Signature,
		MaterialCounts = surface.MaterialCounts, MissingSurfaceColumns = surface.MissingColumns,
		DetailSignature = details.Signature, DetailCount = details.Count, DetailKindCounts = details.KindCounts,
		InvalidInstances = details.Invalid + invalidAtmosphere, AtmosphereEmitterCount = emitterCount,
		LightingPassed = lightingPassed, GeneratedDescendantCount = descendants,
		WithinInstanceBudget = descendants <= Config.GeneratedDescendantBudget,
	}
end

function Validator.ValidateMaterializedAgainstPlan(spec: WorldSpec, plan: Plan)
	local capture = Validator.CaptureMaterialized(spec)
	local expectedSurface = expectedSurfaceSignature(spec, plan)
	local countMismatches = 0
	for name, count in plan.MaterialCounts do if capture.MaterialCounts[name] ~= count then countMismatches += 1 end end
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local details = generated:WaitForChild("EnvironmentPolish"):WaitForChild("SurfaceDetails")
	local detailMismatches = 0
	for _, detail in plan.Details do
		local part = details:FindFirstChild(string.format("Detail_%03d_%s", detail.Index, detail.Kind))
		if not part or not part:IsA("BasePart")
			or (part.Position - Vector3.new(detail.WorldX, detail.GroundY + detail.Height * 0.12, detail.WorldZ)).Magnitude > 0.002
			or (part.Size - Vector3.new(detail.Width, detail.Height, detail.Depth)).Magnitude > 0.002
			or part:GetAttribute("RegionId") ~= detail.RegionId then detailMismatches += 1 end
	end
	return {
		Passed = capture.Passed and capture.SurfaceSignature == expectedSurface
			and countMismatches == 0 and capture.DetailCount == #plan.Details and detailMismatches == 0,
		ExpectedSurfaceSignature = expectedSurface, ActualSurfaceSignature = capture.SurfaceSignature,
		MaterialCountMismatches = countMismatches, DetailMismatches = detailMismatches,
	}
end

return table.freeze(Validator)
