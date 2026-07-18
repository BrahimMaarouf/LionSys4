--!strict

-- Milestone 9 golden baseline: world-edge skirt, boundary walls, seed-browser
-- composition/ruin signatures, and full-world census for the golden seed.
-- Baselined 2026-07-19 after M9_RUNTIME_VALIDATED (56/56 props grounded with
-- the landmark-stack exemption, 77/77 ruin pieces, deterministic skirt) and
-- owner visual sign-off recorded in MilestoneNineEvidence.
-- Do not update automatically on mismatch: investigate, then rebaseline intentionally.
local golden = {
	Pending = false,
	BaselineSessionId = "b809059c-b01d-4590-917b-87015cf07701",
	WorldEdgeVersion = "9.0.0-m9-world-hardening",
	WorldSeed = 271828,
	SkirtSignature = "fnv1a32:6d0de742",
	BoundaryWallCount = 4,
	PropCount = 56,
	RuinPieceCount = 77,
	CompositionSignature = "fnv1a32:9357cc40",
	RuinSignature = "fnv1a32:f5412a23",
}

return table.freeze(golden)
