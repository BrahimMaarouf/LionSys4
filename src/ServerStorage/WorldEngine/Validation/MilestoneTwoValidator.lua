--!strict

local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Catalog = require(WorldEngine.Assets.Rocks.RockCatalog)
local Preset = require(WorldEngine.Config.Lighting.DesertGoldenHour)
local Checksum = require(WorldEngine.Core.Checksum)
local PropPlanner = require(WorldEngine.Planning.RockPlacementPlanner)

type Plan = PropPlanner.Plan

local Validator = {}

local function validAssetId(value: string): boolean
	return value:match("^rbxassetid://%d+$") ~= nil
end

local function allIdsValid(values: {[string]: string}): boolean
	for _, value in values do
		if not validAssetId(value) then
			return false
		end
	end
	return true
end

function Validator.ValidateCatalog()
	local invalidAssets = 0
	local rockCount = 0
	local vegetationCount = 0
	local weightTotal = 0
	for _, asset in Catalog.Assets do
		weightTotal += asset.Weight
		rockCount += if asset.Kind == "Rock" then 1 else 0
		vegetationCount += if asset.Kind == "Vegetation" then 1 else 0
		if not allIdsValid(asset.MeshIds)
			or not allIdsValid(asset.TextureIds)
			or asset.SourceGlb == ""
			or asset.ScaleMin <= 0
			or asset.ScaleMax < asset.ScaleMin
			or asset.SpacingRadius <= 0 then
			invalidAssets += 1
		end
	end
	local shrub = Catalog.ById.DryShrub
	local assertions = {
		ExactlyThreeOwnedAssets = #Catalog.Assets == 3,
		TwoRockOneVegetation = rockCount == 2 and vegetationCount == 1,
		AssetIdFormatsValid = invalidAssets == 0,
		WeightsNormalizeToOne = math.abs(weightTotal - 1) < 0.000001,
		ShrubExercisesAlphaCards = shrub ~= nil and shrub.UsesAlphaCards,
		ShrubExercisesWindPath = shrub ~= nil and shrub.WindEnabled,
		PinnedBlenderVersion = Catalog.Dcc == "Blender 4.5.0 LTS",
	}
	local passed = true
	for _, assertion in assertions do
		passed = passed and assertion
	end
	return {
		Passed = passed,
		Assertions = assertions,
		AssetCount = #Catalog.Assets,
		RockAssetCount = rockCount,
		VegetationAssetCount = vegetationCount,
		InvalidAssetCount = invalidAssets,
		CatalogVersion = Catalog.Version,
	}
end

local function meshMatches(instance: Instance?, expectedId: string): boolean
	return instance ~= nil and instance:IsA("MeshPart") and instance.MeshId == expectedId
end

local function appearanceMatches(instance: Instance?, textureIds, alphaRequired: boolean): boolean
	if not instance or not instance:IsA("MeshPart") then
		return false
	end
	local appearance = instance:FindFirstChildOfClass("SurfaceAppearance")
	return appearance ~= nil
		and appearance.ColorMap == textureIds.BaseColor
		and appearance.NormalMap == textureIds.Normal
		and appearance.RoughnessMap == textureIds.Roughness
		and (not alphaRequired or appearance.AlphaMode == Enum.AlphaMode.Transparency)
end

