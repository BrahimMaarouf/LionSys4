local HttpService = game:GetService("HttpService")

local report = require(game.ServerScriptService.WorldEngineRunners.WorldEngineRegressionRunner).Run()
assert(report.Passed, "WorldEngine cumulative M1+M2+M3+M4 regression failed")
local summary = {
	Passed = report.Passed,
	Status = report.Status,
	M1 = report.MilestoneOne.Status,
	M2 = report.MilestoneTwo.Status,
	M3 = report.MilestoneThree.Status,
	M4 = report.MilestoneFour.Status,
	M4Session = report.MilestoneFour.SessionId,
	M4Plan = report.MilestoneFour.PlanSignature,
	M4Materialized = report.MilestoneFour.MaterializedSignature,
	M4Variants = report.MilestoneFour.VariantCount,
	M4Components = report.MilestoneFour.ComponentCount,
}
local encoded = HttpService:JSONEncode(summary)
print("WORLDENGINE_SUMMARY=" .. encoded)
return encoded
