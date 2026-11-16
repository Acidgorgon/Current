--!optimize 2
-- burst for ByteNet (see adapters/blink/schemas/burst.blink).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage:WaitForChild("ByteNet"))

return ByteNet.defineNamespace("burst", function()
	local function Hit()
		return ByteNet.struct({ Id = ByteNet.uint16, Pos = ByteNet.vec3, Damage = ByteNet.uint8 })
	end
	return {
		HitAsync = ByteNet.definePacket({ value = Hit() }),
		HitSync = ByteNet.definePacket({ value = Hit() }),
	}
end)