function Validator.ValidateTemplates()
	local templates = WorldEngine.Assets.Rocks:FindFirstChild("Templates")
	local invalidTemplates = 0
	local alphaTemplateCount = 0
	local collisionProxyCount = 0
	local sourceLodCount = 0
	local importConventionCount = 0
	local textureSetCount = 0
	for _, asset in Catalog.Assets do
		local template = if templates then templates:FindFirstChild(asset.TemplateName) else nil
		local valid = template ~= nil and template:IsA("Model")
		if valid then
			local model = template :: Model
			local collision = model:FindFirstChild("Collision")
			local lods = model:FindFirstChild("LODVariants")
			valid = meshMatches(collision, asset.MeshIds.Collision)
				and lods ~= nil and lods:IsA("Folder")
				and meshMatches(lods:FindFirstChild("LOD1"), asset.MeshIds.LOD1)
				and meshMatches(lods:FindFirstChild("LOD2"), asset.MeshIds.LOD2)
			if valid then
				collisionProxyCount += 1
				sourceLodCount += 2
			end
			local renderParts = {}
			if asset.Kind == "Rock" then
				local render = model:FindFirstChild("Render")
				valid = valid and meshMatches(render, asset.MeshIds.LOD0)
				table.insert(renderParts, render)
				if appearanceMatches(render, asset.TextureIds, false) then
					textureSetCount += 1
				else
					valid = false
				end
			else
				local branches = model:FindFirstChild("Branches")
				local foliage = model:FindFirstChild("Foliage")
				valid = valid
					and meshMatches(branches, asset.MeshIds.BranchesLOD0)
					and meshMatches(foliage, asset.MeshIds.FoliageLOD0)
				table.insert(renderParts, branches)
				table.insert(renderParts, foliage)
				local appearance = if foliage then foliage:FindFirstChildOfClass("SurfaceAppearance") else nil
				if appearanceMatches(foliage, asset.TextureIds, true) then
					alphaTemplateCount += 1
					textureSetCount += 1
				else
					valid = false
				end
			end
			local bottomY = math.huge
			for _, part in renderParts do
				if part and part:IsA("BasePart") then
					bottomY = math.min(bottomY, part.Position.Y - part.Size.Y * 0.5)
				end
			end
			local collisionValid = collision ~= nil and collision:IsA("MeshPart")
				and collision.Transparency == 1 and collision.CanCollide and not collision.CanTouch
			local pivotGrounded = math.abs(bottomY - model.WorldPivot.Position.Y) <= 0.01
			if collisionValid and pivotGrounded then
				importConventionCount += 1
			else
				valid = false
			end
		end
		if not valid then
			invalidTemplates += 1
		end
	end
	return {
		Passed = templates ~= nil and #templates:GetChildren() == #Catalog.Assets and invalidTemplates == 0,
		TemplateCount = if templates then #templates:GetChildren() else 0,
		InvalidTemplateCount = invalidTemplates,
		CollisionProxyCount = collisionProxyCount,
		SourceLODCount = sourceLodCount,
		AlphaTemplateCount = alphaTemplateCount,
		ImportConventionCount = importConventionCount,
		TextureSetCount = textureSetCount,
	}
end

function Validator.ValidatePlan(spec, plan: Plan)
	local assetCounts: {[string]: number} = {}
	local outOfBounds = 0
	local slopeViolations = 0
	local spacingViolations = 0
	local spawnViolations = 0

	for index, placement in plan.Placements do
		local asset = Catalog.ById[placement.AssetId]
		assetCounts[placement.AssetId] = (assetCounts[placement.AssetId] or 0) + 1
		if placement.WorldX < spec.OriginX or placement.WorldX > spec.OriginX + spec.WorldSize
			or placement.WorldZ < spec.OriginZ or placement.WorldZ > spec.OriginZ + spec.WorldSize then
			outOfBounds += 1
		end
		if not asset or placement.SlopeDegrees > asset.MaxSlopeDegrees then
			slopeViolations += 1
		end
		if placement.WorldX * placement.WorldX + placement.WorldZ * placement.WorldZ < 52 * 52 then
			spawnViolations += 1
		end
		for otherIndex = 1, index - 1 do
			local other = plan.Placements[otherIndex]
			local dx = placement.WorldX - other.WorldX
			local dz = placement.WorldZ - other.WorldZ
			local minimum = placement.SpacingRadius + other.SpacingRadius
			if dx * dx + dz * dz < minimum * minimum then
				spacingViolations += 1
			end
		end
	end

	local representedAssets = 0
	for _, asset in Catalog.Assets do
		if (assetCounts[asset.Id] or 0) > 0 then
			representedAssets += 1
		end
	end
	return {
		Passed = #plan.Placements >= 24
			and representedAssets == #Catalog.Assets
			and outOfBounds == 0
			and slopeViolations == 0
			and spacingViolations == 0
			and spawnViolations == 0,
		PlacementCount = #plan.Placements,
		RepresentedAssets = representedAssets,
		AssetCounts = assetCounts,
		OutOfBounds = outOfBounds,
		SlopeViolations = slopeViolations,
		SpacingViolations = spacingViolations,
		SpawnViolations = spawnViolations,
		Signature = plan.Signature,
	}
