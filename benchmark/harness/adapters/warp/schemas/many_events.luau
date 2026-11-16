--!optimize 2
-- many_events for Warp: 120 events E001..E120. A Warp schema describes ONE
-- value, so (u8, u16) events are a struct {a: u8, b: u16} (same 3 bytes);
-- the adapter packs/unpacks it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Warp = require(ReplicatedStorage:WaitForChild("Warp"))
local isServer = game:GetService("RunService"):IsServer()
local Side = if isServer then Warp.Server() else Warp.Client()
local Buffer = Warp.Buffer
local Schema = Buffer.Schema

local EVENTS = {}
for e = 1, 120 do
	EVENTS[string.format("E%03d", e)] = {
		if e % 3 == 0 then Schema.struct({ a = Schema.u8, b = Schema.u16 }) else Schema.u16,
		true,
	}
end

-- The server registers every event (and so its id) as the module loads; a
-- client applies the schemas once the ids have replicated (adapter.luau).
if isServer then
	for name, event in EVENTS do
		Side.useSchema(name, event[1])
	end
end

return { Side = Side, Events = EVENTS }
