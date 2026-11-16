--!optimize 2
-- per_player for ByteNet (see adapters/blink/schemas/per_player.blink).
-- Differences: string and array lengths are u16.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage:WaitForChild("ByteNet"))

-- ByteNet has no enum or set type. Its data types are plain {read, write}
-- tables over its own bufferWriter, so these two are written the way its
-- built-in types are, giving the same wire encoding as Blink (enum: u8 index,
-- set: u8 bitfield).
local bufferWriter = require(ReplicatedStorage.ByteNet.process.bufferWriter)
local writeU8 = bufferWriter.u8

local function enum(names: { string })
	local index = {}
	for i, name in names do
		index[name] = i - 1
	end
	return {
		read = function(b: buffer, cursor: number)
			return names[buffer.readu8(b, cursor) + 1], 1
		end,
		write = function(value: string)
			writeU8(index[value])
		end,
	}
end

local function set(names: { string })
	return {
		read = function(b: buffer, cursor: number)
			local mask = buffer.readu8(b, cursor)
			local out = {}
			for i, name in names do
				out[name] = bit32.btest(mask, bit32.lshift(1, i - 1))
			end
			return out, 1
		end,
		write = function(value: { [string]: boolean })
			local mask = 0
			for i, name in names do
				if value[name] then
					mask += bit32.lshift(1, i - 1)
				end
			end
			writeU8(mask)
		end,
	}
end

return ByteNet.defineNamespace("per_player", function()
	return {
		Wallet = ByteNet.definePacket({ value = ByteNet.uint32 }),
		Notify = ByteNet.definePacket({ value = ByteNet.string }),
		Inventory = ByteNet.definePacket({
			value = ByteNet.array(ByteNet.struct({ Item = ByteNet.uint16, Count = ByteNet.uint8 })),
		}),
		PlayerFlags = ByteNet.definePacket({
			value = set({ "Muted", "Spectating", "Captain", "Ready", "Away", "Premium" }),
		}),
		BoostApplied = ByteNet.definePacket({
			value = ByteNet.struct({
				Kind = ByteNet.uint8,
				Duration = ByteNet.optional(ByteNet.float32),
				Source = ByteNet.optional(ByteNet.uint16),
			}),
		}),
	}
end)
