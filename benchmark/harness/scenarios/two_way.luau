--!optimize 2
-- two_way (FORK-ONLY): one `From: Both` event. Every frame the server
-- FireAll's a u32 to 44 clients and every client Fire's a u32 back on the same
-- event. Stock Blink cannot compile two_way.blink, so this scenario is skipped
-- for variants whose compile of it fails.

local H = ...

-- Contract (schema two_way):
--   server: pingAll(u32), onPing(cb(player, u32))
--   client: ping(u32), onPing(cb(u32))
local S = {
	schema = "two_way",
	clients = 44,
	api = { server = { "pingAll", "onPing" }, client = { "ping", "onPing" } },
}

local sentDown = 0
local gotDown, gotDownCount = {}, {}
local gotUp, gotUpCount = {}, {}
local frameCount = 0

function S.setup(ctx)
	for i = 1, ctx.nclients do
		gotDownCount[i] = 0
		gotUpCount[i] = 0
		ctx.clients[i].onPing(function(value)
			gotDown[i] = value
			gotDownCount[i] += 1
		end)
	end
	local playerIndex = ctx.playerIndex
	ctx.server.onPing(function(player, value)
		local i = playerIndex[player]
		gotUp[i] = value
		gotUpCount[i] += 1
	end)
end

function S.prepare(ctx, f: number)
	sentDown = (f * 2654435761) % 4294967296
end

function S.serverSend(ctx, f: number)
	ctx.server.pingAll(sentDown)
end

function S.clientSend(ctx, f: number, i: number)
	ctx.clients[i].ping((f * 64 + i) % 4294967296)
end

function S.verify(ctx, f: number, full: boolean)
	frameCount += 1
	for i = 1, ctx.nclients do
		H.eq(gotDownCount[i], frameCount, `client {i} Ping (server->client) count`)
		H.eq(gotDown[i], sentDown, `client {i} Ping (server->client) value`)
		H.eq(gotUpCount[i], frameCount, `client {i} Ping (client->server) count`)
		H.eq(gotUp[i], (f * 64 + i) % 4294967296, `client {i} Ping (client->server) value`)
	end
end

return S
