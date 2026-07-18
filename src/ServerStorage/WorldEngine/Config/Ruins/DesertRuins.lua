--!strict

-- Milestone 8 socket-grammar ruin configuration. Ruins are structural
-- storytelling anchored to the M5 landmarks: a main sanctuary, a wadi
-- garden ruin, and a lone watch post along the pilgrim route.
local config = {
	Version = "8.0.0-m8-modular-ruins",
	CellSize = 8, -- wall segment length; foundation grid pitch
	SinkStuds = 0.4,
	MaximumPieces = 110,
	GeneratedDescendantBudget = 3200,
	RouteClearance = 14, -- pieces stay at least this far from route centerlines
	MaximumSiteSlopeDegrees = 7,

	-- Per-site definitions. OffsetDirections are candidate compass bearings
	-- (degrees) from the landmark; the planner picks the first whose footprint
	-- clears routes, bounds, and slope, so siting is deterministic yet safe.
	Sites = {
		{
			Id = "SanctuaryRuin",
			LandmarkId = "SentinelCrown",
			CellsX = 5,
			CellsZ = 4,
			Ruination = 0.42, -- probability weight of degraded/missing sockets
			Colonnade = true,
			FloorCoverage = 0.55,
			OffsetDistance = 34,
			OffsetDirections = {45, 135, 225, 315, 0, 90, 180, 270},
		},
		{
			Id = "WadiGardenRuin",
			LandmarkId = "WadiGate",
			CellsX = 3,
			CellsZ = 3,
			Ruination = 0.62,
			Colonnade = false,
			FloorCoverage = 0.35,
			OffsetDistance = 30,
			OffsetDirections = {90, 180, 0, 270, 45, 135, 225, 315},
		},
		{
			Id = "RouteWatchPost",
			LandmarkId = nil, -- sited along the longest route instead
			CellsX = 2,
			CellsZ = 2,
			Ruination = 0.75,
			Colonnade = false,
			FloorCoverage = 0.2,
			OffsetDistance = 26,
			OffsetDirections = {90, 270, 0, 180, 45, 225, 135, 315},
			RouteFraction = 0.55, -- position along the longest route
		},
	},
}

return table.freeze(config)
