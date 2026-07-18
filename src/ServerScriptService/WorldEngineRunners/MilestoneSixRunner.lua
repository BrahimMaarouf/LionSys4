--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Config = require(WorldEngine.Config.Polish.DesertSurfacePolish)
local Evidence = require(WorldEngine.Config.MilestoneSixEvidence)
local Spec = require(WorldEngine.Config.WorldSpecs.DesertVerticalSlice)
local TerrainMaterializer = require(WorldEngine.Materialization.TerrainMaterializer)
local BaseCompositionMaterializer = require(WorldEngine.Materialization.DesertCompositionMaterializer)
local VariationMaterializer = require(WorldEngine.Materialization.AssetVariationMaterializer)
local WorldCompositionMaterializer = require(WorldEngine.Materialization.WorldCompositionMaterializer)
local LightingMaterializer = require(WorldEngine.Materialization.DesertLightingMaterializer)
local Materializer = require(WorldEngine.Materialization.SurfacePolishMaterializer)
local VariationPlanner = require(WorldEngine.Planning.AssetVariationPlanner)
local Planner = require(WorldEngine.Planning.SurfacePolishPlanner)
local M4Validator = require(WorldEngine.Validation.MilestoneFourValidator)
local M5Validator = require(WorldEngine.Validation.MilestoneFiveValidator)
local Validator = require(WorldEngine.Validation.MilestoneSixValidator)

local function getStudioSessionId(): string
	local marker = ServerStorage:FindFirstChild("_WorldEngineStudioSession")
	if not marker then
		marker = Instance.new("Folder")
		marker.Name = "_WorldEngineStudioSession"
		marker.Archivable = false
		marker:SetAttribute("SessionId", HttpService:GenerateGUID(false))
		marker.Parent = ServerStorage
	end
	local id = marker:GetAttribute("SessionId")
	assert(type(id) == "string", "Studio session marker has no SessionId")
	return id
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

local function saveAttributes(report)
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone6Passed", report.Passed)
	root:SetAttribute("Milestone6Status", report.Status)
	root:SetAttribute("Milestone6VerifiedAt", os.time())
	root:SetAttribute("Milestone6PolishVersion", Config.Version)
	root:SetAttribute("Milestone6PlanSignature", report.PlanSignature)
	root:SetAttribute("Milestone6MaterializedSignature", report.MaterializedSignature)
	root:SetAttribute("Milestone6SessionBoundaryVerified", report.SessionBoundaryVerified or false)
	root:SetAttribute("Milestone6HumanVisualSignoff", report.HumanVisualSignoff or false)
	root:SetAttribute("Milestone6ClientRuntimeValidationPassed", report.ClientRuntimeValidationPassed or false)
end

function Runner.Generate(specOverride: any?)
	local spec = specOverride or Spec
	local started = os.clock()
	local plan = Planner.Plan(spec)
	TerrainMaterializer.Materialize(spec, "Forward")
	BaseCompositionMaterializer.Materialize(plan.Composition.BaseComposition)
	VariationMaterializer.Materialize(plan.Composition.Variation)
	WorldCompositionMaterializer.Materialize(plan.Composition)
	LightingMaterializer.Apply()
	local materialized = Materializer.Materialize(spec, plan)
	return {Spec = spec, Plan = plan, Materialized = materialized, GenerationSeconds = os.clock() - started}
end

