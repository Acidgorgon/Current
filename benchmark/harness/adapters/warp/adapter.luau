--!optimize 2
-- Warp adapter (imezx/Warp 1.1.0-pre8, runtime schemas via Warp.Buffer.Schema).
--
-- Mounting: the library is mounted on the SERVER as ReplicatedStorage.Warp;
-- Warp creates its remotes under its own ModuleScript, so clients find them
-- through replication. Clients run their own copy of the files (see
-- adapters/bytenet/adapter.luau, adoptReplicas).
--
-- Startup handshake: a Warp client only knows event ids after the server has
-- answered its `_repl` request (Warp's documented `Client.awaitReady()`); until
-- then Connect/useSchema warn and do nothing. The mock cannot yield, so the
-- client start pumps the mock network once (client -> server request, server
-- reply -> client) before applying schemas and handing out the API. The
-- handshake traffic happens before warmup, so it is not in the per-frame stats.
--
-- API mapping: Warp addresses events by name on every call, so every entry is
-- a thin closure: Fire(player, v) -> Server.Fire(name, reliable, player, v),
-- FireAll(v) -> Server.Fires(name, reliable, v), On(cb) -> Connect(name, cb)
-- (server listeners already get (player, value)). Warp queues the argument
-- tables per player and serialises them on PostSimulation (server_step /
-- client_step); every listener runs on a reused thread (no sync mode).

local A = ... -- { Mock = Mock, outDir = string, benchRoot = string }
local LIB = "Warp"

local function libDir(side: string): string
	return if side == "server" then `{A.outDir}/_shared/{LIB}` else `{A.outDir}/_client/{LIB}`
end

local function netPath(schema: string, side: string): string
	return if side == "server" then `{A.outDir}/{schema}/net.luau` else `{A.outDir}/_client/{schema}/net.luau`
end

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

-- Contract builders over a Warp side (Server or Client module).
local function fireTo(S, name, reliable)
	local fire = S.Fire
	return function(player, value)
		fire(name, reliable, player, value)
	end
end
local function fireAll(S, name, reliable)
	local fires = S.Fires
	return function(value)
		fires(name, reliable, value)
	end
end
local function fireServer(S, name, reliable)
	local fire = S.Fire
	return function(value)
		fire(name, reliable, value)
	end
end
local function on(S, name)
	local connect = S.Connect
	return function(cb)
		connect(name, cb)
	end
end

local CONTRACTS = {
	match_state = {
		server = function(S)
			return { fireAllReliable = fireAll(S, "MatchReliable", true), fireAllUnreliable = fireAll(S, "MatchUnreliable", false) }
		end,
		client = function(S)
			return { onReliable = on(S, "MatchReliable"), onUnreliable = on(S, "MatchUnreliable") }
		end,
	},
	per_player = {
		server = function(S)
			return {
				wallet = fireTo(S, "Wallet", true),
				notify = fireTo(S, "Notify", true),
				inventory = fireTo(S, "Inventory", true),
				flags = fireTo(S, "PlayerFlags", true),
				boost = fireTo(S, "BoostApplied", true),
			}
		end,
		client = function(S)
			return {
				onWallet = on(S, "Wallet"),
				onNotify = on(S, "Notify"),
				onInventory = on(S, "Inventory"),
				onFlags = on(S, "PlayerFlags"),
				onBoost = on(S, "BoostApplied"),
			}
		end,
	},
	client_input = {
		server = function(S)
			return { onInput = on(S, "Input"), onAction = on(S, "PlayerAction") }
		end,
		client = function(S)
			return { input = fireServer(S, "Input", false), action = fireServer(S, "PlayerAction", true) }
		end,
	},
	many_events = {
		server = function(S)
			local all = {}
			for e = 1, 120 do
				local name = string.format("E%03d", e)
				if e % 3 == 0 then
					-- (u8, u16) travels as a struct. Warp keeps the argument by
					-- reference until its PostSimulation flush; each event is
					-- fired at most once per frame here, so one table per event
					-- can be reused safely.
					local fires, pair = S.Fires, { a = 0, b = 0 }
					all[e] = function(a, b)
						pair.a, pair.b = a, b
						fires(name, true, pair)
					end
				else
					all[e] = fireAll(S, name, true)
				end
			end
			return { fireAll = all }
		end,
		client = function(S)
			local all = {}
			for e = 1, 120 do
				local name = string.format("E%03d", e)
				if e % 3 == 0 then
					all[e] = function(cb)
						S.Connect(name, function(pair)
							cb(pair.a, pair.b)
						end)
					end
				else
					all[e] = on(S, name)
				end
			end
			return { on = all }
		end,
	},
	burst = {
		server = function(S)
			return { hitAsync = fireTo(S, "HitAsync", true), hitSync = fireTo(S, "HitSync", true) }
		end,
		client = function(S)
			return { onHitAsync = on(S, "HitAsync"), onHitSync = on(S, "HitSync") }
		end,
	},
	two_way = {
		server = function(S)
			return { pingAll = fireAll(S, "Ping", true), onPing = on(S, "Ping") }
		end,
		client = function(S)
			return { ping = fireServer(S, "Ping", true), onPing = on(S, "Ping") }
		end,
	},
}

local Adapter = {}

function Adapter.compile(schema: string, side: "server" | "client")
	if readfile(`{A.outDir}/{schema}/ok`) == nil then
		return nil, `schema {schema} was not built (see {A.outDir}/{schema}/compile.log)`
	end
	if CONTRACTS[schema] == nil then
		return nil, `warp adapter has no contract mapping for schema {schema}`
	end
	A.Mock.compileTree(libDir(side))
	A.Mock.compileFile(netPath(schema, side))
	return { schema = schema, side = side }
end

function Adapter.start(handle, env)
	if env.isServer then
		env:mountTree(libDir("server"), env.ReplicatedStorage, LIB)
		local net = env:requireFile(netPath(handle.schema, "server"))
		return CONTRACTS[handle.schema].server(net.Side)
	end
	adoptReplicas(env, env.ReplicatedStorage:WaitForChild(LIB), libDir("server"), libDir("client"))
	local net = env:requireFile(netPath(handle.schema, "client")) -- fires Warp's _repl request
	-- Handshake (Client.awaitReady): request -> server, id table -> this client.
	local world = env.world
	world:deliver()
	world:receiveServer()
	world:deliver()
	world:receiveClient(env.index)
	for name, event in net.Events do
		net.Side.useSchema(name, event[1])
	end
	return CONTRACTS[handle.schema].client(net.Side)
end

return Adapter
