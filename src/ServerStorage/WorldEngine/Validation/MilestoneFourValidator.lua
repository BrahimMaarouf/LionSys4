--!strict

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Checksum = require(WorldEngine.Core.Checksum)
local Config = require(WorldEngine.Config.Variation.DesertAssetFamilies)
local CompositionPlanner = require(WorldEngine.Planning.DesertCompositionPlanner)
local Planner = require(WorldEngine.Planning.AssetVariationPlanner)

type CompositionPlan = CompositionPlanner.Plan
type Plan = Planner.Plan

local Validator = {}

local function countKeys(values): number
	local count = 0
	for _ in values do count += 1 end
	return count
end

function Validator.ValidatePlan(composition: CompositionPlan, plan: Plan, identityAudit)
	local missingRecipes = 0
	for _, family in Config.Families do
		for _, recipe in family.Recipes do
			if not plan.RecipeCounts[family.AssetId .. "/" .. recipe.Id] then
				missingRecipes += 1
			end
		end
	end
	local malformedComponents = 0
	local footprintViolations = 0
	for _, variant in plan.Variants do
		if #variant.Components < 1 or #variant.Components > 3 then
			malformedComponents += 1
		end
		if variant.FootprintRadius > variant.ReservedRadius * Config.FootprintUtilizationLimit + 0.001 then
			footprintViolations += 1
		end
		for index, component in variant.Components do
			if component.Index ~= index or component.CollisionRadius <= 0
				or component.UniformScale <= 0 or component.StretchX <= 0
				or component.StretchY <= 0 or component.StretchZ <= 0 then
				malformedComponents += 1
			end
		end
	end
	local auditPassed = identityAudit.MinimumUnique >= Config.MinimumUniqueIdentitiesPerFamily
	for _, familyResult in identityAudit.Families do
		auditPassed = auditPassed and familyResult.Passed
	end
	local assertions = {
		VersionMatches = plan.Version == Config.Version,
		SeedMatches = plan.WorldSeed == composition.WorldSeed,
		CompositionUnchanged = plan.CompositionSignature == composition.Signature,
		BaseAccountingMatches = #plan.Variants + plan.Repair.OmittedBySafety == plan.BasePlacementCount,
		UsefulVariantCount = #plan.Variants >= plan.BasePlacementCount - Config.MaximumSafetyOmissions,
		WithinVariantBudget = #plan.Variants <= Config.MaximumVariants,
		WithinComponentBudget = plan.ComponentCount <= Config.MaximumComponents,
		ActuallyComposesAssets = plan.ComponentCount >= #plan.Variants + 20,
		AllRecipesCovered = missingRecipes == 0,
		AllFamiliesCovered = countKeys(plan.AssetCounts) == #Config.Families,
		AllWorldIdentitiesUnique = plan.DuplicateIdentityCount == 0 and plan.UniqueIdentityCount == #plan.Variants,
		FootprintsReserved = footprintViolations == 0,
		ComponentsWellFormed = malformedComponents == 0,
		SafetyRepairBounded = plan.Repair.OmittedBySafety <= Config.MaximumSafetyOmissions,
		IdentitySpaceProvesHundreds = auditPassed and identityAudit.TotalUnique >= 1440,
	}
	local passed = true
	for _, assertion in assertions do passed = passed and assertion end
	return {
		Passed = passed,
		Assertions = assertions,
		VariantCount = #plan.Variants,
		ComponentCount = plan.ComponentCount,
		UniqueIdentityCount = plan.UniqueIdentityCount,
		MissingRecipes = missingRecipes,
		MalformedComponents = malformedComponents,
		FootprintViolations = footprintViolations,
		RecipeCount = countKeys(plan.RecipeCounts),
		AssetCounts = plan.AssetCounts,
		RoleCounts = plan.RoleCounts,
		Repair = plan.Repair,
		IdentityAudit = identityAudit,
		Signature = plan.Signature,
	}
end

local function sortedChildren(folder: Instance, attribute: string): {Instance}
	local children = folder:GetChildren()
	table.sort(children, function(left, right)
		return (left:GetAttribute(attribute) or 0) < (right:GetAttribute(attribute) or 0)
	end)
	return children
