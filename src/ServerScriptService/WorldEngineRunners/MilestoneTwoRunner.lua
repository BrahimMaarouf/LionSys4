--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Catalog = require(WorldEngine.Assets.Rocks.RockCatalog)
local Spec = require(WorldEngine.Config.WorldSpecs.DesertVerticalSlice)
local Evidence = require(WorldEngine.Config.MilestoneTwoPipelineEvidence)
local LightingMaterializer = require(WorldEngine.Materialization.DesertLightingMaterializer)
local TextureApplier = require(WorldEngine.Assets.Rocks.MilestoneSevenTextureApplier)
local PropMaterializer = require(WorldEngine.Materialization.RockMaterializer)
local PropPlanner = require(WorldEngine.Planning.RockPlacementPlanner)
local Validator = require(WorldEngine.Validation.MilestoneTwoValidator)

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

local function humanVisualSignoff(): boolean
	local root = Workspace:WaitForChild("WorldRoot")
	local override = root:GetAttribute("Milestone2HumanVisualSignoff")
	if type(override) == "boolean" then
		return override
	end
	return Evidence.HumanVisualSignoffPassed
end

local function saveJson(name: string, report)
	local diagnostics = Workspace:WaitForChild("WorldRoot"):WaitForChild("Diagnostics")
	local value = diagnostics:FindFirstChild(name)
	if not value then
		value = Instance.new("StringValue")
		value.Name = name
		value.Parent = diagnostics
	end
	assert(value:IsA("StringValue"))
	value.Value = HttpService:JSONEncode(report)
end

local function saveAttributes(report)
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone2Passed", report.Passed)
	root:SetAttribute("Milestone2Status", report.Status)
	root:SetAttribute("Milestone2VerifiedAt", os.time())
	root:SetAttribute("Milestone2CatalogVersion", Catalog.Version)
	root:SetAttribute("Milestone2PlacementSignature", report.PlacementSignature)
	root:SetAttribute("Milestone2MaterializedSignature", report.MaterializedSignature)
	root:SetAttribute("Milestone2PropCount", report.PropCount)
	root:SetAttribute("Milestone2LightingPreset", report.LightingPreset)
	root:SetAttribute("Milestone2SessionBoundaryVerified", report.SessionBoundaryVerified or false)
	root:SetAttribute("Milestone2BlenderPipelineVerified", report.BlenderPipelineVerified or report.PipelinePassed or false)
	root:SetAttribute("Milestone2HumanVisualSignoff", report.HumanVisualSignoff or false)
	root:SetAttribute("Milestone2SourceManifestSchema", Evidence.SourceManifestSchema)
	root:SetAttribute("Milestone2TemplateArtifactSha256", Evidence.TemplateArtifactSha256)
end

function Runner.Generate()
	TextureApplier.Apply()
	local plan = PropPlanner.Plan(Spec)
	PropMaterializer.Materialize(plan)
	local lighting = LightingMaterializer.Apply()
	return { Plan = plan, Lighting = lighting }
end

function Runner.RegenerateAndVerify()
	TextureApplier.Apply()
	local catalogValidation = Validator.ValidateCatalog()
	local templateValidation = Validator.ValidateTemplates()
	local first = Runner.Generate()
	local firstPlanValidation = Validator.ValidatePlan(Spec, first.Plan)
	local firstMaterialized = Validator.CaptureMaterialized()
	local firstMaterializedPlan = Validator.ValidateMaterializedAgainstPlan(first.Plan)
	local lightingValidation = Validator.ValidateLighting(first.Lighting.Preset)
	local second = Runner.Generate()
	local secondPlanValidation = Validator.ValidatePlan(Spec, second.Plan)
	local secondMaterialized = Validator.CaptureMaterialized()
	local secondMaterializedPlan = Validator.ValidateMaterializedAgainstPlan(second.Plan)

	local alternateSpec = table.clone(Spec)
	alternateSpec.WorldSeed += 1
	local alternate = PropPlanner.Plan(alternateSpec)
	local alternateSeedDiffers = alternate.Signature ~= first.Plan.Signature
	local deterministicPlan = first.Plan.Signature == second.Plan.Signature
	local deterministicMaterialization = firstMaterialized.Signature == secondMaterialized.Signature
	local expectedCountMatches = firstMaterialized.ModelCount == #first.Plan.Placements
		and secondMaterialized.ModelCount == #second.Plan.Placements
	local runtimePassed = catalogValidation.Passed
		and templateValidation.Passed
		and firstPlanValidation.Passed
		and secondPlanValidation.Passed
		and firstMaterialized.InvalidModelCount == 0
		and secondMaterialized.InvalidModelCount == 0
		and firstMaterialized.CustomLODCount == firstMaterialized.ModelCount
		and secondMaterialized.CustomLODCount == secondMaterialized.ModelCount
		and firstMaterializedPlan.Passed
		and secondMaterializedPlan.Passed
		and lightingValidation.Passed
		and deterministicPlan
		and deterministicMaterialization
		and expectedCountMatches
		and alternateSeedDiffers

	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone2BaselineSessionId", SESSION_ID)
	local report = {
		Milestone = 2,
		Passed = false,
		Status = if runtimePassed then "PROVISIONAL_CROSS_SESSION_AND_VISUAL_REQUIRED" else "FAILED",
		RuntimeValidationPassed = runtimePassed,
		SessionBoundaryVerified = false,
		BlenderPipelineVerified = Evidence.DccValidationPassed,
		OwnedSourceAssetsVerified = Evidence.CreatorStoreAssetCount == 0 and catalogValidation.Passed,
		SourceManifestSchema = Evidence.SourceManifestSchema,
		TemplateArtifactSha256 = Evidence.TemplateArtifactSha256,
		HumanVisualSignoff = humanVisualSignoff(),
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
		SessionId = SESSION_ID,
		WorldSeed = Spec.WorldSeed,
		CatalogVersion = Catalog.Version,
		AssetFamily = Catalog.Family,
		AssetCount = catalogValidation.AssetCount,
		TemplateCount = templateValidation.TemplateCount,
		PropCount = #first.Plan.Placements,
		PlacementSignature = first.Plan.Signature,
		MaterializedSignature = firstMaterialized.Signature,
		AlternatePlacementSignature = alternate.Signature,
		AlternateSeedDiffers = alternateSeedDiffers,
		DeterministicPlan = deterministicPlan,
		DeterministicMaterialization = deterministicMaterialization,
		InvalidMaterializedModels = secondMaterialized.InvalidModelCount,
		CustomLODCount = secondMaterialized.CustomLODCount,
		MaterializedPlanAssertionsPassed = firstMaterializedPlan.Passed and secondMaterializedPlan.Passed,
		AssetCounts = firstPlanValidation.AssetCounts,
		PlanAssertionsPassed = firstPlanValidation.Passed and secondPlanValidation.Passed,
		TemplateAssertionsPassed = templateValidation.Passed,
		LightingPreset = lightingValidation.Preset,
		LightingPassed = lightingValidation.Passed,
		LightingAssertions = lightingValidation.Assertions,
	}
	saveAttributes(report)
	saveJson("MilestoneTwoReport", report)
	return report
