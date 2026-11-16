--!optimize 2
-- many_events for Lync: 120 packets E001..E120. A Lync packet carries ONE
-- value, so (u8, u16) events are a struct {a, b} (24 bits); the adapter
-- packs/unpacks it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lync = require(ReplicatedStorage:WaitForChild("Lync"))
local U8, U16, U32 = Lync.int(0, 255), Lync.int(0, 65535), Lync.int(0, 4294967295)

local defs = {}
for e = 1, 120 do
	defs[string.format("E%03d", e)] = Lync.packet(if e % 3 == 0 then Lync.struct({ a = U8, b = U16 }) else U16)
end
return { Lync = Lync, net = Lync.define("many_events", defs) }
