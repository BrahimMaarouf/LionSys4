--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Config = require(WorldEngine.Config.Composition.DesertPilgrimage)
local Evidence = require(WorldEngine.Config.MilestoneThreeEvidence)
local Spec = require(WorldEngine.Config.WorldSpecs.DesertVerticalSlice)
local LightingMaterializer = require(WorldEngine.Materialization.DesertLightingMaterializer)
local CompositionMaterializer = require(WorldEngine.Materialization.DesertCompositionMaterializer)
local Planner = require(WorldEngine.Planning.DesertCompositionPlanner)
local Validator = require(WorldEngine.Validation.MilestoneThreeValidator)

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
	local override = Workspace:WaitForChild("WorldRoot"):GetAttribute("Milestone3HumanVisualSignoff")
	if type(override) == "boolean" then
		return override
	end
	return Evidence.HumanVisualSignoffPassed
end

local function saveAttributes(report)
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone3Passed", report.Passed)
	root:SetAttribute("Milestone3Status", report.Status)
	root:SetAttribute("Milestone3VerifiedAt", os.time())
	root:SetAttribute("Milestone3CompositionVersion", Config.Version)
	root:SetAttribute("Milestone3PlanSignature", report.PlanSignature)
	root:SetAttribute("Milestone3MaterializedSignature", report.MaterializedSignature)
	root:SetAttribute("Milestone3PropCount", report.PropCount)
	root:SetAttribute("Milestone3RouteNodeCount", report.RouteNodeCount)
	root:SetAttribute("Milestone3PathPatchCount", report.PathPatchCount)
	root:SetAttribute("Milestone3SessionBoundaryVerified", report.SessionBoundaryVerified or false)
	root:SetAttribute("Milestone3HumanVisualSignoff", report.HumanVisualSignoff or false)
end

function Runner.Generate()
	local started = os.clock()
	local plan = Planner.Plan(Spec)
	local materialized = CompositionMaterializer.Materialize(plan)
	local lighting = LightingMaterializer.Apply()
	return {
		Plan = plan,
		Materialized = materialized,
		Lighting = lighting,
		GenerationSeconds = os.clock() - started,
	}
end

function Runner.RegenerateAndVerify()
	local first = Runner.Generate()
	local firstPlan = Validator.ValidatePlan(Spec, first.Plan)
	local firstCapture = Validator.CaptureMaterialized()
	local firstAgainstPlan = Validator.ValidateMaterializedAgainstPlan(first.Plan)
	local second = Runner.Generate()
	local secondPlan = Validator.ValidatePlan(Spec, second.Plan)
	local secondCapture = Validator.CaptureMaterialized()
	local secondAgainstPlan = Validator.ValidateMaterializedAgainstPlan(second.Plan)

	local alternateSpec = table.clone(Spec)
	alternateSpec.WorldSeed += 1
	local alternate = Planner.Plan(alternateSpec)
	local deterministicPlan = first.Plan.Signature == second.Plan.Signature
	local deterministicMaterialization = firstCapture.Signature == secondCapture.Signature
	local alternateSeedDiffers = alternate.Signature ~= first.Plan.Signature
	local runtimePassed = firstPlan.Passed
		and secondPlan.Passed
		and firstCapture.Passed
		and secondCapture.Passed
		and firstAgainstPlan.Passed
		and secondAgainstPlan.Passed
		and deterministicPlan
		and deterministicMaterialization
		and alternateSeedDiffers

	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone3BaselineSessionId", SESSION_ID)
	local report = {
		Milestone = 3,
		Passed = false,
		Status = if runtimePassed then "PROVISIONAL_GOLDEN_AND_VISUAL_REQUIRED" else "FAILED",
		RuntimeValidationPassed = runtimePassed,
		SessionBoundaryVerified = false,
		HumanVisualSignoff = humanVisualSignoff(),
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
		SessionId = SESSION_ID,
		WorldSeed = Spec.WorldSeed,
		CompositionVersion = Config.Version,
		Landmark = first.Plan.Landmark.Id,
		PropCount = #first.Plan.Placements,
		RoleCounts = first.Plan.RoleCounts,
		RouteNodeCount = #first.Plan.RouteNodes,
		PathPatchCount = #first.Plan.PathSamples,
		Repair = first.Plan.Repair,
		RepairRevalidated = first.Plan.RevalidationPassed,
		PlanSignature = first.Plan.Signature,
		MaterializedSignature = firstCapture.Signature,
		AlternatePlanSignature = alternate.Signature,
		AlternateSeedDiffers = alternateSeedDiffers,
		DeterministicPlan = deterministicPlan,
		DeterministicMaterialization = deterministicMaterialization,
		PlanAssertions = firstPlan.Assertions,
		PlanAssertionsPassed = firstPlan.Passed and secondPlan.Passed,
		MaterializedAssertionsPassed = firstCapture.Passed and secondCapture.Passed,
		MaterializedPlanAssertionsPassed = firstAgainstPlan.Passed and secondAgainstPlan.Passed,
		GeneratedDescendantCount = secondCapture.GeneratedDescendantCount,
		WithinInstanceBudget = secondCapture.WithinInstanceBudget,
		GenerationSeconds = first.GenerationSeconds,
		RegenerationSeconds = second.GenerationSeconds,
	}
	saveAttributes(report)
	saveJson("MilestoneThreeReport", report)
	return report
