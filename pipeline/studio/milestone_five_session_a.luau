local HttpService = game:GetService("HttpService")

require(game.ServerScriptService.WorldEngineRunners.MilestoneOneRunner).Generate("Forward")
local report = require(game.ServerScriptService.WorldEngineRunners.MilestoneFiveRunner).RegenerateAndVerify()
assert(report.RuntimeValidationPassed, "Milestone 5 runtime validation failed")
local encoded = HttpService:JSONEncode(report)
print("WORLDENGINE_M5_RESULT=" .. encoded)
return encoded
