--!optimize 2
-- BlinkBlox adapter: maps the scenario API contracts (see README.md, "Adapter
-- interface") onto BlinkBlox-generated modules. BlinkBlox keeps Blink's public
-- API (Fire/FireAll/FireList/FireExcept/On; replication runs on Heartbeat), so
-- this is the Blink adapter except for two_way.
--
-- Functions are handed out directly (e.g. `fireAllReliable =
-- module.MatchReliable.FireAll`), so the harness times BlinkBlox itself with
-- no wrapper in between.
--
-- two_way: BlinkBlox has no `From: Both`, so two_way.blink declares PingDown
-- (server -> client) and PingUp (client -> server) ("needs 2 declarations").
--
-- Inbound limits: BlinkBlox's defaults (64 events / 8192 bytes a packet,
-- 64 KB/s per player) are raised in every schema of adapters/blinkblox/schemas
-- exactly as BlinkBlox's own benchmark/definitions do.
--
-- The generated server sizes its polling queues with `Players.MaxPlayers`,
-- which the mock's Players service lacks; start() sets it (50, a typical
-- football server size) on the server's Players before requiring the module.

local A = ... -- { Mock = Mock, outDir = string, benchRoot = string }

local function manyEventsName(e: number): string
	return string.format("E%03d", e)
end

-- [schema] = { server = function(module) -> api, client = function(module) -> api }
local CONTRACTS = {
	match_state = {
		server = function(m)
			return {
				fireAllReliable = m.MatchReliable.FireAll,
				fireAllUnreliable = m.MatchUnreliable.FireAll,
			}
		end,
		client = function(m)
			return {
				onReliable = m.MatchReliable.On,
				onUnreliable = m.MatchUnreliable.On,
			}
		end,
	},

	per_player = {
		server = function(m)
			return {
				wallet = m.Wallet.Fire,
				notify = m.Notify.Fire,
				inventory = m.Inventory.Fire,
				flags = m.PlayerFlags.Fire,
				boost = m.BoostApplied.Fire,
			}
		end,
		client = function(m)
			return {
				onWallet = m.Wallet.On,
				onNotify = m.Notify.On,
				onInventory = m.Inventory.On,
				onFlags = m.PlayerFlags.On,
				onBoost = m.BoostApplied.On,
			}
		end,
	},

	client_input = {
		server = function(m)
			return {
				onInput = m.Input.On,
				onAction = m.PlayerAction.On,
			}
		end,
		client = function(m)
			return {
				input = m.Input.Fire,
				action = m.PlayerAction.Fire,
			}
		end,
	},

	many_events = {
		server = function(m)
			local fireAll = {}
			for e = 1, 120 do
				fireAll[e] = m[manyEventsName(e)].FireAll
			end
			return { fireAll = fireAll }
		end,
		client = function(m)
			local on = {}
			for e = 1, 120 do
				on[e] = m[manyEventsName(e)].On
			end
			return { on = on }
		end,
	},

	burst = {
		server = function(m)
			return {
				hitAsync = m.HitAsync.Fire,
				hitSync = m.HitSync.Fire,
			}
		end,
		client = function(m)
			return {
				onHitAsync = m.HitAsync.On,
				onHitSync = m.HitSync.On,
			}
		end,
	},

	-- needs 2 declarations: PingDown (server -> client), PingUp (client -> server)
	two_way = {
		server = function(m)
			return {
				pingAll = m.PingDown.FireAll,
				onPing = m.PingUp.On,
			}
		end,
		client = function(m)
			return {
				ping = m.PingUp.Fire,
				onPing = m.PingDown.On,
			}
		end,
	},
}

local Adapter = {}

-- Compile phase (measured as "code" heap): compile the side's module once.
-- Returns a handle, or nil + reason when the schema is not available.
function Adapter.compile(schema: string, side: "server" | "client")
	local dir = `{A.outDir}/{schema}`
	if readfile(`{dir}/ok`) == nil then
		return nil, `schema {schema} was not built (see {dir}/compile.log)`
	end
	if CONTRACTS[schema] == nil then
		return nil, `blinkblox adapter has no contract mapping for schema {schema}`
	end
	local path = `{dir}/{side}.luau`
	A.Mock.compileFile(path)
	return { schema = schema, side = side, path = path }
end

-- Start phase (measured as "state" heap): run the module in `env` (a server
-- or client environment of the mock world) and return the contract API.
function Adapter.start(handle, env)
	if rawget(env.Players, "MaxPlayers") == nil then
		rawset(env.Players, "MaxPlayers", 50)
	end
	local module = env:requireFile(handle.path)
	return CONTRACTS[handle.schema][handle.side](module)
end

return Adapter
