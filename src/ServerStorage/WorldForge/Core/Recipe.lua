--!strict

-- WorldForge Recipe: one world, described entirely as data.
--
-- A recipe holds per-stage seeds, parameter overrides, zone definitions and
-- a structure-kit reference. Only values that differ from the schema defaults
-- are stored, so a saved recipe stays short and readable.
--
-- Recipes live in ServerStorage.WorldForge.Recipes as StringValues (JSON), so
-- they persist with the place and can be exported to the repo verbatim.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local WorldForge = script.Parent.Parent
local Schema = require(WorldForge.Core.Schema)
local Checksum = require(WorldForge.Core.Checksum)

local Recipe = {}

export type Zone = {
	Name: string,
	Rule: string,        -- "everywhere" | "altitude" | "slope" | "patch" | "nearWater"
	Min: number?,        -- rule bounds (altitude fraction, slope degrees, ...)
	Max: number?,
	Allow: {string},     -- asset ids or "*" or "kind:Tree"
	Density: number,     -- multiplies the global scatter density
}

export type Data = {
	Schema: number,
	Name: string,
	Seeds: {[string]: number},
	Params: {[string]: any},
	Zones: {Zone},
	StructureKit: {string},   -- library asset ids used as structure pieces
	CreatedAt: number,
	UpdatedAt: number,
}

local function recipesFolder(): Folder
	local forge = ServerStorage:FindFirstChild("WorldForge")
	if not forge then
		forge = Instance.new("Folder")
		forge.Name = "WorldForge"
		forge.Parent = ServerStorage
	end
	local folder = forge:FindFirstChild("Recipes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Recipes"
		folder.Parent = forge
	end
	return folder :: Folder
end

function Recipe.New(name: string?): Data
	local seeds = {}
	for _, stage in Schema.SeedStages do
		seeds[stage] = math.random(1, 1000000)
	end
	return {
		Schema = 1,
		Name = name or "Untitled World",
		Seeds = seeds,
		Params = {},
		Zones = {
			{Name = "Everywhere", Rule = "everywhere", Allow = {"*"}, Density = 1},
		},
		StructureKit = {},
		CreatedAt = os.time(),
		UpdatedAt = os.time(),
	}
end

-- Reads a parameter, falling back to the schema default.
function Recipe.Get(data: Data, id: string): any
	local value = data.Params[id]
	if value == nil then
		local parameter = Schema.ById[id]
		return parameter and parameter.Default
	end
	return value
end

-- Writes a parameter with coercion. Returns the stored value and any note.
function Recipe.Set(data: Data, id: string, value: any): (any, string?)
	local coerced, note = Schema.Coerce(id, value)
	local parameter = Schema.ById[id]
	if not parameter then
		return nil, note
	end
	if coerced == parameter.Default then
		data.Params[id] = nil        -- stay minimal: defaults are not stored
	else
		data.Params[id] = coerced
	end
	data.UpdatedAt = os.time()
	return coerced, note
end

function Recipe.SetSeed(data: Data, stage: string, seed: number?)
	assert(table.find(Schema.SeedStages, stage), "unknown seed stage: " .. tostring(stage))
	data.Seeds[stage] = seed or math.random(1, 1000000)
	data.UpdatedAt = os.time()
	return data.Seeds[stage]
end

function Recipe.GetSeed(data: Data, stage: string): number
	return data.Seeds[stage] or 0
end

-- Fully resolved parameter table (defaults + overrides), for the stages.
function Recipe.Resolve(data: Data): {[string]: any}
	local resolved = Schema.Defaults()
	for id, value in data.Params do
		if Schema.ById[id] then
			resolved[id] = value
		end
	end
	return resolved
end

-- Stable identity of a world: same recipe → same hash on any machine.
function Recipe.Hash(data: Data): string
	local ids = {}
	for id in Schema.ById do
		table.insert(ids, id)
	end
	table.sort(ids)

	local state = Checksum.New()
	Checksum.UpdateString(state, "worldforge-recipe-v1")
	for _, stage in Schema.SeedStages do
		Checksum.UpdateString(state, stage)
		Checksum.UpdateUInt32(state, data.Seeds[stage] or 0)
	end
	local resolved = Recipe.Resolve(data)
	for _, id in ids do
		local value = resolved[id]
		Checksum.UpdateString(state, id)
		if type(value) == "number" then
			Checksum.UpdateUInt32(state, math.floor(value * 4096 + 0.5) % 4294967296)
		elseif type(value) == "boolean" then
			Checksum.UpdateUInt32(state, value and 1 or 0)
		else
			Checksum.UpdateString(state, tostring(value))
		end
	end
	for index, zone in data.Zones do
		Checksum.UpdateUInt32(state, index)
		Checksum.UpdateString(state, zone.Name .. "|" .. zone.Rule)
		Checksum.UpdateUInt32(state, math.floor((zone.Min or 0) * 1024 + 0.5) % 4294967296)
		Checksum.UpdateUInt32(state, math.floor((zone.Max or 0) * 1024 + 0.5) % 4294967296)
		Checksum.UpdateUInt32(state, math.floor((zone.Density or 1) * 1024 + 0.5) % 4294967296)
		for _, allow in zone.Allow do
			Checksum.UpdateString(state, allow)
		end
	end
	for _, piece in data.StructureKit do
		Checksum.UpdateString(state, piece)
	end
	return Checksum.Digest(state)
end

function Recipe.ToJson(data: Data): string
	return HttpService:JSONEncode(data)
end

function Recipe.FromJson(json: string): Data
	local decoded = HttpService:JSONDecode(json)
	local data = Recipe.New(decoded.Name)
	data.Schema = decoded.Schema or 1
	data.Seeds = decoded.Seeds or data.Seeds
	data.Params = {}
	for id, value in decoded.Params or {} do
		if Schema.ById[id] then
			data.Params[id] = (Schema.Coerce(id, value))
		end
	end
	data.Zones = decoded.Zones or data.Zones
	data.StructureKit = decoded.StructureKit or {}
	data.CreatedAt = decoded.CreatedAt or os.time()
	data.UpdatedAt = decoded.UpdatedAt or os.time()
	return data
end

-- Save / load -----------------------------------------------------------------

function Recipe.Save(data: Data): string
	local folder = recipesFolder()
	local name = data.Name
	local value = folder:FindFirstChild(name)
	if not value then
		value = Instance.new("StringValue")
		value.Name = name
		value.Parent = folder
	end
	assert(value:IsA("StringValue"))
	data.UpdatedAt = os.time()
	value.Value = Recipe.ToJson(data)
	value:SetAttribute("Hash", Recipe.Hash(data))
	value:SetAttribute("UpdatedAt", data.UpdatedAt)
	return Recipe.Hash(data)
end

function Recipe.Load(name: string): Data?
	local value = recipesFolder():FindFirstChild(name)
	if value and value:IsA("StringValue") then
		return Recipe.FromJson(value.Value)
	end
	return nil
end

function Recipe.Delete(name: string): boolean
	local value = recipesFolder():FindFirstChild(name)
	if value then
		value:Destroy()
		return true
	end
	return false
end

function Recipe.List()
	local entries = {}
	for _, value in recipesFolder():GetChildren() do
		if value:IsA("StringValue") then
			table.insert(entries, {
				Name = value.Name,
				Hash = value:GetAttribute("Hash"),
				UpdatedAt = value:GetAttribute("UpdatedAt"),
			})
		end
	end
	table.sort(entries, function(a, b) return a.Name < b.Name end)
	return entries
end

return table.freeze(Recipe)
