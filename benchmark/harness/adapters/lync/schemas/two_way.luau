--!optimize 2
-- two_way for Lync: a Lync packet can be fired both ways (native).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lync = require(ReplicatedStorage:WaitForChild("Lync"))
local U8, U16, U32 = Lync.int(0, 255), Lync.int(0, 65535), Lync.int(0, 4294967295)

return { Lync = Lync, net = Lync.define("two_way", { Ping = Lync.packet(U32) }) }
