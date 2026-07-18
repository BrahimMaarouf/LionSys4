--!strict

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TAG = "WorldEngineCustomLOD"
local UPDATE_INTERVAL = 0.15
local elapsed = 0

type Entry = {
	Model: Model,
	LOD0: {BasePart},
	LOD1: {BasePart},
	LOD2: {BasePart},
	CurrentLevel: number,
}

local entries: {[Model]: Entry} = {}
local pending: {[Model]: boolean} = {}

local function parts(model: Model, level: number, names: {string}): {BasePart}
	local result = {}
	local nameSet: {[string]: boolean} = {}
	for _, name in names do
		nameSet[name] = true
	end
	for _, instance in model:GetDescendants() do
		if instance:IsA("BasePart") then
			local authoredLevel = instance:GetAttribute("WorldEngineLODLevel")
			if authoredLevel == level or (authoredLevel == nil and nameSet[instance.Name]) then
				table.insert(result, instance)
			end
		end
	end
	return result
end

local function show(group: {BasePart}, visible: boolean)
	for _, part in group do
		part.LocalTransparencyModifier = if visible then 0 else 1
	end
end

local function setLevel(entry: Entry, level: number)
	if entry.CurrentLevel == level then
		return
	end
	show(entry.LOD0, level == 0)
	show(entry.LOD1, level == 1)
	show(entry.LOD2, level == 2)
	entry.CurrentLevel = level
end

local function tryAdd(instance: Model): boolean
	local kind = instance:GetAttribute("AssetKind")
	local lod0Names = if kind == "Vegetation" then { "Branches", "Foliage" } else { "Render" }
	local entry: Entry = {
		Model = instance,
		LOD0 = parts(instance, 0, lod0Names),
		LOD1 = parts(instance, 1, { "LOD1" }),
		LOD2 = parts(instance, 2, { "LOD2" }),
		CurrentLevel = -1,
	}
	if #entry.LOD0 > 0 and #entry.LOD1 > 0 and #entry.LOD1 == #entry.LOD2 then
		entries[instance] = entry
		setLevel(entry, 0)
		return true
	end
	return false
end

local function add(instance: Instance)
	if not instance:IsA("Model") or entries[instance] or pending[instance] then
		return
	end
	if tryAdd(instance) then
		return
	end
	pending[instance] = true
	task.spawn(function()
		for _ = 1, 20 do
			if not instance.Parent or tryAdd(instance) then
				break
			end
			task.wait(0.05)
		end
		pending[instance] = nil
	end)
end

local function remove(instance: Instance)
	if instance:IsA("Model") then
		entries[instance] = nil
		pending[instance] = nil
	end
end

for _, instance in CollectionService:GetTagged(TAG) do
	add(instance)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)

RunService.RenderStepped:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < UPDATE_INTERVAL then
		return
	end
	elapsed = 0
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	for model, entry in entries do
		if not model.Parent then
			entries[model] = nil
			continue
		end
		local distance = (model:GetPivot().Position - cameraPosition).Magnitude
		local nearDistance = model:GetAttribute("LODNearDistance")
		local farDistance = model:GetAttribute("LODFarDistance")
		local near = if type(nearDistance) == "number" then nearDistance else 180
		local far = if type(farDistance) == "number" then farDistance else 360
		setLevel(entry, if distance < near then 0 elseif distance < far then 1 else 2)
	end
end)
