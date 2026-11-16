--!optimize 2
-- per_player, plain remotes: listeners connect straight to OnClientEvent.
local folder = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")

local function listen(name: string)
	local r = folder:WaitForChild(name)
	return function(cb)
		return r.OnClientEvent:Connect(cb)
	end
end

return {
	onWallet = listen("Wallet"),
	onNotify = listen("Notify"),
	onInventory = listen("Inventory"),
	onFlags = listen("PlayerFlags"),
	onBoost = listen("BoostApplied"),
}
