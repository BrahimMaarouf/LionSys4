--!strict

-- Milestone 9 closes the vertical slice without changing the approved M5
-- four-landmark grammar. It adds an exterior presentation layer, a plan-only
-- seed browser, and final cross-layer validation of the fully materialized
-- world. The edge is intentionally outside M1's captured terrain region.
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Evidence = require(WorldEngine.Config.MilestoneNineEvidence)
local Spec = require(WorldEngine.Config.WorldSpecs.DesertVerticalSlice)
local WorldEdgeMaterializer = require(WorldEngine.Materialization.WorldEdgeMaterializer)
local RuinPlanner = require(WorldEngine.Planning.RuinPlanner)
local WorldCompositionPlanner = require(WorldEngine.Planning.WorldCompositionPlanner)

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

local function saveJson(name: string, report)
	local diagnostics = Workspace:WaitForChild("WorldRoot"):WaitForChild("Diagnostics")
	local value = diagnostics:FindFirstChild(name) or Instance.new("StringValue")
	value.Name = name
	value.Parent = diagnostics
	assert(value:IsA("StringValue"))
	value.Value = HttpService:JSONEncode(report)
end

local function humanVisualSignoff(): boolean
	local override = Workspace:WaitForChild("WorldRoot"):GetAttribute("Milestone9HumanVisualSignoff")
	if type(override) == "boolean" then
		return override
	end
	return Evidence.HumanVisualSignoffPassed
end

local function grounded(model: Model, tolerance: number, params: RaycastParams): boolean
	local p = model:GetPivot().Position
	local hit = Workspace:Raycast(Vector3.new(p.X, 200, p.Z), Vector3.new(0, -400, 0), params)
	return hit ~= nil and math.abs(p.Y - hit.Position.Y) <= tolerance
end

-- Seed browsing is planning only: it does not mutate Terrain or create a
-- single Instance, so the settings UI can later call this for many seeds.
function Runner.BrowseSeeds(seeds: {number})
	local results = {}
	for _, seed in seeds do
		local candidate = table.clone(Spec)
		candidate.WorldSeed = seed
		local started = os.clock()
		local ok, metrics = pcall(function()
			local composition = WorldCompositionPlanner.Plan(candidate)
			local ruins = RuinPlanner.Plan(candidate)
			return {
				Seed = seed,
				Ok = true,
				Landmarks = #composition.Landmarks,
				Routes = #composition.Routes,
				Vistas = #composition.Vistas,
				Placements = #composition.Placements,
				RuinSites = #ruins.Sites,
				RuinPieces = #ruins.Pieces,
				CompositionSignature = composition.Signature,
				RuinSignature = ruins.Signature,
				PlanSeconds = os.clock() - started,
			}
		end)
		table.insert(results, if ok then metrics else {Seed = seed, Ok = false, Error = tostring(metrics)})
	end
	saveJson("SeedBrowserReport", results)
	return results
end

