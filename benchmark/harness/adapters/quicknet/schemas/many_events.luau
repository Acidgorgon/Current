--!optimize 2
-- many_events for QuickNet: 120 events E001..E120; QuickNet events take
-- several arguments, so (u8, u16) is native.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuickNet = require(ReplicatedStorage:WaitForChild("QuickNet"))
local D = QuickNet.Data

-- One event: registered on both sides (the server assigns the id), rate limit
-- lifted as BlinkBlox and QuickNet's own benchmarks do. QuickNet rewrites the
-- schema tables it is given, so every event gets fresh ones.
local function event(name: string, unreliable: boolean, ...)
	local object = QuickNet:register(name, ...):SetRateLimit(math.huge, 1)
	if unreliable then
		object = object:Unreliable()
	end
	return object
end

local events = {}
for e = 1, 120 do
	local name = string.format("E%03d", e)
	events[name] = if e % 3 == 0 then event(name, false, D.NumberU8, D.NumberU16) else event(name, false, D.NumberU16)
end
return events
