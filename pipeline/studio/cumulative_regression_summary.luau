local HttpService = game:GetService("HttpService")

local report = require(game.ServerScriptService.WorldEngineRunners.WorldEngineRegressionRunner).Run()
assert(report.Passed, "WorldEngine cumulative M1+M2+M3+M4+M5+M6 regression failed")
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
	M5 = report.MilestoneFive.Status,
	M5Session = report.MilestoneFive.SessionId,
	M5Plan = report.MilestoneFive.PlanSignature,
	M5Materialized = report.MilestoneFive.MaterializedSignature,
	M5Regions = report.MilestoneFive.RegionCount,
	M5Routes = report.MilestoneFive.RouteCount,
	M5Landmarks = report.MilestoneFive.LandmarkCount,
	M5Vistas = report.MilestoneFive.VistaCount,
	M5Variants = report.MilestoneFive.VariantCount,
	M5Components = report.MilestoneFive.ComponentCount,
	M6 = report.MilestoneSix.Status,
	M6Session = report.MilestoneSix.SessionId,
	M6Plan = report.MilestoneSix.PlanSignature,
	M6Surface = report.MilestoneSix.SurfaceSignature,
	M6Details = report.MilestoneSix.DetailCount,
	M6Emitters = report.MilestoneSix.AtmosphereEmitterCount,
	M6Materialized = report.MilestoneSix.MaterializedSignature,
}
local encoded = HttpService:JSONEncode(summary)
print("WORLDENGINE_SUMMARY=" .. encoded)
return encoded
