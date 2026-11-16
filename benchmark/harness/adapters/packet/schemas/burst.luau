--!optimize 2
-- burst for Packet (see adapters/blink/schemas/burst.blink).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage:WaitForChild("Packet"))

return {
	HitAsync = Packet("HitAsync", { Id = Packet.NumberU16, Pos = Packet.Vector3F32, Damage = Packet.NumberU8 }),
	HitSync = Packet("HitSync", { Id = Packet.NumberU16, Pos = Packet.Vector3F32, Damage = Packet.NumberU8 }),
}
