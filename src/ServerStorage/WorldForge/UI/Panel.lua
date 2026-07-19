--!strict

-- WorldForge panel.
--
-- A sectioned control surface built entirely from the parameter schema — add a
-- parameter to Schema.lua and a control for it appears here automatically.
--
-- Sections follow the build order, so the tool reads top to bottom:
--   1 Terrain     seeds + landform controls
--   2 Library     your assets, imported and organised
--   3 Zones       where things are allowed to grow
--   4 Scatter     how densely they are placed
--   5 Structures  modular assembly from your kit
--   6 Surface     materials, atmosphere, light
--   7 Save        name it, keep it, load it back
--
-- Launch:  require(game.ServerStorage.WorldForge.UI.Panel).Open()

local CoreGui = game:GetService("CoreGui")
local ServerStorage = game:GetService("ServerStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local WorldForgeFolder = script.Parent.Parent
local Schema = require(WorldForgeFolder.Core.Schema)
local WorldForge = require(WorldForgeFolder.WorldForge)

local Panel = {}

local GUI_NAME = "WorldForgePanel"

local COLORS = {
	bg = Color3.fromRGB(24, 24, 28),
	panel = Color3.fromRGB(32, 33, 38),
	row = Color3.fromRGB(40, 41, 47),
	edge = Color3.fromRGB(58, 60, 68),
	text = Color3.fromRGB(232, 232, 238),
	dim = Color3.fromRGB(150, 152, 162),
	accent = Color3.fromRGB(226, 118, 62),
	good = Color3.fromRGB(126, 190, 106),
	warn = Color3.fromRGB(226, 180, 80),
}

local SECTIONS = {
	{Id = "Terrain", Label = "1 · Terrain"},
	{Id = "Library", Label = "2 · Library"},
	{Id = "Zones", Label = "3 · Zones"},
	{Id = "Scatter", Label = "4 · Scatter"},
	{Id = "Structures", Label = "5 · Structures"},
	{Id = "Surface", Label = "6 · Surface & Light"},
	{Id = "Save", Label = "7 · Save"},
}

local state = {
	section = "Terrain",
	gui = nil :: ScreenGui?,
	body = nil :: Frame?,
	status = nil :: TextLabel?,
	refresh = nil :: (() -> ())?,
}

-- helpers ---------------------------------------------------------------------

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 6)
	c.Parent = parent
	return c
end

local function padding(parent: Instance, amount: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, amount)
	p.PaddingBottom = UDim.new(0, amount)
	p.PaddingLeft = UDim.new(0, amount)
	p.PaddingRight = UDim.new(0, amount)
	p.Parent = parent
	return p
end

local function label(parent: Instance, text: string, size: number, color: Color3?, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextColor3 = color or COLORS.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Size = UDim2.new(1, 0, 0, size + 8)
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3, callback: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.TextSize = 13
	b.Font = Enum.Font.GothamMedium
	b.TextColor3 = if color == COLORS.row then COLORS.text else Color3.fromRGB(20, 14, 8)
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	b.Size = UDim2.new(1, 0, 0, 30)
	b.Parent = parent
	corner(b)
	b.Activated:Connect(function()
		local ok, err = pcall(callback)
		if not ok and state.status then
			state.status.Text = "error: " .. tostring(err)
			state.status.TextColor3 = COLORS.warn
		end
	end)
	return b
end

local function textbox(parent: Instance, placeholder: string, default: string?): TextBox
	local box = Instance.new("TextBox")
	box.PlaceholderText = placeholder
	box.Text = default or ""
	box.TextSize = 13
	box.Font = Enum.Font.Code
	box.TextColor3 = COLORS.text
	box.PlaceholderColor3 = COLORS.dim
	box.BackgroundColor3 = COLORS.bg
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.Size = UDim2.new(1, 0, 0, 28)
	box.Parent = parent
	corner(box, 4)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 8)
	p.PaddingRight = UDim.new(0, 8)
	p.Parent = box
	return box
end

