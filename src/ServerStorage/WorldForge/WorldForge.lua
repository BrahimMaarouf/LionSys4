--!strict

-- WorldForge — public API.
--
-- One entry point for the panel, the command bar, and any future tooling.
-- Holds the "active recipe" you are editing, runs stages, and tracks which
-- layers have gone stale so nothing silently disappears.
--
--   local WF = require(game.ServerStorage.WorldForge.WorldForge)
--   WF.Set("terrain.amplitude", 1.8)
--   WF.Build("terrain")
--
-- The engine never authors content: everything placed comes from the assets
-- you imported into the Library.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldForgeFolder = script.Parent
local Library = require(WorldForgeFolder.Core.AssetLibrary)
local Recipe = require(WorldForgeFolder.Core.Recipe)
local Schema = require(WorldForgeFolder.Core.Schema)
local ScatterStage = require(WorldForgeFolder.Stages.ScatterStage)
local StructureStage = require(WorldForgeFolder.Stages.StructureStage)
local SurfaceStage = require(WorldForgeFolder.Stages.SurfaceStage)
local TerrainStage = require(WorldForgeFolder.Stages.TerrainStage)

local WorldForge = {}

WorldForge.Schema = Schema
WorldForge.Library = Library
WorldForge.Recipe = Recipe

local active: Recipe.Data = Recipe.New("Untitled World")
local dirty: {[string]: boolean} = {}

-- Layers that must be rebuilt when a given layer changes.
local DOWNSTREAM = {
	terrain = {"surface", "scatter", "structures"},
	surface = {},
	scatter = {},
	structures = {},
	lighting = {},
}

local function markDirty(layer: string)
	dirty[layer] = true
	for _, downstream in DOWNSTREAM[layer] or {} do
		dirty[downstream] = true
	end
end

-- Recipe access ---------------------------------------------------------------

function WorldForge.Active(): Recipe.Data
	return active
end

function WorldForge.NewRecipe(name: string?)
	active = Recipe.New(name)
	dirty = {terrain = true, surface = true, scatter = true, structures = true, lighting = true}
	return WorldForge.Status()
end

function WorldForge.Get(id: string): any
	return Recipe.Get(active, id)
end

function WorldForge.Set(id: string, value: any)
	local parameter = Schema.ById[id]
	if not parameter then
		return {Ok = false, Error = "unknown parameter: " .. tostring(id)}
	end
	local stored, note = Recipe.Set(active, id, value)
	markDirty(parameter.Rebuild)
	return {Ok = true, Id = id, Value = stored, Note = note, Dirty = WorldForge.DirtyLayers()}
end

-- Bulk set, e.g. from the panel applying a whole stage at once.
function WorldForge.SetMany(values: {[string]: any})
	local notes = {}
	for id, value in values do
		local result = WorldForge.Set(id, value)
		if result.Note then
			notes[id] = result.Note
		end
	end
	return {Ok = true, Notes = notes, Dirty = WorldForge.DirtyLayers()}
end

function WorldForge.Seed(stage: string): number
	return Recipe.GetSeed(active, stage)
end

function WorldForge.SetSeed(stage: string, seed: number?)
	local value = Recipe.SetSeed(active, stage, seed)
	markDirty(if stage == "zones" then "scatter" else stage)
	return {Stage = stage, Seed = value, Dirty = WorldForge.DirtyLayers()}
end

function WorldForge.RollSeed(stage: string)
	return WorldForge.SetSeed(stage, nil)
end

function WorldForge.DirtyLayers(): {string}
	local layers = {}
	for _, layer in Schema.RebuildOrder do
		if dirty[layer] then
			table.insert(layers, layer)
		end
	end
	return layers
end

-- Zones -----------------------------------------------------------------------

function WorldForge.Zones()
	return active.Zones
end