end

function Runner.RecordVisualSignoff(passed: boolean, notes: string)
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone2HumanVisualSignoff", passed)
	root:SetAttribute("Milestone2VisualSignoffNotes", notes)
	root:SetAttribute("Milestone2VisualSignoffAt", os.time())
	return { Passed = passed, Notes = notes }
end

function Runner.RunGoldenRegression()
	TextureApplier.Apply()
	local goldenModule = WorldEngine.Seeds.GoldenSeeds:FindFirstChild("MilestoneTwoGolden")
	assert(goldenModule and goldenModule:IsA("ModuleScript"), "MilestoneTwoGolden baseline is missing")
	local golden = require(goldenModule)
	local generated = Runner.Generate()
	local capture = Validator.CaptureMaterialized()
	local materializedPlan = Validator.ValidateMaterializedAgainstPlan(generated.Plan)
	local catalogValidation = Validator.ValidateCatalog()
	local templateValidation = Validator.ValidateTemplates()
	local lightingValidation = Validator.ValidateLighting(generated.Lighting.Preset)
	local signaturesMatch = golden.CatalogVersion == Catalog.Version
		and golden.WorldSeed == Spec.WorldSeed
		and golden.PlacementSignature == generated.Plan.Signature
		and golden.MaterializedSignature == capture.Signature
		and golden.PropCount == #generated.Plan.Placements
	local root = Workspace:WaitForChild("WorldRoot")
	local baselineSessionId = golden.BaselineSessionId or root:GetAttribute("Milestone2BaselineSessionId")
	local sessionBoundaryVerified = type(baselineSessionId) == "string" and baselineSessionId ~= SESSION_ID
	local visualSignoff = humanVisualSignoff()
	local pipelinePassed = Evidence.DccValidationPassed
		and Evidence.CreatorStoreAssetCount == 0
		and Evidence.SourceManifestSchema == 2
		and catalogValidation.Passed
		and templateValidation.Passed
		and lightingValidation.Passed
		and capture.CustomLODCount == capture.ModelCount
		and materializedPlan.Passed
	local passed = signaturesMatch and sessionBoundaryVerified and visualSignoff and pipelinePassed
	local report = {
		Milestone = 2,
		Passed = passed,
		Status = if passed
			then "PASSED_CROSS_SESSION_CUMULATIVE_READY"
			elseif signaturesMatch and not sessionBoundaryVerified
			then "MATCHED_BUT_SAME_SESSION"
			else "FAILED_OR_GATES_OPEN",
		CurrentSessionMatched = signaturesMatch,
		SessionBoundaryVerified = sessionBoundaryVerified,
		PipelinePassed = pipelinePassed,
		HumanVisualSignoff = visualSignoff,
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
		CustomLODCount = capture.CustomLODCount,
		MaterializedPlanAssertionsPassed = materializedPlan.Passed,
		SessionId = SESSION_ID,
		BaselineSessionId = baselineSessionId,
		CatalogVersion = Catalog.Version,
		WorldSeed = Spec.WorldSeed,
		PropCount = #generated.Plan.Placements,
		PlacementSignature = generated.Plan.Signature,
		MaterializedSignature = capture.Signature,
		LightingPreset = lightingValidation.Preset,
		ExpectedPlacementSignature = golden.PlacementSignature,
		ExpectedMaterializedSignature = golden.MaterializedSignature,
	}
	saveAttributes(report)
	saveJson("MilestoneTwoGoldenRegressionReport", report)
	return report
end

return table.freeze(Runner)
