--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Config = require(WorldEngine.Config.Composition.DesertWorldComposition)
local Evidence = require(WorldEngine.Config.MilestoneFiveEvidence)
local Spec = require(WorldEngine.Config.WorldSpecs.DesertVerticalSlice)
local BaseMaterializer = require(WorldEngine.Materialization.DesertCompositionMaterializer)
local LightingMaterializer = require(WorldEngine.Materialization.DesertLightingMaterializer)
local VariationMaterializer = require(WorldEngine.Materialization.AssetVariationMaterializer)
local Materializer = require(WorldEngine.Materialization.WorldCompositionMaterializer)
local VariationPlanner = require(WorldEngine.Planning.AssetVariationPlanner)
local Planner = require(WorldEngine.Planning.WorldCompositionPlanner)
local M4Validator = require(WorldEngine.Validation.MilestoneFourValidator)
local Validator = require(WorldEngine.Validation.MilestoneFiveValidator)

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
	root:SetAttribute("Milestone5Passed", report.Passed)
	root:SetAttribute("Milestone5Status", report.Status)
	root:SetAttribute("Milestone5VerifiedAt", os.time())
	root:SetAttribute("Milestone5CompositionVersion", Config.Version)
	root:SetAttribute("Milestone5PlanSignature", report.PlanSignature)
	root:SetAttribute("Milestone5MaterializedSignature", report.MaterializedSignature)
	root:SetAttribute("Milestone5SessionBoundaryVerified", report.SessionBoundaryVerified or false)
	root:SetAttribute("Milestone5HumanVisualSignoff", report.HumanVisualSignoff or false)
	root:SetAttribute("Milestone5ClientRuntimeValidationPassed", report.ClientRuntimeValidationPassed or false)
end

function Runner.Generate(specOverride: any?)
	local spec = specOverride or Spec
	local started = os.clock()
	local plan = Planner.Plan(spec)
	BaseMaterializer.Materialize(plan.BaseComposition)
	VariationMaterializer.Materialize(plan.Variation)
	local materialized = Materializer.Materialize(plan)
	local lighting = LightingMaterializer.Apply()
	return {Spec = spec, Plan = plan, Materialized = materialized, Lighting = lighting, GenerationSeconds = os.clock() - started}
end

function Runner.RegenerateAndVerify()
	local audit = VariationPlanner.AuditIdentitySpace(Spec.WorldSeed)
	local first = Runner.Generate()
	local firstPlan = Validator.ValidatePlan(first.Plan, audit)
	local firstCapture = Validator.CaptureMaterialized()
	local firstAgainst = Validator.ValidateMaterializedAgainstPlan(first.Plan)
	local firstM4Capture = M4Validator.CaptureMaterialized()
	local firstM4Against = M4Validator.ValidateMaterializedAgainstPlan(first.Plan.Variation)
	local second = Runner.Generate()
	local secondPlan = Validator.ValidatePlan(second.Plan, VariationPlanner.AuditIdentitySpace(Spec.WorldSeed))
	local secondCapture = Validator.CaptureMaterialized()
	local secondAgainst = Validator.ValidateMaterializedAgainstPlan(second.Plan)
	local secondM4Capture = M4Validator.CaptureMaterialized()
	local secondM4Against = M4Validator.ValidateMaterializedAgainstPlan(second.Plan.Variation)
	local alternateSpec = table.clone(Spec)
	alternateSpec.WorldSeed += 1
	local alternate = Planner.Plan(alternateSpec)
	local deterministicPlan = first.Plan.Signature == second.Plan.Signature
	local deterministicMaterialization = firstCapture.Signature == secondCapture.Signature
	local alternateSeedDiffers = alternate.Signature ~= first.Plan.Signature
	local runtimePassed = firstPlan.Passed and secondPlan.Passed and firstCapture.Passed and secondCapture.Passed
		and firstAgainst.Passed and secondAgainst.Passed and firstM4Capture.Passed and secondM4Capture.Passed
		and firstM4Against.Passed and secondM4Against.Passed and deterministicPlan
		and deterministicMaterialization and alternateSeedDiffers
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone5BaselineSessionId", SESSION_ID)
	local report = {
		Milestone = 5, Passed = false,
		Status = if runtimePassed then "PROVISIONAL_GOLDEN_VISUAL_CLIENT_REQUIRED" else "FAILED",
		RuntimeValidationPassed = runtimePassed, SessionBoundaryVerified = false,
		HumanVisualSignoff = Evidence.HumanVisualSignoffPassed,
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
		ClientRuntimeValidationPassed = Evidence.RuntimeClientValidationPassed,
		ClientRuntimeValidationNotes = Evidence.RuntimeClientValidationNotes,
		SessionId = SESSION_ID, WorldSeed = Spec.WorldSeed, CompositionVersion = Config.Version,
		PlanSignature = first.Plan.Signature, VariationSignature = first.Plan.Variation.Signature,
		MaterializedSignature = firstCapture.Signature, AlternatePlanSignature = alternate.Signature,
		DeterministicPlan = deterministicPlan, DeterministicMaterialization = deterministicMaterialization,
		AlternateSeedDiffers = alternateSeedDiffers, RegionCount = #first.Plan.Regions,
		RouteCount = #first.Plan.Routes, LandmarkCount = #first.Plan.Landmarks, VistaCount = #first.Plan.Vistas,
		PlacementCount = #first.Plan.Placements, VariantCount = #first.Plan.Variation.Variants,
		ComponentCount = first.Plan.Variation.ComponentCount, RegionCellCounts = first.Plan.RegionCellCounts,
		RegionPlacementCounts = first.Plan.RegionPlacementCounts, RoleCounts = first.Plan.RoleCounts,
		Repair = first.Plan.Repair, PlanAssertions = firstPlan.Assertions,
		PlanAssertionsPassed = firstPlan.Passed and secondPlan.Passed,
		MaterializedAssertionsPassed = firstCapture.Passed and secondCapture.Passed,
		MaterializedPlanAssertionsPassed = firstAgainst.Passed and secondAgainst.Passed,
		Milestone4MaterializationPreserved = firstM4Capture.Passed and secondM4Capture.Passed
			and firstM4Against.Passed and secondM4Against.Passed,
		IdentityAuditSignature = audit.Signature, IdentityAuditTotalUnique = audit.TotalUnique,
		BranchPatchCount = secondCapture.BranchPatchCount,
		GeneratedDescendantCount = secondCapture.GeneratedDescendantCount,
		WithinInstanceBudget = secondCapture.WithinInstanceBudget,
		GenerationSeconds = first.GenerationSeconds, RegenerationSeconds = second.GenerationSeconds,
	}
	saveAttributes(report)
	saveJson("MilestoneFiveReport", report)
	return report
