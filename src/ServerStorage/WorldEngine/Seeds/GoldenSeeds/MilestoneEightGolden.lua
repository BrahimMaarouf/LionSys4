--!strict

-- Milestone 8 golden baseline: socket-grammar modular ruins from the
-- math-authored M8 kit (8 pieces). Baselined after runtime validation,
-- visual sign-off, and cross-session verification.
-- Do not update automatically on mismatch: investigate, then rebaseline intentionally.
local golden = {
	Pending = false,
	BaselineSessionId = "fb931e01-f725-4b5a-b08c-c8b6edfdfa17",
	RuinVersion = "8.0.0-m8-modular-ruins",
	WorldSeed = 271828,
	PieceCount = 77,
	PlanSignature = "fnv1a32:f5412a23",
	MaterializedSignature = "fnv1a32:3d52e8e5",
}

return table.freeze(golden)
