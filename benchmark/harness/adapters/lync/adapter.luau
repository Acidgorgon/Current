--!optimize 2
-- Lync adapter (Axp3cter/Lync 4.0.x, bit-packed runtime schemas).
--
-- Mounting: the library is mounted on the SERVER as ReplicatedStorage.Lync;
-- Lync puts each namespace's remotes under ReplicatedStorage.LyncRemotes,
-- found by clients through replication. Clients run their own copy of the
-- files (see adapters/bytenet/adapter.luau, adoptReplicas).
--
-- Lifecycle, as Lync's guide prescribes: require the definitions, then
-- Lync.start(), and call Lync.flush() every frame from PostSimulation (a
-- closure, since a signal passing dt straight to flush would be read as a
-- byte budget). A client is only reachable once its handshake (hello ->
-- verdict) has completed; packets fired at a joining client are dropped. The
-- mock cannot yield, so the client start pumps the mock network until the
-- verdict has arrived. This happens before warmup and is not in the stats.
--
-- API mapping (Lync's fire/listen functions are methods, so all are thin
-- closures): Fire(player, v) -> p:fireClient(player, v), FireAll(v) ->
-- p:fireClient(Lync.all, v), client Fire(v) -> p:fireServer(v), client
-- On(cb) -> p:onClient(cb), server On(cb(player, v)) -> p:onServer(fn(v,
-- player)). Every Lync listener runs on its own pooled thread (no sync mode).

local A = ... -- { Mock = Mock, outDir = string, benchRoot = string }
local LIB = "Lync"
local DT = 1 / 30

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

local ALL -- Lync.all (set at start)

local function fireTo(p)
	return function(player, value)
		p:fireClient(player, value)
	end
end
local function fireAll(p)
	return function(value)
		p:fireClient(ALL, value)
	end
end
local function fireServer(p)
	return function(value)
		p:fireServer(value)
	end
end
local function onClient(p)
	return function(cb)
		p:onClient(cb)
	end
end
local function onServer(p)
	return function(cb)
		p:onServer(function(value, player)
			cb(player, value)
		end)
	end
end

local CONTRACTS = {
	match_state = {
		server = function(m)
			return { fireAllReliable = fireAll(m.MatchReliable), fireAllUnreliable = fireAll(m.MatchUnreliable) }
		end,
		client = function(m)
			return { onReliable = onClient(m.MatchReliable), onUnreliable = onClient(m.MatchUnreliable) }
		end,
	},
	per_player = {
		server = function(m)
			return {
				wallet = fireTo(m.Wallet),
				notify = fireTo(m.Notify),
				inventory = fireTo(m.Inventory),
				flags = fireTo(m.PlayerFlags),
				boost = fireTo(m.BoostApplied),
			}
		end,
		client = function(m)
			return {
				onWallet = onClient(m.Wallet),
				onNotify = onClient(m.Notify),
				onInventory = onClient(m.Inventory),
				onFlags = onClient(m.PlayerFlags),
				onBoost = onClient(m.BoostApplied),
			}
		end,
	},
	client_input = {
		server = function(m)
			return { onInput = onServer(m.Input), onAction = onServer(m.PlayerAction) }
		end,
		client = function(m)
			return { input = fireServer(m.Input), action = fireServer(m.PlayerAction) }
		end,
	},
	many_events = {
		server = function(m)
			local all = {}
			for e = 1, 120 do
				local p = m[string.format("E%03d", e)]
				if e % 3 == 0 then
					-- (u8, u16) travels as a struct. Each event is fired at most
					-- once per frame, so one table per event can be reused even
					-- if the library kept it until its flush.
					local pair = { a = 0, b = 0 }
					all[e] = function(a, b)
						pair.a, pair.b = a, b
						p:fireClient(ALL, pair)
					end
				else
					all[e] = fireAll(p)
				end
			end
			return { fireAll = all }
		end,
		client = function(m)
			local all = {}
			for e = 1, 120 do
				local p = m[string.format("E%03d", e)]
				if e % 3 == 0 then
					all[e] = function(cb)
						p:onClient(function(pair)
							cb(pair.a, pair.b)
						end)
					end
				else
					all[e] = onClient(p)
				end
			end
			return { on = all }
		end,
	},
	burst = {
		server = function(m)
			return { hitAsync = fireTo(m.HitAsync), hitSync = fireTo(m.HitSync) }
		end,
		client = function(m)
			return { onHitAsync = onClient(m.HitAsync), onHitSync = onClient(m.HitSync) }
		end,
	},
	two_way = {
		server = function(m)
			return { pingAll = fireAll(m.Ping), onPing = onServer(m.Ping) }
		end,
		client = function(m)
			return { ping = fireServer(m.Ping), onPing = onClient(m.Ping) }
		end,
	},
}

local Adapter = {}

function Adapter.compile(schema: string, side: "server" | "client")
	if readfile(`{A.outDir}/{schema}/ok`) == nil then
		return nil, `schema {schema} was not built (see {A.outDir}/{schema}/compile.log)`
	end
	if CONTRACTS[schema] == nil then
		return nil, `lync adapter has no contract mapping for schema {schema}`
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
	local defs = env:requireFile(netPath(handle.schema, handle.side))
	local Lync = defs.Lync
	ALL = Lync.all
	Lync.start()
	env.RunService.PostSimulation:Connect(function()
		Lync.flush()
	end)
	if not env.isServer then
		-- Handshake: hello -> server, verdict -> this client (a couple of
		-- network round trips through the mock, stepping both machines).
		local world = env.world
		for _ = 1, 3 do
			world:stepClient(env.index, DT)
			world:deliver()
			world:receiveServer()
			world:stepServer(DT)
			world:deliver()
			world:receiveClient(env.index)
		end
	end
	return CONTRACTS[handle.schema][handle.side](defs.net)
end

return Adapter
