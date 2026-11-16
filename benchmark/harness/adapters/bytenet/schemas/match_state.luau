--!optimize 2
-- match_state for ByteNet (see adapters/blink/schemas/match_state.blink).
-- Differences: Vel is f32 (ByteNet has no f16 vector), Players length is u16.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage:WaitForChild("ByteNet"))

-- ByteNet has no enum or set type. Its data types are plain {read, write}
-- tables over its own bufferWriter, so these two are written the way its
-- built-in types are, giving the same wire encoding as Blink (enum: u8 index,
-- set: u8 bitfield).
local bufferWriter = require(ReplicatedStorage.ByteNet.process.bufferWriter)
local writeU8 = bufferWriter.u8

local function enum(names: { string })
	local index = {}
	for i, name in names do
		index[name] = i - 1
	end
	return {
		read = function(b: buffer, cursor: number)
			return names[buffer.readu8(b, cursor) + 1], 1
		end,
		write = function(value: string)
			writeU8(index[value])
		end,
	}
end

local function set(names: { string })
	return {
		read = function(b: buffer, cursor: number)
			local mask = buffer.readu8(b, cursor)
			local out = {}
			for i, name in names do
				out[name] = bit32.btest(mask, bit32.lshift(1, i - 1))
			end
			return out, 1
		end,
		write = function(value: { [string]: boolean })
			local mask = 0
			for i, name in names do
				if value[name] then
					mask += bit32.lshift(1, i - 1)
				end
			end
			writeU8(mask)
		end,
	}
end

local PHASES = { "Warmup", "Kickoff", "Play", "Goal", "HalfTime", "FullTime" }
local STANCES = { "Idle", "Jogging", "Sprinting", "Dribbling", "Tackling", "Diving" }

return ByteNet.defineNamespace("match_state", function()
	local PlayerState = ByteNet.struct({
		Id = ByteNet.uint16,
		Pos = ByteNet.vec3,
		Vel = ByteNet.vec3,
		Stamina = ByteNet.uint8,
		State = enum(STANCES),
	})
	local MatchState = ByteNet.struct({
		Ball = ByteNet.vec3,
		Clock = ByteNet.float32,
		HomeScore = ByteNet.uint8,
		AwayScore = ByteNet.uint8,
		Phase = enum(PHASES),
		Players = ByteNet.array(PlayerState),
	})
	return {
		MatchReliable = ByteNet.definePacket({ value = MatchState }),
		MatchUnreliable = ByteNet.definePacket({ value = MatchState, reliabilityType = "unreliable" }),
	}
end)
