--!optimize 2
-- two_way, plain remotes: FireServer / OnClientEvent on the same remote.
local Ping = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Ping")

return {
	ping = function(value)
		Ping:FireServer(value)
	end,
	onPing = function(cb)
		return Ping.OnClientEvent:Connect(cb)
	end,
}
