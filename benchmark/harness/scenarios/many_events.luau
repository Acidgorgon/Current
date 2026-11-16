--!optimize 2
-- many_events: an IDL with 120 server->client reliable events (E001..E120).
-- Every frame the server FireAll's 24 of them, chosen to cover the whole index
-- range (the selection rotates each frame), to 44 clients. This stresses the
-- client's receive dispatch (stock Blink: linear if/elseif chain on the index).
-- Events whose number is divisible by 3 carry (u8, u16), the others a u16.

local H = ...

local EVENTS = 120
local PER_FRAME = 24

-- Contract (schema many_events):
--   server: fireAll[e](a[, b])  for e = 1..120; events with e % 3 == 0 take (u8, u16), others a u16
--   client: on[e](cb(a[, b]))
--   The 120 events are distinct (each library declares 120 separate events).
local S = {
	schema = "many_events",
	clients = 44,
	api = { server = { "fireAll" }, client = { "on" } },
}

local fireAll = {} -- [e] = server FireAll function
local isPack = {} -- [e] = carries (u8, u16)
local chosen = table.create(PER_FRAME) -- event numbers fired this frame
local sentA = table.create(PER_FRAME)
local sentB = table.create(PER_FRAME)

-- Per client flat arrays indexed by event number: last values received.
local gotA, gotB, gotCount = {}, {}, {}
local frameCount = 0

local function eventName(e: number): string
	return string.format("E%03d", e)
end

function S.setup(ctx)
	for e = 1, EVENTS do
		fireAll[e] = ctx.server.fireAll[e]
		isPack[e] = e % 3 == 0
	end
	for i = 1, ctx.nclients do
		local a, b = table.create(EVENTS, false), table.create(EVENTS, false)
		gotA[i], gotB[i], gotCount[i] = a, b, 0
		local net = ctx.clients[i]
		for e = 1, EVENTS do
			if isPack[e] then
				net.on[e](function(x, y)
					a[e] = x
					b[e] = y
					gotCount[i] += 1
				end)
			else
				net.on[e](function(x)
					a[e] = x
					gotCount[i] += 1
				end)
			end
		end
	end
end

function S.prepare(ctx, f: number)
	-- 24 distinct events spaced 5 apart, rotating with the frame number:
	-- over 5 frames every event index is hit.
	for j = 1, PER_FRAME do
		local e = (f + (j - 1) * 5) % EVENTS + 1
		chosen[j] = e
		sentA[j] = if isPack[e] then (f + j) % 256 else (f * 31 + e) % 65536
		sentB[j] = (f * 7 + e * 3) % 65536
	end
end

function S.serverSend(ctx, f: number)
	for j = 1, PER_FRAME do
		local e = chosen[j]
		if isPack[e] then
			fireAll[e](sentA[j], sentB[j])
		else
			fireAll[e](sentA[j])
		end
	end
end

function S.verify(ctx, f: number, full: boolean)
	frameCount += 1
	local sampled = f % ctx.nclients + 1
	for i = 1, ctx.nclients do
		H.eq(gotCount[i], frameCount * PER_FRAME, `client {i} event count`)
		if full or i == sampled then
			local a, b = gotA[i], gotB[i]
			for j = 1, PER_FRAME do
				local e = chosen[j]
				H.eq(a[e], sentA[j], `client {i} {eventName(e)} value`)
				if isPack[e] then
					H.eq(b[e], sentB[j], `client {i} {eventName(e)} second value`)
				end
			end
		end
	end
end

return S
