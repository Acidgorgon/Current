--!optimize 2
-- Packet adapter (Suphi Kaner's Packet 1.7, runtime schemas).
--
-- Mounting: the module tree is mounted on the SERVER as
-- ReplicatedStorage.Packet; Packet creates its single RemoteEvent under its
-- own ModuleScript and publishes packet ids as attributes on it, which clients
-- read through replication. Clients run their own copy of the files (see
-- adapters/bytenet/adapter.luau, adoptReplicas).
--
-- API mapping: Packet's fire functions are methods, so sends are thin
-- closures: Fire(player, v) -> p:FireClient(player, v), FireAll(v) ->
-- p:Fire(v) (on the server Fire goes to every client), client Fire(v) ->
-- p:Fire(v). Listeners connect straight to p.OnClientEvent / p.OnServerEvent
-- (server listeners get (player, value)). Packet defers EVERY listener call
-- (task.defer of a pooled thread), so there is no sync mode; deferred threads
-- run at the end of the receive phase. Packet has ONE reliable RemoteEvent and
-- no unreliable channel: the contract's unreliable events go reliably.
-- Sends are written into one buffer for FireAll plus one per player and sent
-- on Heartbeat (deferred), i.e. in server_step / client_step.

local A = ... -- { Mock = Mock, outDir = string, benchRoot = string }
local LIB = "Packet"

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

local function fireTo(p)
	return function(player, ...)
		p:FireClient(player, ...)
	end
end
local function fire(p)
	return function(...)
		p:Fire(...)
	end
end
local fireAll, fireServer = fire, fire
-- Packet has a single (deferred) listener mode.
local function on(signal)
	return function(cb)
		signal:Connect(cb)
	end
end
local onSync, onAsync = on, on

local CONTRACTS = {
	match_state = {
		server = function(m)
			return { fireAllReliable = fireAll(m.MatchReliable), fireAllUnreliable = fireAll(m.MatchUnreliable) }
		end,
		client = function(m)
			return {
				onReliable = onAsync(m.MatchReliable.OnClientEvent),
				onUnreliable = onSync(m.MatchUnreliable.OnClientEvent),
			}
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
				onWallet = onSync(m.Wallet.OnClientEvent),
				onNotify = onAsync(m.Notify.OnClientEvent),
				onInventory = onSync(m.Inventory.OnClientEvent),
				onFlags = onSync(m.PlayerFlags.OnClientEvent),
				onBoost = onSync(m.BoostApplied.OnClientEvent),
			}
		end,
	},
	client_input = {
		server = function(m)
			return { onInput = onSync(m.Input.OnServerEvent), onAction = onAsync(m.PlayerAction.OnServerEvent) }
		end,
		client = function(m)
			return { input = fireServer(m.Input), action = fireServer(m.PlayerAction) }
		end,
	},
	many_events = {
		server = function(m)
			local all = {}
			for e = 1, 120 do
				all[e] = fireAll(m[string.format("E%03d", e)])
			end
			return { fireAll = all }
		end,
		client = function(m)
			local all = {}
			for e = 1, 120 do
				all[e] = onSync(m[string.format("E%03d", e)].OnClientEvent)
			end
			return { on = all }
		end,
	},
	burst = {
		server = function(m)
			return { hitAsync = fireTo(m.HitAsync), hitSync = fireTo(m.HitSync) }
		end,
		client = function(m)
			return { onHitAsync = onAsync(m.HitAsync.OnClientEvent), onHitSync = onSync(m.HitSync.OnClientEvent) }
		end,
	},
	two_way = {
		server = function(m)
			return { pingAll = fireAll(m.Ping), onPing = onSync(m.Ping.OnServerEvent) }
		end,
		client = function(m)
			return { ping = fireServer(m.Ping), onPing = onSync(m.Ping.OnClientEvent) }
		end,
	},
}

local Adapter = {}

function Adapter.compile(schema: string, side: "server" | "client")
	if readfile(`{A.outDir}/{schema}/ok`) == nil then
		return nil, `schema {schema} was not built (see {A.outDir}/{schema}/compile.log)`
	end
	if CONTRACTS[schema] == nil then
		return nil, `packet adapter has no contract mapping for schema {schema}`
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
