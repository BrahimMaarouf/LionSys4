--!strict

-- Milestone 3 golden baseline: deterministic route, repaired final prop plan,
-- path patches, ecological composition, and the Sentinel Crown landmark.
-- Baselined only after runtime, materialized, visual, and navigation checks passed.
-- Rebaseline by explicit source edit only; never rewrite this from runtime code.
local golden = {
	Pending = false,
	BaselineSessionId = "e5820932-34d3-4458-a5e7-5be02cfe7b7e",
	CompositionVersion = "3.0.0-m3-composition",
	WorldSeed = 271828,
	PropCount = 49,
	RouteNodeCount = 6,
	PathPatchCount = 13,
	PlanSignature = "fnv1a32:83330968",
	MaterializedSignature = "fnv1a32:51a74ae4",
}

return table.freeze(golden)