function WorldForge.SetZones(zones)
	active.Zones = zones
	markDirty("scatter")
	return {Ok = true, Count = #zones}
end

function WorldForge.AddZone(name: string, rule: string, min: number?, max: number?, allow: {string}?, density: number?)
	table.insert(active.Zones, {
		Name = name, Rule = rule, Min = min, Max = max,
		Allow = allow or {"*"}, Density = density or 1,
		PatchIndex = #active.Zones,
	})
	markDirty("scatter")
	return active.Zones
end

function WorldForge.RemoveZone(name: string)
	for index, zone in active.Zones do
		if zone.Name == name then
			table.remove(active.Zones, index)
			markDirty("scatter")
			return true
		end
	end
	return false
end

function WorldForge.SetStructureKit(assetIds: {string})
	active.StructureKit = assetIds
	markDirty("structures")
	return {Ok = true, Count = #assetIds}
end

-- Build -----------------------------------------------------------------------

-- WorldForge and the legacy WorldEngine both own Workspace.Terrain, so they
-- cannot be materialized at the same time. Building a WorldForge world parks
-- the WorldEngine world (nothing is lost — it rebuilds from its own golden
-- regression on demand) and clears the terrain exactly once.
local function yieldTerrain()
	local legacy = Workspace:FindFirstChild("WorldRoot")
	if legacy then
		local parked = ServerStorage:FindFirstChild("_ParkedWorldRoot")
		if parked then
			parked:Destroy()          -- only ever keep one parked copy
		end
		legacy.Name = "_ParkedWorldRoot"
		legacy.Parent = ServerStorage
	end
end

-- Restores the legacy WorldEngine world and removes the WorldForge one, so the
-- M1-M9 cumulative regression can run cleanly.
function WorldForge.ReleaseToWorldEngine()
	WorldForge.Clear()
	Workspace.Terrain:Clear()
	local parked = ServerStorage:FindFirstChild("_ParkedWorldRoot")
	if parked then
		local existing = Workspace:FindFirstChild("WorldRoot")
		if existing then
			existing:Destroy()        -- never allow two WorldRoots to coexist
		end
		parked.Name = "WorldRoot"
		parked.Parent = Workspace
	end
	return {Released = true, Restored = parked ~= nil}
end

--[[
	Builds one layer, or "all". Layers are built in dependency order and the
	dirty flags for what was built are cleared.
]]
function WorldForge.Build(layer: string?)
	local target = layer or "all"
	if target == "all" or target == "terrain" then
		yieldTerrain()
	end
	local report = {Recipe = active.Name, Hash = Recipe.Hash(active)}
	local started = os.clock()

	local function build(name: string)
		if name == "terrain" then
			report.Terrain = TerrainStage.Materialize(active)
		elseif name == "surface" then
			report.Surface = SurfaceStage.Apply(active)
		elseif name == "scatter" then
			report.Scatter = ScatterStage.Materialize(active)
		elseif name == "structures" then
			report.Structures = StructureStage.Materialize(active)
		elseif name == "lighting" then
			report.Lighting = SurfaceStage.ApplyLighting(active)
		end
		dirty[name] = nil
	end

	if target == "all" then
		for _, name in {"terrain", "surface", "scatter", "structures", "lighting"} do
			build(name)
		end
	else
		build(target)
		-- rebuilding terrain invalidates everything below it
		if target == "terrain" then
			for _, downstream in DOWNSTREAM.terrain do
				dirty[downstream] = true
			end
		end
	end

	report.Seconds = os.clock() - started
	report.Dirty = WorldForge.DirtyLayers()
	return report
end

-- Preview: plan without materializing. Cheap, creates nothing.
function WorldForge.Preview()
	local field = TerrainStage.BuildField(active)
	local scatter = ScatterStage.Plan(active)
	local structures = StructureStage.Plan(active)
	return {
		Recipe = active.Name,
		Hash = Recipe.Hash(active),
		Terrain = {
			Seed = field.Seed, Size = field.Size,
			MinHeight = math.floor(field.MinHeight * 10) / 10,
			MaxHeight = math.floor(field.MaxHeight * 10) / 10,
			Relief = math.floor((field.MaxHeight - field.MinHeight) * 10) / 10,
			Signature = TerrainStage.Signature(active),
		},
		Scatter = {
			Count = #scatter.Placements, Counts = scatter.Counts,
			Rejected = scatter.Rejected, Signature = scatter.Signature,
		},
		Structures = {
			Pieces = #structures.Pieces, Sites = #structures.Sites,
			Signature = structures.Signature, Error = structures.Error,
		},
		LibraryAssets = Library.Count(),
	}
end

function WorldForge.Clear()
	ScatterStage.Clear()
	StructureStage.Clear()
	TerrainStage.Clear(active)
	local root = Workspace:FindFirstChild("WorldForgeWorld")
	if root then root:Destroy() end
	dirty = {terrain = true, surface = true, scatter = true, structures = true, lighting = true}
	return {Cleared = true}
end

-- Save / load -----------------------------------------------------------------

function WorldForge.Save(name: string?)
	if name and name ~= "" then
		active.Name = name
	end
	local hash = Recipe.Save(active)
	return {Saved = active.Name, Hash = hash}
end

function WorldForge.Load(name: string)
	local loaded = Recipe.Load(name)
	if not loaded then
		return {Ok = false, Error = "no saved world named " .. name}
	end
	active = loaded
	dirty = {terrain = true, surface = true, scatter = true, structures = true, lighting = true}
	return {Ok = true, Loaded = name, Hash = Recipe.Hash(active), Dirty = WorldForge.DirtyLayers()}
end

function WorldForge.SavedWorlds()
	return Recipe.List()
end

function WorldForge.Delete(name: string)
	return {Deleted = Recipe.Delete(name)}
end

function WorldForge.Export(): string
	return Recipe.ToJson(active)
end

function WorldForge.Import(json: string)
	active = Recipe.FromJson(json)
	dirty = {terrain = true, surface = true, scatter = true, structures = true, lighting = true}
	return {Ok = true, Name = active.Name, Hash = Recipe.Hash(active)}
end

-- Status ----------------------------------------------------------------------

function WorldForge.Status()
	local root = Workspace:FindFirstChild("WorldForgeWorld")
	return {
		Recipe = active.Name,
		Hash = Recipe.Hash(active),
		Seeds = active.Seeds,
		Zones = #active.Zones,
		LibraryAssets = Library.Count(),
		Dirty = WorldForge.DirtyLayers(),
		Built = root ~= nil,
		ScatterCount = root and root:GetAttribute("ScatterCount") or 0,
		StructureCount = root and root:GetAttribute("StructureCount") or 0,
	}
end

function WorldForge.Help(): string
	return table.concat({
		"WorldForge — build any world from your own assets.",
		"",
		'local WF = require(game.ServerStorage.WorldForge.WorldForge)',
		"",
		"LIBRARY (your assets)",
		'  WF.Library.Import({Id="pine", Kind="Tree", MeshId="rbxassetid://123",',
		'                     ColorMap="rbxassetid://456", Spacing=9, MaxSlope=30})',
		"  WF.Library.List()            -- what is in the library",
		"  WF.Library.BuildPreview()    -- lay the whole kit out to review",
		"",
		"TERRAIN",
		'  WF.Set("terrain.amplitude", 1.8)   WF.Set("terrain.ridges", 0.8)',
		'  WF.RollSeed("terrain")             WF.Build("terrain")',
		"",
		"ZONES + SCATTER",
		'  WF.AddZone("Highlands", "altitude", 0.6, 1.0, {"kind:Rock"}, 1)',
		'  WF.Set("scatter.density", 0.6)     WF.Build("scatter")',
		"",
		"WHOLE WORLD",
		"  WF.Build()        -- everything    WF.Preview()   -- plan only",
		'  WF.Save("My World")               WF.Load("My World")',
		"  WF.Status()       WF.SavedWorlds()",
	}, "\n")
end

return table.freeze(WorldForge)
