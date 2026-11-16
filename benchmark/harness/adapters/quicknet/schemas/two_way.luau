--!optimize 2
-- two_way for QuickNet: one event object, fired both ways (native).
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

return {
	Ping = event("Ping", false, D.NumberU32),
}
