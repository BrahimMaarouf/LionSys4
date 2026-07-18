--!strict

-- Milestone 4 golden baseline: deterministic art-directed recipes, bounded
-- morphology, composite component placement, authored LODs, and collisions.
-- Baselined after visual, navigation, wind, near/far LOD, and server validation.
-- Rebaseline by explicit source edit only; never rewrite this at runtime.
local golden = {
	Pending = false,
	BaselineSessionId = "d8c4f759-d30f-42b2-9833-8c83da2031fd",
	VariationVersion = "4.0.0-m4-asset-variation",
	WorldSeed = 271828,
	VariantCount = 47,
	ComponentCount = 99,
	RecipeCount = 15,
	IdentityAuditSignature = "fnv1a32:483a9cf7",
	PlanSignature = "fnv1a32:3b3ba273",
	MaterializedSignature = "fnv1a32:975a1fce",
}

return table.freeze(golden)
