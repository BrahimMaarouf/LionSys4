--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Config = require(WorldEngine.Config.Ruins.DesertRuins)
local Evidence = require(WorldEngine.Config.MilestoneEightEvidence)
local RuinMaterializer = require(WorldEngine.Materialization.RuinMaterializer)
local RuinPlanner = require(WorldEngine.Planning.RuinPlanner)
local Spec = require(WorldEngine.Config.WorldSpecs.DesertVerticalSlice)
local Validator = require(WorldEngine.Validation.MilestoneEightValidator)

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
	local override = Workspace:WaitForChild("WorldRoot"):GetAttribute("Milestone8HumanVisualSignoff")
	if type(override) == "boolean" then
		return override
	end
	return Evidence.HumanVisualSignoffPassed
end

function Runner.Generate()
	local started = os.clock()
	local plan = RuinPlanner.Plan(Spec)
	RuinMaterializer.Materialize(plan)
	return {Plan = plan, GenerationSeconds = os.clock() - started}
end

function Runner.RegenerateAndVerify()
	local templates = Validator.ValidateTemplates()
	local first = Runner.Generate()
	local firstPlanValidation = Validator.ValidatePlan(Spec, first.Plan)
	local firstCapture = Validator.CaptureMaterialized()
	local second = Runner.Generate()
	local secondCapture = Validator.CaptureMaterialized()
	local alternateSpec = table.clone(Spec)
	alternateSpec.WorldSeed += 1
	local alternate = RuinPlanner.Plan(alternateSpec)

	local deterministicPlan = first.Plan.Signature == second.Plan.Signature
	local deterministicMaterialization = firstCapture.Signature == secondCapture.Signature
	local alternateSeedDiffers = alternate.Signature ~= first.Plan.Signature
	local passed = templates.Passed
		and firstPlanValidation.Passed
		and firstCapture.InvalidPieces == 0
		and deterministicPlan
		and deterministicMaterialization
		and alternateSeedDiffers

	local report = {
		Milestone = 8,
		Passed = passed,
		Status = if passed then "M8_RUNTIME_VALIDATED" else "FAILED",
		RuinVersion = Config.Version,
		WorldSeed = Spec.WorldSeed,
		PlanSignature = first.Plan.Signature,
		MaterializedSignature = firstCapture.Signature,
		AlternatePlanSignature = alternate.Signature,
		TemplateValidation = templates,
		PlanValidation = firstPlanValidation,
		DeterministicPlan = deterministicPlan,
		DeterministicMaterialization = deterministicMaterialization,
		AlternateSeedDiffers = alternateSeedDiffers,
		GenerationSeconds = second.GenerationSeconds,
		RejectedSiteBearings = first.Plan.RejectedSiteBearings,
	}
	saveJson("MilestoneEightReport", report)
	return report
end

function Runner.RecordVisualSignoff(passed: boolean, notes: string)
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone8HumanVisualSignoff", passed)
	root:SetAttribute("Milestone8VisualSignoffNotes", notes)
	root:SetAttribute("Milestone8VisualSignoffAt", os.time())
	return {Passed = passed, Notes = notes}
end

function Runner.RunGoldenRegression()
	local goldenModule = WorldEngine.Seeds.GoldenSeeds:FindFirstChild("MilestoneEightGolden")
	assert(goldenModule and goldenModule:IsA("ModuleScript"), "MilestoneEightGolden baseline missing")
	local golden = require(goldenModule)
	assert(not golden.Pending, "MilestoneEightGolden is still pending an intentional baseline")
	local runtime = Runner.RegenerateAndVerify()
	local signaturesMatch = golden.RuinVersion == Config.Version
		and golden.WorldSeed == Spec.WorldSeed
		and golden.PlanSignature == runtime.PlanSignature
		and golden.MaterializedSignature == runtime.MaterializedSignature
		and golden.PieceCount == runtime.PlanValidation.PieceCount
	local sessionBoundaryVerified = type(golden.BaselineSessionId) == "string"
		and golden.BaselineSessionId ~= ""
		and golden.BaselineSessionId ~= SESSION_ID
	local root = Workspace:WaitForChild("WorldRoot")
	local signoff = humanVisualSignoff()
	local passed = runtime.Passed and signaturesMatch and sessionBoundaryVerified and signoff
	local report = {
		Milestone = 8,
		Passed = passed,
		Status = if passed
			then "PASSED_CROSS_SESSION_GOLDEN_MODULAR_RUINS"
			elseif signaturesMatch and not sessionBoundaryVerified then "MATCHED_BUT_SAME_SESSION"
			elseif not signoff then "AWAITING_VISUAL_SIGNOFF"
			elseif not signaturesMatch then "SIGNATURE_MISMATCH"
			else "FAILED",
		RuntimeStatus = runtime.Status,
		SessionId = SESSION_ID,
		BaselineSessionId = golden.BaselineSessionId,
		SessionBoundaryVerified = sessionBoundaryVerified,
		PlanSignature = runtime.PlanSignature,
		ExpectedPlanSignature = golden.PlanSignature,
		MaterializedSignature = runtime.MaterializedSignature,
		ExpectedMaterializedSignature = golden.MaterializedSignature,
		PieceCount = runtime.PlanValidation.PieceCount,
		HumanVisualSignoff = signoff,
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
	}
	root:SetAttribute("Milestone8Passed", passed)
	root:SetAttribute("Milestone8Status", report.Status)
	saveJson("MilestoneEightGoldenRegressionReport", report)
	return report
end

return table.freeze(Runner)
