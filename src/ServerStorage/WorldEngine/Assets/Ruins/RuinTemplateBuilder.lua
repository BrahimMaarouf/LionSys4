--!strict

-- Rebuilds the M8 ruin templates deterministically from RuinAssetIds using
-- AssetService:CreateMeshPartAsync. Templates are therefore reproducible from
-- committed code alone: if the Studio-side Templates folder is ever lost or
-- corrupted, run this builder (Studio, edit mode) to restore it exactly.
local AssetService = game:GetService("AssetService")
local ServerStorage = game:GetService("ServerStorage")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local RuinAssetIds = require(WorldEngine.Assets.Ruins.RuinAssetIds)

local Builder = {}

local function meshPart(meshId: string, collisionFidelity: Enum.CollisionFidelity): MeshPart
	return AssetService:CreateMeshPartAsync(Content.fromUri(meshId), {
		CollisionFidelity = collisionFidelity,
		RenderFidelity = Enum.RenderFidelity.Automatic,
	})
end

function Builder.Build(): Folder
	local ruins = WorldEngine.Assets:WaitForChild("Ruins")
	local templates = ruins:FindFirstChild("Templates")
	if templates then
		templates:Destroy()
	end
	templates = Instance.new("Folder")
	templates.Name = "Templates"

	local names = {}
	for pieceId in RuinAssetIds.Pieces do
		table.insert(names, pieceId)
	end
	table.sort(names)

	for _, pieceId in names do
		local ids = RuinAssetIds.Pieces[pieceId]
		local tpl = Instance.new("Model")
		tpl.Name = pieceId

		local render = meshPart(ids.LOD0, Enum.CollisionFidelity.Box)
		render.Name = "Render"
		render.Anchored = true
		render.CanCollide = false
		render.CanQuery = false
		render.CanTouch = false
		render.CastShadow = true
		local sa = Instance.new("SurfaceAppearance")
		sa.ColorMap = RuinAssetIds.StoneTextures.BaseColor
		sa.NormalMap = RuinAssetIds.StoneTextures.Normal
		sa.RoughnessMap = RuinAssetIds.StoneTextures.Roughness
		sa.AlphaMode = Enum.AlphaMode.Overlay
		sa.Parent = render
		render.Parent = tpl

		local collision = meshPart(ids.Collision, Enum.CollisionFidelity.Default)
		collision.Name = "Collision"
		collision.Anchored = true
		collision.Transparency = 1
		collision.CanCollide = true
		collision.CanQuery = true
		collision.CanTouch = false
		collision.CastShadow = false
		collision.Parent = tpl

		-- MeshParts recenter geometry on the part origin, losing the kit's
		-- authored ground pivot. All kit pieces are authored symmetric in X/Z
		-- with their base at y = 0, so bottom-aligning each part at the model
		-- origin reconstructs the authored ground pivot exactly.
		render.CFrame = CFrame.new(0, render.Size.Y / 2, 0)
		collision.CFrame = CFrame.new(0, collision.Size.Y / 2, 0)
		tpl.WorldPivot = CFrame.new()
		tpl.PrimaryPart = render
		tpl.Parent = templates
	end

	templates.Parent = ruins
	return templates
end

return table.freeze(Builder)
