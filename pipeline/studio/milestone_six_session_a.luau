local HttpService = game:GetService("HttpService")

local report = require(game.ServerScriptService.WorldEngineRunners.MilestoneSixRunner).RegenerateAndVerify()
assert(report.RuntimeValidationPassed, "Milestone 6 runtime validation failed")
local encoded = HttpService:JSONEncode(report)
print("WORLDENGINE_M6_RESULT=" .. encoded)
return encoded
