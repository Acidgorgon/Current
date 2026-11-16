--!optimize 2
-- Shared driver for match_state_reliable / match_state_unreliable.
-- Contract (schema match_state):
--   server: fireAllReliable(state), fireAllUnreliable(state)
--   client: onReliable(cb(state)), onUnreliable(cb(state))
--   state = { Ball: vector, Clock: f32, HomeScore: u8, AwayScore: u8,
--             Phase: "Warmup"|"Kickoff"|"Play"|"Goal"|"HalfTime"|"FullTime",
--             Players: { {Id: u16, Pos: vector(f32), Vel: vector(f16 precision ok),
--                         Stamina: u8, State: "Idle"|"Jogging"|"Sprinting"|"Dribbling"|"Tackling"|"Diving"} } (22) }
--   Reliable listeners may be ManyAsync-style (own thread), Unreliable SingleSync.
-- The server broadcasts the full match snapshot (22 players) with FireAll
-- every frame (30 Hz) to 44 clients.

local H = ...

local PHASES = { "Warmup", "Kickoff", "Play", "Goal", "HalfTime", "FullTime" }
local STANCES = { "Idle", "Jogging", "Sprinting", "Dribbling", "Tackling", "Diving" }
local ON_FIELD = 22

-- variant: "Reliable" | "Unreliable"
return function(variant: string)
	local fireName, onName = "fireAll" .. variant, "on" .. variant
	local S = {
		schema = "match_state",
		clients = 44,
		api = { server = { fireName }, client = { onName } },
	}

	local state -- the snapshot the server sends (mutated in place every frame)
	local received = {} -- [client] = last snapshot received
	local recvCount = {} -- [client] = number of snapshots received
	local expectedCount = 0

	function S.setup(ctx)
		local list = table.create(ON_FIELD)
		for p = 1, ON_FIELD do
			list[p] = { Id = p, Pos = vector.zero, Vel = vector.zero, Stamina = 0, State = "Idle" }
		end
		state = { Ball = vector.zero, Clock = 0, HomeScore = 0, AwayScore = 0, Phase = "Play", Players = list }

		for i = 1, ctx.nclients do
			recvCount[i] = 0
			ctx.clients[i][onName](function(value)
				received[i] = value
				recvCount[i] += 1
				-- touch the payload so decoding cannot be skipped
				ctx.sink += value.Clock + value.Players[1].Stamina
			end)
		end
	end

	function S.prepare(ctx, f: number)
		state.Clock = f * 0.03125 -- exactly representable in f32
		state.Ball = vector.create(f % 105 - 52.5, (f % 7) * 0.5, f % 68 - 34)
		state.HomeScore = (f // 97) % 256
		state.AwayScore = (f // 131) % 256
		state.Phase = PHASES[(f // 50) % 6 + 1]
		for p = 1, ON_FIELD do
			local ps = state.Players[p]
			ps.Pos = vector.create((f + p * 13) % 105 - 52.5, 0.25 * (p % 3), (f * 3 + p * 7) % 68 - 34)
			-- quarter steps in [-8, 8): exactly representable in f16
			ps.Vel = vector.create(((f + p) % 64 - 32) * 0.25, 0, ((f * 2 + p) % 64 - 32) * 0.25)
			ps.Stamina = (f + p * 7) % 256
			ps.State = STANCES[(f + p) % 6 + 1]
		end
	end

	function S.serverSend(ctx, f: number)
		ctx.server[fireName](state)
	end

	local function verifyPlayer(got, want, what)
		H.eq(got.Id, want.Id, what .. ".Id")
		H.vecNear(got.Pos, want.Pos, 0, what .. ".Pos")
		H.vecNear(got.Vel, want.Vel, 1e-3, what .. ".Vel")
		H.eq(got.Stamina, want.Stamina, what .. ".Stamina")
		H.eq(got.State, want.State, what .. ".State")
	end

	local function verifySnapshot(got, full: boolean, f: number, what: string)
		H.eq(got.Clock, state.Clock, what .. ".Clock")
		H.eq(#got.Players, ON_FIELD, what .. ".#Players")
		if full then
			H.vecNear(got.Ball, state.Ball, 0, what .. ".Ball")
			H.eq(got.HomeScore, state.HomeScore, what .. ".HomeScore")
			H.eq(got.AwayScore, state.AwayScore, what .. ".AwayScore")
			H.eq(got.Phase, state.Phase, what .. ".Phase")
			for p = 1, ON_FIELD do
				verifyPlayer(got.Players[p], state.Players[p], `{what}.Players[{p}]`)
			end
		else
			local p = f % ON_FIELD + 1
			verifyPlayer(got.Players[p], state.Players[p], `{what}.Players[{p}]`)
		end
	end

	function S.verify(ctx, f: number, full: boolean)
		expectedCount += 1
		local sampled = f % ctx.nclients + 1
		for i = 1, ctx.nclients do
			H.eq(recvCount[i], expectedCount, `client {i} snapshot count`)
			verifySnapshot(received[i], full or i == sampled, f, `client {i}`)
		end
	end

	return S
end
