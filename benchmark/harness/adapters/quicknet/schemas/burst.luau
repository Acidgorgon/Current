--!optimize 2
-- burst for QuickNet (see adapters/blink/schemas/burst.blink).
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
	HitAsync = event("HitAsync", false, { Id = D.NumberU16, Pos = D.Vector3F32, Damage = D.NumberU8 }),
	HitSync = event("HitSync", false, { Id = D.NumberU16, Pos = D.Vector3F32, Damage = D.NumberU8 }),
}
