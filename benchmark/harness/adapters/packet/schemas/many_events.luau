--!optimize 2
-- many_events for Packet: 120 packets E001..E120; Packet takes several
-- parameters per packet, so (u8, u16) is native.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage:WaitForChild("Packet"))

local packets = {}
for e = 1, 120 do
	local name = string.format("E%03d", e)
	packets[name] = if e % 3 == 0
		then Packet(name, Packet.NumberU8, Packet.NumberU16)
		else Packet(name, Packet.NumberU16)
end
return packets
