--!strict

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WIND_TAG = "WorldEngineWindVegetation"
local UPDATE_INTERVAL = 1 / 20
local elapsed = 0

type WindEntry = {
	Model: Model,
	Visuals: {BasePart},
	BaseCFrames: {CFrame},
	Phase: number,
}

local entries: {[Model]: WindEntry} = {}

local function add(instance: Instance)
	if not instance:IsA("Model") or entries[instance] then
		return
	end
	local visuals = {}
	local baseCFrames = {}
	for _, name in { "Branches", "Foliage" } do
		local part = instance:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(visuals, part)
			table.insert(baseCFrames, part.CFrame)
		end
	end
	if #visuals > 0 then
		local index = instance:GetAttribute("PlacementIndex")
		entries[instance] = {
			Model = instance,
			Visuals = visuals,
			BaseCFrames = baseCFrames,
			Phase = (if type(index) == "number" then index else 0) * 1.61803398875,
		}
	end
end

local function remove(instance: Instance)
	if instance:IsA("Model") then
		entries[instance] = nil
	end
end

for _, instance in CollectionService:GetTagged(WIND_TAG) do
	add(instance)
end
CollectionService:GetInstanceAddedSignal(WIND_TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(WIND_TAG):Connect(remove)

RunService.RenderStepped:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < UPDATE_INTERVAL then
		return
	end
	elapsed = 0
	local now = Workspace:GetServerTimeNow()
	for model, entry in entries do
		if not model.Parent then
			entries[model] = nil
			continue
		end
		local gust = math.sin(now * 1.45 + entry.Phase) * 0.018
			+ math.sin(now * 3.7 + entry.Phase * 0.43) * 0.006
		for index, visual in entry.Visuals do
			visual.CFrame = entry.BaseCFrames[index] * CFrame.Angles(0, 0, gust)
		end
	end
end)
