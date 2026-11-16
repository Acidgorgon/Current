--!optimize 2
-- client_input, plain remotes: Input on an UnreliableRemoteEvent, PlayerAction
-- on a RemoteEvent; server listeners connect straight to OnServerEvent
-- (which passes (player, value), the contract's callback shape).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"
folder.Parent = ReplicatedStorage

local function remote(className: string, name: string)
	local r = Instance.new(className)
	r.Name = name
	r.Parent = folder
	return r
end

local Input = remote("UnreliableRemoteEvent", "Input")
local PlayerAction = remote("RemoteEvent", "PlayerAction")

return {
	onInput = function(cb)
		return Input.OnServerEvent:Connect(cb)
	end,
	onAction = function(cb)
		return PlayerAction.OnServerEvent:Connect(cb)
	end,
}
