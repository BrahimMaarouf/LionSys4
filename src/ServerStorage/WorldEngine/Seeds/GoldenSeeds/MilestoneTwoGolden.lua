--!strict

-- Milestone 2 golden baseline: owned Blender DCC assets (2 rocks + 1 shrub),
-- data-only clustered placement, deterministic half-voxel terrain surface,
-- and authored LOD0/LOD1/LOD2 meshes retained in every materialized model.
-- Baselined 2026-07-17 after Roblox-side import and runtime LOD validation.
-- Do not update automatically on mismatch: investigate, then rebaseline intentionally.
local golden = {
	BaselineSessionId = "703807b8-25f6-4f61-8afe-8c28fa0ffa58",
	CatalogVersion = "2.1.0-m2-owned-dcc-lod",
	WorldSeed = 271828,
	PropCount = 32,
	PlacementSignature = "fnv1a32:4308cf52",
	MaterializedSignature = "fnv1a32:e1310853",
}

return table.freeze(golden)