end

function Validator.CaptureMaterialized()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local props = generated:FindFirstChild("DesertProps")
	if not props or not props:IsA("Folder") then
		return {Passed = false, Signature = "missing", ModelCount = 0, InvalidModels = 1}
	end
	local models = sortedChildren(props, "VariantIndex")
	local state = Checksum.New()
	Checksum.UpdateString(state, Config.Version)
	Checksum.UpdateUInt32(state, #models)
	local invalidModels = 0
	local componentCount = 0
	local collisionCount = 0
	local lod0Count = 0
	local lod1Count = 0
	local lod2Count = 0
	local vegetationCount = 0
	for modelIndex, instance in models do
		if not instance:IsA("Model") then
			invalidModels += 1
			continue
		end
		local variantIndex = instance:GetAttribute("VariantIndex")
		local assetId = instance:GetAttribute("SourceAsset")
		local recipeId = instance:GetAttribute("RecipeId")
		local identity = instance:GetAttribute("IdentityKey")
		if variantIndex ~= modelIndex or type(assetId) ~= "string" or type(recipeId) ~= "string"
			or type(identity) ~= "string" or instance:GetAttribute("VariationVersion") ~= Config.Version
			or not instance.PrimaryPart or instance.PrimaryPart.Name ~= "VariantAnchor"
			or instance.PrimaryPart.CanCollide or instance.PrimaryPart.Transparency ~= 1 then
			invalidModels += 1
			continue
		end
		local components = {}
		for _, child in instance:GetChildren() do
			if child:IsA("Model") and type(child:GetAttribute("ComponentIndex")) == "number" then
				table.insert(components, child)
			end
		end
		table.sort(components, function(left, right)
			return left:GetAttribute("ComponentIndex") < right:GetAttribute("ComponentIndex")
		end)
		if #components ~= instance:GetAttribute("ComponentCount") then
			invalidModels += 1
		end
		componentCount += #components
		if instance:GetAttribute("AssetKind") == "Vegetation" then vegetationCount += 1 end
		Checksum.UpdateIndexedUInt32(state, modelIndex, variantIndex)
		Checksum.UpdateString(state, assetId)
		Checksum.UpdateString(state, recipeId)
		Checksum.UpdateString(state, identity)
		Checksum.UpdateString(state, instance:GetAttribute("CompositionRole") or "")
		Checksum.UpdateString(state, instance:GetAttribute("CompositionZone") or "")
		for componentIndex, component in components do
			if component:GetAttribute("ComponentIndex") ~= componentIndex then invalidModels += 1 end
			local localLod0 = 0
			local localLod1 = 0
			local localLod2 = 0
			local localCollision = 0
			for _, descendant in component:GetDescendants() do
				if descendant:IsA("MeshPart") then
					local level = descendant:GetAttribute("WorldEngineLODLevel")
					if level == 0 then localLod0 += 1
					elseif level == 1 then localLod1 += 1
					elseif level == 2 then localLod2 += 1
					elseif descendant:GetAttribute("WorldEngineVariationCollision") then localCollision += 1
					end
					if level ~= nil and (not descendant.Anchored or descendant.CanCollide or descendant.CanQuery) then
						invalidModels += 1
					end
					if descendant:GetAttribute("WorldEngineVariationCollision")
						and (not descendant.Anchored or not descendant.CanCollide or not descendant.CanQuery or descendant.Transparency ~= 1) then
						invalidModels += 1
					end
				end
			end
			local expectedLod0 = if instance:GetAttribute("AssetKind") == "Vegetation" then 2 else 1
			if localLod0 ~= expectedLod0 or localLod1 ~= 1 or localLod2 ~= 1 or localCollision ~= 1 then
				invalidModels += 1
			end
			lod0Count += localLod0
			lod1Count += localLod1
			lod2Count += localLod2
			collisionCount += localCollision
			local pivot = component:GetPivot()
			Checksum.UpdateIndexedUInt32(state, componentIndex, math.floor(pivot.Position.X * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(pivot.Position.Y * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(pivot.Position.Z * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor((component:GetAttribute("UniformScale") or 0) * 65536 + 0.5))
			Checksum.UpdateUInt32(state, math.floor((component:GetAttribute("StretchX") or 0) * 65536 + 0.5))
			Checksum.UpdateUInt32(state, math.floor((component:GetAttribute("StretchY") or 0) * 65536 + 0.5))
			Checksum.UpdateUInt32(state, math.floor((component:GetAttribute("StretchZ") or 0) * 65536 + 0.5))
			Checksum.UpdateUInt32(state, component:GetAttribute("TintIndex") or 0)
		end
	end
	local descendants = #generated:GetDescendants()
	local variantTags = #CollectionService:GetTagged("WorldEngineAssetVariant")
	local lodTags = #CollectionService:GetTagged("WorldEngineCustomLOD")
	local windTags = #CollectionService:GetTagged("WorldEngineWindVegetation")
	local passed = invalidModels == 0
		and collisionCount == componentCount
		and lod1Count == componentCount and lod2Count == componentCount
		and variantTags == #models and lodTags == #models and windTags == vegetationCount
		and descendants <= Config.GeneratedDescendantBudget
	return {
		Passed = passed,
		Signature = Checksum.Digest(state),
		ModelCount = #models,
		ComponentCount = componentCount,
		CollisionCount = collisionCount,
		LOD0Count = lod0Count,
		LOD1Count = lod1Count,
		LOD2Count = lod2Count,
		VegetationCount = vegetationCount,
		InvalidModels = invalidModels,
		GeneratedDescendantCount = descendants,
		WithinInstanceBudget = descendants <= Config.GeneratedDescendantBudget,
		VariantTagCount = variantTags,
		LODTagCount = lodTags,
		WindTagCount = windTags,
	}
end

function Validator.ValidateMaterializedAgainstPlan(plan: Plan)
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local props = generated:FindFirstChild("DesertProps")
	if not props then return {Passed = false, MissingVariants = #plan.Variants, ComponentMismatches = plan.ComponentCount} end
	local missingVariants = 0
	local metadataMismatches = 0
	local componentMismatches = 0
	local positionMismatches = 0
	for _, variant in plan.Variants do
		local name = string.format("%03d_%s_%s", variant.Index, variant.AssetId, variant.RecipeId)
		local model = props:FindFirstChild(name)
		if not model or not model:IsA("Model") then
			missingVariants += 1
			continue
		end
		if model:GetAttribute("IdentityKey") ~= variant.IdentityKey
			or model:GetAttribute("BasePlacementIndex") ~= variant.BasePlacementIndex
			or model:GetAttribute("ComponentCount") ~= #variant.Components then
			metadataMismatches += 1
		end
		if not model.PrimaryPart or (model.PrimaryPart.Position - Vector3.new(variant.WorldX, variant.GroundY, variant.WorldZ)).Magnitude > 0.001 then
			positionMismatches += 1
		end
		for _, componentPlan in variant.Components do
			local component = model:FindFirstChild(string.format("Component_%02d_%s", componentPlan.Index, componentPlan.AssetId))
			if not component or not component:IsA("Model") then
				componentMismatches += 1
				continue
			end
			if (component:GetPivot().Position - Vector3.new(componentPlan.WorldX, componentPlan.PivotY, componentPlan.WorldZ)).Magnitude > 0.001 then
				positionMismatches += 1
			end
			if math.abs((component:GetAttribute("UniformScale") or 0) - componentPlan.UniformScale) > 0.000001
				or component:GetAttribute("TintIndex") ~= componentPlan.TintIndex then
				metadataMismatches += 1
			end
		end
	end
	return {
		Passed = missingVariants == 0 and metadataMismatches == 0 and componentMismatches == 0 and positionMismatches == 0,
		MissingVariants = missingVariants,
		MetadataMismatches = metadataMismatches,
		ComponentMismatches = componentMismatches,
		PositionMismatches = positionMismatches,
	}
end

return table.freeze(Validator)
