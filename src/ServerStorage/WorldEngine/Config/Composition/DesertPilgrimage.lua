--!strict

local config = {
	Name = "DesertPilgrimage",
	Version = "3.0.0-m3-composition",

	PathGridSize = 16,
	PathMaxSlopeDegrees = 24,
	PathMaxStepHeight = 9,
	PathCorridorRadius = 11,
	PathPatchSpacing = 9,
	PathPatchWidth = 10.5,

	SpawnSafeRadius = 52,
	WorldEdgeMargin = 24,
	LandmarkMinRadius = 155,
	LandmarkMaxRadius = 198,
	LandmarkMaxSlopeDegrees = 15,
	LandmarkPlazaRadius = 46,
	LandmarkClearRadius = 42,

	RepairPassLimit = 3,
	PropBudget = 96,
	GeneratedDescendantBudget = 850,
}

return table.freeze(config)
