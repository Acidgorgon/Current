--!optimize 2
-- per_player: every frame the server sends each of its 44 players five small
-- reliable events with Fire(player, ...):
--   Wallet (u32, SingleSync), Notify (string(0..64), ManyAsync),
--   Inventory ({Item: u16, Count: u8}[0..16], SingleSync),
--   PlayerFlags (set of 6 flags, SingleSync), BoostApplied (struct with two
--   optional fields, ManySync).

local H = ...

local FLAG_KEYS = { "Muted", "Spectating", "Captain", "Ready", "Away", "Premium" }

-- Contract (schema per_player):
--   server: wallet(player, u32), notify(player, string 0..64),
--           inventory(player, { {Item: u16, Count: u8} } 0..16),
--           flags(player, {Muted, Spectating, Captain, Ready, Away, Premium: boolean}),
--           boost(player, {Kind: u8, Duration: f32?, Source: u16?})
--   client: onWallet(cb), onNotify(cb), onInventory(cb), onFlags(cb), onBoost(cb)
local S = {
	schema = "per_player",
	clients = 44,
	api = {
		server = { "wallet", "notify", "inventory", "flags", "boost" },
		client = { "onWallet", "onNotify", "onInventory", "onFlags", "onBoost" },
	},
}

-- Payload pools, built once so the driver allocates nothing per frame.
local notifyPool = {}
local flagPool = {}
local boostPool = {}
local inventoryPool = {} -- [player] = { [len 0..4] = array }

-- What was sent this frame, per player.
local sentWallet, sentNotify, sentInventory, sentFlags, sentBoost = {}, {}, {}, {}, {}
-- What each client received this frame.
local gotWallet, gotNotify, gotInventory, gotFlags, gotBoost = {}, {}, {}, {}, {}
local gotCount = {}
local frameCount = 0

function S.setup(ctx)
	for i = 0, 31 do
		-- lengths 0..62, includes the empty string
		notifyPool[i + 1] = string.rep(string.char(65 + i % 26), i * 2)
	end
	for mask = 0, 63 do
		local set = {}
		for b, key in FLAG_KEYS do
			set[key] = bit32.btest(mask, bit32.lshift(1, b - 1))
		end
		flagPool[mask + 1] = set
	end
	boostPool[1] = { Kind = 1 }
	boostPool[2] = { Kind = 2, Duration = 2.5 }
	boostPool[3] = { Kind = 3, Source = 777 }
	boostPool[4] = { Kind = 4, Duration = 0.125, Source = 65535 }

	for i = 1, ctx.nclients do
		local pool = {}
		for len = 0, 4 do
			local arr = table.create(len)
			for k = 1, len do
				arr[k] = { Item = 0, Count = 0 }
			end
			pool[len] = arr
		end
		inventoryPool[i] = pool
		gotCount[i] = 0

		local net = ctx.clients[i]
		net.onWallet(function(value)
			gotWallet[i] = value
			gotCount[i] += 1
		end)
		net.onNotify(function(value)
			gotNotify[i] = value
			gotCount[i] += 1
			ctx.sink += #value
		end)
		net.onInventory(function(value)
			gotInventory[i] = value
			gotCount[i] += 1
			ctx.sink += #value
		end)
		net.onFlags(function(value)
			gotFlags[i] = value
			gotCount[i] += 1
		end)
		net.onBoost(function(value)
			gotBoost[i] = value
			gotCount[i] += 1
			ctx.sink += value.Kind
		end)
	end
end

function S.prepare(ctx, f: number)
	for i = 1, ctx.nclients do
		sentWallet[i] = (f * 1000 + i * 7919) % 4294967296
		sentNotify[i] = notifyPool[(f + i) % 32 + 1]
		local inv = inventoryPool[i][(f + i) % 5]
		for k = 1, #inv do
			local item = inv[k]
			item.Item = (f * 31 + i * 17 + k) % 65536
			item.Count = (f + k) % 256
		end
		sentInventory[i] = inv
		sentFlags[i] = flagPool[(f + i) % 64 + 1]
		sentBoost[i] = boostPool[(f + i) % 4 + 1]
	end
end

function S.serverSend(ctx, f: number)
	local net = ctx.server
	local Wallet, Notify, Inventory, PlayerFlags, BoostApplied = net.wallet, net.notify, net.inventory, net.flags, net.boost
	local players = ctx.players
	for i = 1, ctx.nclients do
		local player = players[i]
		Wallet(player, sentWallet[i])
		Notify(player, sentNotify[i])
		Inventory(player, sentInventory[i])
		PlayerFlags(player, sentFlags[i])
		BoostApplied(player, sentBoost[i])
	end
end

local function verifyClient(i: number, full: boolean)
	H.eq(gotWallet[i], sentWallet[i], `client {i} Wallet`)
	H.eq(gotNotify[i], sentNotify[i], `client {i} Notify`)
	local inv, want = gotInventory[i], sentInventory[i]
	H.eq(#inv, #want, `client {i} #Inventory`)
	if full then
		for k = 1, #want do
			H.eq(inv[k].Item, want[k].Item, `client {i} Inventory[{k}].Item`)
			H.eq(inv[k].Count, want[k].Count, `client {i} Inventory[{k}].Count`)
		end
		H.setEq(gotFlags[i], sentFlags[i], FLAG_KEYS, `client {i} PlayerFlags`)
		local b, wb = gotBoost[i], sentBoost[i]
		H.eq(b.Kind, wb.Kind, `client {i} Boost.Kind`)
		H.eq(b.Duration, wb.Duration, `client {i} Boost.Duration`)
		H.eq(b.Source, wb.Source, `client {i} Boost.Source`)
	end
end

function S.verify(ctx, f: number, full: boolean)
	frameCount += 1
	local sampled = f % ctx.nclients + 1
	for i = 1, ctx.nclients do
		H.eq(gotCount[i], frameCount * 5, `client {i} event count`)
		verifyClient(i, full or i == sampled)
	end
end

return S
