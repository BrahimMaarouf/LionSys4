local HttpService = game:GetService("HttpService")

local report = require(game.ServerScriptService.WorldEngineRunners.WorldEngineRegressionRunner).Run()
assert(report.Passed, "WorldEngine cumulative M1+M2+M3+M4 regression failed")
local encoded = HttpService:JSONEncode(report)
print("WORLDENGINE_RESULT=" .. encoded)
return encoded
