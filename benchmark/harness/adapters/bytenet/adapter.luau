--!optimize 2
-- ByteNet adapter (runtime-schema library, release 0.4.x).
--
-- Layout (see build.sh): the library is mounted on the SERVER as
-- ReplicatedStorage.ByteNet (ByteNet requires its modules through `script`),
-- so clients reach it through replication, as in a game. The client machines
-- run a second, identical copy of the files (<outDir>/_client): their replicas
-- of the library's ModuleScripts are pointed at it, so the client's compiled
-- code is counted as client code instead of being shared with the server's
-- (the mock caches compiled chunks by path).
--
-- API mapping (thin wrappers only where ByteNet's signature differs):
--   server Fire(player, v)  -> packet.sendTo(v, player)        (wrapper: argument order)
--   server FireAll(v)       -> packet.sendToAll                (direct)
--   client Fire(v)          -> packet.send                     (direct)
--   client On(cb)           -> packet.listen                   (direct; cb(value))
--   server On(cb(player,v)) -> packet.listen(fn(v, player))    (wrapper: argument order)
-- ByteNet runs every listener through task.spawn on a reused thread (there is
-- no synchronous listener mode), so Sync/Async contract variants are the same.
-- Batching: everything is written into one buffer per channel (+ one per
-- player) and sent on Heartbeat (server_step / client_step).

local A = ... -- { Mock = Mock, outDir = string, benchRoot = string }
local LIB = "ByteNet"

local function libDir(side: string): string
	return if side == "server" then `{A.outDir}/_shared/{LIB}` else `{A.outDir}/_client/{LIB}`
end

local function netPath(schema: string, side: string): string
	return if side == "server" then `{A.outDir}/{schema}/net.luau` else `{A.outDir}/_client/{schema}/net.luau`
end

-- Points a client's replicas of the server-mounted library at the client copy
-- of the files, and registers them so string requires resolve to them.
local function adoptReplicas(env, root, fromDir: string, toDir: string)
	local all = root:GetDescendants()
	table.insert(all, root)
	for _, inst in all do
		local path = rawget(inst, "_path")
		if path and string.sub(path, 1, #fromDir) == fromDir then
			local mine = toDir .. string.sub(path, #fromDir + 1)
			rawset(inst, "_path", mine)
			env.scripts[mine] = inst
		end
	end
end

local function swapArgs(packet)
	return function(cb)
		packet.listen(function(value, player)
			cb(player, value)
		end)
	end
end

local function sendTo(packet)
	local send = packet.sendTo
	return function(player, value)
		send(value, player)
	end
end

local CONTRACTS = {
	match_state = {
		server = function(m)
			return { fireAllReliable = m.MatchReliable.sendToAll, fireAllUnreliable = m.MatchUnreliable.sendToAll }
		end,
		client = function(m)
			return { onReliable = m.MatchReliable.listen, onUnreliable = m.MatchUnreliable.listen }
		end,
	},
	per_player = {
		server = function(m)
			return {
				wallet = sendTo(m.Wallet),
				notify = sendTo(m.Notify),
				inventory = sendTo(m.Inventory),
				flags = sendTo(m.PlayerFlags),
				boost = sendTo(m.BoostApplied),
			}
		end,
		client = function(m)
			return {
				onWallet = m.Wallet.listen,
				onNotify = m.Notify.listen,
				onInventory = m.Inventory.listen,
				onFlags = m.PlayerFlags.listen,
				onBoost = m.BoostApplied.listen,
			}
		end,
	},
	client_input = {
		server = function(m)
			return { onInput = swapArgs(m.Input), onAction = swapArgs(m.PlayerAction) }
		end,
		client = function(m)
			return { input = m.Input.send, action = m.PlayerAction.send }
		end,
	},
	many_events = {
		server = function(m)
			local fireAll = {}
			for e = 1, 120 do
				local packet = m[string.format("E%03d", e)]
				if e % 3 == 0 then
					-- (u8, u16) travels as a struct; ByteNet writes it into its
					-- buffer at the call, so one table per event can be reused.
					local send, pair = packet.sendToAll, { a = 0, b = 0 }
					fireAll[e] = function(a, b)
						pair.a, pair.b = a, b
						send(pair)
					end
				else
					fireAll[e] = packet.sendToAll
				end
			end
			return { fireAll = fireAll }
		end,
		client = function(m)
			local on = {}
			for e = 1, 120 do
				local packet = m[string.format("E%03d", e)]
				if e % 3 == 0 then
					on[e] = function(cb)
						packet.listen(function(pair)
							cb(pair.a, pair.b)
						end)
					end
				else
					on[e] = packet.listen
				end
			end
			return { on = on }
		end,
	},
	burst = {
		server = function(m)
			return { hitAsync = sendTo(m.HitAsync), hitSync = sendTo(m.HitSync) }
		end,
		client = function(m)
			return { onHitAsync = m.HitAsync.listen, onHitSync = m.HitSync.listen }
		end,
	},
	two_way = {
		server = function(m)
			return { pingAll = m.Ping.sendToAll, onPing = swapArgs(m.Ping) }
		end,
		client = function(m)
			return { ping = m.Ping.send, onPing = m.Ping.listen }
		end,
	},
}

local Adapter = {}

function Adapter.compile(schema: string, side: "server" | "client")
	if readfile(`{A.outDir}/{schema}/ok`) == nil then
		return nil, `schema {schema} was not built (see {A.outDir}/{schema}/compile.log)`
	end
	if CONTRACTS[schema] == nil then
		return nil, `bytenet adapter has no contract mapping for schema {schema}`
	end
	A.Mock.compileTree(libDir(side))
	A.Mock.compileFile(netPath(schema, side))
	return { schema = schema, side = side }
end

function Adapter.start(handle, env)
	if env.isServer then
		env:mountTree(libDir("server"), env.ReplicatedStorage, LIB)
	else
		adoptReplicas(env, env.ReplicatedStorage:WaitForChild(LIB), libDir("server"), libDir("client"))
	end
	local net = env:requireFile(netPath(handle.schema, handle.side))
	return CONTRACTS[handle.schema][handle.side](net)
end

return Adapter
