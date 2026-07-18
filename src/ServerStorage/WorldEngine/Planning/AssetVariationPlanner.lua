--!strict

local ServerStorage = game:GetService("ServerStorage")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Catalog = require(WorldEngine.Assets.Rocks.RockCatalog)
local Checksum = require(WorldEngine.Core.Checksum)
local Hash32 = require(WorldEngine.Core.Hash32)
local Config = require(WorldEngine.Config.Variation.DesertAssetFamilies)
local CompositionConfig = require(WorldEngine.Config.Composition.DesertPilgrimage)
local CompositionPlanner = require(WorldEngine.Planning.DesertCompositionPlanner)
local HeightfieldPlanner = require(WorldEngine.Planning.HeightfieldPlanner)

type WorldSpec = HeightfieldPlanner.WorldSpec
type CompositionPlan = CompositionPlanner.Plan
type CompositionPlacement = CompositionPlanner.Placement

export type VariationComponent = {
	Index: number,
	AssetId: string,
	WorldX: number,
	PivotY: number,
	WorldZ: number,
	Normal: Vector3,
	YawRadians: number,
	PitchRadians: number,
	RollRadians: number,
	UniformScale: number,
	StretchX: number,
	StretchY: number,
	StretchZ: number,
	TintIndex: number,
	CollisionRadius: number,
	LocalDistance: number,
}

export type Variant = {
	Index: number,
	BasePlacementIndex: number,
	AssetId: string,
	AssetKind: string,
	RecipeId: string,
	RecipeIndex: number,
	IdentityKey: string,
	VariantSeed: number,
	Role: string,
	ZoneId: string,
	WorldX: number,
	GroundY: number,
	WorldZ: number,
	Normal: Vector3,
	YawRadians: number,
	Scale: number,
	ReservedRadius: number,
	FootprintRadius: number,
	Components: {VariationComponent},
}

export type RepairStats = {
	RejectedAttempts: number,
	RecipeFallbacks: number,
	OmittedBySafety: number,
	RejectedByFootprint: number,
	RejectedByBounds: number,
	RejectedBySpawn: number,
	RejectedByPath: number,
	RejectedByLandmark: number,
	RejectedBySlope: number,
	RejectedBySpacing: number,
}

export type Plan = {
	Version: string,
	WorldSeed: number,
	CompositionSignature: string,
	BasePlacementCount: number,
	Variants: {Variant},
	ComponentCount: number,
	AssetCounts: {[string]: number},
	RecipeCounts: {[string]: number},
	RoleCounts: {[string]: number},
	UniqueIdentityCount: number,
	DuplicateIdentityCount: number,
	Repair: RepairStats,
	Signature: string,
}

local CHANNEL = 0x4D345641
local Planner = {}

local function unit(seed: number, a: number, b: number, c: number, property: number): number
	-- Put the property channel before the varying coordinates. FNV-1a is a
	-- streaming hash, so appending adjacent property numbers at the end creates
	-- visibly correlated quantized bins even though the raw hashes differ.
	return (Hash32.ToSignedUnit(Hash32.HashIntegers(seed, CHANNEL, property, a, b, c)) + 1) * 0.5
end

local function degrees(value: number): number
	return value / 180 * math.pi
end

local function quantized(value: number, minimum: number, maximum: number, bins: number): (number, number)
	local index = math.clamp(math.floor(value * bins), 0, bins - 1)
	local alpha = if bins > 1 then index / (bins - 1) else 0
	return minimum + (maximum - minimum) * alpha, index
end

local function sampleSurface(spec: WorldSpec, worldX: number, worldZ: number): (number, Vector3, number)
	local step = spec.Resolution * 2
	local left = HeightfieldPlanner.HeightAt(spec, worldX - step, worldZ)
	local right = HeightfieldPlanner.HeightAt(spec, worldX + step, worldZ)
	local back = HeightfieldPlanner.HeightAt(spec, worldX, worldZ - step)
	local front = HeightfieldPlanner.HeightAt(spec, worldX, worldZ + step)
	local center = HeightfieldPlanner.HeightAt(spec, worldX, worldZ)
	local dx = (right - left) / (step * 2)
	local dz = (front - back) / (step * 2)
	local normal = Vector3.new(-dx, 1, -dz).Unit
	return center + spec.Resolution * 0.5, normal, math.deg(math.atan(math.sqrt(dx * dx + dz * dz)))
