--!strict

local evidence = {
	-- Texture pass: pipeline/textures/generate_m7_textures.py produces the
	-- three PBR sets deterministically (pure math, seeded); the carrier GLB
	-- (pipeline/textures/build_m7_texture_carrier.py) ferries them through the
	-- Studio 3D Importer. Both scripts plus the PNGs are committed.
	TexturePipelineReproducible = true,
	HumanVisualSignoffPassed = true,
	HumanVisualSignoffNotes = "The complete ten-surface M7 texture assignment and the fifteen-recipe contact sheet were reviewed in Studio play mode; rock strata, foliage alpha, and dedicated bark all remained readable.",
	TextureGenerator = "pipeline/textures/generate_m7_textures.py",
	TextureCarrier = "pipeline/textures/build_m7_texture_carrier.py",
	CarrierGlb = "assets/export/M7TextureCarrier.glb",
	UploadedAt = "2026-07-18",

	-- Signature safety: golden signatures hash mesh IDs and quantized
	-- positions, never SurfaceAppearance maps. The full M1-M6 cumulative
	-- regression passed unchanged immediately after the texture swap.
	SignatureSafeSwapVerified = true,

	-- Device profiling: Studio-side snapshots are collected by
	-- MilestoneSevenValidator.CollectPerformanceSnapshot. A real-device
	-- profile requires publishing the place and running on hardware; recorded
	-- here when performed.
	DeviceProfileRecorded = false,
	DeviceProfileNotes = "Deferred to Milestone 9 hardening by owner decision (2026-07-18): profile the full-size world on a mid-range phone with MicroProfiler once M9 scale-up lands.",
}

return table.freeze(evidence)
