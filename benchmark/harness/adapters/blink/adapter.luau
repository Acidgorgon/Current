--!optimize 2
-- Blink adapter: maps the scenario API contracts (see README.md, "Adapter
-- interface") onto Blink-generated modules. Works for stock Blink and for
-- Current, since it only uses Blink's public API
-- (Fire/FireAll/FireList/FireExcept/On; replication runs on Heartbeat).
--
-- Functions are handed out directly (e.g. `fireAllReliable =
-- module.MatchReliable.FireAll`), so the harness times Blink itself with no
-- wrapper in between.

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

	two_way = {
		server = function(m)
			return {
				pingAll = m.Ping.FireAll,
				onPing = m.Ping.On,
			}
		end,
		client = function(m)
			return {
				ping = m.Ping.Fire,
				onPing = m.Ping.On,
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
		return nil, `blink adapter has no contract mapping for schema {schema}`
	end
	local path = `{dir}/{side}.luau`
	A.Mock.compileFile(path)
	return { schema = schema, side = side, path = path }
end

-- Start phase (measured as "state" heap): run the module in `env` (a server
-- or client environment of the mock world) and return the contract API.
function Adapter.start(handle, env)
	local module = env:requireFile(handle.path)
	return CONTRACTS[handle.schema][handle.side](module)
end

return Adapter
