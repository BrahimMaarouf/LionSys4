--!strict

-- WorldForge Asset Library.
--
-- You supply the assets. This module imports them into the active experience,
-- organises them, validates them, and hands the placement stages a clean,
-- uniform template for every one — regardless of where the mesh came from.
--
-- On import each asset becomes a template Model under:
--
--   ServerStorage.WorldForge.Library.<Kind>.<AssetId>
--       Render      MeshPart   visible geometry (+ SurfaceAppearance if textured)
--       Collision   MeshPart   invisible collider (falls back to Render's mesh)
--       LODVariants Folder     optional LOD1 / LOD2 meshes
--
-- The engine NEVER authors geometry or textures. It only wraps what you give
-- it in a predictable shape, records the placement rules you set, and reuses
-- that template. Metadata lives on the template as attributes, so the library
-- survives place saves with no external file.

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local Library = {}

Library.Kinds = {"Rock", "Tree", "Bush", "Plant", "Prop", "Debris", "Structure"}

export type AssetSpec = {
	Id: string,            -- unique name you choose, e.g. "pine_a"
	Kind: string,          -- one of Library.Kinds
	MeshId: string,        -- rbxassetid:// of the mesh (required)
	CollisionMeshId: string?,
	Lod1MeshId: string?,
	Lod2MeshId: string?,
	ColorMap: string?,
	NormalMap: string?,
	RoughnessMap: string?,
	AlphaMode: string?,    -- "Overlay" (default) or "Transparency" for cutout foliage
	Color: {number}?,      -- optional {r,g,b} 0-255 tint when no texture supplied
	Material: string?,     -- optional Enum.Material name when no texture supplied
	Spacing: number?,      -- minimum distance to the next object (studs)
	Scale: number?,        -- base scale multiplier
	MaxSlope: number?,     -- reject placement on ground steeper than this (deg)
	Sink: number?,         -- push this far into the ground (studs)
	Weight: number?,       -- relative likelihood vs other assets of same kind
	Wind: boolean?,        -- gentle sway (foliage)
	CastShadow: boolean?,
	Tags: {string}?,
}

local ATTRIBUTE_KEYS = {
	"Kind", "MeshId", "CollisionMeshId", "Lod1MeshId", "Lod2MeshId",
	"ColorMap", "NormalMap", "RoughnessMap", "AlphaMode",
	"Spacing", "Scale", "MaxSlope", "Sink", "Weight", "Wind", "CastShadow", "Tags",
}

local function root(): Folder
	local forge = ServerStorage:FindFirstChild("WorldForge")
	if not forge then
		forge = Instance.new("Folder")
		forge.Name = "WorldForge"
		forge.Parent = ServerStorage
	end
	local library = forge:FindFirstChild("Library")
	if not library then
		library = Instance.new("Folder")
		library.Name = "Library"
		library.Parent = forge
	end
	return library :: Folder
end

local function kindFolder(kind: string): Folder
	local libraryRoot = root()
	local folder = libraryRoot:FindFirstChild(kind)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = kind
		folder.Parent = libraryRoot
	end
	return folder :: Folder
end

local function normalizeAssetId(value: string?): string?
	if value == nil or value == "" then
		return nil
	end
	local text = tostring(value)
	local digits = string.match(text, "(%d+)")
	if not digits then
		return nil
	end
	return "rbxassetid://" .. digits
end

local function buildMeshPart(meshId: string, fidelity: Enum.CollisionFidelity): MeshPart
	return AssetService:CreateMeshPartAsync(Content.fromUri(meshId), {
		CollisionFidelity = fidelity,
		RenderFidelity = Enum.RenderFidelity.Automatic,
	})
end

-- Bottom-aligns a part at the model origin so every library asset shares the
-- same convention: pivot at the base, standing on y = 0.
local function groundAlign(part: BasePart)
	part.CFrame = CFrame.new(0, part.Size.Y / 2, 0)
end

--[[
	Imports one asset. Safe to call repeatedly — re-importing replaces the
	existing template with the new definition.
	Returns (template, report). Throws only on an unusable mesh id.
]]
function Library.Import(spec: AssetSpec): (Model, {[string]: any})
	assert(type(spec) == "table", "AssetSpec table required")
	assert(type(spec.Id) == "string" and spec.Id ~= "", "asset Id required")

	local kind = spec.Kind or "Prop"
	local validKind = false
	for _, candidate in Library.Kinds do
		if candidate == kind then validKind = true break end
	end
	assert(validKind, "unknown asset kind: " .. tostring(kind))

	local meshId = normalizeAssetId(spec.MeshId)
	assert(meshId, "MeshId is required and must contain an asset id")

	local warnings = {}
	local collisionId = normalizeAssetId(spec.CollisionMeshId) or meshId
	local lod1 = normalizeAssetId(spec.Lod1MeshId)
	local lod2 = normalizeAssetId(spec.Lod2MeshId)
	local colorMap = normalizeAssetId(spec.ColorMap)
	local normalMap = normalizeAssetId(spec.NormalMap)
	local roughnessMap = normalizeAssetId(spec.RoughnessMap)

	local template = Instance.new("Model")
	template.Name = spec.Id

	-- Render mesh
	local okRender, render = pcall(buildMeshPart, meshId, Enum.CollisionFidelity.Box)
	if not okRender then
		error("could not load mesh " .. meshId .. " (" .. tostring(render) .. ")")
	end
	local renderPart = render :: MeshPart
	renderPart.Name = "Render"
	renderPart.Anchored = true
	renderPart.CanCollide = false
	renderPart.CanQuery = false
	renderPart.CanTouch = false
	renderPart.CastShadow = spec.CastShadow ~= false
	if spec.Color then
		renderPart.Color = Color3.fromRGB(spec.Color[1], spec.Color[2], spec.Color[3])
	end
	if spec.Material then
		local ok = pcall(function()
			renderPart.Material = (Enum.Material :: any)[spec.Material]
		end)
		if not ok then
			table.insert(warnings, "unknown material " .. tostring(spec.Material))
		end
	end
	if colorMap then
		local appearance = Instance.new("SurfaceAppearance")
		appearance.ColorMap = colorMap
		if normalMap then appearance.NormalMap = normalMap end
		if roughnessMap then appearance.RoughnessMap = roughnessMap end
		appearance.AlphaMode = if spec.AlphaMode == "Transparency"
			then Enum.AlphaMode.Transparency
			else Enum.AlphaMode.Overlay
		appearance.Parent = renderPart
	elseif normalMap or roughnessMap then
		table.insert(warnings, "normal/roughness maps ignored without a ColorMap")
	end
	groundAlign(renderPart)
	renderPart.Parent = template

	-- Collision proxy
	local okCollision, collision = pcall(buildMeshPart, collisionId, Enum.CollisionFidelity.Default)
	if okCollision then
		local collisionPart = collision :: MeshPart
		collisionPart.Name = "Collision"
		collisionPart.Anchored = true
		collisionPart.Transparency = 1
		collisionPart.CanCollide = true
		collisionPart.CanQuery = true
		collisionPart.CanTouch = false
		collisionPart.CastShadow = false
		groundAlign(collisionPart)
		collisionPart.Parent = template
	else
		table.insert(warnings, "collision mesh failed to load; using render mesh box")
		local fallback = renderPart:Clone()
		for _, child in fallback:GetChildren() do child:Destroy() end
		fallback.Name = "Collision"
		fallback.Transparency = 1
		fallback.CanCollide = true
		fallback.CanQuery = true
		fallback.CastShadow = false
		fallback.Parent = template
	end

	-- Optional LODs
	if lod1 or lod2 then
		local lods = Instance.new("Folder")
		lods.Name = "LODVariants"
		for name, id in {LOD1 = lod1, LOD2 = lod2} do
			if id then
				local ok, part = pcall(buildMeshPart, id, Enum.CollisionFidelity.Box)
				if ok then
					local lodPart = part :: MeshPart
					lodPart.Name = name
					lodPart.Anchored = true
					lodPart.Transparency = 1
					lodPart.CanCollide = false
					lodPart.CanQuery = false
					lodPart.CastShadow = false
					if colorMap then
						local appearance = Instance.new("SurfaceAppearance")
						appearance.ColorMap = colorMap
						if normalMap then appearance.NormalMap = normalMap end
						if roughnessMap then appearance.RoughnessMap = roughnessMap end
						appearance.AlphaMode = if spec.AlphaMode == "Transparency"
							then Enum.AlphaMode.Transparency
							else Enum.AlphaMode.Overlay
						appearance.Parent = lodPart
					end
					groundAlign(lodPart)
					lodPart.Parent = lods
				else
					table.insert(warnings, name .. " mesh failed to load")
				end
			end
		end
		if #lods:GetChildren() > 0 then
			lods.Parent = template
		else
			lods:Destroy()
		end
	end

	-- Derive sensible defaults from the mesh itself when not supplied
	local size = renderPart.Size
	local footprint = math.max(size.X, size.Z)
	local spacing = spec.Spacing or math.max(2, footprint * 0.9)

	template.PrimaryPart = renderPart
	template.WorldPivot = CFrame.new()
	template:SetAttribute("Kind", kind)
	template:SetAttribute("MeshId", meshId)
	template:SetAttribute("CollisionMeshId", collisionId)
	template:SetAttribute("Lod1MeshId", lod1 or "")
	template:SetAttribute("Lod2MeshId", lod2 or "")
	template:SetAttribute("ColorMap", colorMap or "")
	template:SetAttribute("NormalMap", normalMap or "")
	template:SetAttribute("RoughnessMap", roughnessMap or "")
	template:SetAttribute("AlphaMode", spec.AlphaMode or "Overlay")
	template:SetAttribute("Spacing", spacing)
	template:SetAttribute("Scale", spec.Scale or 1)
	template:SetAttribute("MaxSlope", spec.MaxSlope or 35)
	template:SetAttribute("Sink", spec.Sink or 0.3)
	template:SetAttribute("Weight", spec.Weight or 1)
	template:SetAttribute("Wind", spec.Wind == true)
	template:SetAttribute("CastShadow", spec.CastShadow ~= false)
	template:SetAttribute("Tags", spec.Tags and table.concat(spec.Tags, ",") or "")
	template:SetAttribute("FootprintX", size.X)
	template:SetAttribute("FootprintZ", size.Z)
	template:SetAttribute("Height", size.Y)
	template:SetAttribute("ImportedAt", os.time())

	local folder = kindFolder(kind)
	local existing = folder:FindFirstChild(spec.Id)
	if existing then
		existing:Destroy()
	end
	-- an asset may have changed kind: remove any stale copy elsewhere
	for _, otherKind in Library.Kinds do
		if otherKind ~= kind then
			local stale = root():FindFirstChild(otherKind)
			local staleAsset = stale and stale:FindFirstChild(spec.Id)
			if staleAsset then staleAsset:Destroy() end
		end
	end
	template.Parent = folder

	return template, {
		Id = spec.Id,
		Kind = kind,
		Size = string.format("%.1f x %.1f x %.1f", size.X, size.Y, size.Z),
		Spacing = spacing,
		HasCollision = template:FindFirstChild("Collision") ~= nil,
		HasTexture = colorMap ~= nil,
		LodCount = template:FindFirstChild("LODVariants")
			and #(template.LODVariants :: Folder):GetChildren() or 0,
		Warnings = warnings,
	}
end

-- Imports many assets, collecting per-asset failures instead of aborting.
function Library.ImportMany(specs: {AssetSpec})
	local imported, failed = {}, {}
	for _, spec in specs do
		local ok, result = pcall(Library.Import, spec)
		if ok then
			table.insert(imported, (select(2, Library.Import(spec))))
		else
			table.insert(failed, {Id = spec.Id, Error = tostring(result)})
		end
	end
	return {Imported = imported, Failed = failed}
end

function Library.Get(assetId: string): Model?
	for _, kind in Library.Kinds do
		local folder = root():FindFirstChild(kind)
		local asset = folder and folder:FindFirstChild(assetId)
		if asset and asset:IsA("Model") then
			return asset
		end
	end
	return nil
end

function Library.Remove(assetId: string): boolean
	local asset = Library.Get(assetId)
	if asset then
		asset:Destroy()
		return true
	end
	return false
end

function Library.Clear()
	for _, kind in Library.Kinds do
		local folder = root():FindFirstChild(kind)
		if folder then folder:Destroy() end
	end
end

-- Full listing with metadata — this is what the UI renders and what the
-- scatter stage reads.
function Library.List(kindFilter: string?)
	local entries = {}
	for _, kind in Library.Kinds do
		if kindFilter == nil or kindFilter == kind then
			local folder = root():FindFirstChild(kind)
			if folder then
				for _, asset in folder:GetChildren() do
					if asset:IsA("Model") then
						table.insert(entries, {
							Id = asset.Name,
							Kind = kind,
							Spacing = asset:GetAttribute("Spacing"),
							Scale = asset:GetAttribute("Scale"),
							MaxSlope = asset:GetAttribute("MaxSlope"),
							Sink = asset:GetAttribute("Sink"),
							Weight = asset:GetAttribute("Weight"),
							Wind = asset:GetAttribute("Wind"),
							Height = asset:GetAttribute("Height"),
							FootprintX = asset:GetAttribute("FootprintX"),
							FootprintZ = asset:GetAttribute("FootprintZ"),
							Tags = asset:GetAttribute("Tags"),
							MeshId = asset:GetAttribute("MeshId"),
						})
					end
				end
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.Kind ~= b.Kind then return a.Kind < b.Kind end
		return a.Id < b.Id
	end)
	return entries
