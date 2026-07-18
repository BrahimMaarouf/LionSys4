--!strict

-- Intentional baseline only. Set after plan/material validation, visual review,
-- client traversal, and a second independent Studio process all agree.
local golden = {
	Pending = false,
	BaselineSessionId = "a4300597-dadd-4583-b544-f7cadcff8766",
	CompositionVersion = "5.0.0-m5-world-composition",
	WorldSeed = 271828,
	RegionCount = 4,
	RouteCount = 4,
	LandmarkCount = 4,
	VistaCount = 4,
	PlacementCount = 57,
	VariantCount = 56,
	ComponentCount = 115,
	IdentityAuditSignature = "fnv1a32:483a9cf7",
	PlanSignature = "fnv1a32:9357cc40",
	VariationSignature = "fnv1a32:7350c2f9",
	MaterializedSignature = "fnv1a32:a93d3cb3",
}

return table.freeze(golden)
