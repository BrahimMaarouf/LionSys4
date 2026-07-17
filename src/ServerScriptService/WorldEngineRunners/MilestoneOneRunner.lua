--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Spec = require(WorldEngine.Config.WorldSpecs.DesertVerticalSlice)
local Materializer = require(WorldEngine.Materialization.TerrainMaterializer)
local Planner = require(WorldEngine.Planning.HeightfieldPlanner)
local Validator = require(WorldEngine.Validation.MilestoneOneValidator)

local function getStudioSessionId(): string
	local marker = ServerStorage:FindFirstChild("_WorldEngineStudioSession")
	if not marker then
		marker = Instance.new("Folder")
		marker.Name = "_WorldEngineStudioSession"
		marker.Archivable = false
		marker:SetAttribute("SessionId", HttpService:GenerateGUID(false))
		marker.Parent = ServerStorage
	end
	local sessionId = marker:GetAttribute("SessionId")
	assert(type(sessionId) == "string", "Studio session marker has no SessionId")
	return sessionId
end

local SESSION_ID = getStudioSessionId()
local Runner = {}

local function diagnosticsFolder(): Folder
	local worldRoot = Workspace:WaitForChild("WorldRoot")
	return worldRoot:WaitForChild("Diagnostics") :: Folder
end

local function saveJsonValue(name: string, report)
	local diagnostics = diagnosticsFolder()
	local value = diagnostics:FindFirstChild(name)
	if not value then
		value = Instance.new("StringValue")
		value.Name = name
		value.Parent = diagnostics
	end
	assert(value:IsA("StringValue"))
	value.Value = HttpService:JSONEncode(report)
end

local function saveMilestoneReport(report)
	local worldRoot = Workspace:WaitForChild("WorldRoot")
	worldRoot:SetAttribute("GeneratorVersion", Spec.GeneratorVersion)
	worldRoot:SetAttribute("Milestone1Passed", report.Passed)
	worldRoot:SetAttribute("Milestone1CurrentSessionPassed", report.CurrentSessionPassed)
	worldRoot:SetAttribute("Milestone1SessionBoundaryVerified", report.SessionBoundaryVerified)
	worldRoot:SetAttribute("Milestone1PlanSignature", report.PlanSignature)
	worldRoot:SetAttribute("Milestone1TerrainSignature", report.TerrainSignature)
	worldRoot:SetAttribute("Milestone1ClearSucceeded", report.ClearSucceeded)
	worldRoot:SetAttribute("Milestone1VerifiedSeed", report.WorldSeed)
	worldRoot:SetAttribute("Milestone1VerifiedAt", os.time())
	saveJsonValue("MilestoneOneReport", report)
end

local function chunkKey(chunkX: number, chunkZ: number): string
	return string.format("%d:%d", chunkX, chunkZ)
end

local function captureChunkManifest()
	local manifest = {}
	local chunkCount = Planner.GetChunkCount(Spec)
	for chunkZ = 0, chunkCount - 1 do
		for chunkX = 0, chunkCount - 1 do
			local capture = Validator.CaptureChunk(Spec, chunkX, chunkZ)
			manifest[chunkKey(chunkX, chunkZ)] = {
				Signature = capture.Signature,
				FilledCells = capture.FilledCells,
				TotalCells = capture.TotalCells,
			}
		end
	end
	return manifest
end

local function compareChunkManifests(left, right): number
	local mismatches = 0
	for key, expected in left do
		local actual = right[key]
		if actual == nil
			or actual.Signature ~= expected.Signature
			or actual.FilledCells ~= expected.FilledCells
			or actual.TotalCells ~= expected.TotalCells then
			mismatches += 1
		end
	end
	return mismatches
end

function Runner.Clear()
	Materializer.Clear(Spec)
	return Validator.CaptureTerrain(Spec)
end

function Runner.Generate(orderName: string?)
	local order = orderName or "Forward"
	local planValidation = Validator.ValidatePlan(Spec)
	assert(planValidation.Passed, "Plan validation failed before materialization")

	local materialization = Materializer.Materialize(Spec, order)
	local terrain = Validator.CaptureTerrain(Spec)
	return {
		PlanValidation = planValidation,
		Materialization = materialization,
		Terrain = terrain,
	}