end

function Library.Count(): number
	return #Library.List()
end

-- Updates placement rules on an already-imported asset without re-importing
-- the mesh (fast, and the UI uses it for slider edits).
function Library.SetRules(assetId: string, rules: {[string]: any}): boolean
	local asset = Library.Get(assetId)
	if not asset then
		return false
	end
	for key, value in rules do
		if table.find(ATTRIBUTE_KEYS, key) then
			asset:SetAttribute(key, value)
		end
	end
	return true
end

-- Serialises the whole library so it can be committed to the repo or moved to
-- another place. Import the result with Library.ImportMany.
function Library.Export(): string
	local specs = {}
	for _, entry in Library.List() do
		local asset = Library.Get(entry.Id) :: Model
		table.insert(specs, {
			Id = entry.Id,
			Kind = entry.Kind,
			MeshId = asset:GetAttribute("MeshId"),
			CollisionMeshId = asset:GetAttribute("CollisionMeshId"),
			Lod1MeshId = asset:GetAttribute("Lod1MeshId"),
			Lod2MeshId = asset:GetAttribute("Lod2MeshId"),
			ColorMap = asset:GetAttribute("ColorMap"),
			NormalMap = asset:GetAttribute("NormalMap"),
			RoughnessMap = asset:GetAttribute("RoughnessMap"),
			AlphaMode = asset:GetAttribute("AlphaMode"),
			Spacing = asset:GetAttribute("Spacing"),
			Scale = asset:GetAttribute("Scale"),
			MaxSlope = asset:GetAttribute("MaxSlope"),
			Sink = asset:GetAttribute("Sink"),
			Weight = asset:GetAttribute("Weight"),
			Wind = asset:GetAttribute("Wind"),
			CastShadow = asset:GetAttribute("CastShadow"),
			Tags = asset:GetAttribute("Tags"),
		})
	end
	return HttpService:JSONEncode({schema = 1, assets = specs})
