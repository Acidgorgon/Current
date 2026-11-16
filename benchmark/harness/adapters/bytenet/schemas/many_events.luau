--!optimize 2
-- many_events for ByteNet: 120 packets E001..E120 (see the Blink schema).
-- A ByteNet packet carries ONE value, so the (u8, u16) events are a struct
-- {a: u8, b: u16} (same 3 bytes on the wire); the adapter packs/unpacks it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage:WaitForChild("ByteNet"))

return ByteNet.defineNamespace("many_events", function()
	local packets = {}
	for e = 1, 120 do
		local value = if e % 3 == 0
			then ByteNet.struct({ a = ByteNet.uint8, b = ByteNet.uint16 })
			else ByteNet.uint16
		packets[string.format("E%03d", e)] = ByteNet.definePacket({ value = value })
	end
	return packets
end)
