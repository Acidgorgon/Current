--!optimize 2
-- two_way, plain remotes: a RemoteEvent is two-way by nature, so one remote
-- carries both directions (FireAllClients / OnServerEvent).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"
folder.Parent = ReplicatedStorage

local Ping = Instance.new("RemoteEvent")
Ping.Name = "Ping"
Ping.Parent = folder

return {
	pingAll = function(value)
		Ping:FireAllClients(value)
	end,
	onPing = function(cb)
		return Ping.OnServerEvent:Connect(cb)
	end,
}
