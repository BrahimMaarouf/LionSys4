--!strict

local evidence = {
	Schema = 1,
	HumanVisualSignoffPassed = true,
	HumanVisualSignoffDate = "2026-07-18",
	HumanVisualSignoffNotes = "Erg, wadi, hamada, and crown vista captures were reviewed in Play mode. Sand, cracked ground, sandstone, and rock fields blend at terrain resolution; detail accents stay subordinate to landmarks; dust, bloom, depth, and clouds add atmosphere without hiding routes.",
	RuntimeClientValidationPassed = true,
	RuntimeClientValidationNotes = "All 70 surface details replicated anchored and non-blocking; four regional dust emitters were enabled; Bloom, depth of field, and clouds replicated. All four landmark approaches remained reachable, with 56 inherited LOD registrations and 10 wind registrations intact.",
}

return table.freeze(evidence)
