--!strict

local spec = {
	Name = "DesertVerticalSlice",
	GeneratorVersion = "1.0.0-m1",
	WorldSeed = 271828,

	Resolution = 4,
	WorldSize = 512,
	ChunkSize = 128,
	OriginX = -256,
	OriginZ = -256,
	MinY = -32,
	MaxY = 96,

	BaseHeight = 18,
	MacroScale = 320,
	MacroAmplitude = 24,
	RidgeScale = 210,
	RidgeAmplitude = 7,
	DuneScale = 72,
	DuneAmplitude = 8,
	DetailScale = 26,
	DetailAmplitude = 2.5,

	TerrainMaterial = Enum.Material.Sand,
}

return table.freeze(spec)
