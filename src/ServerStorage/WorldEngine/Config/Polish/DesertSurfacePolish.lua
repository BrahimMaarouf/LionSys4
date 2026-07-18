--!strict

local config = {
	Version = "6.0.0-m6-surface-atmosphere",
	SurfaceThicknessCells = 2,
	RouteSurfaceRadius = 8,
	DetailWorldMargin = 28,
	DetailSpawnRadius = 58,
	DetailRouteClearance = 15,
	DetailMaximumSlope = 14,
	DetailMinimumSpacing = 9,
	MaximumDetails = 76,
	MinimumDetailsPerRegion = 8,
	GeneratedDescendantBudget = 2400,
	AtmosphereAnchorHeight = 12,
	AtmosphereEmitterCount = 4,

	Materials = {
		Enum.Material.Sand,
		Enum.Material.Sandstone,
		Enum.Material.Rock,
		Enum.Material.Ground,
		Enum.Material.Mud,
	},
	MaterialColors = {
		Sand = Color3.fromRGB(205, 155, 103),
		Sandstone = Color3.fromRGB(171, 104, 69),
		Rock = Color3.fromRGB(111, 82, 72),
		Ground = Color3.fromRGB(137, 109, 76),
		Mud = Color3.fromRGB(102, 83, 66),
	},

	RegionDetails = {
		ErgDunes = {DuneRipple = 14, SandDrift = 5},
		WadiGardens = {WadiCrack = 12, SandDrift = 4},
		HamadaShelf = {PebbleField = 14, StrataAccent = 5},
		CrownHighlands = {StrataAccent = 10, PebbleField = 6},
	},
	DetailOrder = {"DuneRipple", "SandDrift", "WadiCrack", "PebbleField", "StrataAccent"},
	DetailStyle = {
		DuneRipple = {Material = Enum.Material.Sandstone, Color = Color3.fromRGB(225, 177, 122), Width = 11, Depth = 1.05, Height = 0.10},
		SandDrift = {Material = Enum.Material.Sand, Color = Color3.fromRGB(220, 170, 112), Width = 8.5, Depth = 4.2, Height = 0.18},
		WadiCrack = {Material = Enum.Material.Ground, Color = Color3.fromRGB(91, 72, 58), Width = 6.2, Depth = 0.20, Height = 0.07},
		PebbleField = {Material = Enum.Material.Rock, Color = Color3.fromRGB(118, 91, 78), Width = 2.4, Depth = 1.6, Height = 0.34},
		StrataAccent = {Material = Enum.Material.Sandstone, Color = Color3.fromRGB(164, 96, 65), Width = 7.5, Depth = 1.0, Height = 0.22},
	},

	RegionAtmosphere = {
		ErgDunes = {Rate = 0.55, Color = Color3.fromRGB(235, 195, 144), Speed = 2.2},
		WadiGardens = {Rate = 0.35, Color = Color3.fromRGB(188, 173, 133), Speed = 1.2},
		HamadaShelf = {Rate = 0.75, Color = Color3.fromRGB(209, 149, 111), Speed = 2.8},
		CrownHighlands = {Rate = 0.45, Color = Color3.fromRGB(214, 174, 142), Speed = 2.0},
	},

	Bloom = {Intensity = 0.16, Size = 26, Threshold = 1.85},
	DepthOfField = {FarIntensity = 0.075, FocusDistance = 135, InFocusRadius = 105, NearIntensity = 0},
	Atmosphere = {Density = 0.285, Offset = 0.075, Glare = 0.24, Haze = 1.48},
	Clouds = {Cover = 0.08, Density = 0.18, Color = Color3.fromRGB(255, 225, 196)},
}

return table.freeze(config)
