--!optimize 2
-- match_state, plain remotes: listeners connect straight to OnClientEvent.
local folder = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local MatchReliable = folder:WaitForChild("MatchReliable")
local MatchUnreliable = folder:WaitForChild("MatchUnreliable")

return {
	onReliable = function(cb)
		return MatchReliable.OnClientEvent:Connect(cb)
	end,
	onUnreliable = function(cb)
		return MatchUnreliable.OnClientEvent:Connect(cb)
	end,
}
