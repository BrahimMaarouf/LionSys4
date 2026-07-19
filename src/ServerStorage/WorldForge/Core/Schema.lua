--!strict

-- WorldForge parameter schema.
--
-- Every tunable value in the system is declared here exactly once, with the
-- metadata the UI needs to render a control for it. The panel builds itself
-- from this table: add a parameter here and it appears in the UI with the
-- right widget, range and rebuild behaviour. No UI code changes.
--
-- Rebuild scopes, from cheapest to most expensive:
--   "lighting"   -- re-apply lighting only (instant)
--   "surface"    -- repaint terrain materials + detail
--   "structures" -- rebuild structure layer
--   "scatter"    -- rebuild scattered props
--   "terrain"    -- rebuild terrain and everything downstream

export type Parameter = {
	Id: string,
	Label: string,
	Help: string,
	Type: "number" | "integer" | "boolean" | "string" | "enum",
	Default: any,
	Min: number?,
	Max: number?,
	Step: number?,
	Options: {string}?,
	Stage: string,
	Rebuild: string,
}

local function n(id, label, help, default, min, max, step, stage, rebuild): Parameter
	return {Id = id, Label = label, Help = help, Type = "number", Default = default,
		Min = min, Max = max, Step = step, Stage = stage, Rebuild = rebuild}
end

local function i(id, label, help, default, min, max, stage, rebuild): Parameter
	return {Id = id, Label = label, Help = help, Type = "integer", Default = default,
		Min = min, Max = max, Step = 1, Stage = stage, Rebuild = rebuild}
end

local function b(id, label, help, default, stage, rebuild): Parameter
	return {Id = id, Label = label, Help = help, Type = "boolean", Default = default,
		Stage = stage, Rebuild = rebuild}
end

local function e(id, label, help, default, options, stage, rebuild): Parameter
	return {Id = id, Label = label, Help = help, Type = "enum", Default = default,
		Options = options, Stage = stage, Rebuild = rebuild}
end

local TERRAIN_MATERIALS = {
	"Sand", "Grass", "Snow", "Rock", "Slate", "Basalt", "Ground", "Mud",
	"LeafyGrass", "Salt", "Limestone", "Asphalt", "Glacier", "CrackedLava",
}