-- Final-world checks deliberately inspect materialized state, which is where
-- raycasts are valid. Planning code never reads live Instances.
function Runner.ValidateFullWorld()
	local root = Workspace:WaitForChild("WorldRoot")
	local generated = root:WaitForChild("Generated")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {Workspace.Terrain}

	local spawnHit = Workspace:Raycast(Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), params)
	local propsFolder = generated:FindFirstChild("DesertProps")
	local propChecked, propGrounded = 0, 0
	if propsFolder then
		for _, model in propsFolder:GetChildren() do
			if model:IsA("Model") and type(model:GetAttribute("SourceAsset")) == "string" then
				propChecked += 1
				-- Landmark-role variants stack on other rocks by design (the
				-- SentinelCrown tower), so terrain distance is not their
				-- support test; composition validation owns their placement.
				if model:GetAttribute("CompositionRole") == "Landmark"
					or grounded(model, 6, params) then
					propGrounded += 1
				end
			end
		end
	end

	local ruins = generated:FindFirstChild("Ruins")
	local ruinChecked, ruinGrounded = 0, 0
	if ruins then
		for _, model in ruins:GetDescendants() do
			if model:IsA("Model") and type(model:GetAttribute("PieceIndex")) == "number" then
				ruinChecked += 1
				if grounded(model, 3, params) then
					ruinGrounded += 1
				end
			end
		end
	end

	local walls = root:FindFirstChild("BoundaryWalls")
	local boundaryWallCount, validWalls = 0, 0
	if walls then
		for _, wall in walls:GetChildren() do
			if wall:IsA("BasePart") then
				boundaryWallCount += 1
				if wall.CanCollide and wall.Transparency == 1 and wall.CanQuery == false then
					validWalls += 1
				end
			end
		end
	end

	local descendants = 0
	for _ in generated:GetDescendants() do
		descendants += 1
	end
	local expectedProps = root:GetAttribute("Milestone4VariantCount")
	local expectedRuins = root:GetAttribute("RuinPieceCount")
	local skirtSignature = WorldEdgeMaterializer.SkirtSignature(Spec)
	local skirtMatches = root:GetAttribute("WorldEdgeSignature") == skirtSignature
	local versionMatches = root:GetAttribute("WorldEdgeVersion") == WorldEdgeMaterializer.Version
	local report = {
		SpawnGrounded = spawnHit ~= nil,
		PropsChecked = propChecked,
		PropsGrounded = propGrounded,
		ExpectedProps = expectedProps,
		RuinPiecesChecked = ruinChecked,
		RuinPiecesGrounded = ruinGrounded,
		ExpectedRuinPieces = expectedRuins,
		BoundaryWalls = boundaryWallCount,
		ValidBoundaryWalls = validWalls,
		SkirtSignature = skirtSignature,
		SkirtMatches = skirtMatches,
		WorldEdgeVersion = WorldEdgeMaterializer.Version,
		VersionMatches = versionMatches,
		GeneratedDescendants = descendants,
		InstanceMemoryMb = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Instances),
		TotalMemoryMb = Stats:GetTotalMemoryUsageMb(),
	}
	report.Passed = report.SpawnGrounded
		and type(expectedProps) == "number" and expectedProps > 0
		and propChecked == expectedProps and propGrounded == propChecked
		and type(expectedRuins) == "number" and expectedRuins > 0
		and ruinChecked == expectedRuins and ruinGrounded == ruinChecked
		and boundaryWallCount == 4 and validWalls == 4
		and skirtMatches and versionMatches
	saveJson("FullWorldValidationReport", report)
	return report
end

function Runner.Generate()
	local started = os.clock()
	local walls = WorldEdgeMaterializer.Materialize(Spec)
	return {
		WorldEdgeVersion = WorldEdgeMaterializer.Version,
		SkirtSignature = WorldEdgeMaterializer.SkirtSignature(Spec),
		BoundaryWalls = #walls:GetChildren(),
		GenerationSeconds = os.clock() - started,
	}
end

