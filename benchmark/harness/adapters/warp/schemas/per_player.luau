--!optimize 2
-- per_player for Warp (see adapters/blink/schemas/per_player.blink).
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
	Wallet = { Schema.u32, true },
	Notify = { Schema.string, true },
	Inventory = { Schema.array(Schema.struct({ Item = Schema.u16, Count = Schema.u8 })), true },
	PlayerFlags = { set("BenchFlags", { "Muted", "Spectating", "Captain", "Ready", "Away", "Premium" }), true },
	BoostApplied = {
		Schema.struct({ Kind = Schema.u8, Duration = Schema.optional(Schema.f32), Source = Schema.optional(Schema.u16) }),
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
