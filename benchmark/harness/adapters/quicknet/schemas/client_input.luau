--!optimize 2
-- client_input for QuickNet (see adapters/blink/schemas/client_input.blink).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuickNet = require(ReplicatedStorage:WaitForChild("QuickNet"))
local D = QuickNet.Data

-- One event: registered on both sides (the server assigns the id), rate limit
-- lifted as BlinkBlox and QuickNet's own benchmarks do. QuickNet rewrites the
-- schema tables it is given, so every event gets fresh ones.
local function event(name: string, unreliable: boolean, ...)
	local object = QuickNet:register(name, ...):SetRateLimit(math.huge, 1)
	if unreliable then
		object = object:Unreliable()
	end
	return object
end

-- QuickNet has no set type (a struct of booleans costs 1 byte per flag);
-- Data.custom, its public extension point, gives Blink's u8 bitfield.
local function set(names: { string })
	return D.custom(function(b: buffer, offset: number, value)
		local mask = 0
		for i, n in names do
			if value[n] then
				mask += bit32.lshift(1, i - 1)
			end
		end
		buffer.writeu8(b, offset, mask)
		return 1
	end, function(b: buffer, offset: number)
		local mask = buffer.readu8(b, offset)
		local out = {}
		for i, n in names do
			out[n] = bit32.btest(mask, bit32.lshift(1, i - 1))
		end
		return out, 1
	end)
end

return {
	Input = event("Input", true, {
		Seq = D.NumberU8,
		Dir = D.Vector3F32,
		Buttons = set({ "Sprint", "Shoot", "Pass", "Tackle", "Jump", "Dive" }),
	}),
	PlayerAction = event("PlayerAction", false, {
		Kind = D.literal("Shoot", "Pass", "Tackle", "Header", "Emote"),
		Target = D.NumberU16,
		Power = D.NumberF32,
	}),
}