end

function Runner.RegenerateAndVerify()
	local planValidation = Validator.ValidatePlan(Spec)
	assert(planValidation.Passed, "Plan validation failed")

	local first = Runner.Generate("Forward")
	local firstChunks = captureChunkManifest()

	Materializer.Clear(Spec)
	local cleared = Validator.CaptureTerrain(Spec)

	local second = Runner.Generate("Reverse")
	local secondChunks = captureChunkManifest()

	local planMatches = first.Materialization.PlanSignature == second.Materialization.PlanSignature
		and first.Materialization.PlanSignature == planValidation.PlanSignature
	local terrainMatches = first.Terrain.Signature == second.Terrain.Signature
	local chunkOrderMismatchCount = compareChunkManifests(firstChunks, secondChunks)
	local clearSucceeded = cleared.FilledCells == 0
	local terrainIsNonEmpty = first.Terrain.FilledCells > 0
		and second.Terrain.FilledCells > 0
		and first.Terrain.FilledCells == second.Terrain.FilledCells

	local isolatedChunkMismatchCount = 0
	local isolatedChunksChecked = 0
	local chunkCount = Planner.GetChunkCount(Spec)
	for chunkZ = 0, chunkCount - 1 do
		for chunkX = 0, chunkCount - 1 do
			Materializer.Clear(Spec)
			Materializer.MaterializeChunk(Spec, chunkX, chunkZ)
			local isolated = Validator.CaptureChunk(Spec, chunkX, chunkZ)
			local expected = firstChunks[chunkKey(chunkX, chunkZ)]
			isolatedChunksChecked += 1
			if isolated.Signature ~= expected.Signature
				or isolated.FilledCells ~= expected.FilledCells
				or isolated.TotalCells ~= expected.TotalCells then
				isolatedChunkMismatchCount += 1
			end
		end
	end

	Materializer.Materialize(Spec, "Forward")
	local restored = Validator.CaptureTerrain(Spec)
	local restoreMatches = restored.Signature == first.Terrain.Signature
		and restored.FilledCells == first.Terrain.FilledCells

	local alternateSpec = table.clone(Spec)
	alternateSpec.WorldSeed += 1
	local alternatePlan = Planner.PlanWorld(alternateSpec)
	local alternatePlanSignature = Planner.Signature(alternateSpec, alternatePlan)
	local differentSeedProducesDifferentPlan = alternatePlanSignature ~= planValidation.PlanSignature

	local currentSessionPassed = planValidation.Passed
		and planMatches
		and terrainMatches
		and chunkOrderMismatchCount == 0
		and clearSucceeded
		and terrainIsNonEmpty
		and isolatedChunkMismatchCount == 0
		and restoreMatches
		and differentSeedProducesDifferentPlan

	local worldRoot = Workspace:WaitForChild("WorldRoot")
	worldRoot:SetAttribute("Milestone1BaselineSessionId", SESSION_ID)

	local report = {
		Milestone = 1,
		Passed = false,
		Status = if currentSessionPassed then "PROVISIONAL_CROSS_SESSION_CHECK_REQUIRED" else "FAILED",
		CurrentSessionPassed = currentSessionPassed,
		SessionBoundaryVerified = false,
		WorldSpec = Spec.Name,
		GeneratorVersion = Spec.GeneratorVersion,
		WorldSeed = Spec.WorldSeed,
		WorldSize = Spec.WorldSize,
		Resolution = Spec.Resolution,
		ChunkSize = Spec.ChunkSize,
		ChunkCount = planValidation.ChunkCount,
		CheckedHeightCells = planValidation.CheckedCells,
		ChunkMismatchCount = planValidation.ChunkMismatchCount,
		MinimumHeight = planValidation.MinimumHeight,
		MaximumHeight = planValidation.MaximumHeight,
		PlanSignature = planValidation.PlanSignature,
		TerrainSignature = restored.Signature,
		ForwardTerrainSignature = first.Terrain.Signature,
		ReverseTerrainSignature = second.Terrain.Signature,
		ForwardFilledCells = first.Terrain.FilledCells,
		ReverseFilledCells = second.Terrain.FilledCells,
		ClearedFilledCells = cleared.FilledCells,
		ClearSucceeded = clearSucceeded,
		PlanMatches = planMatches,
		TerrainMatches = terrainMatches,
		ChunkOrderMismatchCount = chunkOrderMismatchCount,
		TerrainIsNonEmpty = terrainIsNonEmpty,
		IsolatedChunksChecked = isolatedChunksChecked,
		IsolatedChunkMismatchCount = isolatedChunkMismatchCount,
		RestoreMatches = restoreMatches,
		DifferentSeedProducesDifferentPlan = differentSeedProducesDifferentPlan,
		AlternatePlanSignature = alternatePlanSignature,
		ForwardChunkOrder = first.Materialization.Order,
		ReverseChunkOrder = second.Materialization.Order,
		ChunkSignatures = firstChunks,
	}

	saveMilestoneReport(report)
	return report
