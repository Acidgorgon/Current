--!optimize 2
-- Zap adapter: maps the scenario API contracts (see README.md, "Adapter
-- interface") onto Zap-generated modules (Zap 0.6.x, default PascalCase API).
--
-- Zap's listener API depends on the call mode: Single* events expose
-- `SetCallback(cb)`, Many* events `On(cb)`. Both take the same callback shape
-- as the contract, so they are handed out directly, like the fire functions
-- (`Fire`, `FireAll`): the harness times Zap itself with no wrapper.
--
-- two_way: Zap has no two-way events, so two_way.zap declares PingDown
-- (server -> client) and PingUp (client -> server) ("needs 2 declarations").
--
-- Zap's generated code builds a table of the 24 axis-aligned CFrames at load
-- (`CFrame.Angles`, used only by its AlignedCFrame type). The mock has no
-- CFrame, so a minimal stand-in is installed below (plain frozen tables; real
-- Roblox CFrames are userdata, so this slightly under-counts state heap).

local A = ... -- { Mock = Mock, outDir = string, benchRoot = string }

if CFrame == nil then
	CFrame = table.freeze({
		Angles = function(x: number, y: number, z: number)
			return table.freeze({ x, y, z })
		end,
	})
end

-- Listener entry point of a Zap event, whatever its call mode.
local function listen(event)
	return event.On or event.SetCallback or error("zap event has neither On nor SetCallback")
end

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
				onReliable = listen(m.MatchReliable),
				onUnreliable = listen(m.MatchUnreliable),
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
				onWallet = listen(m.Wallet),
				onNotify = listen(m.Notify),
				onInventory = listen(m.Inventory),
				onFlags = listen(m.PlayerFlags),
				onBoost = listen(m.BoostApplied),
			}
		end,
	},

	client_input = {
		server = function(m)
			return {
				onInput = listen(m.Input),
				onAction = listen(m.PlayerAction),
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
				on[e] = listen(m[manyEventsName(e)])
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
				onHitAsync = listen(m.HitAsync),
				onHitSync = listen(m.HitSync),
			}
		end,
	},

	-- needs 2 declarations: PingDown (server -> client), PingUp (client -> server)
	two_way = {
		server = function(m)
			return {
				pingAll = m.PingDown.FireAll,
				onPing = listen(m.PingUp),
			}
		end,
		client = function(m)
			return {
				ping = m.PingUp.Fire,
				onPing = listen(m.PingDown),
			}
		end,
	},
}

local Adapter = {}

function Adapter.compile(schema: string, side: "server" | "client")
	local dir = `{A.outDir}/{schema}`
	if readfile(`{dir}/ok`) == nil then
		return nil, `schema {schema} was not built (see {dir}/compile.log)`
	end
	if CONTRACTS[schema] == nil then
		return nil, `zap adapter has no contract mapping for schema {schema}`
	end
	local path = `{dir}/{side}.luau`
	A.Mock.compileFile(path)
	return { schema = schema, side = side, path = path }
end

function Adapter.start(handle, env)
	local module = env:requireFile(handle.path)
	return CONTRACTS[handle.schema][handle.side](module)
end

return Adapter
