--!strict

local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local MilestoneOne = require(script.Parent.MilestoneOneRunner)
local MilestoneTwo = require(script.Parent.MilestoneTwoRunner)
local MilestoneThree = require(script.Parent.MilestoneThreeRunner)
local MilestoneFour = require(script.Parent.MilestoneFourRunner)
local MilestoneFive = require(script.Parent.MilestoneFiveRunner)

local Runner = {}

function Runner.Run()
	local milestoneOne = MilestoneOne.RunGoldenRegression()
	local milestoneTwo = MilestoneTwo.RunGoldenRegression()
	local milestoneThree = MilestoneThree.RunGoldenRegression()
	local milestoneFour = MilestoneFour.RunGoldenRegression()
	local milestoneFive = MilestoneFive.RunGoldenRegression()
	local passed = milestoneOne.Passed and milestoneTwo.Passed and milestoneThree.Passed and milestoneFour.Passed and milestoneFive.Passed
	local report = {
		Passed = passed,
		Status = if passed then "PASSED_M1_M2_M3_M4_M5_CUMULATIVE" else "FAILED_OR_GATES_OPEN",
		MilestoneOne = milestoneOne,
		MilestoneTwo = milestoneTwo,
		MilestoneThree = milestoneThree,
		MilestoneFour = milestoneFour,
		MilestoneFive = milestoneFive,
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