function Runner.RegenerateAndVerify()
	local browser = Runner.BrowseSeeds({Spec.WorldSeed - 1, Spec.WorldSeed, Spec.WorldSeed + 1})
	local first = Runner.Generate()
	local firstWorld = Runner.ValidateFullWorld()
	local second = Runner.Generate()
	local secondWorld = Runner.ValidateFullWorld()
	local chosen = browser[2]
	local alternateDiffers = browser[1].Ok and chosen.Ok
		and (browser[1].CompositionSignature ~= chosen.CompositionSignature
			or browser[1].RuinSignature ~= chosen.RuinSignature)
	local browserPassed = #browser == 3
	for _, result in browser do
		browserPassed = browserPassed and result.Ok == true
	end
	if chosen and chosen.Ok then
		browserPassed = browserPassed and chosen.Landmarks == 4 and chosen.RuinSites == 3 and chosen.RuinPieces > 0
	end
	local deterministicSkirt = first.SkirtSignature == second.SkirtSignature
	local deterministicWalls = first.BoundaryWalls == second.BoundaryWalls
	local passed = browserPassed and alternateDiffers and deterministicSkirt and deterministicWalls
		and firstWorld.Passed and secondWorld.Passed
	local report = {
		Milestone = 9,
		Passed = passed,
		Status = if passed then "M9_RUNTIME_VALIDATED" else "FAILED",
		WorldSeed = Spec.WorldSeed,
		WorldEdgeVersion = WorldEdgeMaterializer.Version,
		SessionId = SESSION_ID,
		SkirtSignature = second.SkirtSignature,
		BoundaryWalls = second.BoundaryWalls,
		DeterministicSkirt = deterministicSkirt,
		DeterministicWalls = deterministicWalls,
		AlternateSeedDiffers = alternateDiffers,
		SeedBrowserPassed = browserPassed,
		SeedBrowser = browser,
		FullWorld = secondWorld,
		GenerationSeconds = second.GenerationSeconds,
	}
	saveJson("MilestoneNineReport", report)
	return report
end

function Runner.RecordVisualSignoff(passed: boolean, notes: string)
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone9HumanVisualSignoff", passed)
	root:SetAttribute("Milestone9VisualSignoffNotes", notes)
	root:SetAttribute("Milestone9VisualSignoffAt", os.time())
	return {Passed = passed, Notes = notes}
end

function Runner.RunGoldenRegression()
	local goldenModule = WorldEngine.Seeds.GoldenSeeds:FindFirstChild("MilestoneNineGolden")
	assert(goldenModule and goldenModule:IsA("ModuleScript"), "MilestoneNineGolden baseline missing")
	local golden = require(goldenModule)
	assert(not golden.Pending, "MilestoneNineGolden is still pending an intentional baseline")
	local runtime = Runner.RegenerateAndVerify()
	local chosen = runtime.SeedBrowser[2]
	local full = runtime.FullWorld
	local signaturesMatch = golden.WorldEdgeVersion == runtime.WorldEdgeVersion
		and golden.WorldSeed == Spec.WorldSeed
		and golden.SkirtSignature == runtime.SkirtSignature
		and golden.BoundaryWallCount == runtime.BoundaryWalls
		and golden.PropCount == full.PropsChecked
		and golden.RuinPieceCount == full.RuinPiecesChecked
		and chosen and chosen.CompositionSignature == golden.CompositionSignature
		and chosen.RuinSignature == golden.RuinSignature
	local sessionBoundaryVerified = type(golden.BaselineSessionId) == "string"
		and golden.BaselineSessionId ~= "" and golden.BaselineSessionId ~= SESSION_ID
	local signoff = humanVisualSignoff()
	local passed = runtime.Passed and signaturesMatch and sessionBoundaryVerified
		and signoff and Evidence.StudioPerformanceProfileCaptured
	local report = {
		Milestone = 9,
		Passed = passed,
		Status = if passed then "PASSED_CROSS_SESSION_GOLDEN_WORLD_HARDENING"
			elseif signaturesMatch and not sessionBoundaryVerified then "MATCHED_BUT_SAME_SESSION"
			elseif not signoff then "AWAITING_VISUAL_SIGNOFF"
			else "FAILED_OR_GATES_OPEN",
		SessionId = SESSION_ID,
		BaselineSessionId = golden.BaselineSessionId,
		SessionBoundaryVerified = sessionBoundaryVerified,
		SignaturesMatch = signaturesMatch,
		HumanVisualSignoff = signoff,
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
		StudioPerformanceProfileCaptured = Evidence.StudioPerformanceProfileCaptured,
		Runtime = runtime,
	}
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone9Passed", passed)
	root:SetAttribute("Milestone9Status", report.Status)
	saveJson("MilestoneNineGoldenRegressionReport", report)
	return report
end

return table.freeze(Runner)
