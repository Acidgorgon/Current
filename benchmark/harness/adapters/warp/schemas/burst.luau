--!optimize 2
-- burst for Warp (see adapters/blink/schemas/burst.blink).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Warp = require(ReplicatedStorage:WaitForChild("Warp"))
local isServer = game:GetService("RunService"):IsServer()
local Side = if isServer then Warp.Server() else Warp.Client()
local Buffer = Warp.Buffer
local Schema = Buffer.Schema

local function Hit()
	return Schema.struct({ Id = Schema.u16, Pos = Schema.vector3f32, Damage = Schema.u8 })
end

local EVENTS = {
	HitAsync = { Hit(), true },
	HitSync = { Hit(), true },
}

-- The server registers every event (and so its id) as the module loads; a
-- client applies the schemas once the ids have replicated (adapter.luau).
if isServer then
	for name, event in EVENTS do
		Side.useSchema(name, event[1])
	end
end

return { Side = Side, Events = EVENTS }
