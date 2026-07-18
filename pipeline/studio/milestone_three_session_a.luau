local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

require(game.ServerScriptService.WorldEngineRunners.MilestoneOneRunner).Generate("Forward")
local report = require(game.ServerScriptService.WorldEngineRunners.MilestoneThreeRunner).RegenerateAndVerify()
assert(report.RuntimeValidationPassed, "Milestone 3 runtime validation failed")
local marker = ServerStorage:FindFirstChild("_WorldEngineStudioSession")
local result = {
	SessionId = if marker then marker:GetAttribute("SessionId") else nil,
	RuntimeValidationPassed = report.RuntimeValidationPassed,
	PlanSignature = report.PlanSignature,
	MaterializedSignature = report.MaterializedSignature,
	PropCount = report.PropCount,
	RouteNodeCount = report.RouteNodeCount,
	PathPatchCount = report.PathPatchCount,
	CompositionVersion = report.CompositionVersion,
}
local encoded = HttpService:JSONEncode(result)
print("WORLDENGINE_RESULT=" .. encoded)
return encoded
