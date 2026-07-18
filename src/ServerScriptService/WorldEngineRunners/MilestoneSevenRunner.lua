--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Validator = require(WorldEngine.Validation.MilestoneSevenValidator)
local Evidence = require(WorldEngine.Config.MilestoneSevenEvidence)

local CONTACT_SHEET_NAME = "M7ContactSheet"
local CELL = 34
local SHEET_ORIGIN = Vector3.new(-700, 120, -700) -- far outside the 512-stud world

local Runner = {}

local function humanVisualSignoff(): boolean
	local override = Workspace:WaitForChild("WorldRoot"):GetAttribute("Milestone7HumanVisualSignoff")
	if type(override) == "boolean" then
		return override
	end
	return Evidence.HumanVisualSignoffPassed
end

-- Clones one live representative of every (family, recipe) variant out of the
-- generated golden world into a labeled grid far from the world, so a human
-- can review the shipped expressive range from a single capture. Reviewing
-- clones of the real world (rather than synthetic re-materializations) means
-- the sheet shows exactly what players see.
function Runner.BuildContactSheet()
	Runner.TeardownContactSheet()
	local generated = Workspace:WaitForChild("WorldRoot"):WaitForChild("Generated")
	local representatives: {[string]: Model} = {}
	local order: {string} = {}
	for _, model in generated:GetDescendants() do
		if model:IsA("Model") then
			local recipe = model:GetAttribute("RecipeId")
			local asset = model:GetAttribute("SourceAsset")
			if type(recipe) == "string" and type(asset) == "string" then
				local key = asset .. "/" .. recipe
				if not representatives[key] then
					representatives[key] = model
					table.insert(order, key)
				end
			end
		end
	end
	table.sort(order)

	local folder = Instance.new("Folder")
	folder.Name = CONTACT_SHEET_NAME
	folder.Parent = Workspace

	local columns = 5
	local rows = math.ceil(#order / columns)
	local floor = Instance.new("Part")
	floor.Name = "SheetFloor"
	floor.Anchored = true
	floor.CanCollide = false
	floor.CastShadow = false
	floor.Color = Color3.fromRGB(163, 145, 118)
	floor.Material = Enum.Material.Sand
	floor.Size = Vector3.new(columns * CELL + 30, 1, rows * CELL + 30)
	floor.Position = SHEET_ORIGIN
		+ Vector3.new((columns - 1) * CELL / 2, -0.5, (rows - 1) * CELL / 2)
	floor.Parent = folder

	for index, key in order do
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		local clone = representatives[key]:Clone()
		clone.Name = key
		clone:PivotTo(CFrame.new(SHEET_ORIGIN + Vector3.new(column * CELL, 2, row * CELL)))
		clone.Parent = folder

		local label = Instance.new("Part")
		label.Name = key .. "_Label"
		label.Anchored = true
		label.CanCollide = false
		label.Transparency = 1
		label.Size = Vector3.new(1, 1, 1)
		label.Position = SHEET_ORIGIN + Vector3.new(column * CELL, 14, row * CELL)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromScale(14, 2)
		gui.AlwaysOnTop = true
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.TextScaled = true
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.2
		text.Text = key
		text.Parent = gui
		gui.Parent = label
		label.Parent = folder
	end
	folder:SetAttribute("RecipeCount", #order)
	return {Placed = #order, Columns = columns, Rows = rows}
end

function Runner.TeardownContactSheet()
	local existing = Workspace:FindFirstChild(CONTACT_SHEET_NAME)
	if existing then
		existing:Destroy()
	end
end

function Runner.RecordVisualSignoff(passed: boolean, notes: string)
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("Milestone7HumanVisualSignoff", passed)
	root:SetAttribute("Milestone7VisualSignoffNotes", notes)
	root:SetAttribute("Milestone7VisualSignoffAt", os.time())
	return {Passed = passed, Notes = notes}
end

function Runner.RunGoldenRegression()
	local cumulative = require(script.Parent.WorldEngineRegressionRunner).Run()
	local textures = Validator.ValidateTemplateTextures()
	local performance = Validator.CollectPerformanceSnapshot(nil)
	local root = Workspace:WaitForChild("WorldRoot")
	local signoff = humanVisualSignoff()
	local passed = cumulative.Passed
		and textures.Passed
		and Evidence.TexturePipelineReproducible
		and signoff
	local report = {
		Milestone = 7,
		Passed = passed,
		Status = if passed
			then "PASSED_M7_ASSET_QUALITY"
			elseif not signoff then "AWAITING_VISUAL_SIGNOFF"
			else "FAILED_OR_GATES_OPEN",
		CumulativeStatus = cumulative.Status,
		TextureValidation = textures,
		Performance = performance,
		DeviceProfileRecorded = Evidence.DeviceProfileRecorded,
		HumanVisualSignoff = signoff,
		HumanVisualSignoffNotes = Evidence.HumanVisualSignoffNotes,
	}
	root:SetAttribute("Milestone7Passed", passed)
	root:SetAttribute("Milestone7Status", report.Status)
	local diagnostics = root:WaitForChild("Diagnostics")
	local value = diagnostics:FindFirstChild("MilestoneSevenReport") or Instance.new("StringValue")
	value.Name = "MilestoneSevenReport"
	value.Parent = diagnostics
	assert(value:IsA("StringValue"))
	value.Value = HttpService:JSONEncode(report)
	return report
end

return table.freeze(Runner)
