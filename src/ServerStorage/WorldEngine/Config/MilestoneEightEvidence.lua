--!strict

-- Owner-reviewed, source-controlled evidence. This is deliberately separate
-- from live Workspace attributes so a clean Studio session can still verify
-- the visual gate alongside the immutable numerical golden.
local evidence = {
	Schema = 1,
	HumanVisualSignoffPassed = true,
	HumanVisualSignoffDate = "2026-07-18",
	HumanVisualSignoffNotes = "All three seeded ruin sites were inspected in Studio play mode: terrain-snapped pieces were grounded, doorway gaps were readable, and the ruin kit remained legible within the generated desert composition.",
}

return table.freeze(evidence)