end

function Runner.RecordVisualSignoff(passed: boolean, notes: string)
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone3HumanVisualSignoff", passed)
	root:SetAttribute("Milestone3VisualSignoffNotes", notes)
	root:SetAttribute("Milestone3VisualSignoffAt", os.time())
	return {Passed = passed, Notes = notes}
end

function Runner.RunGoldenRegression()
	local goldenModule = WorldEngine.Seeds.GoldenSeeds:FindFirstChild("MilestoneThreeGolden")
	assert(goldenModule and goldenModule:IsA("ModuleScript"), "MilestoneThreeGolden baseline is missing")
	local golden = require(goldenModule)
	assert(not golden.Pending, "MilestoneThreeGolden is still pending an intentional baseline")

	local generated = Runner.Generate()
	local planValidation = Validator.ValidatePlan(Spec, generated.Plan)
	local capture = Validator.CaptureMaterialized()
	local againstPlan = Validator.ValidateMaterializedAgainstPlan(generated.Plan)
	local signaturesMatch = golden.CompositionVersion == Config.Version
		and golden.WorldSeed == Spec.WorldSeed
		and golden.PropCount == #generated.Plan.Placements
		and golden.RouteNodeCount == #generated.Plan.RouteNodes
		and golden.PathPatchCount == #generated.Plan.PathSamples
		and golden.PlanSignature == generated.Plan.Signature
		and golden.MaterializedSignature == capture.Signature
	local sessionBoundaryVerified = type(golden.BaselineSessionId) == "string"
		and golden.BaselineSessionId ~= ""
		and golden.BaselineSessionId ~= SESSION_ID
	local visualSignoff = humanVisualSignoff()
	local passed = signaturesMatch
		and sessionBoundaryVerified
		and visualSignoff
		and planValidation.Passed
		and capture.Passed
		and againstPlan.Passed
	local report = {
		Milestone = 3,
		Passed = passed,
		Status = if passed
			then "PASSED_CROSS_SESSION_GOLDEN_COMPOSITION"
			elseif signaturesMatch and not sessionBoundaryVerified
			then "MATCHED_BUT_SAME_SESSION"
			else "FAILED_OR_GATES_OPEN",
		SessionId = SESSION_ID,
		BaselineSessionId = golden.BaselineSessionId,
		SessionBoundaryVerified = sessionBoundaryVerified,
		HumanVisualSignoff = visualSignoff,
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
		SignaturesMatch = signaturesMatch,
		WorldSeed = Spec.WorldSeed,
		CompositionVersion = Config.Version,
		Landmark = generated.Plan.Landmark.Id,
		PropCount = #generated.Plan.Placements,
		RoleCounts = generated.Plan.RoleCounts,
		RouteNodeCount = #generated.Plan.RouteNodes,
		PathPatchCount = #generated.Plan.PathSamples,
		Repair = generated.Plan.Repair,
		RepairRevalidated = generated.Plan.RevalidationPassed,
		PlanSignature = generated.Plan.Signature,
		MaterializedSignature = capture.Signature,
		ExpectedPlanSignature = golden.PlanSignature,
		ExpectedMaterializedSignature = golden.MaterializedSignature,
		PlanAssertionsPassed = planValidation.Passed,
		MaterializedAssertionsPassed = capture.Passed,
		MaterializedPlanAssertionsPassed = againstPlan.Passed,
		GeneratedDescendantCount = capture.GeneratedDescendantCount,
		WithinInstanceBudget = capture.WithinInstanceBudget,
		GenerationSeconds = generated.GenerationSeconds,
	}
	saveAttributes(report)
	saveJson("MilestoneThreeGoldenRegressionReport", report)
	return report
end

return table.freeze(Runner)