local parameters: {Parameter} = {
	-- ── Stage 1: Terrain ────────────────────────────────────────────────
	i("terrain.size", "World Size", "Side length in studs. Snapped to the nearest 8.", 512, 128, 2048, "Terrain", "terrain"),
	n("terrain.baseHeight", "Base Height", "Average ground level in studs.", 20, -100, 200, 1, "Terrain", "terrain"),
	n("terrain.amplitude", "Amplitude", "Overall height variation. 0 = dead flat, 3 = extreme.", 1.0, 0, 3, 0.05, "Terrain", "terrain"),
	n("terrain.featureScale", "Feature Scale", "Size of landforms. Low = many small hills, high = few large masses.", 1.0, 0.2, 4, 0.05, "Terrain", "terrain"),
	n("terrain.ridges", "Ridges", "Sharpness of ridgelines. 0 = rounded dunes, 1 = knife-edge mountains.", 0.35, 0, 1, 0.01, "Terrain", "terrain"),
	n("terrain.warp", "Domain Warp", "Distorts the noise so features stop looking like noise.", 0.30, 0, 1, 0.01, "Terrain", "terrain"),
	n("terrain.valleys", "Valleys", "Carves low channels through the landscape.", 0.0, 0, 1, 0.01, "Terrain", "terrain"),
	n("terrain.detail", "Detail", "Fine surface roughness on top of the main shape.", 0.35, 0, 1, 0.01, "Terrain", "terrain"),
	n("terrain.plateau", "Plateau", "Flattens high ground into mesa tops.", 0.0, 0, 1, 0.01, "Terrain", "terrain"),
	n("terrain.waterLevel", "Water Level", "Fills terrain below this height with water. Below base = no water.", -1, -1, 200, 1, "Terrain", "terrain"),
	e("terrain.material", "Ground Material", "Base terrain material.", "Sand", TERRAIN_MATERIALS, "Terrain", "terrain"),
	b("terrain.edgeSkirt", "Edge Skirt", "Extend terrain past the world edge so the horizon is not a cliff.", true, "Terrain", "terrain"),
	b("terrain.boundaryWalls", "Boundary Walls", "Invisible walls keeping players inside the world.", true, "Terrain", "terrain"),

	-- ── Stage 3: Zones ──────────────────────────────────────────────────
	i("zones.count", "Zone Count", "How many regions to divide the world into.", 3, 1, 8, "Zones", "scatter"),
	n("zones.blend", "Zone Blend", "How softly zones bleed into each other.", 0.35, 0, 1, 0.01, "Zones", "scatter"),

	-- ── Stage 4: Scatter ────────────────────────────────────────────────
	n("scatter.density", "Density", "Overall amount of scattered objects.", 0.40, 0, 1, 0.01, "Scatter", "scatter"),
	n("scatter.clustering", "Clustering", "0 = even spread, 1 = tight clumps with open space between.", 0.45, 0, 1, 0.01, "Scatter", "scatter"),
	n("scatter.jitter", "Jitter", "Random offset from the placement grid.", 0.28, 0, 0.5, 0.01, "Scatter", "scatter"),
	n("scatter.spacingScale", "Spacing", "Multiplies each asset's minimum spacing.", 1.0, 0.25, 3, 0.05, "Scatter", "scatter"),
	i("scatter.cellSize", "Grid Cell", "Placement grid pitch in studs. Smaller = denser candidates.", 34, 8, 128, "Scatter", "scatter"),
	i("scatter.edgeMargin", "Edge Margin", "Keep objects this far from the world edge.", 24, 0, 200, "Scatter", "scatter"),
	i("scatter.spawnClear", "Spawn Clearing", "Radius around origin kept clear of objects.", 52, 0, 300, "Scatter", "scatter"),
	i("scatter.maxObjects", "Max Objects", "Hard cap on scattered objects.", 400, 10, 3000, "Scatter", "scatter"),
	b("scatter.alignToSlope", "Align To Slope", "Tilt objects to match the ground normal.", true, "Scatter", "scatter"),
	n("scatter.scaleVariation", "Scale Variation", "How much object size varies from its base scale.", 0.25, 0, 1, 0.01, "Scatter", "scatter"),

	-- ── Stage 5: Structures ─────────────────────────────────────────────
	b("structures.enabled", "Enable Structures", "Build modular structures from a structure kit.", false, "Structures", "structures"),
	i("structures.sites", "Site Count", "How many structures to place.", 3, 1, 20, "Structures", "structures"),
	i("structures.cellsX", "Site Width", "Footprint width in kit cells.", 4, 1, 12, "Structures", "structures"),
	i("structures.cellsZ", "Site Depth", "Footprint depth in kit cells.", 4, 1, 12, "Structures", "structures"),
	i("structures.cellSize", "Cell Size", "Size of one kit cell in studs (your wall length).", 8, 2, 32, "Structures", "structures"),
	n("structures.degradation", "Degradation", "0 = pristine, 1 = collapsed rubble.", 0.45, 0, 1, 0.01, "Structures", "structures"),
	n("structures.floorCoverage", "Floor Coverage", "How much interior floor is laid.", 0.5, 0, 1, 0.01, "Structures", "structures"),
	b("structures.guaranteeEntrance", "Guarantee Entrance", "Always leave at least one doorway per structure.", true, "Structures", "structures"),
	i("structures.maxSlope", "Max Site Slope", "Reject sites steeper than this (degrees).", 8, 0, 45, "Structures", "structures"),

	-- ── Stage 6: Surface & Light ────────────────────────────────────────
	b("surface.enabled", "Enable Surface Rules", "Paint terrain materials by slope and altitude.", true, "Surface", "surface"),
	e("surface.slopeMaterial", "Steep Material", "Material applied to steep ground.", "Rock", TERRAIN_MATERIALS, "Surface", "surface"),
	i("surface.slopeThreshold", "Steep Angle", "Slope angle above which steep material applies.", 28, 5, 80, "Surface", "surface"),
	e("surface.peakMaterial", "Peak Material", "Material applied to high ground.", "Snow", TERRAIN_MATERIALS, "Surface", "surface"),
	n("surface.peakHeight", "Peak Height", "Height fraction above which peak material applies. 1 = never.", 1.0, 0, 1, 0.01, "Surface", "surface"),
	e("surface.shoreMaterial", "Shore Material", "Material applied near water.", "Sand", TERRAIN_MATERIALS, "Surface", "surface"),
	i("surface.shoreBand", "Shore Band", "Height band above water level treated as shore.", 6, 0, 40, "Surface", "surface"),

	n("lighting.clockTime", "Time of Day", "0-24. 6 = dawn, 12 = noon, 19 = dusk.", 7.2, 0, 24, 0.1, "Surface", "lighting"),
	n("lighting.brightness", "Sun Brightness", "Sun intensity.", 2.4, 0, 6, 0.05, "Surface", "lighting"),
	n("lighting.exposure", "Exposure", "Overall exposure compensation.", 0.0, -3, 3, 0.05, "Surface", "lighting"),
	n("lighting.fogDensity", "Haze", "Atmospheric density.", 0.32, 0, 1, 0.01, "Surface", "lighting"),
	n("lighting.fogHaze", "Haze Spread", "How far haze reaches.", 1.8, 0, 5, 0.05, "Surface", "lighting"),
	b("lighting.shadows", "Shadows", "Global shadows.", true, "Surface", "lighting"),
	b("lighting.clouds", "Clouds", "Sky clouds.", true, "Surface", "lighting"),
	n("lighting.cloudCover", "Cloud Cover", "How much sky the clouds fill.", 0.45, 0, 1, 0.01, "Surface", "lighting"),
}

