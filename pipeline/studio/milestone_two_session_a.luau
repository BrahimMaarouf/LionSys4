local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local report = require(game.ServerScriptService.WorldEngineRunners.MilestoneTwoRunner).RegenerateAndVerify()
local marker = ServerStorage:FindFirstChild("_WorldEngineStudioSession")
local result = {
	SessionId = if marker then marker:GetAttribute("SessionId") else nil,
	RuntimeValidationPassed = report.RuntimeValidationPassed,
	PlacementSignature = report.PlacementSignature,
	MaterializedSignature = report.MaterializedSignature,
	PropCount = report.PropCount,
	CatalogVersion = report.CatalogVersion,
	CustomLODCount = report.CustomLODCount,
}
local encoded = HttpService:JSONEncode(result)
print("WORLDENGINE_RESULT=" .. encoded)
return encoded
