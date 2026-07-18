--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Config = require(WorldEngine.Config.Variation.DesertAssetFamilies)
local Evidence = require(WorldEngine.Config.MilestoneFourEvidence)
local Spec = require(WorldEngine.Config.WorldSpecs.DesertVerticalSlice)
local CompositionMaterializer = require(WorldEngine.Materialization.DesertCompositionMaterializer)
local LightingMaterializer = require(WorldEngine.Materialization.DesertLightingMaterializer)
local VariationMaterializer = require(WorldEngine.Materialization.AssetVariationMaterializer)
local CompositionPlanner = require(WorldEngine.Planning.DesertCompositionPlanner)
local VariationPlanner = require(WorldEngine.Planning.AssetVariationPlanner)
local Validator = require(WorldEngine.Validation.MilestoneFourValidator)

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
	local override = Workspace:WaitForChild("WorldRoot"):GetAttribute("Milestone4HumanVisualSignoff")
	if type(override) == "boolean" then return override end
	return Evidence.HumanVisualSignoffPassed
end

local function saveAttributes(report)
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone4Passed", report.Passed)
	root:SetAttribute("Milestone4Status", report.Status)
	root:SetAttribute("Milestone4VerifiedAt", os.time())
	root:SetAttribute("Milestone4VariationVersion", Config.Version)
	root:SetAttribute("Milestone4PlanSignature", report.PlanSignature)
	root:SetAttribute("Milestone4MaterializedSignature", report.MaterializedSignature)
	root:SetAttribute("Milestone4VariantCount", report.VariantCount)
	root:SetAttribute("Milestone4ComponentCount", report.ComponentCount)
	root:SetAttribute("Milestone4IdentityAuditUnique", report.IdentityAuditTotalUnique)
	root:SetAttribute("Milestone4SessionBoundaryVerified", report.SessionBoundaryVerified or false)
	root:SetAttribute("Milestone4HumanVisualSignoff", report.HumanVisualSignoff or false)
	root:SetAttribute("Milestone4ClientRuntimeValidationPassed", report.ClientRuntimeValidationPassed or false)
end

function Runner.Generate(specOverride: any?)
	local spec = specOverride or Spec
	local started = os.clock()
	local composition = CompositionPlanner.Plan(spec)
	local variation = VariationPlanner.Plan(spec, composition)
	CompositionMaterializer.Materialize(composition)
	local materialized = VariationMaterializer.Materialize(variation)
	local lighting = LightingMaterializer.Apply()
	return {
		Spec = spec,
		Composition = composition,
		Plan = variation,
		Materialized = materialized,
		Lighting = lighting,
		GenerationSeconds = os.clock() - started,
	}
end

function Runner.RegenerateAndVerify()
	local identityAudit = VariationPlanner.AuditIdentitySpace(Spec.WorldSeed)
	local repeatedAudit = VariationPlanner.AuditIdentitySpace(Spec.WorldSeed)
	local first = Runner.Generate()
	local firstPlan = Validator.ValidatePlan(first.Composition, first.Plan, identityAudit)
	local firstCapture = Validator.CaptureMaterialized()
	local firstAgainst = Validator.ValidateMaterializedAgainstPlan(first.Plan)
	local second = Runner.Generate()
	local secondPlan = Validator.ValidatePlan(second.Composition, second.Plan, repeatedAudit)
	local secondCapture = Validator.CaptureMaterialized()
	local secondAgainst = Validator.ValidateMaterializedAgainstPlan(second.Plan)
	local alternateSpec = table.clone(Spec)
	alternateSpec.WorldSeed += 1
	local alternateComposition = CompositionPlanner.Plan(alternateSpec)
	local alternatePlan = VariationPlanner.Plan(alternateSpec, alternateComposition)
	local deterministicPlan = first.Plan.Signature == second.Plan.Signature
	local deterministicMaterialization = firstCapture.Signature == secondCapture.Signature
	local deterministicAudit = identityAudit.Signature == repeatedAudit.Signature
	local alternateSeedDiffers = alternatePlan.Signature ~= first.Plan.Signature
	local runtimePassed = firstPlan.Passed and secondPlan.Passed
		and firstCapture.Passed and secondCapture.Passed
		and firstAgainst.Passed and secondAgainst.Passed
		and deterministicPlan and deterministicMaterialization and deterministicAudit and alternateSeedDiffers
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone4BaselineSessionId", SESSION_ID)
	local report = {
		Milestone = 4,
		Passed = false,
		Status = if runtimePassed then "PROVISIONAL_GOLDEN_AND_VISUAL_REQUIRED" else "FAILED",
		RuntimeValidationPassed = runtimePassed,
		SessionBoundaryVerified = false,
		HumanVisualSignoff = humanVisualSignoff(),
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
		ClientRuntimeValidationPassed = Evidence.RuntimeClientValidationPassed,
		ClientRuntimeValidationNotes = Evidence.RuntimeClientValidationNotes,
		SessionId = SESSION_ID,
		WorldSeed = Spec.WorldSeed,
		VariationVersion = Config.Version,
		CompositionSignature = first.Composition.Signature,
		PlanSignature = first.Plan.Signature,
		MaterializedSignature = firstCapture.Signature,
		AlternatePlanSignature = alternatePlan.Signature,
		AlternateSeedDiffers = alternateSeedDiffers,
		DeterministicPlan = deterministicPlan,
		DeterministicMaterialization = deterministicMaterialization,
		DeterministicIdentityAudit = deterministicAudit,
		VariantCount = #first.Plan.Variants,
		ComponentCount = first.Plan.ComponentCount,
		UniqueWorldIdentityCount = first.Plan.UniqueIdentityCount,
		RecipeCount = firstPlan.RecipeCount,
		AssetCounts = first.Plan.AssetCounts,
		RoleCounts = first.Plan.RoleCounts,
		Repair = first.Plan.Repair,
		PlanAssertions = firstPlan.Assertions,
		PlanAssertionsPassed = firstPlan.Passed and secondPlan.Passed,
		MaterializedAssertionsPassed = firstCapture.Passed and secondCapture.Passed,
		MaterializedPlanAssertionsPassed = firstAgainst.Passed and secondAgainst.Passed,
		IdentityAuditSignature = identityAudit.Signature,
		IdentityAuditMinimumUnique = identityAudit.MinimumUnique,
		IdentityAuditTotalUnique = identityAudit.TotalUnique,
		IdentityAuditFamilies = identityAudit.Families,
		LOD0Count = secondCapture.LOD0Count,
		LOD1Count = secondCapture.LOD1Count,
		LOD2Count = secondCapture.LOD2Count,
		CollisionCount = secondCapture.CollisionCount,
		GeneratedDescendantCount = secondCapture.GeneratedDescendantCount,
		WithinInstanceBudget = secondCapture.WithinInstanceBudget,
		GenerationSeconds = first.GenerationSeconds,
		RegenerationSeconds = second.GenerationSeconds,
	}
	saveAttributes(report)
	saveJson("MilestoneFourReport", report)
	return report