end

function Validator.CaptureMaterialized()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local folder = generated:FindFirstChild("DesertProps")
	if not folder then
		return { Signature = "missing", ModelCount = 0, InvalidModelCount = 1, CustomLODCount = 0 }
	end
	local models = folder:GetChildren()
	table.sort(models, function(left, right)
		return (left:GetAttribute("PlacementIndex") or 0) < (right:GetAttribute("PlacementIndex") or 0)
	end)
	local state = Checksum.New()
	local invalidModels = 0
	local customLODCount = 0
	Checksum.UpdateString(state, Catalog.Version)
	Checksum.UpdateUInt32(state, #models)
	for index, instance in models do
		if not instance:IsA("Model") then
			invalidModels += 1
			continue
		end
		local assetId = instance:GetAttribute("SourceAsset")
		local asset = if type(assetId) == "string" then Catalog.ById[assetId] else nil
		if not asset or instance:FindFirstChild("LODVariants") then
			invalidModels += 1
			continue
		end
		local lod1 = instance:FindFirstChild("LOD1")
		local lod2 = instance:FindFirstChild("LOD2")
		if not meshMatches(lod1, asset.MeshIds.LOD1)
			or not meshMatches(lod2, asset.MeshIds.LOD2)
			or not CollectionService:HasTag(instance, "WorldEngineCustomLOD")
			or instance.LevelOfDetail ~= Enum.ModelLevelOfDetail.Disabled then
			invalidModels += 1
		else
			customLODCount += 1
		end
		local meshes = {}
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("MeshPart") then
				table.insert(meshes, descendant)
			end
		end
		table.sort(meshes, function(left, right) return left.Name < right.Name end)
		local expectedMeshCount = if asset.Kind == "Vegetation" then 5 else 4
		if #meshes ~= expectedMeshCount then
			invalidModels += 1
		end
		for _, mesh in meshes do
			if not mesh.Anchored
				or (mesh.Name ~= "Collision" and mesh.RenderFidelity ~= Enum.RenderFidelity.Precise) then
				invalidModels += 1
			end
			Checksum.UpdateString(state, mesh.Name)
			Checksum.UpdateString(state, mesh.MeshId)
			Checksum.UpdateUInt32(state, math.floor(mesh.Position.X * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(mesh.Position.Y * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(mesh.Position.Z * 1024 + 0.5))
		end
		Checksum.UpdateUInt32(state, index)
		Checksum.UpdateString(state, assetId :: string)
		Checksum.UpdateUInt32(state, math.floor(instance:GetScale() * 65536 + 0.5))
	end
	return {
		Signature = Checksum.Digest(state),
		ModelCount = #models,
		InvalidModelCount = invalidModels,
		CustomLODCount = customLODCount,
	}
end

function Validator.ValidateMaterializedAgainstPlan(plan: Plan)
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local folder = generated:FindFirstChild("DesertProps")
	if not folder then
		return { Passed = false, PositionMismatches = #plan.Placements, NormalMismatches = #plan.Placements }
	end
	local positionMismatches = 0
	local normalMismatches = 0
	for _, placement in plan.Placements do
		local asset = Catalog.ById[placement.AssetId]
		local model = folder:FindFirstChild(string.format("%03d_%s", placement.Index, placement.AssetId))
		if not asset or not model or not model:IsA("Model") then
			positionMismatches += 1
			normalMismatches += 1
			continue
		end
		local pivot = model:GetPivot()
		local expected = Vector3.new(
			placement.WorldX,
			placement.GroundY - asset.SinkStuds * placement.Scale,
			placement.WorldZ
		)
		if (pivot.Position - expected).Magnitude > 0.001 then
			positionMismatches += 1
		end
		if pivot.UpVector:Dot(placement.Normal) < 0.9999 then
			normalMismatches += 1
		end
	end
	return {
		Passed = positionMismatches == 0 and normalMismatches == 0,
		PositionMismatches = positionMismatches,
		NormalMismatches = normalMismatches,
	}
end

local function near(left: number, right: number): boolean
	return math.abs(left - right) <= 0.0001
end

local function colorNear(left: Color3, right: Color3): boolean
	return near(left.R, right.R) and near(left.G, right.G) and near(left.B, right.B)
end

function Validator.ValidateLighting(presetName: string)
	local atmosphere = Lighting:FindFirstChild("WorldEngineAtmosphere")
	local correction = Lighting:FindFirstChild("WorldEngineColorCorrection")
	local sunRays = Lighting:FindFirstChild("WorldEngineSunRays")
	local assertions = {
		PresetName = presetName == Preset.Name,
		ClockTime = near(Lighting.ClockTime, Preset.ClockTime),
		Brightness = near(Lighting.Brightness, Preset.Brightness),
		Exposure = near(Lighting.ExposureCompensation, Preset.ExposureCompensation),
		Ambient = colorNear(Lighting.Ambient, Preset.Ambient),
		OutdoorAmbient = colorNear(Lighting.OutdoorAmbient, Preset.OutdoorAmbient),
		ColorShiftTop = colorNear(Lighting.ColorShift_Top, Preset.ColorShiftTop),
		ColorShiftBottom = colorNear(Lighting.ColorShift_Bottom, Preset.ColorShiftBottom),
		DiffuseScale = near(Lighting.EnvironmentDiffuseScale, Preset.EnvironmentDiffuseScale),
		SpecularScale = near(Lighting.EnvironmentSpecularScale, Preset.EnvironmentSpecularScale),
		ShadowSoftness = near(Lighting.ShadowSoftness, Preset.ShadowSoftness),
		GlobalShadows = Lighting.GlobalShadows,
		Atmosphere = atmosphere ~= nil and atmosphere:IsA("Atmosphere")
			and near(atmosphere.Density, Preset.AtmosphereDensity)
			and near(atmosphere.Offset, Preset.AtmosphereOffset)
			and colorNear(atmosphere.Color, Preset.AtmosphereColor)
			and colorNear(atmosphere.Decay, Preset.AtmosphereDecay)
			and near(atmosphere.Glare, Preset.AtmosphereGlare)
			and near(atmosphere.Haze, Preset.AtmosphereHaze),
		ColorCorrection = correction ~= nil and correction:IsA("ColorCorrectionEffect")
			and near(correction.Brightness, Preset.ColorCorrectionBrightness)
			and near(correction.Contrast, Preset.ColorCorrectionContrast)
			and near(correction.Saturation, Preset.ColorCorrectionSaturation)
			and colorNear(correction.TintColor, Preset.ColorCorrectionTint),
		SunRays = sunRays ~= nil and sunRays:IsA("SunRaysEffect")
			and near(sunRays.Intensity, Preset.SunRaysIntensity)
			and near(sunRays.Spread, Preset.SunRaysSpread),
	}
	local passed = true
	for _, assertion in assertions do
		passed = passed and assertion
	end
	return { Passed = passed, Preset = presetName, Assertions = assertions }
end

return table.freeze(Validator)
