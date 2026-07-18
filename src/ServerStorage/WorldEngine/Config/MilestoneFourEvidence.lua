--!strict

local evidence = {
	Schema = 1,
	HumanVisualSignoffPassed = true,
	HumanVisualSignoffDate = "2026-07-18",
	HumanVisualSignoffNotes = "All three families and fifteen recipes were inspected in Studio play mode. The saturated first tint and floating crown iteration were rejected and corrected; the final crown is grounded, composite silhouettes are readable, and the trail remains visually clear.",
	RuntimeClientValidationPassed = true,
	RuntimeClientValidationNotes = "47/47 variant and LOD tags registered; 9 vegetation wind tags registered; near camera selected LOD0; far camera showed 0 LOD0, 0 LOD1, and all 99 LOD2 meshes; vegetation wind motion was observed; character navigation reached (92.69, 35.92, 31.85) at the landmark approach.",
}

return table.freeze(evidence)
