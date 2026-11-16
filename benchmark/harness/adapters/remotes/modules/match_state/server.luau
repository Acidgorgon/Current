--!optimize 2
-- match_state, plain remotes: the snapshot table is fired as-is, once on a
-- RemoteEvent (Reliable) and once on an UnreliableRemoteEvent (Unreliable).
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

local MatchReliable = remote("RemoteEvent", "MatchReliable")
local MatchUnreliable = remote("UnreliableRemoteEvent", "MatchUnreliable")

return {
	fireAllReliable = function(state)
		MatchReliable:FireAllClients(state)
	end,
	fireAllUnreliable = function(state)
		MatchUnreliable:FireAllClients(state)
	end,
}
