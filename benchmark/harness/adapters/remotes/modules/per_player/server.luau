--!optimize 2
-- per_player, plain remotes: one RemoteEvent per event, FireClient(player, value).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"
folder.Parent = ReplicatedStorage

local function remote(name: string)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = folder
	return r
end

local Wallet = remote("Wallet")
local Notify = remote("Notify")
local Inventory = remote("Inventory")
local PlayerFlags = remote("PlayerFlags")
local BoostApplied = remote("BoostApplied")

return {
	wallet = function(player, value)
		Wallet:FireClient(player, value)
	end,
	notify = function(player, value)
		Notify:FireClient(player, value)
	end,
	inventory = function(player, value)
		Inventory:FireClient(player, value)
	end,
	flags = function(player, value)
		PlayerFlags:FireClient(player, value)
	end,
	boost = function(player, value)
		BoostApplied:FireClient(player, value)
	end,
}
