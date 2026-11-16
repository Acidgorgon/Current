--!optimize 2
-- per_player for QuickNet (see adapters/blink/schemas/per_player.blink).
-- Strings carry a u8 length (fine for 0..64); arrays a u16 length.
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
	Wallet = event("Wallet", false, D.NumberU32),
	Notify = event("Notify", false, D.String),
	Inventory = event("Inventory", false, { { Item = D.NumberU16, Count = D.NumberU8 } }),
	PlayerFlags = event("PlayerFlags", false, set({ "Muted", "Spectating", "Captain", "Ready", "Away", "Premium" })),
	BoostApplied = event(
		"BoostApplied",
		false,
		{ Kind = D.NumberU8, Duration = D.optional(D.NumberF32), Source = D.optional(D.NumberU16) }
	),
}
