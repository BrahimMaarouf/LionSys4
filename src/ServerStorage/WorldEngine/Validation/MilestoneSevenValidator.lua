--!strict

local ServerStorage = game:GetService("ServerStorage")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local AssetIds = require(WorldEngine.Assets.Rocks.AssetIds)

local Validator = {}

-- Every template surface must carry exactly the M7 texture sets from AssetIds.
function Validator.ValidateTemplateTextures()
	local templates = WorldEngine.Assets.Rocks:WaitForChild("Templates")
	local expected: {[Instance]: {[string]: string}} = {}
	local function expect(part: Instance?, set): ()
		if part then
			expected[part] = set
		end
	end
	for _, name in {"WindBoulder", "LayeredMesa"} do
		local tpl = templates:FindFirstChild(name)
		if tpl then
			expect(tpl:FindFirstChild("Render"), AssetIds.RockTextures)
			local lods = tpl:FindFirstChild("LODVariants")
			if lods then
				expect(lods:FindFirstChild("LOD1"), AssetIds.RockTextures)
				expect(lods:FindFirstChild("LOD2"), AssetIds.RockTextures)
			end
		end
	end
	local shrub = templates:FindFirstChild("DryShrub")
	if shrub then
		expect(shrub:FindFirstChild("Foliage"), AssetIds.ShrubTextures)
		expect(shrub:FindFirstChild("Branches"), AssetIds.BarkTextures)
		local lods = shrub:FindFirstChild("LODVariants")
		if lods then
			expect(lods:FindFirstChild("LOD1"), AssetIds.ShrubTextures)
			expect(lods:FindFirstChild("LOD2"), AssetIds.ShrubTextures)
		end
	end

	local checked, wrong = 0, {}
	for part, set in expected do
		checked += 1
		local sa = part:FindFirstChildOfClass("SurfaceAppearance")
		if not sa
			or sa.ColorMap ~= set.BaseColor
			or sa.NormalMap ~= set.Normal
			or sa.RoughnessMap ~= set.Roughness then
			table.insert(wrong, part:GetFullName())
		end
	end
	local barkDistinct = AssetIds.BarkTextures.BaseColor ~= AssetIds.ShrubTextures.BaseColor
	return {
		Passed = checked == 10 and #wrong == 0 and barkDistinct,
		CheckedSurfaces = checked,
		WrongSurfaces = wrong,
		BarkSetDistinct = barkDistinct,
	}
end

-- Snapshot of generation cost and runtime footprint for the recap and for
-- comparison across future milestones. Studio-side numbers; device profiling
-- is recorded separately in MilestoneSevenEvidence.
function Validator.CollectPerformanceSnapshot(generationSeconds: number?)
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local descendants = 0
	local meshParts = 0
	local particleEmitters = 0
	for _, d in generated:GetDescendants() do
		descendants += 1
		if d:IsA("MeshPart") then meshParts += 1 end
		if d:IsA("ParticleEmitter") then particleEmitters += 1 end
	end
	return {
		GeneratedDescendants = descendants,
		MeshParts = meshParts,
		ParticleEmitters = particleEmitters,
		GenerationSeconds = generationSeconds,
		InstanceCountMemoryMb = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Instances),
		GraphicsMeshPartsMemoryMb = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.GraphicsMeshParts),
		GraphicsTextureMemoryMb = Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.GraphicsTexture),
		TotalMemoryMb = Stats:GetTotalMemoryUsageMb(),
	}
end

return table.freeze(Validator)