end

local function recipeIndexFor(spec: WorldSpec, placement: CompositionPlacement, ordinal: number, family): number
	if placement.Role == "TrailMarker" and placement.AssetId == "WindBoulder" then
		for index, recipe in family.Recipes do
			if recipe.Id == "TrailCairn" then
				return index
			end
		end
	end
	local rawGround = select(1, sampleSurface(spec, placement.WorldX, placement.WorldZ))
	if placement.Role == "Landmark" and placement.GroundY - rawGround > 2 then
		local compactId = if placement.AssetId == "LayeredMesa" then "LoneShelf" else "GroundedMass"
		for index, recipe in family.Recipes do
			if recipe.Id == compactId then return index end
		end
	end
	local offset = math.floor(unit(spec.WorldSeed, placement.AssetIndex, 0, 0, 1) * #family.Recipes) % #family.Recipes
	return ((ordinal - 1 + offset) % #family.Recipes) + 1
end

local function identityFields(seed: number, assetIndex: number, logicalIndex: number, recipeIndex: number, paletteCount: number)
	local bins = Config.MorphBins
	local _, widthBin = quantized(unit(seed, logicalIndex, assetIndex, recipeIndex, 10), 0, 1, bins)
	local _, heightBin = quantized(unit(seed, logicalIndex, assetIndex, recipeIndex, 11), 0, 1, bins)
	local _, depthBin = quantized(unit(seed, logicalIndex, assetIndex, recipeIndex, 12), 0, 1, bins)
	local tintIndex = math.clamp(math.floor(unit(seed, logicalIndex, assetIndex, recipeIndex, 13) * paletteCount) + 1, 1, paletteCount)
	local yawBin = math.clamp(math.floor(unit(seed, logicalIndex, assetIndex, recipeIndex, 14) * Config.YawBins), 0, Config.YawBins - 1)
	return widthBin, heightBin, depthBin, tintIndex, yawBin
end

local function buildVariant(
	spec: WorldSpec,
	composition: CompositionPlan,
	placement: CompositionPlacement,
	variantIndex: number,
	ordinal: number,
	recipeIndex: number
): Variant
	local asset = Catalog.ById[placement.AssetId]
	local family = Config.ByAsset[placement.AssetId]
	assert(asset and family, "Missing Milestone 4 family for " .. placement.AssetId)
	local recipe = family.Recipes[recipeIndex]
	local morphology = Config.Morphology[asset.Kind]
	local paletteCount = #Config.Palettes[if asset.Kind == "Rock" then "Rock" else "Foliage"]
	local widthBin, heightBin, depthBin, tintIndex, yawBin = identityFields(
		spec.WorldSeed, placement.AssetIndex, placement.Index, recipeIndex, paletteCount
	)
	local bins = Config.MorphBins
	local stretchX = morphology.WidthMin + (morphology.WidthMax - morphology.WidthMin) * widthBin / (bins - 1)
	local stretchY = morphology.HeightMin + (morphology.HeightMax - morphology.HeightMin) * heightBin / (bins - 1)
	local stretchZ = morphology.DepthMin + (morphology.DepthMax - morphology.DepthMin) * depthBin / (bins - 1)
	local yawJitter = degrees((yawBin / (Config.YawBins - 1) * 2 - 1) * Config.YawJitterDegrees)
	local variantSeed = Hash32.HashIntegers(spec.WorldSeed, placement.Index, placement.AssetIndex, recipeIndex, CHANNEL)
	local identityKey = string.format(
		"%s/%s/%d-%d-%d-%d-%d",
		placement.AssetId, recipe.Id, widthBin, heightBin, depthBin, tintIndex, yawBin
	)
	local components: {VariationComponent} = {}
	local footprintRadius = 0
	local rawBaseGround = select(1, sampleSurface(spec, placement.WorldX, placement.WorldZ))
	local verticalOverride = placement.GroundY - rawBaseGround
	local adjustedVerticalOverride = if placement.Role == "Landmark" and verticalOverride > 2
		then verticalOverride * 0.72
		else verticalOverride
	for componentIndex, definition in recipe.Components do
		local localX = definition.X * placement.Scale
		local localZ = definition.Z * placement.Scale
		local cosine = math.cos(placement.YawRadians)
		local sine = math.sin(placement.YawRadians)
		local worldX = placement.WorldX + localX * cosine - localZ * sine
		local worldZ = placement.WorldZ + localX * sine + localZ * cosine
		local groundY, normal = sampleSurface(spec, worldX, worldZ)
		local microScale = 0.965 + unit(spec.WorldSeed, placement.Index, recipeIndex, componentIndex, 20) * 0.07
		local uniformScale = placement.Scale * definition.Scale * microScale
		local componentStretchX = stretchX * (0.98 + unit(spec.WorldSeed, placement.Index, recipeIndex, componentIndex, 21) * 0.04)
		local componentStretchY = stretchY * (0.98 + unit(spec.WorldSeed, placement.Index, recipeIndex, componentIndex, 22) * 0.04)
		local componentStretchZ = stretchZ * (0.98 + unit(spec.WorldSeed, placement.Index, recipeIndex, componentIndex, 23) * 0.04)
		local collisionRadius = asset.SpacingRadius * uniformScale * math.max(componentStretchX, componentStretchZ)
		local localDistance = math.sqrt(localX * localX + localZ * localZ)
		footprintRadius = math.max(footprintRadius, localDistance + collisionRadius)
		table.insert(components, {
			Index = componentIndex,
			AssetId = placement.AssetId,
			WorldX = worldX,
			PivotY = groundY + adjustedVerticalOverride + definition.Y * placement.Scale
				- asset.SinkStuds * uniformScale * componentStretchY,
			WorldZ = worldZ,
			Normal = normal,
			YawRadians = placement.YawRadians + degrees(definition.Yaw) + yawJitter,
			PitchRadians = degrees(definition.Pitch),
			RollRadians = degrees(definition.Roll),
			UniformScale = uniformScale,
			StretchX = componentStretchX,
			StretchY = componentStretchY,
			StretchZ = componentStretchZ,
			TintIndex = tintIndex,
			CollisionRadius = collisionRadius,
			LocalDistance = localDistance,
		})
	end
	return {
		Index = variantIndex,
		BasePlacementIndex = placement.Index,
		AssetId = placement.AssetId,
		AssetKind = asset.Kind,
		RecipeId = recipe.Id,
		RecipeIndex = recipeIndex,
		IdentityKey = identityKey,
		VariantSeed = variantSeed,
		Role = placement.Role,
		ZoneId = placement.ZoneId,
		WorldX = placement.WorldX,
		GroundY = placement.GroundY,
		WorldZ = placement.WorldZ,
		Normal = placement.Normal,
		YawRadians = placement.YawRadians,
		Scale = placement.Scale,
		ReservedRadius = placement.SpacingRadius,
		FootprintRadius = footprintRadius,
		Components = components,
	}
end

local function rejectReason(spec: WorldSpec, composition: CompositionPlan, variant: Variant, accepted: {Variant}): string?
	if variant.FootprintRadius > variant.ReservedRadius * Config.FootprintUtilizationLimit then
		return "Footprint"
	end
	for _, component in variant.Components do
		local radius = component.CollisionRadius
		if component.WorldX - radius < spec.OriginX + CompositionConfig.WorldEdgeMargin
			or component.WorldZ - radius < spec.OriginZ + CompositionConfig.WorldEdgeMargin
			or component.WorldX + radius > spec.OriginX + spec.WorldSize - CompositionConfig.WorldEdgeMargin
			or component.WorldZ + radius > spec.OriginZ + spec.WorldSize - CompositionConfig.WorldEdgeMargin then
			return "Bounds"
		end
		local surfaceY, _, slopeDegrees = sampleSurface(spec, component.WorldX, component.WorldZ)
		local asset = Catalog.ById[component.AssetId]
		if slopeDegrees > asset.MaxSlopeDegrees and variant.Role ~= "Landmark" then
			return "Slope"
		end
		if variant.Role ~= "Landmark" then
			local spawnLimit = CompositionConfig.SpawnSafeRadius + radius
			if component.WorldX ^ 2 + component.WorldZ ^ 2 < spawnLimit ^ 2 then
				return "Spawn"
			end
			local pathLimit = CompositionConfig.PathCorridorRadius + radius * Config.PathCollisionPaddingScale
			if CompositionPlanner.DistanceToRouteSquared(
				composition.RouteNodes, component.WorldX, component.WorldZ
			) < pathLimit ^ 2 then
				return "Path"
			end
			local dxLandmark = component.WorldX - composition.Landmark.WorldX
			local dzLandmark = component.WorldZ - composition.Landmark.WorldZ
			local landmarkLimit = CompositionConfig.LandmarkClearRadius + radius * 0.35
			if dxLandmark ^ 2 + dzLandmark ^ 2 < landmarkLimit ^ 2 then
				return "Landmark"
			end
		end
		-- Keep the sample referenced so strict analysis catches accidental changes
		-- between the planned pivot and the heightfield used for safety.
		assert(surfaceY == surfaceY)
		for _, otherVariant in accepted do
			if variant.Role == "Landmark" and otherVariant.Role == "Landmark" then
				continue
			end
			for _, other in otherVariant.Components do
				local dx = component.WorldX - other.WorldX
				local dz = component.WorldZ - other.WorldZ
				if dx * dx + dz * dz < (radius + other.CollisionRadius) ^ 2 then
					return "Spacing"
				end
			end
		end
	end
	return nil
end

local function incrementRejection(stats: RepairStats, reason: string)
	stats.RejectedAttempts += 1
	if reason == "Footprint" then stats.RejectedByFootprint += 1
	elseif reason == "Bounds" then stats.RejectedByBounds += 1
	elseif reason == "Spawn" then stats.RejectedBySpawn += 1
	elseif reason == "Path" then stats.RejectedByPath += 1
	elseif reason == "Landmark" then stats.RejectedByLandmark += 1
	elseif reason == "Slope" then stats.RejectedBySlope += 1
	elseif reason == "Spacing" then stats.RejectedBySpacing += 1
	end
end

local function signature(plan: Plan): string
	local state = Checksum.New()
	Checksum.UpdateString(state, plan.Version)
	Checksum.UpdateString(state, plan.CompositionSignature)
	Checksum.UpdateUInt32(state, plan.WorldSeed)
	Checksum.UpdateUInt32(state, #plan.Variants)
	Checksum.UpdateUInt32(state, plan.ComponentCount)
	Checksum.UpdateUInt32(state, plan.Repair.OmittedBySafety)
	for index, variant in plan.Variants do
		Checksum.UpdateIndexedUInt32(state, index, variant.BasePlacementIndex)
		Checksum.UpdateString(state, variant.AssetId)
		Checksum.UpdateString(state, variant.RecipeId)
		Checksum.UpdateString(state, variant.IdentityKey)
		Checksum.UpdateString(state, variant.Role)
		Checksum.UpdateString(state, variant.ZoneId)
		Checksum.UpdateUInt32(state, variant.VariantSeed)
		Checksum.UpdateUInt32(state, #variant.Components)
		for componentIndex, component in variant.Components do
			Checksum.UpdateIndexedUInt32(state, componentIndex, math.floor(component.WorldX * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(component.PivotY * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(component.WorldZ * 1024 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(component.YawRadians * 65536 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(component.PitchRadians * 65536 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(component.RollRadians * 65536 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(component.UniformScale * 65536 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(component.StretchX * 65536 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(component.StretchY * 65536 + 0.5))
			Checksum.UpdateUInt32(state, math.floor(component.StretchZ * 65536 + 0.5))
			Checksum.UpdateUInt32(state, component.TintIndex)
		end
	end
	return Checksum.Digest(state)
end

function Planner.Plan(spec: WorldSpec, composition: CompositionPlan): Plan
	local variants: {Variant} = {}
	local ordinalByAsset: {[string]: number} = {}
	local assetCounts: {[string]: number} = {}
	local recipeCounts: {[string]: number} = {}
	local roleCounts: {[string]: number} = {}
	local identities: {[string]: boolean} = {}
	local duplicateIdentityCount = 0
	local componentCount = 0
	local repair: RepairStats = {
		RejectedAttempts = 0,
		RecipeFallbacks = 0,
		OmittedBySafety = 0,
		RejectedByFootprint = 0,
		RejectedByBounds = 0,
		RejectedBySpawn = 0,
		RejectedByPath = 0,
		RejectedByLandmark = 0,
		RejectedBySlope = 0,
		RejectedBySpacing = 0,
	}

	for _, placement in composition.Placements do
		local family = Config.ByAsset[placement.AssetId]
		assert(family, "No variation family for " .. placement.AssetId)
		local ordinal = (ordinalByAsset[placement.AssetId] or 0) + 1
		ordinalByAsset[placement.AssetId] = ordinal
		local preferred = recipeIndexFor(spec, placement, ordinal, family)
		local selected: Variant? = nil
		for attempt = 0, #family.Recipes - 1 do
			local recipeIndex = ((preferred - 1 + attempt) % #family.Recipes) + 1
			local candidate = buildVariant(spec, composition, placement, #variants + 1, ordinal, recipeIndex)
			local reason = rejectReason(spec, composition, candidate, variants)
			if reason == nil then
				selected = candidate
				if attempt > 0 then
					repair.RecipeFallbacks += 1
				end
				break
			end
			incrementRejection(repair, reason)
		end
		if not selected then
			repair.OmittedBySafety += 1
			continue
		end
		table.insert(variants, selected)
		assetCounts[selected.AssetId] = (assetCounts[selected.AssetId] or 0) + 1
		local recipeKey = selected.AssetId .. "/" .. selected.RecipeId
		recipeCounts[recipeKey] = (recipeCounts[recipeKey] or 0) + 1
		roleCounts[selected.Role] = (roleCounts[selected.Role] or 0) + 1
		componentCount += #selected.Components
		if identities[selected.IdentityKey] then
			duplicateIdentityCount += 1
		else
			identities[selected.IdentityKey] = true
		end
	end

	local plan: Plan = {
		Version = Config.Version,
		WorldSeed = spec.WorldSeed,
		CompositionSignature = composition.Signature,
		BasePlacementCount = #composition.Placements,
		Variants = variants,
		ComponentCount = componentCount,
		AssetCounts = assetCounts,
		RecipeCounts = recipeCounts,
		RoleCounts = roleCounts,
		UniqueIdentityCount = #variants - duplicateIdentityCount,
		DuplicateIdentityCount = duplicateIdentityCount,
		Repair = repair,
		Signature = "",
	}
	plan.Signature = signature(plan)
	return plan
end

function Planner.AuditIdentitySpace(seed: number, samplesPerFamily: number?)
	local samples = samplesPerFamily or Config.IdentitySamplesPerFamily
	local result = {SamplesPerFamily = samples, Families = {}, MinimumUnique = math.huge, TotalUnique = 0, Signature = ""}
	local state = Checksum.New()
	Checksum.UpdateString(state, Config.Version)
	Checksum.UpdateUInt32(state, seed)
	Checksum.UpdateUInt32(state, samples)
	for assetIndex, family in Config.Families do
		local asset = Catalog.ById[family.AssetId]
		local paletteCount = #Config.Palettes[if asset.Kind == "Rock" then "Rock" else "Foliage"]
		local unique: {[string]: boolean} = {}
		local recipes: {[string]: boolean} = {}
		for logicalIndex = 1, samples do
			local recipeIndex = ((logicalIndex - 1 + math.floor(unit(seed, assetIndex, 0, 0, 1) * #family.Recipes)) % #family.Recipes) + 1
			local recipe = family.Recipes[recipeIndex]
			local width, height, depth, tint, yaw = identityFields(seed, assetIndex, logicalIndex, recipeIndex, paletteCount)
			local key = string.format("%s/%s/%d-%d-%d-%d-%d", family.AssetId, recipe.Id, width, height, depth, tint, yaw)
			unique[key] = true
			recipes[recipe.Id] = true
		end
		local uniqueCount = 0
		for _ in unique do uniqueCount += 1 end
		local recipeCount = 0
		for _ in recipes do recipeCount += 1 end
		result.Families[family.AssetId] = {
			UniqueIdentities = uniqueCount,
			RecipeCoverage = recipeCount,
			RecipeCount = #family.Recipes,
			Passed = uniqueCount >= Config.MinimumUniqueIdentitiesPerFamily and recipeCount == #family.Recipes,
		}
		result.MinimumUnique = math.min(result.MinimumUnique, uniqueCount)
		result.TotalUnique += uniqueCount
		Checksum.UpdateString(state, family.AssetId)
		Checksum.UpdateUInt32(state, uniqueCount)
		Checksum.UpdateUInt32(state, recipeCount)
	end
	result.Signature = Checksum.Digest(state)
	return result
end

return table.freeze(Planner)
