--!optimize 2
-- two_way for Warp: one event name used in both directions (native).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Warp = require(ReplicatedStorage:WaitForChild("Warp"))
local isServer = game:GetService("RunService"):IsServer()
local Side = if isServer then Warp.Server() else Warp.Client()
local Buffer = Warp.Buffer
local Schema = Buffer.Schema

local EVENTS = {
	Ping = { Schema.u32, true },
}

-- The server registers every event (and so its id) as the module loads; a
-- client applies the schemas once the ids have replicated (adapter.luau).
if isServer then
	for name, event in EVENTS do
		Side.useSchema(name, event[1])
	end
end

return { Side = Side, Events = EVENTS }
