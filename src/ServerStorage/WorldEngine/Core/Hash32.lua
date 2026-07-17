--!strict

local UINT32 = 4294967296
local FNV_OFFSET_BASIS = 2166136261
local FNV_PRIME = 16777619

local Hash32 = {}

local function normalize(value: number): number
	return math.floor(value) % UINT32
end

function Hash32.Multiply(left: number, right: number): number
	local a = normalize(left)
	local b = normalize(right)

	local aLow = bit32.band(a, 0xFFFF)
	local aHigh = bit32.band(bit32.rshift(a, 16), 0xFFFF)
	local bLow = bit32.band(b, 0xFFFF)
	local bHigh = bit32.band(bit32.rshift(b, 16), 0xFFFF)

	local lowProduct = aLow * bLow
	local crossProduct = aHigh * bLow + aLow * bHigh
	local result = lowProduct + bit32.lshift(bit32.band(crossProduct, 0xFFFF), 16)

	return result % UINT32
end

function Hash32.OffsetBasis(): number
	return FNV_OFFSET_BASIS
end

function Hash32.MixByte(hash: number, value: number): number
	local byte = math.floor(value) % 256
	return Hash32.Multiply(bit32.bxor(normalize(hash), byte), FNV_PRIME)
end

function Hash32.MixUInt32(hash: number, value: number): number
	local mixed = hash
	local normalized = normalize(value)
	for _ = 1, 4 do
		mixed = Hash32.MixByte(mixed, normalized % 256)
		normalized = math.floor(normalized / 256)
	end
	return mixed
end

function Hash32.HashIntegers(...: number): number
	local hash = FNV_OFFSET_BASIS
	for index = 1, select("#", ...) do
		hash = Hash32.MixUInt32(hash, select(index, ...))
	end
	return hash
end

function Hash32.ToSignedUnit(hash: number): number
	return (normalize(hash) / 4294967295) * 2 - 1
end

function Hash32.ToHex(hash: number): string
	local normalized = normalize(hash)
	local characters = "0123456789abcdef"
	local output = table.create(8)

	for index = 8, 1, -1 do
		local nibble = normalized % 16
		output[index] = string.sub(characters, nibble + 1, nibble + 1)
		normalized = math.floor(normalized / 16)
	end

	return table.concat(output)
end

return table.freeze(Hash32)
