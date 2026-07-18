--!strict

local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local MilestoneOne = require(script.Parent.MilestoneOneRunner)
local MilestoneTwo = require(script.Parent.MilestoneTwoRunner)
local MilestoneThree = require(script.Parent.MilestoneThreeRunner)

local Runner = {}

function Runner.Run()
	local milestoneOne = MilestoneOne.RunGoldenRegression()
	local milestoneTwo = MilestoneTwo.RunGoldenRegression()
	local milestoneThree = MilestoneThree.RunGoldenRegression()
	local passed = milestoneOne.Passed and milestoneTwo.Passed and milestoneThree.Passed
	local report = {
		Passed = passed,
		Status = if passed then "PASSED_M1_M2_M3_CUMULATIVE" else "FAILED_OR_GATES_OPEN",
		MilestoneOne = milestoneOne,
		MilestoneTwo = milestoneTwo,
		MilestoneThree = milestoneThree,
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
