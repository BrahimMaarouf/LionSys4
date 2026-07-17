--!strict

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Preset = require(WorldEngine.Config.Lighting.DesertGoldenHour)

local Materializer = {}

local function getOrCreate(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

function Materializer.Apply()
	Lighting.ClockTime = Preset.ClockTime
	Lighting.Brightness = Preset.Brightness
	Lighting.ExposureCompensation = Preset.ExposureCompensation
	Lighting.Ambient = Preset.Ambient
	Lighting.OutdoorAmbient = Preset.OutdoorAmbient
	Lighting.ColorShift_Top = Preset.ColorShiftTop
	Lighting.ColorShift_Bottom = Preset.ColorShiftBottom
	Lighting.EnvironmentDiffuseScale = Preset.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = Preset.EnvironmentSpecularScale
	Lighting.ShadowSoftness = Preset.ShadowSoftness
	Lighting.GlobalShadows = true

	local atmosphere = getOrCreate("Atmosphere", "WorldEngineAtmosphere") :: Atmosphere
	atmosphere.Density = Preset.AtmosphereDensity
	atmosphere.Offset = Preset.AtmosphereOffset
	atmosphere.Color = Preset.AtmosphereColor
	atmosphere.Decay = Preset.AtmosphereDecay
	atmosphere.Glare = Preset.AtmosphereGlare
	atmosphere.Haze = Preset.AtmosphereHaze

	local correction = getOrCreate("ColorCorrectionEffect", "WorldEngineColorCorrection") :: ColorCorrectionEffect
	correction.Brightness = Preset.ColorCorrectionBrightness
	correction.Contrast = Preset.ColorCorrectionContrast
	correction.Saturation = Preset.ColorCorrectionSaturation
	correction.TintColor = Preset.ColorCorrectionTint

	local sunRays = getOrCreate("SunRaysEffect", "WorldEngineSunRays") :: SunRaysEffect
	sunRays.Intensity = Preset.SunRaysIntensity
	sunRays.Spread = Preset.SunRaysSpread

	return {
		Preset = Preset.Name,
		PostEffects = 3,
	}
end

return table.freeze(Materializer)
