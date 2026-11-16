--!optimize 2
-- client_input, plain remotes: FireServer(value).
local folder = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local Input = folder:WaitForChild("Input")
local PlayerAction = folder:WaitForChild("PlayerAction")

return {
	input = function(value)
		Input:FireServer(value)
	end,
	action = function(value)
		PlayerAction:FireServer(value)
	end,
}
