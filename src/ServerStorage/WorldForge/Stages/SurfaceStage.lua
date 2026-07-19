--!strict

-- WorldForge Stage 6: Surface & Light.
--
-- Surface repaints terrain material by RULE (steep ground, high ground, near
-- water) rather than by theme. Lighting applies the recipe's atmosphere.
-- Both are cheap and independent of everything else, so they re-apply
-- instantly while you tune them.

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldForge = script.Parent.Parent
local Recipe = require(WorldForge.Core.Recipe)
local TerrainStage = require(WorldForge.Stages.TerrainStage)

local Stage = {}

local EFFECT_NAMES = {
	Atmosphere = "WorldForgeAtmosphere",
	Clouds = "WorldForgeClouds",
}

--[[
	Repaints terrain materials by slope / altitude / shoreline rules.
	Only cells whose rule differs from the base material are rewritten.
]]
function Stage.ApplySurface(recipe: Recipe.Data)
	local started = os.clock()
	local p = Recipe.Resolve(recipe)
	if not p["surface.enabled"] then
		return {Skipped = true}
	end

	local field = TerrainStage.BuildField(recipe)
	local terrain = Workspace.Terrain
	local resolution = field.Resolution
	local size = field.Size
	local origin = field.Origin

	local baseMaterial = (Enum.Material :: any)[p["terrain.material"]] or Enum.Material.Sand
	local slopeMaterial = (Enum.Material :: any)[p["surface.slopeMaterial"]] or baseMaterial
	local peakMaterial = (Enum.Material :: any)[p["surface.peakMaterial"]] or baseMaterial
	local shoreMaterial = (Enum.Material :: any)[p["surface.shoreMaterial"]] or baseMaterial

	local slopeThreshold = p["surface.slopeThreshold"]
	local peakFraction = p["surface.peakHeight"]
	local shoreBand = p["surface.shoreBand"]
	local waterLevel = field.WaterLevel
	local hasWater = waterLevel > field.MinHeight
	local range = math.max(0.001, field.MaxHeight - field.MinHeight)

	local step = resolution * 2
	local painted = {Slope = 0, Peak = 0, Shore = 0}
	local processed = 0

	for gx = 0, size - step, step do
		for gz = 0, size - step, step do
			local x = origin + gx + step / 2
			local z = origin + gz + step / 2
			local h = field.HeightAt(x, z)

			-- local slope
			local left = field.HeightAt(x - resolution, z)
			local right = field.HeightAt(x + resolution, z)
			local back = field.HeightAt(x, z - resolution)
			local front = field.HeightAt(x, z + resolution)
			local dx = (right - left) / (resolution * 2)
			local dz = (front - back) / (resolution * 2)
			local slope = math.deg(math.atan(math.sqrt(dx * dx + dz * dz)))
			local altitude = (h - field.MinHeight) / range

			local material
			if hasWater and h <= waterLevel + shoreBand and h >= waterLevel - shoreBand then
				material = shoreMaterial
				painted.Shore += 1
			elseif slope >= slopeThreshold then
				material = slopeMaterial
				painted.Slope += 1
			elseif peakFraction < 1 and altitude >= peakFraction then
				material = peakMaterial
				painted.Peak += 1
			end

			if material and material ~= baseMaterial then
				local region = Region3.new(
					Vector3.new(origin + gx, h - 6, origin + gz),
					Vector3.new(origin + gx + step, h + 2, origin + gz + step)
				):ExpandToGrid(resolution)
				terrain:ReplaceMaterial(region, resolution, baseMaterial, material)
			end

			processed += 1
			if processed % 500 == 0 then
				task.wait()
			end
		end
	end

	return {
		Painted = painted,
		Seconds = os.clock() - started,
	}
end

function Stage.ApplyLighting(recipe: Recipe.Data)
	local p = Recipe.Resolve(recipe)

	Lighting.ClockTime = p["lighting.clockTime"]
	Lighting.Brightness = p["lighting.brightness"]
	Lighting.ExposureCompensation = p["lighting.exposure"]
	Lighting.GlobalShadows = p["lighting.shadows"]

	local atmosphere = Lighting:FindFirstChild(EFFECT_NAMES.Atmosphere)
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = EFFECT_NAMES.Atmosphere
		atmosphere.Parent = Lighting
	end
	local air = atmosphere :: Atmosphere
	air.Density = p["lighting.fogDensity"]
	air.Haze = p["lighting.fogHaze"]

	local sky = Lighting:FindFirstChildOfClass("Sky")
	local clouds = Workspace.Terrain:FindFirstChild(EFFECT_NAMES.Clouds)
	if p["lighting.clouds"] then
		if not clouds then
			clouds = Instance.new("Clouds")
			clouds.Name = EFFECT_NAMES.Clouds
			clouds.Parent = Workspace.Terrain
		end
		local cloudObject = clouds :: Clouds
		cloudObject.Cover = p["lighting.cloudCover"]
		cloudObject.Density = 0.55
	elseif clouds then
		clouds:Destroy()
	end

	return {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		Haze = air.Haze,
		Clouds = p["lighting.clouds"],
	}
end

function Stage.Apply(recipe: Recipe.Data)
	local surface = Stage.ApplySurface(recipe)
	local lighting = Stage.ApplyLighting(recipe)
	return {Surface = surface, Lighting = lighting}
end

return table.freeze(Stage)
