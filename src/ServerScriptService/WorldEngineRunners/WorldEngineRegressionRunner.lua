--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MilestoneOne = require(script.Parent.MilestoneOneRunner)
local MilestoneTwo = require(script.Parent.MilestoneTwoRunner)
local MilestoneThree = require(script.Parent.MilestoneThreeRunner)
local MilestoneFour = require(script.Parent.MilestoneFourRunner)
local MilestoneFive = require(script.Parent.MilestoneFiveRunner)
local MilestoneSix = require(script.Parent.MilestoneSixRunner)
local MilestoneEight = require(script.Parent.MilestoneEightRunner)
local MilestoneNine = require(script.Parent.MilestoneNineRunner)

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local RuinMaterializer = require(WorldEngine.Materialization.RuinMaterializer)
local RuinTemplateBuilder = require(WorldEngine.Assets.Ruins.RuinTemplateBuilder)
local TextureApplier = require(WorldEngine.Assets.Rocks.MilestoneSevenTextureApplier)

local Runner = {}

-- Rojo sync-in removes Studio-owned instances it does not manage (the ruin
-- template Models and template SurfaceAppearance edits). Both are reproducible
-- from committed code, so the suite self-heals before validating.
local function selfHealStudioAssets()
	local templates = WorldEngine.Assets.Ruins:FindFirstChild("Templates")
	if not templates or #templates:GetChildren() ~= 8 then
		RuinTemplateBuilder.Build()
	end
	TextureApplier.Apply()
end

-- Cumulative state machine (explicit, order matters):
-- 1. Clear the M8 ruins layer. The M1-M6 validators predate ruins and some
--    capture the Generated tree broadly; ruin models would pollute their
--    signatures. Their regressions therefore run against a ruin-free world,
--    exactly the state in which their goldens were baselined.
-- 2. Run M1-M6 golden regressions in milestone order (each regenerates its
--    own layer deterministically).
-- 3. Run M8 last; it regenerates the ruins layer over the verified world and
--    leaves the place in its complete final state.
function Runner.Run()
	selfHealStudioAssets()
	RuinMaterializer.Clear()
	local milestoneOne = MilestoneOne.RunGoldenRegression()
	local milestoneTwo = MilestoneTwo.RunGoldenRegression()
	local milestoneThree = MilestoneThree.RunGoldenRegression()
	local milestoneFour = MilestoneFour.RunGoldenRegression()
	local milestoneFive = MilestoneFive.RunGoldenRegression()
	local milestoneSix = MilestoneSix.RunGoldenRegression()
	local milestoneEight = MilestoneEight.RunGoldenRegression()
	local milestoneNine = MilestoneNine.RunGoldenRegression()
	local passed = milestoneOne.Passed and milestoneTwo.Passed and milestoneThree.Passed and milestoneFour.Passed and milestoneFive.Passed and milestoneSix.Passed and milestoneEight.Passed and milestoneNine.Passed
	local report = {
		Passed = passed,
		Status = if passed then "PASSED_M1_M2_M3_M4_M5_M6_M8_M9_CUMULATIVE" else "FAILED_OR_GATES_OPEN",
		MilestoneOne = milestoneOne,
		MilestoneTwo = milestoneTwo,
		MilestoneThree = milestoneThree,
		MilestoneFour = milestoneFour,
		MilestoneFive = milestoneFive,
		MilestoneSix = milestoneSix,
		MilestoneEight = milestoneEight,
		MilestoneNine = milestoneNine,
	}
	local root = Workspace:WaitForChild("WorldRoot")
	root:SetAttribute("CumulativeRegressionPassed", passed)
	root:SetAttribute("CumulativeRegressionVerifiedAt", os.time())
	local diagnostics = root:WaitForChild("Diagnostics")
	local value = diagnostics:FindFirstChild("CumulativeRegressionReport") or Instance.new("StringValue")
	value.Name = "CumulativeRegressionReport"
	value.Parent = diagnostics
	assert(value:IsA("StringValue"))
	value.Value = HttpService:JSONEncode(report)
	return report
end

return table.freeze(Runner)