function Runner.RegenerateAndVerify()
	local audit = VariationPlanner.AuditIdentitySpace(Spec.WorldSeed)
	local first = Runner.Generate()
	local firstPlan = Validator.ValidatePlan(Spec, first.Plan, audit)
	local firstCapture = Validator.CaptureMaterialized(Spec)
	local firstAgainst = Validator.ValidateMaterializedAgainstPlan(Spec, first.Plan)
	local firstM5 = M5Validator.CaptureMaterialized()
	local firstM5Against = M5Validator.ValidateMaterializedAgainstPlan(first.Plan.Composition)
	local firstM4 = M4Validator.CaptureMaterialized()
	local firstM4Against = M4Validator.ValidateMaterializedAgainstPlan(first.Plan.Composition.Variation)
	local second = Runner.Generate()
	local secondPlan = Validator.ValidatePlan(Spec, second.Plan, VariationPlanner.AuditIdentitySpace(Spec.WorldSeed))
	local secondCapture = Validator.CaptureMaterialized(Spec)
	local secondAgainst = Validator.ValidateMaterializedAgainstPlan(Spec, second.Plan)
	local secondM5 = M5Validator.CaptureMaterialized()
	local secondM5Against = M5Validator.ValidateMaterializedAgainstPlan(second.Plan.Composition)
	local secondM4 = M4Validator.CaptureMaterialized()
	local secondM4Against = M4Validator.ValidateMaterializedAgainstPlan(second.Plan.Composition.Variation)
	local alternateSpec = table.clone(Spec)
	alternateSpec.WorldSeed += 1
	local alternate = Planner.Plan(alternateSpec)
	local deterministicPlan = first.Plan.Signature == second.Plan.Signature
	local deterministicMaterialization = firstCapture.Signature == secondCapture.Signature
	local alternateSeedDiffers = first.Plan.Signature ~= alternate.Signature
	local inheritedPassed = firstM5.Passed and secondM5.Passed and firstM5Against.Passed and secondM5Against.Passed
		and firstM4.Passed and secondM4.Passed and firstM4Against.Passed and secondM4Against.Passed
	local runtimePassed = firstPlan.Passed and secondPlan.Passed and firstCapture.Passed and secondCapture.Passed
		and firstAgainst.Passed and secondAgainst.Passed and inheritedPassed
		and deterministicPlan and deterministicMaterialization and alternateSeedDiffers
	Workspace.WorldRoot:SetAttribute("Milestone6BaselineSessionId", SESSION_ID)
	local report = {
		Milestone = 6, Passed = false,
		Status = if runtimePassed then "PROVISIONAL_GOLDEN_VISUAL_CLIENT_REQUIRED" else "FAILED",
		RuntimeValidationPassed = runtimePassed, SessionBoundaryVerified = false,
		HumanVisualSignoff = Evidence.HumanVisualSignoffPassed,
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
		ClientRuntimeValidationPassed = Evidence.RuntimeClientValidationPassed,
		ClientRuntimeValidationNotes = Evidence.RuntimeClientValidationNotes,
		SessionId = SESSION_ID, WorldSeed = Spec.WorldSeed, PolishVersion = Config.Version,
		PlanSignature = first.Plan.Signature, SurfaceSignature = firstCapture.SurfaceSignature,
		DetailSignature = firstCapture.DetailSignature, MaterializedSignature = firstCapture.Signature,
		AlternatePlanSignature = alternate.Signature, DeterministicPlan = deterministicPlan,
		DeterministicMaterialization = deterministicMaterialization, AlternateSeedDiffers = alternateSeedDiffers,
		SurfaceCellCount = firstPlan.SurfaceCellCount, MaterialCounts = first.Plan.MaterialCounts,
		RegionMaterialCounts = first.Plan.RegionMaterialCounts, RouteSurfaceCellCount = first.Plan.RouteSurfaceCellCount,
		DetailCount = #first.Plan.Details, DetailCounts = first.Plan.DetailCounts,
		RegionDetailCounts = first.Plan.RegionDetailCounts,
		AtmosphereEmitterCount = firstCapture.AtmosphereEmitterCount,
		PlanAssertions = firstPlan.Assertions, PlanAssertionsPassed = firstPlan.Passed and secondPlan.Passed,
		MaterializedAssertionsPassed = firstCapture.Passed and secondCapture.Passed,
		MaterializedPlanAssertionsPassed = firstAgainst.Passed and secondAgainst.Passed,
		InheritedM4M5Passed = inheritedPassed, IdentityAuditSignature = audit.Signature,
		GeneratedDescendantCount = secondCapture.GeneratedDescendantCount,
		WithinInstanceBudget = secondCapture.WithinInstanceBudget,
		GenerationSeconds = first.GenerationSeconds, RegenerationSeconds = second.GenerationSeconds,
	}
	saveAttributes(report)
	saveJson("MilestoneSixReport", report)
	return report
end

