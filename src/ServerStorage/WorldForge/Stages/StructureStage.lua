--!strict

-- WorldForge Stage 5: Structures.
--
-- Socket-grammar assembly from YOUR kit. You nominate library assets as kit
-- pieces by role; the engine lays out footprints, walks the perimeter sockets,
-- degrades them by the degradation control, and guarantees an entrance.
--
-- Roles are resolved from asset tags, so tagging an asset "wall" makes it a
-- wall. Nothing about the kit's style is known to the engine.
--
--   wall      perimeter segment
--   door      entrance segment (falls back to omitting a wall)
--   corner    corner post
--   floor     interior slab
--   pillar    interior column
--   rubble    scattered debris where a wall collapsed

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Checksum = require(WorldEngine.Core.Checksum)
local Hash32 = require(WorldEngine.Core.Hash32)

local WorldForge = script.Parent.Parent
local Library = require(WorldForge.Core.AssetLibrary)
local Recipe = require(WorldForge.Core.Recipe)
local TerrainStage = require(WorldForge.Stages.TerrainStage)

local Stage = {}

local CHANNEL = 0x53545255 -- "STRU"
local TAG = "WorldForgeStructure"

local function unit(seed: number, a: number, b: number, c: number): number
	return (Hash32.ToSignedUnit(Hash32.HashIntegers(seed, a, b, c, CHANNEL)) + 1) * 0.5
end

-- Buckets kit assets by role, using tags first and falling back to any
-- structure-kind asset so a single-piece kit still works.
local function resolveKit(recipe: Recipe.Data)
	local roles = {wall = {}, door = {}, corner = {}, floor = {}, pillar = {}, rubble = {}}
	local ids = recipe.StructureKit
	if #ids == 0 then
		for _, entry in Library.List("Structure") do
			table.insert(ids, entry.Id)
		end
	end
	for _, assetId in ids do
		local asset = Library.Get(assetId)
		if asset then
			local tags = string.split(asset:GetAttribute("Tags") or "", ",")
			local matched = false
			for _, tag in tags do
				local role = string.lower(string.gsub(tag, "%s", ""))
				if roles[role] then
					table.insert(roles[role], assetId)
					matched = true
				end
			end
			if not matched then
				table.insert(roles.wall, assetId)
			end
		end
	end
	return roles
end