end

function Runner.RecordVisualSignoff(passed: boolean, notes: string)
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone4HumanVisualSignoff", passed)
	root:SetAttribute("Milestone4VisualSignoffNotes", notes)
	root:SetAttribute("Milestone4VisualSignoffAt", os.time())
	return {Passed = passed, Notes = notes}
end

function Runner.RunGoldenRegression()
	local goldenModule = WorldEngine.Seeds.GoldenSeeds:FindFirstChild("MilestoneFourGolden")
	assert(goldenModule and goldenModule:IsA("ModuleScript"), "MilestoneFourGolden baseline is missing")
	local golden = require(goldenModule)
	assert(not golden.Pending, "MilestoneFourGolden is still pending an intentional baseline")
	local generated = Runner.Generate()
	local identityAudit = VariationPlanner.AuditIdentitySpace(Spec.WorldSeed)
	local planValidation = Validator.ValidatePlan(generated.Composition, generated.Plan, identityAudit)
	local capture = Validator.CaptureMaterialized()
	local againstPlan = Validator.ValidateMaterializedAgainstPlan(generated.Plan)
	local signaturesMatch = golden.VariationVersion == Config.Version
		and golden.WorldSeed == Spec.WorldSeed
		and golden.VariantCount == #generated.Plan.Variants
		and golden.ComponentCount == generated.Plan.ComponentCount
		and golden.RecipeCount == planValidation.RecipeCount
		and golden.IdentityAuditSignature == identityAudit.Signature
		and golden.PlanSignature == generated.Plan.Signature
		and golden.MaterializedSignature == capture.Signature
	local sessionBoundaryVerified = type(golden.BaselineSessionId) == "string"
		and golden.BaselineSessionId ~= "" and golden.BaselineSessionId ~= SESSION_ID
	local visualSignoff = humanVisualSignoff()
	local clientRuntimeValidation = Evidence.RuntimeClientValidationPassed
	local passed = signaturesMatch and sessionBoundaryVerified and visualSignoff
		and clientRuntimeValidation and planValidation.Passed and capture.Passed and againstPlan.Passed
	local report = {
		Milestone = 4,
		Passed = passed,
		Status = if passed then "PASSED_CROSS_SESSION_GOLDEN_ASSET_VARIATION"
			elseif signaturesMatch and not sessionBoundaryVerified then "MATCHED_BUT_SAME_SESSION"
			else "FAILED_OR_GATES_OPEN",
		SessionId = SESSION_ID,
		BaselineSessionId = golden.BaselineSessionId,
		SessionBoundaryVerified = sessionBoundaryVerified,
		HumanVisualSignoff = visualSignoff,
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
		ClientRuntimeValidationPassed = clientRuntimeValidation,
		ClientRuntimeValidationNotes = Evidence.RuntimeClientValidationNotes,
		SignaturesMatch = signaturesMatch,
		WorldSeed = Spec.WorldSeed,
		VariationVersion = Config.Version,
		CompositionSignature = generated.Composition.Signature,
		PlanSignature = generated.Plan.Signature,
		MaterializedSignature = capture.Signature,
		IdentityAuditSignature = identityAudit.Signature,
		IdentityAuditMinimumUnique = identityAudit.MinimumUnique,
		IdentityAuditTotalUnique = identityAudit.TotalUnique,
		VariantCount = #generated.Plan.Variants,
		ComponentCount = generated.Plan.ComponentCount,
		UniqueWorldIdentityCount = generated.Plan.UniqueIdentityCount,
		RecipeCount = planValidation.RecipeCount,
		Repair = generated.Plan.Repair,
		PlanAssertionsPassed = planValidation.Passed,
		MaterializedAssertionsPassed = capture.Passed,
		MaterializedPlanAssertionsPassed = againstPlan.Passed,
		LOD0Count = capture.LOD0Count,
		LOD1Count = capture.LOD1Count,
		LOD2Count = capture.LOD2Count,
		CollisionCount = capture.CollisionCount,
		GeneratedDescendantCount = capture.GeneratedDescendantCount,
		WithinInstanceBudget = capture.WithinInstanceBudget,
		GenerationSeconds = generated.GenerationSeconds,
	}
	saveAttributes(report)
	saveJson("MilestoneFourGoldenRegressionReport", report)
	return report
end

return table.freeze(Runner)
