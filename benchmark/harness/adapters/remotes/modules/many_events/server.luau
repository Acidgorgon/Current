--!optimize 2
-- many_events, plain remotes: 120 RemoteEvents E001..E120. Events with
-- e % 3 == 0 carry two arguments (u8, u16), the others one (u16).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"
folder.Parent = ReplicatedStorage

local fireAll = table.create(120)
for e = 1, 120 do
	local r = Instance.new("RemoteEvent")
	r.Name = string.format("E%03d", e)
	r.Parent = folder
	if e % 3 == 0 then
		fireAll[e] = function(a, b)
			r:FireAllClients(a, b)
		end
	else
		fireAll[e] = function(a)
			r:FireAllClients(a)
		end
	end
end

return { fireAll = fireAll }
