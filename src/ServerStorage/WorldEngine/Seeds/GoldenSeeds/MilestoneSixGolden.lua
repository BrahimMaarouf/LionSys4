--!strict

local golden = {
	Pending = false,
	BaselineSessionId = "5829943b-799d-428b-b8ef-649a839a465f",
	PolishVersion = "6.0.0-m6-surface-atmosphere",
	WorldSeed = 271828,
	SurfaceCellCount = 16384,
	DetailCount = 70,
	AtmosphereEmitterCount = 4,
	PlanSignature = "fnv1a32:0855b3d5",
	SurfaceSignature = "fnv1a32:c94510dc",
	DetailSignature = "fnv1a32:8983b17e",
	MaterializedSignature = "fnv1a32:2293511d",
	IdentityAuditSignature = "fnv1a32:483a9cf7",
}

return table.freeze(golden)