local function setStatus(text: string, color: Color3?)
	if state.status then
		state.status.Text = text
		state.status.TextColor3 = color or COLORS.dim
	end
end

local function statusLine(): string
	local s = WorldForge.Status()
	local dirty = #s.Dirty > 0 and ("  ·  stale: " .. table.concat(s.Dirty, ", ")) or "  ·  up to date"
	return string.format("%s  ·  %d assets  ·  %d objects%s", s.Recipe, s.LibraryAssets, s.ScatterCount, dirty)
end

-- parameter controls ----------------------------------------------------------

local function numberRow(parent: Instance, parameter)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = COLORS.row
	row.Size = UDim2.new(1, 0, 0, 52)
	row.Parent = parent
	corner(row)
	padding(row, 8)

	local name = label(row, parameter.Label, 12, COLORS.text, true)
	name.Size = UDim2.new(1, -70, 0, 16)

	local value = Instance.new("TextBox")
	value.Text = tostring(WorldForge.Get(parameter.Id))
	value.TextSize = 12
	value.Font = Enum.Font.Code
	value.TextColor3 = COLORS.accent
	value.BackgroundColor3 = COLORS.bg
	value.Size = UDim2.new(0, 62, 0, 20)
	value.Position = UDim2.new(1, -62, 0, 0)
	value.ClearTextOnFocus = false
	value.Parent = row
	corner(value, 4)

	local help = label(row, parameter.Help, 10, COLORS.dim)
	help.Position = UDim2.new(0, 0, 0, 18)
	help.Size = UDim2.new(1, 0, 0, 12)
	help.TextTruncate = Enum.TextTruncate.AtEnd

	-- slider track
	local track = Instance.new("Frame")
	track.BackgroundColor3 = COLORS.bg
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.new(0, 0, 0, 32)
	track.Parent = row
	corner(track, 3)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = COLORS.accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 3)

	local min = parameter.Min or 0
	local max = parameter.Max or 1

	local function paint()
		local current = tonumber(WorldForge.Get(parameter.Id)) or min
		local t = if max > min then (current - min) / (max - min) else 0
		fill.Size = UDim2.new(math.clamp(t, 0, 1), 0, 1, 0)
		value.Text = tostring(current)
	end
	paint()

	local function apply(v: number)
		local result = WorldForge.Set(parameter.Id, v)
		paint()
		setStatus(statusLine())
		if result.Note then
			setStatus(parameter.Label .. ": " .. result.Note, COLORS.warn)
		end
	end

	local dragging = false
	local function fromX(x: number)
		local t = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		local raw = min + t * (max - min)
		if parameter.Type == "integer" then
			raw = math.floor(raw + 0.5)
		elseif parameter.Step then
			raw = math.floor(raw / parameter.Step + 0.5) * parameter.Step
		end
		apply(raw)
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	value.FocusLost:Connect(function()
		local typed = tonumber(value.Text)
		if typed then apply(typed) else paint() end
	end)
end

local function booleanRow(parent: Instance, parameter)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = COLORS.row
	row.Size = UDim2.new(1, 0, 0, 38)
	row.Parent = parent
	corner(row)
	padding(row, 8)

	local name = label(row, parameter.Label, 12, COLORS.text, true)
	name.Size = UDim2.new(1, -50, 0, 14)
	local help = label(row, parameter.Help, 10, COLORS.dim)
	help.Position = UDim2.new(0, 0, 0, 14)
	help.Size = UDim2.new(1, -50, 0, 10)
	help.TextTruncate = Enum.TextTruncate.AtEnd

	local toggle = Instance.new("TextButton")
	toggle.Size = UDim2.new(0, 42, 0, 22)
	toggle.Position = UDim2.new(1, -42, 0, 0)
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 11
	toggle.Parent = row
	corner(toggle, 11)

	local function paint()
		local on = WorldForge.Get(parameter.Id) == true
		toggle.BackgroundColor3 = if on then COLORS.good else COLORS.bg
		toggle.TextColor3 = if on then Color3.fromRGB(16, 24, 12) else COLORS.dim
		toggle.Text = if on then "ON" else "OFF"
	end
	paint()
	toggle.Activated:Connect(function()
		WorldForge.Set(parameter.Id, not (WorldForge.Get(parameter.Id) == true))
		paint()
		setStatus(statusLine())
	end)
