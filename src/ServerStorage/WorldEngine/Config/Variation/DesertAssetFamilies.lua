--!strict

-- Milestone 4 art direction. Recipes deliberately stay inside the footprint
-- reserved by Milestone 3, so variation adds silhouette richness without
-- changing the authored world composition or blocking traversal.
local config = {
	Version = "4.0.0-m4-asset-variation",
	IdentitySamplesPerFamily = 512,
	MinimumUniqueIdentitiesPerFamily = 480,
	MaximumVariants = 96,
	MaximumComponents = 180,
	GeneratedDescendantBudget = 1450,
	MaximumSafetyOmissions = 6,
	FootprintUtilizationLimit = 0.985,
	PathCollisionPaddingScale = 0.55,
	YawJitterDegrees = 8,
	MorphBins = 8,
	YawBins = 24,

	Morphology = {
		Rock = {
			WidthMin = 0.90,
			WidthMax = 1.08,
			HeightMin = 0.88,
			HeightMax = 1.14,
			DepthMin = 0.90,
			DepthMax = 1.08,
		},
		Vegetation = {
			WidthMin = 0.87,
			WidthMax = 1.12,
			HeightMin = 0.91,
			HeightMax = 1.15,
			DepthMin = 0.87,
			DepthMax = 1.12,
		},
	},

	Palettes = {
		Rock = {
			Color3.fromRGB(213, 193, 176),
			Color3.fromRGB(198, 177, 159),
			Color3.fromRGB(225, 207, 188),
			Color3.fromRGB(184, 165, 151),
			Color3.fromRGB(207, 184, 164),
			Color3.fromRGB(232, 216, 197),
		},
		Foliage = {
			Color3.fromRGB(142, 125, 68),
			Color3.fromRGB(159, 139, 74),
			Color3.fromRGB(124, 111, 61),
			Color3.fromRGB(174, 146, 75),
			Color3.fromRGB(132, 119, 73),
			Color3.fromRGB(151, 128, 65),
		},
		Branch = {
			Color3.fromRGB(106, 73, 48),
			Color3.fromRGB(120, 80, 49),
			Color3.fromRGB(91, 65, 45),
			Color3.fromRGB(128, 88, 57),
			Color3.fromRGB(101, 70, 48),
			Color3.fromRGB(114, 75, 46),
		},
	},

	Families = {
		{
			AssetId = "WindBoulder",
			Recipes = {
				{Id = "GroundedMass", Components = {
					{X = 0, Z = 0, Y = 0, Scale = 0.88, Yaw = 0, Pitch = 0, Roll = 0},
				}},
				{Id = "CompanionPair", Components = {
					{X = -1.1, Z = -0.2, Y = 0, Scale = 0.70, Yaw = -9, Pitch = 0, Roll = -2},
					{X = 4.2, Z = 1.1, Y = 0, Scale = 0.32, Yaw = 41, Pitch = 0, Roll = 3},
				}},
				{Id = "ThreeStoneDrift", Components = {
					{X = -1.7, Z = 0.1, Y = 0, Scale = 0.61, Yaw = -16, Pitch = 0, Roll = -3},
					{X = 3.8, Z = 1.4, Y = 0, Scale = 0.27, Yaw = 37, Pitch = 0, Roll = 4},
					{X = 0.9, Z = -4.0, Y = 0, Scale = 0.22, Yaw = 81, Pitch = 0, Roll = -2},
				}},
				{Id = "SplitCrown", Components = {
					{X = -1.4, Z = 0, Y = 0, Scale = 0.65, Yaw = -24, Pitch = 0, Roll = -4},
					{X = 3.0, Z = -1.2, Y = 0, Scale = 0.38, Yaw = 29, Pitch = 0, Roll = 5},
				}},
				{Id = "TrailCairn", Components = {
					{X = 0, Z = 0, Y = 0, Scale = 0.55, Yaw = 0, Pitch = 0, Roll = 0},
					{X = 0.1, Z = 0, Y = 3.9, Scale = 0.31, Yaw = 53, Pitch = 0, Roll = 0},
					{X = -0.1, Z = 0.1, Y = 6.4, Scale = 0.18, Yaw = 101, Pitch = 0, Roll = 0},
				}},
			},
		},
		{
			AssetId = "LayeredMesa",
			Recipes = {
				{Id = "LoneShelf", Components = {
					{X = 0, Z = 0, Y = 0, Scale = 0.88, Yaw = 0, Pitch = 0, Roll = 0},
				}},
				{Id = "BrokenPair", Components = {
					{X = -1.6, Z = 0, Y = 0, Scale = 0.66, Yaw = -12, Pitch = 0, Roll = -2},
					{X = 4.3, Z = 0.9, Y = 0, Scale = 0.31, Yaw = 38, Pitch = 0, Roll = 3},
				}},
				{Id = "SteppedRidge", Components = {
					{X = -2.3, Z = 0.2, Y = 0, Scale = 0.58, Yaw = -8, Pitch = 0, Roll = -2},
					{X = 3.7, Z = -0.6, Y = 0.35, Scale = 0.34, Yaw = 19, Pitch = 0, Roll = 3},
				}},
				{Id = "CrosswindTerrace", Components = {
					{X = -2.7, Z = 0, Y = 0, Scale = 0.50, Yaw = -19, Pitch = 0, Roll = -3},
					{X = 3.2, Z = 1.4, Y = 0, Scale = 0.27, Yaw = 26, Pitch = 0, Roll = 4},
					{X = 1.0, Z = -4.1, Y = 0, Scale = 0.19, Yaw = 73, Pitch = 0, Roll = -2},
				}},
				{Id = "TiltedMonolith", Components = {
					{X = 0, Z = 0, Y = 0, Scale = 0.82, Yaw = 7, Pitch = 0, Roll = 6},
				}},
			},
		},
		{
			AssetId = "DryShrub",
			Recipes = {
				{Id = "WindFan", Components = {
					{X = 0, Z = 0, Y = 0, Scale = 0.88, Yaw = 0, Pitch = 0, Roll = 0},
				}},
				{Id = "TwinRoot", Components = {
					{X = -0.6, Z = 0, Y = 0, Scale = 0.62, Yaw = -11, Pitch = 0, Roll = -2},
					{X = 2.4, Z = 0.5, Y = 0, Scale = 0.29, Yaw = 31, Pitch = 0, Roll = 3},
				}},
				{Id = "SparseThicket", Components = {
					{X = -0.8, Z = 0.2, Y = 0, Scale = 0.51, Yaw = -18, Pitch = 0, Roll = -2},
					{X = 2.1, Z = 1.2, Y = 0, Scale = 0.23, Yaw = 43, Pitch = 0, Roll = 3},
					{X = 0.8, Z = -2.6, Y = 0, Scale = 0.18, Yaw = 77, Pitch = 0, Roll = -2},
				}},
				{Id = "CrescentCluster", Components = {
					{X = -1.6, Z = 0.3, Y = 0, Scale = 0.40, Yaw = -26, Pitch = 0, Roll = -3},
					{X = 1.5, Z = 1.5, Y = 0, Scale = 0.25, Yaw = 18, Pitch = 0, Roll = 2},
					{X = 1.9, Z = -1.7, Y = 0, Scale = 0.20, Yaw = 59, Pitch = 0, Roll = 3},
				}},
				{Id = "WindRow", Components = {
					{X = -2.2, Z = 0, Y = 0, Scale = 0.35, Yaw = -31, Pitch = 0, Roll = -3},
					{X = 0.3, Z = 0.5, Y = 0, Scale = 0.28, Yaw = 4, Pitch = 0, Roll = 1},
					{X = 2.5, Z = -0.2, Y = 0, Scale = 0.21, Yaw = 37, Pitch = 0, Roll = 3},
				}},
			},
		},
	},
}

local byAsset = {}
for _, family in config.Families do
	byAsset[family.AssetId] = family
end
config.ByAsset = byAsset

return table.freeze(config)
