--!strict

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Config = require(WorldEngine.Config.Ruins.DesertRuins)
local RuinPlanner = require(WorldEngine.Planning.RuinPlanner)

type Plan = RuinPlanner.Plan

local RUIN_TAG = "WorldEngineRuinPiece"

local Materializer = {}

-- Planned heights come from the heightfield; the baked voxel surface sits a
-- few studs higher after occupancy smoothing (same effect fixed for props in
-- M2). Each piece snaps to the golden-verified baked terrain at materialization
-- so walls follow the settled ground instead of floating or burying.
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = {Workspace.Terrain}

local function snappedGroundY(worldX: number, plannedY: number, worldZ: number): number
	local hit = Workspace:Raycast(
		Vector3.new(worldX, plannedY + 64, worldZ),
		Vector3.new(0, -128, 0),
		terrainParams
	)
	if hit then
		return hit.Position.Y
	end
	return plannedY
end

local function template(pieceId: string): Model
	local templates = WorldEngine.Assets.Ruins:WaitForChild("Templates")
	local tpl = templates:FindFirstChild(pieceId)
	assert(tpl and tpl:IsA("Model"), "Missing ruin template: " .. pieceId)
	assert(tpl:FindFirstChild("Render"), "Ruin template missing Render: " .. pieceId)
	assert(tpl:FindFirstChild("Collision"), "Ruin template missing Collision: " .. pieceId)
	return tpl
end

function Materializer.Clear()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local existing = generated:FindFirstChild("Ruins")
	if existing then
		existing:Destroy()
	end
end

function Materializer.Materialize(plan: Plan): Folder
	Materializer.Clear()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local folder = Instance.new("Folder")
	folder.Name = "Ruins"
	folder.Parent = generated

	local siteFolders: {[string]: Folder} = {}
	for _, site in plan.Sites do
		local siteFolder = Instance.new("Folder")
		siteFolder.Name = site.Id
		siteFolder:SetAttribute("CenterX", site.CenterX)
		siteFolder:SetAttribute("CenterZ", site.CenterZ)
		siteFolder:SetAttribute("AnchorY", site.AnchorY)
		siteFolder:SetAttribute("DoorwayCount", site.DoorwayCount)
		siteFolder.Parent = folder
		siteFolders[site.Id] = siteFolder
	end

	for _, piece in plan.Pieces do
		local model = template(piece.PieceId):Clone()
		model.Name = string.format("%03d_%s", piece.Index, piece.PieceId)
		model.LevelOfDetail = Enum.ModelLevelOfDetail.Automatic
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		model:SetAttribute("PieceIndex", piece.Index)
		model:SetAttribute("PieceId", piece.PieceId)
		model:SetAttribute("SiteId", piece.SiteId)
		model:SetAttribute("Socket", piece.Socket)
		model:SetAttribute("RuinVersion", Config.Version)
		local groundY = snappedGroundY(piece.WorldX, piece.WorldY, piece.WorldZ)
		model:PivotTo(CFrame.new(piece.WorldX, groundY - Config.SinkStuds, piece.WorldZ)
			* CFrame.Angles(0, piece.YawRadians, 0))
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("MeshPart") then
				descendant.Anchored = true
				descendant.CanTouch = false
				descendant.RenderFidelity = Enum.RenderFidelity.Automatic
			end
		end
		CollectionService:AddTag(model, RUIN_TAG)
		model.Parent = siteFolders[piece.SiteId] or folder
	end

	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("RuinVersion", Config.Version)
	root:SetAttribute("RuinPlanSignature", plan.Signature)
	root:SetAttribute("RuinPieceCount", #plan.Pieces)
	return folder
end

return table.freeze(Materializer)
