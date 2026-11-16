--!optimize 2
-- two_way for Packet: one packet, fired both ways (native).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage:WaitForChild("Packet"))

return { Ping = Packet("Ping", Packet.NumberU32) }
