--!strict

-- Milestone 8 golden baseline: socket-grammar modular ruins from the
-- math-authored M8 kit (8 pieces). Baselined after runtime validation,
-- visual sign-off, and cross-session verification.
-- Do not update automatically on mismatch: investigate, then rebaseline intentionally.
local golden = {
	Pending = true, -- flipped false at baseline time with real signatures
	RuinVersion = "8.0.0-m8-modular-ruins",
	WorldSeed = 271828,
	PieceCount = 0,
	PlanSignature = "",
	MaterializedSignature = "",
}

return table.freeze(golden)
