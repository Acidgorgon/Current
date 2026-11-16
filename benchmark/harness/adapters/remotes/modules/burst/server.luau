--!optimize 2
-- burst, plain remotes: every hit is its own FireClient call. Roblox has no
-- listener modes, so HitAsync and HitSync are the same thing on two remotes.
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

local HitAsync = remote("HitAsync")
local HitSync = remote("HitSync")

return {
	hitAsync = function(player, hit)
		HitAsync:FireClient(player, hit)
	end,
	hitSync = function(player, hit)
		HitSync:FireClient(player, hit)
	end,
}
