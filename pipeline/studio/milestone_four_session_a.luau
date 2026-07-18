local HttpService = game:GetService("HttpService")

require(game.ServerScriptService.WorldEngineRunners.MilestoneOneRunner).Generate("Forward")
local report = require(game.ServerScriptService.WorldEngineRunners.MilestoneFourRunner).RegenerateAndVerify()
assert(report.RuntimeValidationPassed, "Milestone 4 runtime validation failed")
local encoded = HttpService:JSONEncode(report)
print("WORLDENGINE_M4_RESULT=" .. encoded)
return encoded