end

function Runner.RunGoldenRegression()
	local goldenModule = WorldEngine.Seeds.GoldenSeeds:FindFirstChild("MilestoneFiveGolden")
	assert(goldenModule and goldenModule:IsA("ModuleScript"), "MilestoneFiveGolden baseline is missing")
	local golden = require(goldenModule)
	assert(not golden.Pending, "MilestoneFiveGolden is still pending an intentional baseline")
	local generated = Runner.Generate()
	local audit = VariationPlanner.AuditIdentitySpace(Spec.WorldSeed)
	local planValidation = Validator.ValidatePlan(generated.Plan, audit)
	local capture = Validator.CaptureMaterialized()
	local against = Validator.ValidateMaterializedAgainstPlan(generated.Plan)
	local m4Capture = M4Validator.CaptureMaterialized()
	local m4Against = M4Validator.ValidateMaterializedAgainstPlan(generated.Plan.Variation)
	local signaturesMatch = golden.CompositionVersion == Config.Version and golden.WorldSeed == Spec.WorldSeed
		and golden.RegionCount == #generated.Plan.Regions and golden.RouteCount == #generated.Plan.Routes
		and golden.LandmarkCount == #generated.Plan.Landmarks and golden.VistaCount == #generated.Plan.Vistas
		and golden.PlacementCount == #generated.Plan.Placements and golden.VariantCount == #generated.Plan.Variation.Variants
		and golden.ComponentCount == generated.Plan.Variation.ComponentCount
		and golden.IdentityAuditSignature == audit.Signature and golden.PlanSignature == generated.Plan.Signature
		and golden.VariationSignature == generated.Plan.Variation.Signature
		and golden.MaterializedSignature == capture.Signature
	local sessionBoundary = type(golden.BaselineSessionId) == "string" and golden.BaselineSessionId ~= ""
		and golden.BaselineSessionId ~= SESSION_ID
	local passed = signaturesMatch and sessionBoundary and Evidence.HumanVisualSignoffPassed
		and Evidence.RuntimeClientValidationPassed and planValidation.Passed and capture.Passed
		and against.Passed and m4Capture.Passed and m4Against.Passed
	local report = {
		Milestone = 5, Passed = passed,
		Status = if passed then "PASSED_CROSS_SESSION_GOLDEN_WORLD_COMPOSITION"
			elseif signaturesMatch and not sessionBoundary then "MATCHED_BUT_SAME_SESSION" else "FAILED_OR_GATES_OPEN",
		SessionId = SESSION_ID, BaselineSessionId = golden.BaselineSessionId,
		SessionBoundaryVerified = sessionBoundary, SignaturesMatch = signaturesMatch,
		HumanVisualSignoff = Evidence.HumanVisualSignoffPassed,
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
		ClientRuntimeValidationPassed = Evidence.RuntimeClientValidationPassed,
		ClientRuntimeValidationNotes = Evidence.RuntimeClientValidationNotes,
		WorldSeed = Spec.WorldSeed, CompositionVersion = Config.Version,
		PlanSignature = generated.Plan.Signature, VariationSignature = generated.Plan.Variation.Signature,
		MaterializedSignature = capture.Signature, IdentityAuditSignature = audit.Signature,
		RegionCount = #generated.Plan.Regions, RouteCount = #generated.Plan.Routes,
		LandmarkCount = #generated.Plan.Landmarks, VistaCount = #generated.Plan.Vistas,
		PlacementCount = #generated.Plan.Placements, VariantCount = #generated.Plan.Variation.Variants,
		ComponentCount = generated.Plan.Variation.ComponentCount,
		PlanAssertionsPassed = planValidation.Passed, MaterializedAssertionsPassed = capture.Passed,
		MaterializedPlanAssertionsPassed = against.Passed,
		Milestone4MaterializationPreserved = m4Capture.Passed and m4Against.Passed,
		BranchPatchCount = capture.BranchPatchCount,
		GeneratedDescendantCount = capture.GeneratedDescendantCount,
		WithinInstanceBudget = capture.WithinInstanceBudget,
		GenerationSeconds = generated.GenerationSeconds,
	}
	saveAttributes(report)
	saveJson("MilestoneFiveGoldenRegressionReport", report)
	return report
end

return table.freeze(Runner)
