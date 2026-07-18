--!strict

local config = {
	Version = "5.0.0-m5-world-composition",
	RegionGridSize = 32,
	WorldEdgeMargin = 26,
	RouteGridSize = 16,
	RouteSampleSpacing = 9,
	RouteMaxSlopeDegrees = 25,
	RouteMaxStepHeight = 9,
	RouteCorridorRadius = 12,
	SpawnSafeRadius = 54,
	LandmarkClearRadius = 25,
	VistaMinimumDistance = 54,
	VistaMaximumDistance = 210,
	VistaEyeHeight = 8,
	VistaTargetHeight = 13,
	VistaFrameOffset = 25,
	MaximumPlacements = 92,
	MaximumVariants = 88,
	MaximumComponents = 190,
	GeneratedDescendantBudget = 2200,
	MinimumRegionCoverageCells = 20,
	MaximumRegionCoverageFraction = 0.52,

	Regions = {
		{
			Id = "ErgDunes",
			DisplayName = "Pilgrim Erg",
			Kind = "OpenDunes",
			InfluenceRadius = 172,
			Bias = -0.04,
			RockTint = Color3.fromRGB(238, 224, 207),
			FoliageTint = Color3.fromRGB(205, 192, 152),
			BranchTint = Color3.fromRGB(193, 169, 139),
			PathColor = Color3.fromRGB(176, 119, 71),
			Targets = {WindBoulder = 3, LayeredMesa = 2, DryShrub = 0},
		},
		{
			Id = "WadiGardens",
			DisplayName = "Dry Wadi Gardens",
			Kind = "Wadi",
			InfluenceRadius = 150,
			Bias = 0,
			RockTint = Color3.fromRGB(205, 204, 183),
			FoliageTint = Color3.fromRGB(170, 194, 137),
			BranchTint = Color3.fromRGB(176, 154, 121),
			PathColor = Color3.fromRGB(139, 105, 70),
			Targets = {WindBoulder = 1, LayeredMesa = 0, DryShrub = 14},
		},
		{
			Id = "HamadaShelf",
			DisplayName = "Red Hamada Shelf",
			Kind = "RockShelf",
			InfluenceRadius = 158,
			Bias = 0.01,
			RockTint = Color3.fromRGB(229, 181, 147),
			FoliageTint = Color3.fromRGB(174, 151, 112),
			BranchTint = Color3.fromRGB(180, 133, 102),
			PathColor = Color3.fromRGB(153, 86, 57),
			Targets = {WindBoulder = 4, LayeredMesa = 8, DryShrub = 0},
		},
		{
			Id = "CrownHighlands",
			DisplayName = "Sentinel Crown Highlands",
			Kind = "Highlands",
			InfluenceRadius = 132,
			Bias = -0.08,
			RockTint = Color3.fromRGB(216, 192, 176),
			FoliageTint = Color3.fromRGB(180, 163, 126),
			BranchTint = Color3.fromRGB(174, 145, 120),
			PathColor = Color3.fromRGB(157, 96, 62),
			Targets = {WindBoulder = 3, LayeredMesa = 3, DryShrub = 0},
		},
	},
}

local byId = {}
for _, region in config.Regions do
	byId[region.Id] = region
end
config.ById = byId

return table.freeze(config)