end

function Runner.RunGoldenRegression()
	local goldenFolder = WorldEngine.Seeds:FindFirstChild("GoldenSeeds")
	assert(goldenFolder, "GoldenSeeds folder is missing")
	local goldenModule = goldenFolder:FindFirstChild("MilestoneOneGolden")
	assert(goldenModule and goldenModule:IsA("ModuleScript"), "MilestoneOneGolden baseline is missing")
	local golden = require(goldenModule)

	local planValidation = Validator.ValidatePlan(Spec)
	assert(planValidation.Passed, "Plan validation failed")
	local materialization = Materializer.Materialize(Spec, "Forward")
	local terrain = Validator.CaptureTerrain(Spec)
	local chunks = captureChunkManifest()
	local chunkMismatchCount = compareChunkManifests(golden.ChunkSignatures, chunks)

	local signatureMatches = golden.WorldSpec == Spec.Name
		and golden.GeneratorVersion == Spec.GeneratorVersion
		and golden.WorldSeed == Spec.WorldSeed
		and golden.PlanSignature == planValidation.PlanSignature
		and golden.TerrainSignature == terrain.Signature
		and golden.FilledCells == terrain.FilledCells
		and chunkMismatchCount == 0

	local worldRoot = Workspace:WaitForChild("WorldRoot")
	local baselineSessionId = worldRoot:GetAttribute("Milestone1BaselineSessionId")
	local sessionBoundaryVerified = type(baselineSessionId) == "string"
		and baselineSessionId ~= SESSION_ID
	local passed = signatureMatches and sessionBoundaryVerified

	local report = {
		Milestone = 1,
		Passed = passed,
		Status = if passed
			then "PASSED_CROSS_SESSION_GOLDEN_REGRESSION"
			elseif signatureMatches
			then "MATCHED_BUT_SAME_SESSION"
			else "FAILED_GOLDEN_REGRESSION",
		CurrentSessionPassed = signatureMatches,
		SessionBoundaryVerified = sessionBoundaryVerified,
		WorldSpec = Spec.Name,
		GeneratorVersion = Spec.GeneratorVersion,
		WorldSeed = Spec.WorldSeed,
		PlanSignature = planValidation.PlanSignature,
		TerrainSignature = terrain.Signature,
		FilledCells = terrain.FilledCells,
		ChunkMismatchCount = chunkMismatchCount,
		ExpectedPlanSignature = golden.PlanSignature,
		ExpectedTerrainSignature = golden.TerrainSignature,
		ExpectedFilledCells = golden.FilledCells,
		MaterializationOrder = materialization.Order,
	}

	worldRoot:SetAttribute("Milestone1Passed", report.Passed)
	worldRoot:SetAttribute("Milestone1CurrentSessionPassed", report.CurrentSessionPassed)
	worldRoot:SetAttribute("Milestone1SessionBoundaryVerified", report.SessionBoundaryVerified)
	worldRoot:SetAttribute("Milestone1PlanSignature", report.PlanSignature)
	worldRoot:SetAttribute("Milestone1TerrainSignature", report.TerrainSignature)
	worldRoot:SetAttribute("Milestone1VerifiedSeed", report.WorldSeed)
	worldRoot:SetAttribute("Milestone1VerifiedAt", os.time())
	saveJsonValue("GoldenRegressionReport", report)
	return report
end

return table.freeze(Runner)
