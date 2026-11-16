--!optimize 2
-- two_way for ByteNet: a ByteNet packet can be sent both ways natively.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage:WaitForChild("ByteNet"))

return ByteNet.defineNamespace("two_way", function()
	return {
		Ping = ByteNet.definePacket({ value = ByteNet.uint32 }),
	}
end)
