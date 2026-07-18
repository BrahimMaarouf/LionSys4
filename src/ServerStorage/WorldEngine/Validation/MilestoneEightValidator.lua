--!strict

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Checksum = require(WorldEngine.Core.Checksum)
local Config = require(WorldEngine.Config.Ruins.DesertRuins)
local RuinAssetIds = require(WorldEngine.Assets.Ruins.RuinAssetIds)
local RuinPlanner = require(WorldEngine.Planning.RuinPlanner)
local WorldCompositionPlanner = require(WorldEngine.Planning.WorldCompositionPlanner)

type Plan = RuinPlanner.Plan

local Validator = {}

function Validator.ValidateTemplates()
	local templates = WorldEngine.Assets.Ruins:FindFirstChild("Templates")
	local invalid = {}
	local checked = 0
	for pieceId, ids in RuinAssetIds.Pieces do
		checked += 1
		local tpl = if templates then templates:FindFirstChild(pieceId) else nil
		local render = tpl and tpl:FindFirstChild("Render")
		local collision = tpl and tpl:FindFirstChild("Collision")
		local sa = render and render:FindFirstChildOfClass("SurfaceAppearance")
		local ok = tpl ~= nil and tpl:IsA("Model")
			and render ~= nil and render:IsA("MeshPart") and render.MeshId == ids.LOD0
			and collision ~= nil and collision:IsA("MeshPart") and collision.MeshId == ids.Collision
			and collision.Transparency == 1 and collision.CanCollide
			and sa ~= nil and sa.ColorMap == RuinAssetIds.StoneTextures.BaseColor
		if not ok then
			table.insert(invalid, pieceId)
		end
	end
	return {Passed = checked == 8 and #invalid == 0, Checked = checked, Invalid = invalid}
end

function Validator.ValidatePlan(spec, plan: Plan)
	local composition = WorldCompositionPlanner.Plan(spec)
	local doorwaysPerSite = {}
	local routeViolations = 0
	local boundsViolations = 0
	for _, piece in plan.Pieces do
		for _, route in composition.Routes do
			if WorldCompositionPlanner.DistanceToRouteSquared(route, piece.WorldX, piece.WorldZ)
				< (Config.RouteClearance - 1) ^ 2 then
				routeViolations += 1
				break
			end
		end
		local half = spec.WorldSize / 2
		if piece.WorldX < spec.OriginX or piece.WorldX > spec.OriginX + spec.WorldSize
			or piece.WorldZ < spec.OriginZ or piece.WorldZ > spec.OriginZ + spec.WorldSize then
			boundsViolations += 1
		end
	end
	for _, site in plan.Sites do
		doorwaysPerSite[site.Id] = site.DoorwayCount
	end
	local everyRuinEnterable = true
	for _, site in plan.Sites do
		if site.DoorwayCount < 1 then
			everyRuinEnterable = false
		end
	end
	local assertions = {
		AllSitesPlaced = #plan.Sites == #Config.Sites,
		EveryRuinEnterable = everyRuinEnterable,
		RoutesStayClear = routeViolations == 0,
		InsideWorldBounds = boundsViolations == 0,
		WithinPieceBudget = #plan.Pieces <= Config.MaximumPieces,
	}
	local passed = true
	for _, assertion in assertions do
		passed = passed and assertion
	end
	return {
		Passed = passed,
		Assertions = assertions,
		SiteCount = #plan.Sites,
		PieceCount = #plan.Pieces,
		DoorwaysPerSite = doorwaysPerSite,
		RouteViolations = routeViolations,
		BoundsViolations = boundsViolations,
	}
end

function Validator.CaptureMaterialized()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local folder = generated:FindFirstChild("Ruins")
	if not folder then
		return {Signature = "missing", PieceCount = 0, InvalidPieces = 1}
	end
	local models = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("Model") then
			table.insert(models, d)
		end
	end
	table.sort(models, function(a, b)
		return (a:GetAttribute("PieceIndex") or 0) < (b:GetAttribute("PieceIndex") or 0)
	end)
	local state = Checksum.New()
	Checksum.UpdateString(state, Config.Version)
	Checksum.UpdateUInt32(state, #models)
	local invalid = 0
	for index, model in models do
		local render = model:FindFirstChild("Render")
		local collision = model:FindFirstChild("Collision")
		if not (render and render:IsA("MeshPart") and render.Anchored
			and collision and collision:IsA("MeshPart") and collision.CanCollide) then
			invalid += 1
			continue
		end
		local position = model:GetPivot().Position
		Checksum.UpdateIndexedUInt32(state, index, math.floor(position.X * 1024 + 0.5))
		Checksum.UpdateString(state, render.MeshId)
		Checksum.UpdateUInt32(state, math.floor(position.Y * 1024 + 0.5))
		Checksum.UpdateUInt32(state, math.floor(position.Z * 1024 + 0.5))
	end
	return {Signature = Checksum.Digest(state), PieceCount = #models, InvalidPieces = invalid}
end

return table.freeze(Validator)
