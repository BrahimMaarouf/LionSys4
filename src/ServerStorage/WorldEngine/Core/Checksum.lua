--!strict

local ServerStorage = game:GetService("ServerStorage")

local WorldEngine = ServerStorage:WaitForChild("WorldEngine")
local Hash32 = require(WorldEngine.Core.Hash32)

export type State = {
	Hash: number,
	Count: number,
}

local Checksum = {}

function Checksum.New(): State
	return {
		Hash = Hash32.OffsetBasis(),
		Count = 0,
	}
end

function Checksum.UpdateByte(state: State, value: number)
	state.Hash = Hash32.MixByte(state.Hash, value)
	state.Count += 1
end

function Checksum.UpdateUInt32(state: State, value: number)
	local normalized = math.floor(value) % 4294967296
	for _ = 1, 4 do
		Checksum.UpdateByte(state, normalized % 256)
		normalized = math.floor(normalized / 256)
	end
end

function Checksum.UpdateIndexedUInt32(state: State, index: number, value: number)
	Checksum.UpdateUInt32(state, index)
	Checksum.UpdateUInt32(state, value)
end

function Checksum.UpdateString(state: State, value: string)
	for index = 1, #value do
		Checksum.UpdateByte(state, string.byte(value, index))
	end
end

function Checksum.Digest(state: State): string
	return "fnv1a32:" .. Hash32.ToHex(state.Hash)
end

return table.freeze(Checksum)
