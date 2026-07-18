--!strict

-- WorldEngine Console: the single entry point behind the settings UI
-- (ui/worldengine-panel.html). Every function is safe to call repeatedly from
-- the Studio command bar. Seed-parameterized functions clone the world spec;
-- they never mutate the golden configuration. Building a non-golden seed is a
-- sandbox operation: run Console.RestoreGoldenWorld() (or the cumulative
-- regression) to return to the verified golden state.
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Spec = require(WorldEngine.Config.WorldSpecs.DesertVerticalSlice)
local RuinPlanner = require(WorldEngine.Planning.RuinPlanner)
local RuinMaterializer = require(WorldEngine.Materialization.RuinMaterializer)
local WorldEdgeMaterializer = require(WorldEngine.Materialization.WorldEdgeMaterializer)

local Runners = script.Parent

local Console = {}

local function specWithSeed(seed: number?)
	if seed == nil or seed == Spec.WorldSeed then
		return Spec
	end
	local clone = table.clone(Spec)
	clone.WorldSeed = seed
	return clone
end

-- Plan-only metrics for any list of seeds. Creates zero instances.
function Console.Preview(seeds: {number})
	return require(Runners.MilestoneNineRunner).BrowseSeeds(seeds)
end

-- Builds the COMPLETE world (terrain, props, variation, composition,
-- surfacing, lighting, ruins, edge skirt) for any seed.
function Console.BuildWorld(seed: number?)
	local spec = specWithSeed(seed)
	local started = os.clock()
	local six = require(Runners.MilestoneSixRunner).Generate(spec)
	local ruinPlan = RuinPlanner.Plan(spec)
	RuinMaterializer.Materialize(ruinPlan)
	local walls = WorldEdgeMaterializer.Materialize(spec)
	local report = {
		Seed = spec.WorldSeed,
		IsGoldenSeed = spec.WorldSeed == Spec.WorldSeed,
		RuinPieces = #ruinPlan.Pieces,
		RuinSites = #ruinPlan.Sites,
		BoundaryWalls = #walls:GetChildren(),
		SurfaceSignature = six.Plan and six.Plan.Signature or nil,
		RuinSignature = ruinPlan.Signature,
		TotalSeconds = os.clock() - started,
	}
	Workspace.WorldRoot:SetAttribute("ConsoleWorldSeed", spec.WorldSeed)
	return report
end

-- Rebuilds the verified golden world and re-runs every golden regression.
function Console.RestoreGoldenWorld()
	return require(Runners.WorldEngineRegressionRunner).Run()
end

-- Layer operations (golden seed unless overridden) -------------------------

function Console.RegenerateRuins(seed: number?)
	local plan = RuinPlanner.Plan(specWithSeed(seed))
	RuinMaterializer.Materialize(plan)
	return {Seed = plan.WorldSeed, Pieces = #plan.Pieces, Signature = plan.Signature}
end

function Console.ClearRuins()
	RuinMaterializer.Clear()
	return "ruins cleared"
end

function Console.RegenerateEdge(seed: number?)
	local spec = specWithSeed(seed)
	local walls = WorldEdgeMaterializer.Materialize(spec)
	return {Seed = spec.WorldSeed, Walls = #walls:GetChildren(),
		Signature = WorldEdgeMaterializer.SkirtSignature(spec)}
end

function Console.ClearEdge(seed: number?)
	WorldEdgeMaterializer.Clear(specWithSeed(seed))
	return "edge cleared"
end

-- Review tooling ------------------------------------------------------------

function Console.BuildContactSheet()
	return require(Runners.MilestoneSevenRunner).BuildContactSheet()
end

function Console.TeardownContactSheet()
	require(Runners.MilestoneSevenRunner).TeardownContactSheet()
	return "contact sheet removed"
end

-- Diagnostics ----------------------------------------------------------------

function Console.Status()
	local root = Workspace.WorldRoot
	return {
		ConsoleWorldSeed = root:GetAttribute("ConsoleWorldSeed") or Spec.WorldSeed,
		GoldenSeed = Spec.WorldSeed,
		CumulativePassed = root:GetAttribute("CumulativeRegressionPassed"),
		LastVerifiedAt = root:GetAttribute("CumulativeRegressionVerifiedAt"),
	}
end

function Console.Help()
	return table.concat({
		"WorldEngine Console — Studio command bar usage:",
		'local C = require(game.ServerScriptService.WorldEngineRunners.WorldEngineConsole)',
		"C.Preview({271828, 424242, 9})   -- plan-only metrics for seeds",
		"C.BuildWorld(424242)             -- build the full world for a seed",
		"C.RestoreGoldenWorld()           -- rebuild + verify the golden world",
		"C.RegenerateRuins(7) / C.ClearRuins()",
		"C.RegenerateEdge() / C.ClearEdge()",
		"C.BuildContactSheet() / C.TeardownContactSheet()",
		"C.Status()",
	}, "\n")
end

return table.freeze(Console)
