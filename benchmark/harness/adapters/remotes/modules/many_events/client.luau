--!optimize 2
-- many_events, plain remotes: one OnClientEvent per event.
local folder = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")

local on = table.create(120)
for e = 1, 120 do
	local r = folder:WaitForChild(string.format("E%03d", e))
	on[e] = function(cb)
		return r.OnClientEvent:Connect(cb)
	end
end

return { on = on }
