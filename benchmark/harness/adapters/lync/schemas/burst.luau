--!optimize 2
-- burst for Lync (see adapters/blink/schemas/burst.blink).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lync = require(ReplicatedStorage:WaitForChild("Lync"))
local U8, U16, U32 = Lync.int(0, 255), Lync.int(0, 65535), Lync.int(0, 4294967295)

local function Hit()
	return Lync.struct({ Id = U16, Pos = Lync.vec3(), Damage = U8 })
end

return {
	Lync = Lync,
	net = Lync.define("burst", {
		HitAsync = Lync.packet(Hit()),
		HitSync = Lync.packet(Hit()),
	}),
}