function Runner.RunGoldenRegression()
	local goldenModule = WorldEngine.Seeds.GoldenSeeds:FindFirstChild("MilestoneSixGolden")
	assert(goldenModule and goldenModule:IsA("ModuleScript"), "MilestoneSixGolden baseline is missing")
	local golden = require(goldenModule)
	assert(not golden.Pending, "MilestoneSixGolden is still pending an intentional baseline")
	local generated = Runner.Generate()
	local audit = VariationPlanner.AuditIdentitySpace(Spec.WorldSeed)
	local planValidation = Validator.ValidatePlan(Spec, generated.Plan, audit)
	local capture = Validator.CaptureMaterialized(Spec)
	local against = Validator.ValidateMaterializedAgainstPlan(Spec, generated.Plan)
	local m5 = M5Validator.CaptureMaterialized()
	local m5Against = M5Validator.ValidateMaterializedAgainstPlan(generated.Plan.Composition)
	local m4 = M4Validator.CaptureMaterialized()
	local m4Against = M4Validator.ValidateMaterializedAgainstPlan(generated.Plan.Composition.Variation)
	local signaturesMatch = golden.PolishVersion == Config.Version and golden.WorldSeed == Spec.WorldSeed
		and golden.SurfaceCellCount == planValidation.SurfaceCellCount and golden.DetailCount == #generated.Plan.Details
		and golden.AtmosphereEmitterCount == capture.AtmosphereEmitterCount
		and golden.PlanSignature == generated.Plan.Signature and golden.SurfaceSignature == capture.SurfaceSignature
		and golden.DetailSignature == capture.DetailSignature and golden.MaterializedSignature == capture.Signature
		and golden.IdentityAuditSignature == audit.Signature
	local sessionBoundary = type(golden.BaselineSessionId) == "string" and golden.BaselineSessionId ~= ""
		and golden.BaselineSessionId ~= SESSION_ID
	local inheritedPassed = m5.Passed and m5Against.Passed and m4.Passed and m4Against.Passed
	local passed = signaturesMatch and sessionBoundary and Evidence.HumanVisualSignoffPassed
		and Evidence.RuntimeClientValidationPassed and planValidation.Passed and capture.Passed
		and against.Passed and inheritedPassed
	local report = {
		Milestone = 6, Passed = passed,
		Status = if passed then "PASSED_CROSS_SESSION_GOLDEN_SURFACE_ATMOSPHERE"
			elseif signaturesMatch and not sessionBoundary then "MATCHED_BUT_SAME_SESSION" else "FAILED_OR_GATES_OPEN",
		SessionId = SESSION_ID, BaselineSessionId = golden.BaselineSessionId,
		SessionBoundaryVerified = sessionBoundary, SignaturesMatch = signaturesMatch,
		HumanVisualSignoff = Evidence.HumanVisualSignoffPassed,
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
		ClientRuntimeValidationPassed = Evidence.RuntimeClientValidationPassed,
		ClientRuntimeValidationNotes = Evidence.RuntimeClientValidationNotes,
		WorldSeed = Spec.WorldSeed, PolishVersion = Config.Version,
		PlanSignature = generated.Plan.Signature, SurfaceSignature = capture.SurfaceSignature,
		DetailSignature = capture.DetailSignature, MaterializedSignature = capture.Signature,
		IdentityAuditSignature = audit.Signature, SurfaceCellCount = planValidation.SurfaceCellCount,
		MaterialCounts = generated.Plan.MaterialCounts, DetailCount = #generated.Plan.Details,
		AtmosphereEmitterCount = capture.AtmosphereEmitterCount,
		PlanAssertionsPassed = planValidation.Passed, MaterializedAssertionsPassed = capture.Passed,
		MaterializedPlanAssertionsPassed = against.Passed, InheritedM4M5Passed = inheritedPassed,
		GeneratedDescendantCount = capture.GeneratedDescendantCount,
		WithinInstanceBudget = capture.WithinInstanceBudget, GenerationSeconds = generated.GenerationSeconds,
	}
	saveAttributes(report)
	saveJson("MilestoneSixGoldenRegressionReport", report)
	return report
end

return table.freeze(Runner)
