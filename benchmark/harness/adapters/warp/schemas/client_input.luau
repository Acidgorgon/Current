--!optimize 2
-- client_input for Warp (see adapters/blink/schemas/client_input.blink).
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

local EVENTS = {
	Input = {
		Schema.struct({
			Seq = Schema.u8,
			Dir = Schema.vector3f32,
			Buttons = set("BenchButtons", { "Sprint", "Shoot", "Pass", "Tackle", "Jump", "Dive" }),
		}),
		false,
	},
	PlayerAction = {
		Schema.struct({
			Kind = enum("BenchAction", { "Shoot", "Pass", "Tackle", "Header", "Emote" }),
			Target = Schema.u16,
			Power = Schema.f32,
		}),
		true,
	},
}

-- The server registers every event (and so its id) as the module loads; a
-- client applies the schemas once the ids have replicated (adapter.luau).
if isServer then
	for name, event in EVENTS do
		Side.useSchema(name, event[1])
	end
end

return { Side = Side, Events = EVENTS }
