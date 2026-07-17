--!strict

local preset = {
	Name = "DesertGoldenHour",
	ClockTime = 16.35,
	Brightness = 2.4,
	ExposureCompensation = 0.05,
	Ambient = Color3.fromRGB(92, 73, 67),
	OutdoorAmbient = Color3.fromRGB(151, 126, 111),
	ColorShiftTop = Color3.fromRGB(255, 222, 184),
	ColorShiftBottom = Color3.fromRGB(112, 78, 70),
	EnvironmentDiffuseScale = 0.35,
	EnvironmentSpecularScale = 0.65,
	ShadowSoftness = 0.35,
	AtmosphereDensity = 0.27,
	AtmosphereOffset = 0.08,
	AtmosphereColor = Color3.fromRGB(255, 220, 181),
	AtmosphereDecay = Color3.fromRGB(118, 87, 80),
	AtmosphereGlare = 0.2,
	AtmosphereHaze = 1.35,
	ColorCorrectionBrightness = 0.015,
	ColorCorrectionContrast = 0.08,
	ColorCorrectionSaturation = -0.02,
	ColorCorrectionTint = Color3.fromRGB(255, 234, 214),
	SunRaysIntensity = 0.035,
	SunRaysSpread = 0.72,
}

return table.freeze(preset)