end

local function enumRow(parent: Instance, parameter)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = COLORS.row
	row.Size = UDim2.new(1, 0, 0, 44)
	row.Parent = parent
	corner(row)
	padding(row, 8)

	label(row, parameter.Label, 12, COLORS.text, true).Size = UDim2.new(1, 0, 0, 14)

	local current = Instance.new("TextButton")
	current.Size = UDim2.new(1, 0, 0, 22)
	current.Position = UDim2.new(0, 0, 0, 16)
	current.BackgroundColor3 = COLORS.bg
	current.Font = Enum.Font.Code
	current.TextSize = 12
	current.TextColor3 = COLORS.accent
	current.Text = tostring(WorldForge.Get(parameter.Id)) .. "   ▾"
	current.Parent = row
	corner(current, 4)

	-- cycle through options on click: simple, no dropdown windows to manage
	current.Activated:Connect(function()
		local options = parameter.Options :: {string}
		local value = WorldForge.Get(parameter.Id)
		local index = 1
		for i, option in options do
			if option == value then index = i break end
		end
		local nextValue = options[(index % #options) + 1]
		WorldForge.Set(parameter.Id, nextValue)
		current.Text = nextValue .. "   ▾"
		setStatus(statusLine())
	end)
end

local function seedRow(parent: Instance, stage: string, title: string)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = COLORS.row
	row.Size = UDim2.new(1, 0, 0, 38)
	row.Parent = parent
	corner(row)
	padding(row, 8)

	label(row, title .. " seed", 12, COLORS.text, true).Size = UDim2.new(0, 100, 1, 0)

	local box = Instance.new("TextBox")
	box.Text = tostring(WorldForge.Seed(stage))
	box.TextSize = 12
	box.Font = Enum.Font.Code
	box.TextColor3 = COLORS.accent
	box.BackgroundColor3 = COLORS.bg
	box.Size = UDim2.new(1, -170, 1, -4)
	box.Position = UDim2.new(0, 104, 0, 2)
	box.ClearTextOnFocus = false
	box.Parent = row
	corner(box, 4)

	local roll = Instance.new("TextButton")
	roll.Text = "🎲 roll"
	roll.TextSize = 12
	roll.Font = Enum.Font.GothamMedium
	roll.TextColor3 = Color3.fromRGB(20, 14, 8)
	roll.BackgroundColor3 = COLORS.accent
	roll.Size = UDim2.new(0, 58, 1, -4)
	roll.Position = UDim2.new(1, -58, 0, 2)
	roll.Parent = row
	corner(roll, 4)

	roll.Activated:Connect(function()
		local result = WorldForge.RollSeed(stage)
		box.Text = tostring(result.Seed)
		setStatus(statusLine())
	end)
	box.FocusLost:Connect(function()
		local typed = tonumber(box.Text)
		if typed then
			WorldForge.SetSeed(stage, math.floor(typed))
			setStatus(statusLine())
		else
			box.Text = tostring(WorldForge.Seed(stage))
		end
	end)
end

local function header(parent: Instance, text: string)
	local l = label(parent, text, 11, COLORS.dim, true)
	l.Size = UDim2.new(1, 0, 0, 20)
	return l
end

-- sections --------------------------------------------------------------------

local function buildParameterSection(parent: Instance, stageName: string)
	for _, parameter in Schema.ByStage[stageName] or {} do
		if parameter.Hidden then
			continue                     -- engine constants are not controls
		elseif parameter.Type == "boolean" then
			booleanRow(parent, parameter)
		elseif parameter.Type == "enum" then
			enumRow(parent, parameter)
		else
			numberRow(parent, parameter)
		end
	end
end

local function sectionTerrain(parent: Instance)
	header(parent, "SEED")
	seedRow(parent, "terrain", "Terrain")
	header(parent, "LANDFORM")
	buildParameterSection(parent, "Terrain")
	header(parent, "ACTIONS")
	button(parent, "Generate Terrain", COLORS.accent, function()
		setStatus("generating terrain…", COLORS.warn)
		local report = WorldForge.Build("terrain")
		setStatus(string.format("terrain built in %.1fs  ·  height %.0f→%.0f",
			report.Seconds, report.Terrain.MinHeight, report.Terrain.MaxHeight), COLORS.good)
	end)
	button(parent, "Preview (no build)", COLORS.row, function()
		local preview = WorldForge.Preview()
		setStatus(string.format("relief %.0f studs  ·  %d objects planned  ·  %s",
			preview.Terrain.Relief, preview.Scatter.Count, preview.Hash))
	end)
end

local function sectionLibrary(parent: Instance)
	header(parent, "IMPORT AN ASSET  (your mesh + textures)")

	local idBox = textbox(parent, "name, e.g. pine_a")
	local kindBox = textbox(parent, "kind: Rock / Tree / Bush / Plant / Prop / Debris / Structure", "Rock")
	local meshBox = textbox(parent, "mesh asset id")
	local colorBox = textbox(parent, "colour map id (optional)")
	local normalBox = textbox(parent, "normal map id (optional)")
	local roughBox = textbox(parent, "roughness map id (optional)")
	local collisionBox = textbox(parent, "collision mesh id (optional)")
	local tagBox = textbox(parent, "tags, e.g. wall,door (optional)")

	button(parent, "Import Into Library", COLORS.accent, function()
		if idBox.Text == "" or meshBox.Text == "" then
			setStatus("name and mesh id are required", COLORS.warn)
			return
		end
		local tags = nil
		if tagBox.Text ~= "" then tags = string.split(tagBox.Text, ",") end
		local _, report = WorldForge.Library.Import({
			Id = idBox.Text, Kind = kindBox.Text, MeshId = meshBox.Text,
			ColorMap = colorBox.Text ~= "" and colorBox.Text or nil,
			NormalMap = normalBox.Text ~= "" and normalBox.Text or nil,
			RoughnessMap = roughBox.Text ~= "" and roughBox.Text or nil,
			CollisionMeshId = collisionBox.Text ~= "" and collisionBox.Text or nil,
			Tags = tags,
		})
		setStatus(string.format("imported %s (%s)  ·  %d assets in library",
			idBox.Text, report.Size, WorldForge.Library.Count()), COLORS.good)
		if state.refresh then state.refresh() end
	end)

	header(parent, "LIBRARY")
	local entries = WorldForge.Library.List()
	if #entries == 0 then
		label(parent, "empty — import your first asset above", 11, COLORS.dim)
	end
	for _, entry in entries do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = COLORS.row
		row.Size = UDim2.new(1, 0, 0, 34)
		row.Parent = parent
		corner(row)
		padding(row, 8)

		local title = label(row, entry.Kind .. " · " .. entry.Id, 12, COLORS.text, true)
		title.Size = UDim2.new(1, -60, 0, 14)
		local detail = label(row, string.format("spacing %.1f · slope %d° · %.1f×%.1f studs",
			entry.Spacing or 0, entry.MaxSlope or 0, entry.FootprintX or 0, entry.Height or 0), 10, COLORS.dim)
		detail.Position = UDim2.new(0, 0, 0, 14)
		detail.Size = UDim2.new(1, -60, 0, 10)

		local remove = Instance.new("TextButton")
		remove.Text = "✕"
		remove.TextSize = 12
		remove.Font = Enum.Font.GothamBold
		remove.TextColor3 = COLORS.dim
		remove.BackgroundColor3 = COLORS.bg
		remove.Size = UDim2.new(0, 24, 0, 20)
		remove.Position = UDim2.new(1, -24, 0, 0)
		remove.Parent = row
		corner(remove, 4)
		remove.Activated:Connect(function()
			WorldForge.Library.Remove(entry.Id)
			setStatus("removed " .. entry.Id)
			if state.refresh then state.refresh() end
		end)
	end

	header(parent, "REVIEW")
	button(parent, "Show Library Preview", COLORS.row, function()
		local report = WorldForge.Library.BuildPreview()
		setStatus(string.format("laid out %d assets — fly to %d, %d, %d",
			report.Placed, report.Origin.X, report.Origin.Y, report.Origin.Z), COLORS.good)
	end)
	button(parent, "Hide Library Preview", COLORS.row, function()
		WorldForge.Library.ClearPreview()
		setStatus("preview removed")
	end)
end

local function sectionZones(parent: Instance)
	header(parent, "ZONE SEED")
	seedRow(parent, "zones", "Zones")

	header(parent, "ZONES  (first match wins, top to bottom)")
	for _, zone in WorldForge.Zones() do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = COLORS.row
		row.Size = UDim2.new(1, 0, 0, 40)
		row.Parent = parent
		corner(row)
		padding(row, 8)
		local title = label(row, zone.Name .. "  ·  " .. zone.Rule, 12, COLORS.text, true)
		title.Size = UDim2.new(1, -30, 0, 14)
		local detail = label(row, string.format("range %.2f–%.2f · density %.2f · allows %s",
			zone.Min or 0, zone.Max or 1, zone.Density or 1, table.concat(zone.Allow, ", ")), 10, COLORS.dim)
		detail.Position = UDim2.new(0, 0, 0, 15)
		detail.Size = UDim2.new(1, -30, 0, 20)
		detail.TextWrapped = true

		local remove = Instance.new("TextButton")
		remove.Text = "✕"
		remove.TextSize = 12
		remove.Font = Enum.Font.GothamBold
		remove.TextColor3 = COLORS.dim
		remove.BackgroundColor3 = COLORS.bg
		remove.Size = UDim2.new(0, 24, 0, 20)
		remove.Position = UDim2.new(1, -24, 0, 0)
		remove.Parent = row
		corner(remove, 4)
		remove.Activated:Connect(function()
			WorldForge.RemoveZone(zone.Name)
			if state.refresh then state.refresh() end
		end)
	end

	header(parent, "ADD ZONE")
	local nameBox = textbox(parent, "zone name")
	local ruleBox = textbox(parent, "rule: everywhere / altitude / slope / patch / nearWater", "altitude")
	local minBox = textbox(parent, "min (altitude 0-1, slope degrees)", "0")
	local maxBox = textbox(parent, "max", "1")
	local allowBox = textbox(parent, "allow: * or kind:Tree or asset ids, comma separated", "*")
	local densityBox = textbox(parent, "density multiplier", "1")

	button(parent, "Add Zone", COLORS.accent, function()
		if nameBox.Text == "" then setStatus("zone needs a name", COLORS.warn) return end
		WorldForge.AddZone(nameBox.Text, ruleBox.Text,
			tonumber(minBox.Text), tonumber(maxBox.Text),
			string.split(allowBox.Text, ","), tonumber(densityBox.Text) or 1)
		setStatus("zone added: " .. nameBox.Text, COLORS.good)
		if state.refresh then state.refresh() end
	end)

	buildParameterSection(parent, "Zones")
end

local function sectionScatter(parent: Instance)
	header(parent, "SCATTER SEED")
	seedRow(parent, "scatter", "Scatter")
	header(parent, "PLACEMENT")
	buildParameterSection(parent, "Scatter")
	header(parent, "ACTIONS")
	button(parent, "Scatter Objects", COLORS.accent, function()
		if WorldForge.Library.Count() == 0 then
			setStatus("library is empty — import assets first", COLORS.warn)
			return
		end
		setStatus("scattering…", COLORS.warn)
		local report = WorldForge.Build("scatter")
		setStatus(string.format("placed %d objects in %.1fs",
			report.Scatter.Built, report.Seconds), COLORS.good)
	end)
	button(parent, "Clear Objects", COLORS.row, function()
		WorldForge.Build("scatter")
		setStatus("rescattered")
	end)
end

local function sectionStructures(parent: Instance)
	header(parent, "STRUCTURE SEED")
	seedRow(parent, "structures", "Structures")
	header(parent, "ASSEMBLY")
	buildParameterSection(parent, "Structures")
	header(parent, "KIT")
	label(parent, "Tag library assets wall / door / corner / floor / pillar / rubble,", 10, COLORS.dim)
	label(parent, "then list their names here.", 10, COLORS.dim)
	local kitBox = textbox(parent, "wall,doorway,corner_post,floor_slab",
		table.concat(WorldForge.Active().StructureKit, ","))
	button(parent, "Set Kit", COLORS.row, function()
		local ids = if kitBox.Text == "" then {} else string.split(kitBox.Text, ",")
		WorldForge.SetStructureKit(ids)
		setStatus(#ids .. " kit pieces set", COLORS.good)
	end)
	header(parent, "ACTIONS")
	button(parent, "Build Structures", COLORS.accent, function()
		setStatus("building structures…", COLORS.warn)
		local report = WorldForge.Build("structures")
		if report.Structures.Error then
			setStatus(report.Structures.Error, COLORS.warn)
		else
			setStatus(string.format("%d pieces across %d sites",
				report.Structures.Built, report.Structures.Sites or 0), COLORS.good)
		end
	end)
end

local function sectionSurface(parent: Instance)
	header(parent, "MATERIALS & LIGHT")
	buildParameterSection(parent, "Surface")
	header(parent, "ACTIONS")
	button(parent, "Apply Lighting", COLORS.accent, function()
		WorldForge.Build("lighting")
		setStatus("lighting applied", COLORS.good)
	end)
	button(parent, "Repaint Surface", COLORS.row, function()
		setStatus("repainting…", COLORS.warn)
		local report = WorldForge.Build("surface")
		setStatus(string.format("surface repainted in %.1fs", report.Seconds), COLORS.good)
	end)
end

local function sectionSave(parent: Instance)
	header(parent, "CURRENT WORLD")
	local status = WorldForge.Status()
	label(parent, "recipe: " .. status.Recipe, 12, COLORS.text, true)
	label(parent, "hash: " .. status.Hash, 10, COLORS.dim)

	local nameBox = textbox(parent, "world name", status.Recipe)
	button(parent, "Save World", COLORS.accent, function()
		local report = WorldForge.Save(nameBox.Text)
		setStatus("saved " .. report.Saved .. "  ·  " .. report.Hash, COLORS.good)
		if state.refresh then state.refresh() end
	end)

	header(parent, "BUILD")
	button(parent, "Build Everything", COLORS.accent, function()
		setStatus("building whole world…", COLORS.warn)
		local report = WorldForge.Build()
		setStatus(string.format("world built in %.1fs  ·  %d objects  ·  %d structure pieces",
			report.Seconds, report.Scatter and report.Scatter.Built or 0,
			report.Structures and report.Structures.Built or 0), COLORS.good)
	end)
	button(parent, "Clear World", COLORS.row, function()
		WorldForge.Clear()
		setStatus("world cleared")
	end)
	button(parent, "Release to WorldEngine", COLORS.row, function()
		local report = WorldForge.ReleaseToWorldEngine()
		setStatus(if report.Restored
			then "WorldForge cleared — legacy WorldEngine world restored"
			else "WorldForge cleared — no legacy world was parked", COLORS.good)
	end)

	header(parent, "SAVED WORLDS")
	local saved = WorldForge.SavedWorlds()
	if #saved == 0 then
		label(parent, "none saved yet", 11, COLORS.dim)
	end
	for _, entry in saved do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = COLORS.row
		row.Size = UDim2.new(1, 0, 0, 34)
		row.Parent = parent
		corner(row)
		padding(row, 8)
		local title = label(row, entry.Name, 12, COLORS.text, true)
		title.Size = UDim2.new(1, -110, 0, 14)
		local detail = label(row, entry.Hash or "", 10, COLORS.dim)
		detail.Position = UDim2.new(0, 0, 0, 14)
		detail.Size = UDim2.new(1, -110, 0, 10)

		local load = Instance.new("TextButton")
		load.Text = "load"
		load.TextSize = 11
		load.Font = Enum.Font.GothamMedium
		load.TextColor3 = Color3.fromRGB(20, 14, 8)
		load.BackgroundColor3 = COLORS.good
		load.Size = UDim2.new(0, 44, 0, 22)
		load.Position = UDim2.new(1, -102, 0, 0)
		load.Parent = row
		corner(load, 4)
		load.Activated:Connect(function()
			WorldForge.Load(entry.Name)
			setStatus("loaded " .. entry.Name .. " — press Build Everything", COLORS.good)
			if state.refresh then state.refresh() end
		end)

		local remove = Instance.new("TextButton")
		remove.Text = "delete"
		remove.TextSize = 11
		remove.Font = Enum.Font.GothamMedium
		remove.TextColor3 = COLORS.dim
		remove.BackgroundColor3 = COLORS.bg
		remove.Size = UDim2.new(0, 52, 0, 22)
		remove.Position = UDim2.new(1, -52, 0, 0)
		remove.Parent = row
		corner(remove, 4)
		remove.Activated:Connect(function()
			WorldForge.Delete(entry.Name)
			if state.refresh then state.refresh() end
		end)
	end
end

local BUILDERS = {
	Terrain = sectionTerrain,
	Library = sectionLibrary,
	Zones = sectionZones,
	Scatter = sectionScatter,
	Structures = sectionStructures,
	Surface = sectionSurface,
	Save = sectionSave,
}

-- panel -----------------------------------------------------------------------

function Panel.Close()
	local existing = CoreGui:FindFirstChild(GUI_NAME)
	if existing then existing:Destroy() end
	state.gui = nil
end

function Panel.Open()
	Panel.Close()

	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = CoreGui
	state.gui = gui

	-- Default to a sensible fraction of the viewport rather than a fixed pixel
	-- height: on small or scaled displays a hardcoded 620px window ended up
	-- taller than the screen, which looked like "the panel is empty".
	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
		or Vector2.new(1280, 720)
	local startWidth = math.clamp(360, 300, math.max(320, viewport.X - 40))
	-- leave room below the window so the resize grip is always reachable
	local startHeight = math.clamp(viewport.Y - 200, 320, 900)

	local window = Instance.new("Frame")
	window.BackgroundColor3 = COLORS.bg
	window.Size = UDim2.fromOffset(startWidth, startHeight)
	window.Position = UDim2.new(0, 20, 0, 90)
	window.Active = true
	window.Draggable = true
	window.Parent = gui
	corner(window, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.edge
	stroke.Parent = window

	-- title bar
	local title = Instance.new("Frame")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Parent = window
	local titleText = label(title, "  WorldForge", 16, COLORS.text, true)
	titleText.Size = UDim2.new(1, -40, 1, 0)

	local close = Instance.new("TextButton")
	close.Text = "✕"
	close.TextSize = 14
	close.Font = Enum.Font.GothamBold
	close.TextColor3 = COLORS.dim
	close.BackgroundTransparency = 1
	close.Size = UDim2.new(0, 32, 0, 32)
	close.Position = UDim2.new(1, -36, 0, 4)
	close.Parent = title
	close.Activated:Connect(Panel.Close)

	-- section tabs
	local tabs = Instance.new("ScrollingFrame")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, -16, 0, 30)
	tabs.Position = UDim2.new(0, 8, 0, 38)
	tabs.ScrollBarThickness = 0
	tabs.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.Parent = window
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 4)
	tabLayout.Parent = tabs

	-- body
	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, -16, 1, -112)   -- scales with the window
	body.Position = UDim2.new(0, 8, 0, 72)
	body.ScrollBarThickness = 4
	body.ScrollBarImageColor3 = COLORS.edge
	body.CanvasSize = UDim2.new(0, 0, 0, 0)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.Parent = window
	state.body = body
	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.Padding = UDim.new(0, 6)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = body

	-- status bar
	local statusBar = Instance.new("Frame")
	statusBar.BackgroundColor3 = COLORS.panel
	statusBar.Size = UDim2.new(1, -16, 0, 28)
	statusBar.Position = UDim2.new(0, 8, 1, -34)
	statusBar.Parent = window
	corner(statusBar)
	local statusText = label(statusBar, "", 10, COLORS.dim)
	statusText.Size = UDim2.new(1, -16, 1, 0)
	statusText.Position = UDim2.new(0, 8, 0, 0)
	statusText.TextTruncate = Enum.TextTruncate.AtEnd
	state.status = statusText

	-- Resize grip. Without this the window was a fixed size with no way to
	-- enlarge it, so any section taller than the default was unreachable.
	local grip = Instance.new("TextButton")
	grip.Name = "ResizeGrip"
	grip.Text = "◢"
	grip.TextSize = 16
	grip.Font = Enum.Font.GothamBold
	grip.TextColor3 = COLORS.dim
	grip.BackgroundColor3 = COLORS.panel
	grip.BackgroundTransparency = 0.25
	grip.Size = UDim2.fromOffset(28, 28)        -- comfortable target
	grip.Position = UDim2.new(1, -28, 1, -28)
	grip.AutoButtonColor = true
	grip.ZIndex = 5
	grip.Parent = window
	corner(grip, 6)

	local resizing = false
	local resizeStart, sizeStart
	grip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = true
			resizeStart = input.Position
			sizeStart = window.AbsoluteSize
			window.Draggable = false          -- don't drag and resize at once
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - resizeStart
			window.Size = UDim2.fromOffset(
				math.clamp(sizeStart.X + delta.X, 300, 900),
				math.clamp(sizeStart.Y + delta.Y, 260, 1400))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and resizing then
			resizing = false
			window.Draggable = true
		end
	end)

	local tabButtons = {}

	local function render()
		for _, child in body:GetChildren() do
			if not child:IsA("UIListLayout") then child:Destroy() end
		end
		local builder = BUILDERS[state.section]
		if builder then
			-- A section that throws used to leave the panel silently blank.
			-- Now the failure is shown in place and reported in the status bar.
			local ok, err = pcall(builder, body)
			if not ok then
				local box = Instance.new("Frame")
				box.BackgroundColor3 = COLORS.row
				box.Size = UDim2.new(1, 0, 0, 92)
				box.Parent = body
				corner(box)
				padding(box, 8)
				local title = label(box, "This section failed to draw", 12, COLORS.warn, true)
				title.Size = UDim2.new(1, 0, 0, 16)
				local detail = label(box, tostring(err), 10, COLORS.dim)
				detail.Position = UDim2.new(0, 0, 0, 18)
				detail.Size = UDim2.new(1, 0, 0, 60)
				detail.TextWrapped = true
				detail.TextYAlignment = Enum.TextYAlignment.Top
				setStatus("error in " .. state.section .. ": " .. tostring(err), COLORS.warn)
			end
		end
		for id, tabButton in tabButtons do
			local selected = id == state.section
			tabButton.BackgroundColor3 = if selected then COLORS.accent else COLORS.panel
			tabButton.TextColor3 = if selected then Color3.fromRGB(20, 14, 8) else COLORS.dim
		end
		if state.status and state.status.TextColor3 ~= COLORS.warn then
			setStatus(statusLine())
		end
	end
	state.refresh = render

	for _, section in SECTIONS do
		local tabButton = Instance.new("TextButton")
		tabButton.Text = section.Label
		tabButton.TextSize = 11
		tabButton.Font = Enum.Font.GothamMedium
		tabButton.BackgroundColor3 = COLORS.panel
		tabButton.TextColor3 = COLORS.dim
		tabButton.Size = UDim2.new(0, 96, 1, 0)
		tabButton.Parent = tabs
		corner(tabButton, 5)
		tabButtons[section.Id] = tabButton
		tabButton.Activated:Connect(function()
			state.section = section.Id
			render()
		end)
	end

	render()
	return "WorldForge panel open"
end

return table.freeze(Panel)
