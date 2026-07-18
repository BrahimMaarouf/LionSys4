--!strict

local evidence = {
	Schema = 1,
	HumanVisualSignoffPassed = true,
	HumanVisualSignoffDate = "2026-07-18",
	HumanVisualSignoffNotes = "The four authored vista cameras, foreground framing, route silhouettes, regional palettes, and landmark groupings were reviewed in the live Studio scene. The final plan keeps seven foreground frames, a vegetation-dominant wadi, a rock-dominant hamada, open erg silhouettes, and the grounded Sentinel Crown composition.",
	RuntimeClientValidationPassed = true,
	RuntimeClientValidationNotes = "Client navigation reached all four landmark approaches (Sentinel Crown, Dune Needle, Wadi Gate, Hamada Watch). All 56 custom-LOD tags and 10 vegetation-wind tags registered; 115 components retained authored LOD1/LOD2 and collision proxies. The unchanged M4 LOD/wind controllers remain covered by the cumulative M4 golden.",
}

return table.freeze(evidence)
