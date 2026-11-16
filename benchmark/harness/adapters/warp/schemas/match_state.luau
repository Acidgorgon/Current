--!optimize 2
-- match_state for Warp (see adapters/blink/schemas/match_state.blink).
-- Warp struct fields are written in sorted key order; array length is a varint.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Warp = require(ReplicatedStorage:WaitForChild("Warp"))
local isServer = game:GetService("RunService"):IsServer()
local Side = if isServer then Warp.Server() else Warp.Client()
local Buffer = Warp.Buffer
local Schema = Buffer.Schema

-- Warp has no enum or set type; Schema.custom_datatype (its public extension
-- point) gives them the same wire encoding as Blink: enum = u8 index,
-- set = u8 bitfield.
local writeU8 = Buffer.writeu8

local function enum(name: string, names: { string })
	local index = {}
	for i, n in names do
		index[n] = i - 1
	end
	Schema.custom_datatype(name, {}, function(w, value)
		writeU8(w, index[value])
	end, function(b: buffer, cursor: number)
		return names[buffer.readu8(b, cursor) + 1], cursor + 1
	end)
	return Schema[name]
end

local function set(name: string, names: { string })
	Schema.custom_datatype(name, {}, function(w, value)
		local mask = 0
		for i, n in names do
			if value[n] then
				mask += bit32.lshift(1, i - 1)
			end
		end
		writeU8(w, mask)
	end, function(b: buffer, cursor: number)
		local mask = buffer.readu8(b, cursor)
		local out = {}
		for i, n in names do
			out[n] = bit32.btest(mask, bit32.lshift(1, i - 1))
		end
		return out, cursor + 1
	end)
	return Schema[name]
end

local PlayerState = Schema.struct({
	Id = Schema.u16,
	Pos = Schema.vector3f32,
	Vel = Schema.vector3, -- 3 x f16, like Blink's vector<f16>
	Stamina = Schema.u8,
	State = enum("BenchStance", { "Idle", "Jogging", "Sprinting", "Dribbling", "Tackling", "Diving" }),
})
local MatchState = Schema.struct({
	Ball = Schema.vector3f32,
	Clock = Schema.f32,
	HomeScore = Schema.u8,
	AwayScore = Schema.u8,
	Phase = enum("BenchPhase", { "Warmup", "Kickoff", "Play", "Goal", "HalfTime", "FullTime" }),
	Players = Schema.array(PlayerState),
})

-- [name] = { schema, reliable }
local EVENTS = {
	MatchReliable = { MatchState, true },
	MatchUnreliable = { MatchState, false },
}

-- The server registers every event (and so its id) as the module loads; a
-- client applies the schemas once the ids have replicated (adapter.luau).
if isServer then
	for name, event in EVENTS do
		Side.useSchema(name, event[1])
	end
end

return { Side = Side, Events = EVENTS }
