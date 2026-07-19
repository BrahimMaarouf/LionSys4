--!strict

local Hash32 = require(script.Parent.Hash32)

local Noise = {}

local function fade(value: number): number
	return value * value * value * (value * (value * 6 - 15) + 10)
end

local function lerp(left: number, right: number, alpha: number): number
	return left + (right - left) * alpha
end

local function lattice(seed: number, x: number, z: number, channel: number): number
	local hash = Hash32.HashIntegers(seed, x, z, channel)
	return Hash32.ToSignedUnit(hash)
end

function Noise.Value2D(seed: number, x: number, z: number, channel: number): number
	local x0 = math.floor(x)
	local z0 = math.floor(z)
	local x1 = x0 + 1
	local z1 = z0 + 1

	local tx = fade(x - x0)
	local tz = fade(z - z0)

	local bottom = lerp(
		lattice(seed, x0, z0, channel),
		lattice(seed, x1, z0, channel),
		tx
	)
	local top = lerp(
		lattice(seed, x0, z1, channel),
		lattice(seed, x1, z1, channel),
		tx
	)

	return lerp(bottom, top, tz)
end

return table.freeze(Noise)
