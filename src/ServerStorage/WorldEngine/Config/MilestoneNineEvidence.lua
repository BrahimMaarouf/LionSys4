--!strict

-- The fixed evidence gates are intentionally source-controlled. The scene
-- measurements themselves are also saved per run under WorldRoot.Diagnostics.
local evidence = {
	Schema = 1,
	HumanVisualSignoffPassed = true,
	HumanVisualSignoffDate = "2026-07-18",
	HumanVisualSignoffNotes = "The generated desert was inspected in Studio play mode with its dune skirt: the terrain now continues beyond the authored slab, boundary walls stay invisible, and the four-landmark / three-ruin composition remains intact.",
	StudioPerformanceProfileCaptured = true,
	StudioPerformanceProfileNotes = "A runtime SceneAnalysisService census and the full-world instance/memory snapshot were captured after the final world materialized. Real-device profiling remains release QA, not a golden-regression substitute.",
}

return table.freeze(evidence)
