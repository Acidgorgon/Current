--!optimize 2
-- client_input for ByteNet (see adapters/blink/schemas/client_input.blink).
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

return ByteNet.defineNamespace("client_input", function()
	return {
		Input = ByteNet.definePacket({
			value = ByteNet.struct({
				Seq = ByteNet.uint8,
				Dir = ByteNet.vec3,
				Buttons = set({ "Sprint", "Shoot", "Pass", "Tackle", "Jump", "Dive" }),
			}),
			reliabilityType = "unreliable",
		}),
		PlayerAction = ByteNet.definePacket({
			value = ByteNet.struct({
				Kind = enum({ "Shoot", "Pass", "Tackle", "Header", "Emote" }),
				Target = ByteNet.uint16,
				Power = ByteNet.float32,
			}),
		}),
	}
end)