local function pick(list: {string}, seed: number, a: number, b: number): string?
	if #list == 0 then return nil end
	local index = math.floor(unit(seed, a, b, 21) * #list) + 1
	return list[math.min(index, #list)]
end

function Stage.Plan(recipe: Recipe.Data)
	local p = Recipe.Resolve(recipe)
	if not p["structures.enabled"] then
		return {Pieces = {}, Sites = {}, Signature = "disabled"}
	end

	local seed = Recipe.GetSeed(recipe, "structures")
	local field = TerrainStage.BuildField(recipe)
	local roles = resolveKit(recipe)
	if #roles.wall == 0 and #roles.door == 0 then
		return {Pieces = {}, Sites = {}, Signature = "nokit", Error = "No structure kit assets. Tag library assets wall/door/corner/floor/pillar/rubble and add them to the kit."}
	end

	local siteCount = p["structures.sites"]
	local cellsX = p["structures.cellsX"]
	local cellsZ = p["structures.cellsZ"]
	local cell = p["structures.cellSize"]
	local degradation = p["structures.degradation"]
	local floorCoverage = p["structures.floorCoverage"]
	local guaranteeEntrance = p["structures.guaranteeEntrance"]
	local maxSlope = p["structures.maxSlope"]

	local halfX = cellsX * cell / 2
	local halfZ = cellsZ * cell / 2
	local margin = math.max(halfX, halfZ) + 20
	local limit = field.Size / 2 - margin

	local function siteSlope(cx: number, cz: number): (number, number)
		local minH, maxH = math.huge, -math.huge
		for gx = -1, 1 do
			for gz = -1, 1 do
				local h = field.HeightAt(cx + gx * halfX, cz + gz * halfZ)
				minH = math.min(minH, h)
				maxH = math.max(maxH, h)
			end
		end
		return math.deg(math.atan((maxH - minH) / (math.max(halfX, halfZ) * 2))), minH
	end

	local pieces = {}
	local sites = {}

	for siteIndex = 1, siteCount do
		-- deterministic search for a flat enough spot
		local cx, cz, anchorY
		for attempt = 1, 40 do
			local tx = (unit(seed, siteIndex, attempt, 1) * 2 - 1) * limit
			local tz = (unit(seed, siteIndex, attempt, 2) * 2 - 1) * limit
			local slope, lowest = siteSlope(tx, tz)
			if slope <= maxSlope then
				cx, cz, anchorY = tx, tz, lowest
				break
			end
		end
		if cx then
			local doorways = 0
			local socketIndex = 0
			local function add(assetId: string?, x: number, z: number, yaw: number, role: string)
				if not assetId then return end
				table.insert(pieces, {
					Index = #pieces + 1, AssetId = assetId, Site = siteIndex,
					X = x, Y = anchorY, Z = z, Yaw = yaw, Role = role,
				})
			end

			local edges = {
				{dz = -halfZ, yaw = 0, count = cellsX, axis = "X"},
				{dz = halfZ, yaw = 0, count = cellsX, axis = "X"},
				{dx = -halfX, yaw = math.pi / 2, count = cellsZ, axis = "Z"},
				{dx = halfX, yaw = math.pi / 2, count = cellsZ, axis = "Z"},
			}
			for edgeIndex, edge in edges do
				local doorSlot = math.floor(edge.count / 2) + 1
				for i = 1, edge.count do
					socketIndex += 1
					local along = (i - 0.5 - edge.count / 2) * cell
					local x = cx + (if edge.axis == "X" then along else (edge.dx or 0))
					local z = cz + (if edge.axis == "Z" then along else (edge.dz or 0))
					local isDoor = guaranteeEntrance and edgeIndex == 1 and i == doorSlot
					if isDoor and #roles.door > 0 then
						add(pick(roles.door, seed, siteIndex, socketIndex), x, z, edge.yaw, "door")
						doorways += 1
					elseif isDoor then
						doorways += 1 -- gap serves as the entrance
					else
						local roll = unit(seed, siteIndex, socketIndex, 3)
						if roll < degradation * 0.45 then
							-- collapsed: leave a gap, drop rubble nearby
							if #roles.rubble > 0 then
								local angle = unit(seed, siteIndex, socketIndex, 4) * math.pi * 2
								local distance = 1.5 + unit(seed, siteIndex, socketIndex, 5) * 2.5
								add(pick(roles.rubble, seed, siteIndex, socketIndex),
									x + math.cos(angle) * distance, z + math.sin(angle) * distance,
									unit(seed, siteIndex, socketIndex, 6) * math.pi * 2, "rubble")
							end
						else
							add(pick(roles.wall, seed, siteIndex, socketIndex), x, z, edge.yaw, "wall")
						end
					end
				end
			end

			if #roles.corner > 0 then
				for cornerIndex, corner in {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}} do
					socketIndex += 1
					if unit(seed, siteIndex, socketIndex, 7) > degradation * 0.5 then
						add(pick(roles.corner, seed, siteIndex, socketIndex),
							cx + corner[1] * halfX, cz + corner[2] * halfZ, 0, "corner")
					end
				end
			end

			if #roles.floor > 0 then
				for gx = 1, cellsX do
					for gz = 1, cellsZ do
						socketIndex += 1
						if unit(seed, siteIndex, socketIndex, 8) < floorCoverage then
							add(pick(roles.floor, seed, siteIndex, socketIndex),
								cx + (gx - 0.5 - cellsX / 2) * cell,
								cz + (gz - 0.5 - cellsZ / 2) * cell,
								math.floor(unit(seed, siteIndex, socketIndex, 9) * 4) * math.pi / 2,
								"floor")
						end
					end
				end
			end

			if #roles.pillar > 0 then
				for i = 1, cellsX - 1 do
					socketIndex += 1
					if unit(seed, siteIndex, socketIndex, 10) > degradation * 0.6 then
						add(pick(roles.pillar, seed, siteIndex, socketIndex),
							cx + (i - cellsX / 2) * cell, cz - halfZ + cell, 0, "pillar")
					end
				end
			end

			table.insert(sites, {
				Index = siteIndex, X = cx, Z = cz, Y = anchorY,
				Doorways = doorways, Pieces = #pieces,
			})
		end
	end

	local state = Checksum.New()
	Checksum.UpdateString(state, "worldforge-structures-v1")
	Checksum.UpdateUInt32(state, seed)
	Checksum.UpdateUInt32(state, #pieces)
	for index, piece in pieces do
		Checksum.UpdateIndexedUInt32(state, index, math.floor(piece.X * 512 + 0.5) % 4294967296)
		Checksum.UpdateString(state, piece.AssetId .. piece.Role)
		Checksum.UpdateUInt32(state, math.floor(piece.Z * 512 + 0.5) % 4294967296)
	end

	return {Pieces = pieces, Sites = sites, Signature = Checksum.Digest(state)}
end

function Stage.Clear()
	local root = TerrainStage.WorldRoot()
	local existing = root:FindFirstChild("Structures")
	if existing then existing:Destroy() end
end

function Stage.Materialize(recipe: Recipe.Data, plan)
	local started = os.clock()
	plan = plan or Stage.Plan(recipe)
	Stage.Clear()
	if #plan.Pieces == 0 then
		return {Built = 0, Error = plan.Error, Signature = plan.Signature}
	end

	local root = TerrainStage.WorldRoot()
	local folder = Instance.new("Folder")
	folder.Name = "Structures"
	folder.Parent = root

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {Workspace.Terrain}

	local siteFolders = {}
	for _, site in plan.Sites do
		local siteFolder = Instance.new("Folder")
		siteFolder.Name = "Site" .. site.Index
		siteFolder:SetAttribute("Doorways", site.Doorways)
		siteFolder.Parent = folder
		siteFolders[site.Index] = siteFolder
	end

	local built = 0
	for _, piece in plan.Pieces do
		local template = Library.Get(piece.AssetId)
		if template then
			local model = template:Clone()
			model.Name = string.format("%03d_%s", piece.Index, piece.Role)
			model:SetAttribute("PieceIndex", piece.Index)
			model:SetAttribute("Role", piece.Role)
			model.LevelOfDetail = Enum.ModelLevelOfDetail.Automatic
			model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			local lods = model:FindFirstChild("LODVariants")
			if lods then lods:Destroy() end

			local hit = Workspace:Raycast(
				Vector3.new(piece.X, piece.Y + 96, piece.Z),
				Vector3.new(0, -256, 0), params)
			local groundY = if hit then hit.Position.Y else piece.Y
			local sink = template:GetAttribute("Sink") or 0.3

			model:PivotTo(CFrame.new(piece.X, groundY - sink, piece.Z)
				* CFrame.Angles(0, piece.Yaw, 0))

			for _, descendant in model:GetDescendants() do
				if descendant:IsA("MeshPart") then
					descendant.Anchored = true
					descendant.CanTouch = false
					descendant.RenderFidelity = Enum.RenderFidelity.Automatic
				end
			end
			CollectionService:AddTag(model, TAG)
			model.Parent = siteFolders[piece.Site] or folder
			built += 1
			if built % 100 == 0 then task.wait() end
		end
	end

	root:SetAttribute("StructureSignature", plan.Signature)
	root:SetAttribute("StructureCount", built)

	return {
		Built = built,
		Sites = #plan.Sites,
		Signature = plan.Signature,
		Seconds = os.clock() - started,
	}
end

return table.freeze(Stage)