end

function Library.ImportFromJson(json: string)
	local decoded = HttpService:JSONDecode(json)
	local specs = decoded.assets or decoded
	for _, spec in specs do
		if type(spec.Tags) == "string" and spec.Tags ~= "" then
			spec.Tags = string.split(spec.Tags, ",")
		else
			spec.Tags = nil
		end
	end
	return Library.ImportMany(specs)
end

-- Lays every library asset out on a labelled grid so you can eyeball the whole
-- kit at once. Purely a review aid; deleted by ClearPreview.
function Library.BuildPreview(origin: Vector3?)
	Library.ClearPreview()
	local Workspace = game:GetService("Workspace")
	local base = origin or Vector3.new(-900, 200, -900)
	local folder = Instance.new("Folder")
	folder.Name = "WorldForgeLibraryPreview"
	folder.Parent = Workspace

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.CanCollide = false
	floor.Color = Color3.fromRGB(140, 140, 145)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = folder

	local entries = Library.List()
	local columns = 6
	local pitch = 24
	local rows = math.max(1, math.ceil(#entries / columns))
	floor.Size = Vector3.new(columns * pitch + 20, 1, rows * pitch + 20)
	floor.Position = base + Vector3.new((columns - 1) * pitch / 2, -0.5, (rows - 1) * pitch / 2)

	for index, entry in entries do
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		local template = Library.Get(entry.Id)
		if template then
			local clone = template:Clone()
			clone:PivotTo(CFrame.new(base + Vector3.new(column * pitch, 0, row * pitch)))
			clone.Parent = folder

			local label = Instance.new("Part")
			label.Name = entry.Id .. "_Label"
			label.Anchored = true
			label.CanCollide = false
			label.Transparency = 1
			label.Size = Vector3.one
			label.Position = base + Vector3.new(column * pitch, (entry.Height or 6) + 4, row * pitch)
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromScale(12, 2)
			gui.AlwaysOnTop = true
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.TextScaled = true
			text.TextColor3 = Color3.new(1, 1, 1)
			text.TextStrokeTransparency = 0.3
			text.Text = entry.Kind .. " / " .. entry.Id
			text.Parent = gui
			gui.Parent = label
			label.Parent = folder
		end
	end
	return {Placed = #entries, Origin = base}
end

function Library.ClearPreview()
	local existing = game:GetService("Workspace"):FindFirstChild("WorldForgeLibraryPreview")
	if existing then
		existing:Destroy()
	end
end

return table.freeze(Library)
