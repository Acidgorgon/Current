--!optimize 2
-- client_input: every frame each of the 44 clients fires its input state
-- (Unreliable, SingleSync on the server: u8 seq, vector dir, set of buttons),
-- and every 4th frame (staggered per client) a reliable gameplay action
-- (ManyAsync on the server).

local H = ...

local BUTTONS = { "Sprint", "Shoot", "Pass", "Tackle", "Jump", "Dive" }
local ACTIONS = { "Shoot", "Pass", "Tackle", "Header", "Emote" }

-- Contract (schema client_input):
--   client: input({Seq: u8, Dir: vector, Buttons: {Sprint, Shoot, Pass, Tackle, Jump, Dive: boolean}})  (unreliable)
--           action({Kind: "Shoot"|"Pass"|"Tackle"|"Header"|"Emote", Target: u16, Power: f32})  (reliable)
--   server: onInput(cb(player, input)), onAction(cb(player, action))
local S = {
	schema = "client_input",
	clients = 44,
	api = { server = { "onInput", "onAction" }, client = { "input", "action" } },
}

local buttonPool = {}
local inputs = {} -- [client] = InputFrame table, mutated in place
local actions = {} -- [client] = Action table, mutated in place
local sendsAction = {} -- [client] = whether an action was sent this frame

local gotInput = {} -- [client] = last input received by the server
local gotInputCount = {}
local gotAction = {}
local gotActionCount = {}
local sentActionCount = {}
local frameCount = 0

function S.setup(ctx)
	for mask = 0, 63 do
		local set = {}
		for b, key in BUTTONS do
			set[key] = bit32.btest(mask, bit32.lshift(1, b - 1))
		end
		buttonPool[mask + 1] = set
	end
	for i = 1, ctx.nclients do
		inputs[i] = { Seq = 0, Dir = vector.zero, Buttons = buttonPool[1] }
		actions[i] = { Kind = "Shoot", Target = 0, Power = 0 }
		gotInputCount[i] = 0
		gotActionCount[i] = 0
		sentActionCount[i] = 0
	end

	local playerIndex = ctx.playerIndex
	ctx.server.onInput(function(player, input)
		local i = playerIndex[player]
		gotInput[i] = input
		gotInputCount[i] += 1
		ctx.sink += input.Seq
	end)
	ctx.server.onAction(function(player, action)
		local i = playerIndex[player]
		gotAction[i] = action
		gotActionCount[i] += 1
		ctx.sink += action.Power
	end)
end

function S.prepare(ctx, f: number)
	for i = 1, ctx.nclients do
		local input = inputs[i]
		input.Seq = (f + i) % 256
		input.Dir = vector.create(((f + i) % 17 - 8) * 0.125, 0, ((f * 3 + i) % 17 - 8) * 0.125)
		input.Buttons = buttonPool[(f * 5 + i) % 64 + 1]

		local send = (f + i) % 4 == 0
		sendsAction[i] = send
		if send then
			local action = actions[i]
			action.Kind = ACTIONS[(f + i) % 5 + 1]
			action.Target = (f * 13 + i) % 65536
			action.Power = ((f + i) % 100) * 0.5
			sentActionCount[i] += 1
		end
	end
end

function S.clientSend(ctx, f: number, i: number)
	local net = ctx.clients[i]
	net.input(inputs[i])
	if sendsAction[i] then
		net.action(actions[i])
	end
end

function S.verify(ctx, f: number, full: boolean)
	frameCount += 1
	local sampled = f % ctx.nclients + 1
	for i = 1, ctx.nclients do
		H.eq(gotInputCount[i], frameCount, `client {i} input count`)
		H.eq(gotActionCount[i], sentActionCount[i], `client {i} action count`)
		local input, want = gotInput[i], inputs[i]
		H.eq(input.Seq, want.Seq, `client {i} Input.Seq`)
		if full or i == sampled then
			H.vecNear(input.Dir, want.Dir, 0, `client {i} Input.Dir`)
			H.setEq(input.Buttons, want.Buttons, BUTTONS, `client {i} Input.Buttons`)
			if sendsAction[i] then
				local a, wa = gotAction[i], actions[i]
				H.eq(a.Kind, wa.Kind, `client {i} Action.Kind`)
				H.eq(a.Target, wa.Target, `client {i} Action.Target`)
				H.eq(a.Power, wa.Power, `client {i} Action.Power`)
			end
		end
	end
end

return S