-- Roblox terrain only supports 4-stud voxels, so this is a constant rather
-- than a control. It stays in the table because recipes read it, but the panel
-- skips Hidden parameters so no one can set it to a value that crashes
-- WriteVoxels.
table.insert(parameters, {
	Id = "terrain.resolution", Label = "Voxel Size",
	Help = "Fixed by Roblox at 4 studs.", Type = "integer",
	Default = 4, Min = 4, Max = 4, Step = 1,
	Stage = "Terrain", Rebuild = "terrain", Hidden = true,
})

local byId: {[string]: Parameter} = {}
local byStage: {[string]: {Parameter}} = {}
for _, parameter in parameters do
	byId[parameter.Id] = parameter
	local bucket = byStage[parameter.Stage]
	if not bucket then
		bucket = {}
		byStage[parameter.Stage] = bucket
	end
	table.insert(bucket, parameter)
end

local Schema = {
	Version = "1.1.0",
	Parameters = parameters,
	ById = byId,
	ByStage = byStage,
	Stages = {"Terrain", "Library", "Zones", "Scatter", "Structures", "Surface", "Save"},
	SeedStages = {"terrain", "zones", "scatter", "structures"},
	TerrainMaterials = TERRAIN_MATERIALS,
	RebuildOrder = {"terrain", "surface", "scatter", "structures", "lighting"},
}

-- Returns a fully-populated default value table.
function Schema.Defaults(): {[string]: any}
	local defaults = {}
	for _, parameter in parameters do
		defaults[parameter.Id] = parameter.Default
	end
	return defaults
end

-- Clamps/coerces a value to its declared type and range. Returns the safe
-- value plus a note when it had to be corrected, so the UI can report it.
function Schema.Coerce(id: string, value: any): (any, string?)
	local parameter = byId[id]
	if not parameter then
		return nil, "unknown parameter: " .. tostring(id)
	end
	if parameter.Type == "boolean" then
		if type(value) == "boolean" then return value end
		return parameter.Default, "expected true/false"
	elseif parameter.Type == "enum" then
		for _, option in parameter.Options :: {string} do
			if option == value then return value end
		end
		return parameter.Default, "unknown option " .. tostring(value)
	elseif parameter.Type == "number" or parameter.Type == "integer" then
		local number = tonumber(value)
		if not number then
			return parameter.Default, "expected a number"
		end
		if parameter.Type == "integer" then
			number = math.floor(number + 0.5)
		end
		local clamped = math.clamp(number, parameter.Min or -math.huge, parameter.Max or math.huge)
		if clamped ~= number then
			return clamped, string.format("%s clamped to %s", tostring(number), tostring(clamped))
		end
		return clamped
	end
	return value
end

return table.freeze(Schema)
