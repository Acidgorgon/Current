--!optimize 2
-- burst, plain remotes: listeners connect straight to OnClientEvent.
local folder = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local HitAsync = folder:WaitForChild("HitAsync")
local HitSync = folder:WaitForChild("HitSync")

return {
	onHitAsync = function(cb)
		return HitAsync.OnClientEvent:Connect(cb)
	end,
	onHitSync = function(cb)
		return HitSync.OnClientEvent:Connect(cb)
	end,
}
