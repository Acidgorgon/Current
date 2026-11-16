--!optimize 2
-- Shared driver for burst_async / burst_sync: one server, ONE client, and the
-- server Fire(player, hit)'s 200 events to that client in a single frame.

local H = ...

local BURST = 200

-- Contract (schema burst):
--   server: hitAsync(player, hit), hitSync(player, hit)   hit = {Id: u16, Pos: vector(f32), Damage: u8}
--   client: onHitAsync(cb(hit)) (ManyAsync-style), onHitSync(cb(hit)) (SingleSync-style)
-- variant: "Async" | "Sync"
return function(variant: string)
	local fireName, onName = "hit" .. variant, "onHit" .. variant
	local S = {
		schema = "burst",
		clients = 1,
		api = { server = { fireName }, client = { onName } },
	}

	local hits = table.create(BURST) -- sent payloads, mutated in place
	-- Received values, flat arrays indexed by arrival order (no allocation).
	local gotId = table.create(BURST, 0)
	local gotPos = table.create(BURST, vector.zero)
	local gotDamage = table.create(BURST, 0)
	local gotCount = 0

	function S.setup(ctx)
		for k = 1, BURST do
			hits[k] = { Id = 0, Pos = vector.zero, Damage = 0 }
		end
		ctx.clients[1][onName](function(hit)
			gotCount += 1
			gotId[gotCount] = hit.Id
			gotPos[gotCount] = hit.Pos
			gotDamage[gotCount] = hit.Damage
		end)
	end

	function S.prepare(ctx, f: number)
		for k = 1, BURST do
			local hit = hits[k]
			hit.Id = (f * BURST + k) % 65536
			hit.Pos = vector.create(k * 0.5, f % 50, -k)
			hit.Damage = (f + k) % 256
		end
		gotCount = 0
	end

	function S.serverSend(ctx, f: number)
		local fire = ctx.server[fireName]
		local player = ctx.players[1]
		for k = 1, BURST do
			fire(player, hits[k])
		end
	end

	function S.verify(ctx, f: number, full: boolean)
		H.eq(gotCount, BURST, "events received this frame")
		for k = 1, BURST, if full then 1 else 17 do
			local hit = hits[k]
			H.eq(gotId[k], hit.Id, `hit {k} Id`)
			H.vecNear(gotPos[k], hit.Pos, 0, `hit {k} Pos`)
			H.eq(gotDamage[k], hit.Damage, `hit {k} Damage`)
		end
	end

	return S
end
