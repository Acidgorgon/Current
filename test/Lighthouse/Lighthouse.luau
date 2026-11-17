--!nocheck
--[[
	Lighthouse hook test: compiles Lighthouse.blink in-process, loads the server and three
	clients in a mock Roblox environment with a fake shared.Lighthouse on every machine, sends
	every kind of event (Fire, FireAll, FireList, FireExcept, unreliable, client to server,
	functions) for a few frames, and checks that:
	  * the bytes reported per event match the buffers the remotes actually carried, on both
	    sides (server out == what clients received == client in, client out == server in);
	  * private sends carry their player, receives on the server carry the sender;
	  * a packet the server drops is reported as "Dropped";
	  * probes are balanced;
	  * without shared (or without shared.Lighthouse) nothing is reported and nothing breaks.

	Run from this directory:  lune run Lighthouse
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Parser = require("../../src/Parser")
local Generator = require("../../src/Generator")

local Failures = 0
local function Check(Condition: any, Message: string)
	if not Condition then
		Failures += 1
		print(`FAIL: {Message}`)
	end
end

local Tree = Parser.new("./", "Lighthouse.blink"):Parse(fs.readFile("Lighthouse.blink"))
local ServerSource = Generator.Generate("Server", Tree)
local ClientSource = Generator.Generate("Client", Tree)

---- Fake Lighthouse ----

local function FakeLighthouse()
	local Fake = { Net = {}, Probes = {}, Depth = 0, Misuse = 0, Calls = 0 }
	function Fake.probe(Name: string)
		local Probe = Fake.Probes[Name]
		if Probe == nil then
			Probe = { Begins = 0, Finishes = 0 }
			function Probe.begin(self)
				self.Begins += 1
				Fake.Depth += 1
			end
			function Probe.finish(self)
				self.Finishes += 1
				Fake.Depth -= 1
				if Fake.Depth < 0 then
					Fake.Misuse += 1
				end
			end
			Fake.Probes[Name] = Probe
		end
		return Probe
	end
	-- Net[dir][channel] = { Bytes, Calls, By = { [player] = bytes }, Anonymous = bytes }
	function Fake.net(Lib: string, Channel: string, Direction: string, Bytes: number, Player: any?)
		assert(Lib == "Current", "lib")
		assert(Direction == "in" or Direction == "out", "direction")
		assert(type(Bytes) == "number" and Bytes > 0 and Bytes % 1 == 0, `bytes {Bytes}`)
		Fake.Calls += 1
		Fake.Net[Direction] = Fake.Net[Direction] or {}
		local Entry = Fake.Net[Direction][Channel]
		if Entry == nil then
			Entry = { Bytes = 0, By = {}, Anonymous = 0 }
			Fake.Net[Direction][Channel] = Entry
		end
		Entry.Bytes += Bytes
		if Player ~= nil then
			Entry.By[Player] = (Entry.By[Player] or 0) + Bytes
		else
			Entry.Anonymous += Bytes
		end
	end
	function Fake.count() end
	function Fake.gauge() end
	return Fake
end

local function Bytes(Fake, Direction: string, Channel: string?): number
	local Total = 0
	for Name, Entry in Fake.Net[Direction] or {} do
		if Channel == nil or Name == Channel then
			Total += Entry.Bytes
		end
	end
	return Total
end

local function BytesOf(Fake, Direction: string, Player: any): number
	local Total = 0
	for _, Entry in Fake.Net[Direction] or {} do
		Total += Entry.By[Player] or 0
	end
	return Total
end

---- Mock Roblox ----

local Now = 1000
local Task = {}
function Task.spawn(Callback: any, ...)
	local Thread = if type(Callback) == "thread" then Callback else coroutine.create(Callback)
	local Success, Error = coroutine.resume(Thread, ...)
	if not Success then
		error(Error, 0)
	end
	return Thread
end

local function Signal()
	local Connections = {}
	return {
		Connect = function(_, Callback)
			table.insert(Connections, Callback)
			return { Disconnect = function() end }
		end,
		Fire = function(_, ...)
			for _, Callback in Connections do
				Callback(...)
			end
		end,
	}
end

local function CopyBuffer(Source: buffer): buffer
	local Copy = buffer.create(buffer.len(Source))
	buffer.copy(Copy, 0, Source)
	return Copy
end

local function World(WithShared: boolean, WithLighthouse: boolean)
	local W = {
		Players = {},
		Clients = {}, -- [player] = { Module, Remotes, Fake }
		Wire = {}, -- server to client: { Player, Remote, Buffer, Instances }
		Up = {}, -- client to server: { Player, Remote, Buffer, Instances }
		SentTo = {}, -- [player] = bytes the server fired to it
		SentFrom = {}, -- [player] = bytes it fired to the server
	}
	for Index = 1, 3 do
		W.Players[Index] = { Name = `Player{Index}`, UserId = Index }
	end
	local PlayersService = {
		PlayerAdded = Signal(),
		PlayerRemoving = Signal(),
		GetPlayers = function()
			return table.clone(W.Players)
		end,
	}

	local function ServerRemote(Name: string)
		local Remote = { OnServerEvent = Signal() }
		function Remote:FireClient(Player, Buffer, Instances)
			W.SentTo[Player] = (W.SentTo[Player] or 0) + buffer.len(Buffer)
			table.insert(W.Wire, { Player, Name, CopyBuffer(Buffer), Instances })
		end
		function Remote:FireAllClients(Buffer, Instances)
			for _, Player in W.Players do
				self:FireClient(Player, Buffer, Instances)
			end
		end
		return Remote
	end
	local ServerRemotes = {
		CURRENT_RELIABLE_REMOTE = ServerRemote("CURRENT_RELIABLE_REMOTE"),
		CURRENT_UNRELIABLE_REMOTE = ServerRemote("CURRENT_UNRELIABLE_REMOTE"),
	}
	W.ServerRemotes = ServerRemotes

	local function Load(Source: string, IsServer: boolean, Remotes: any, Fake: any)
		local Services = {
			Players = PlayersService,
			RunService = {
				Heartbeat = Signal(),
				IsServer = function()
					return IsServer
				end,
				IsClient = function()
					return not IsServer
				end,
				IsRunning = function()
					return true
				end,
			},
			ReplicatedStorage = {
				FindFirstChild = function(_, Name)
					return if IsServer then Remotes[Name] else nil
				end,
				WaitForChild = function(_, Name)
					return Remotes[Name]
				end,
			},
		}
		local Environment = {
			game = {
				GetService = function(_, Name)
					return Services[Name]
				end,
			},
			_G = {},
			task = Task,
			warn = function(...)
				print("warn:", ...)
			end,
			os = setmetatable({
				clock = function()
					return Now
				end,
			}, { __index = os }),
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Instance = roblox.Instance,
		}
		if WithShared then
			Environment.shared = { Lighthouse = if WithLighthouse then Fake else nil }
		end
		local Bytecode = luau.compile(Source, { optimizationLevel = 2, debugLevel = 1 })
		return luau.load(Bytecode, { debugName = if IsServer then "Server" else "Client", environment = Environment })()
	end

	W.ServerFake = FakeLighthouse()
	W.Server = Load(ServerSource, true, ServerRemotes, W.ServerFake)
	for _, Player in W.Players do
		local Remotes = {}
		for Name in ServerRemotes do
			Remotes[Name] = {
				OnClientEvent = Signal(),
				FireServer = function(_, Buffer, Instances)
					W.SentFrom[Player] = (W.SentFrom[Player] or 0) + buffer.len(Buffer)
					table.insert(W.Up, { Player, Name, CopyBuffer(Buffer), Instances })
				end,
			}
		end
		local Fake = FakeLighthouse()
		W.Clients[Player] = { Module = Load(ClientSource, false, Remotes, Fake), Remotes = Remotes, Fake = Fake }
	end

	-- one frame: everyone flushes, then everything in flight is delivered
	function W.Frame()
		Now += 1 / 60
		for _, Player in W.Players do
			W.Clients[Player].Module.StepReplication()
		end
		W.Server.StepReplication()
		while #W.Wire > 0 or #W.Up > 0 do
			local Wire, Up = W.Wire, W.Up
			W.Wire, W.Up = {}, {}
			for _, Message in Up do
				ServerRemotes[Message[2]].OnServerEvent:Fire(Message[1], Message[3], Message[4])
			end
			for _, Message in Wire do
				W.Clients[Message[1]].Remotes[Message[2]].OnClientEvent:Fire(Message[3], Message[4])
			end
			-- answers to function calls go out on the next flush
			W.Server.StepReplication()
		end
	end
	-- the modules read shared.Lighthouse at the end of a frame: start counting from the next one
	W.Frame()
	return W
end

---- Traffic ----

local function Drive(W, Frames: number)
	local Server = W.Server
	local P1, P2, P3 = W.Players[1], W.Players[2], W.Players[3]
	local Got = { Score = 0, Inventory = 0, Snapshot = 0, Chat = 0, Input = 0, Buy = 0, Ask = 0 }
	for _, Player in W.Players do
		local Client = W.Clients[Player].Module
		Client.Score.On(function() Got.Score += 1 end)
		Client.Inventory.On(function() Got.Inventory += 1 end)
		Client.Snapshot.On(function() Got.Snapshot += 1 end)
		Client.Chat.On(function() Got.Chat += 1 end)
	end
	Server.Input.On(function() Got.Input += 1 end)
	Server.Chat.On(function() Got.Chat += 1 end)
	Server.Shop.Buy.On(function() Got.Buy += 1 end)
	Server.Ask.On(function(_, Value)
		return Value + 1
	end)

	for Frame = 1, Frames do
		Server.Score.FireAll(Frame, "goal")
		Server.Inventory.Fire(P1, { 1, 2, 3, Frame })
		Server.Inventory.Fire(P2, { Frame })
		Server.Inventory.FireList({ P2, P3 }, { 7, 8 })
		Server.Chat.FireExcept(P1, "hi from the server")
		Server.Snapshot.FireAll(Frame % 256, Frame * 0.5)
		Server.Snapshot.Fire(P3, 1, 2)
		Server.Snapshot.FireList({ P1, P2 }, 3, 4)
		Server.Snapshot.FireExcept(P2, 5, 6)
		for Index, Player in W.Players do
			local Client = W.Clients[Player].Module
			Client.Input.Fire(Index)
			Client.Chat.Fire(`hello {Frame}`)
			Client.Shop.Buy.Fire(Frame)
			if Frame % 2 == 0 then
				Task.spawn(function()
					local Answer = Client.Ask.Invoke(Frame % 200)
					if Answer == Frame % 200 + 1 then
						Got.Ask += 1
					end
				end)
			end
		end
		W.Frame()
	end
	return Got
end

local function CheckWorld(W, Got, Label: string)
	local S = W.ServerFake
	Check(Got.Score > 0 and Got.Inventory > 0 and Got.Snapshot > 0 and Got.Ask > 0, `{Label}: traffic arrived`)

	-- server out == every buffer fired, in total and per event == what the clients read
	local Fired = 0
	for _, Count in W.SentTo do
		Fired += Count
	end
	Check(Bytes(S, "out") == Fired, `{Label}: server out {Bytes(S, "out")} vs fired {Fired}`)
	for _, Event in { "Score", "Inventory", "Snapshot", "Chat", "Ask" } do
		local Read = 0
		for _, Player in W.Players do
			Read += Bytes(W.Clients[Player].Fake, "in", Event)
		end
		Check(Bytes(S, "out", Event) > 0, `{Label}: server out {Event}`)
		Check(Bytes(S, "out", Event) == Read, `{Label}: {Event} out {Bytes(S, "out", Event)} vs clients in {Read}`)
	end
	-- private sends carry their player
	local Inventory = S.Net.out.Inventory
	Check(Inventory.By[W.Players[1]] ~= nil and Inventory.By[W.Players[2]] ~= nil, `{Label}: Inventory per player`)
	Check(S.Net.out.Ask.By[W.Players[1]] ~= nil, `{Label}: function returns per player`)

	for _, Player in W.Players do
		local C = W.Clients[Player].Fake
		-- client in == what the server fired to it
		Check(Bytes(C, "in") == W.SentTo[Player], `{Label}: {Player.Name} in {Bytes(C, "in")} vs sent {W.SentTo[Player]}`)
		-- client out == what it fired == what the server read from it
		Check(Bytes(C, "out") == W.SentFrom[Player], `{Label}: {Player.Name} out {Bytes(C, "out")} vs fired {W.SentFrom[Player]}`)
		Check(BytesOf(S, "in", Player) == W.SentFrom[Player], `{Label}: server in from {Player.Name}`)
		for _, Event in { "Input", "Chat", "Shop.Buy", "Ask" } do
			Check(Bytes(C, "out", Event) > 0, `{Label}: {Player.Name} out {Event}`)
			local In = S.Net["in"][Event]
			Check(In and In.By[Player] == Bytes(C, "out", Event), `{Label}: {Event} from {Player.Name}`)
		end
		Check(C.Net["in"].Dropped == nil, `{Label}: nothing dropped on {Player.Name}`)
	end
	Check(S.Net["in"].Dropped == nil, `{Label}: nothing dropped on the server`)

	for Side, Fake in { Server = S, Client = W.Clients[W.Players[1]].Fake } do
		Check(Fake.Depth == 0 and Fake.Misuse == 0, `{Label}: {Side} probes balanced`)
		for Name, Probe in Fake.Probes do
			Check(Probe.Begins == Probe.Finishes, `{Label}: {Side} {Name} balanced`)
		end
		Check(Fake.Probes["Current.Flush"].Begins > 0, `{Label}: {Side} Current.Flush used`)
		Check(Fake.Probes["Current.Receive"].Begins > 0, `{Label}: {Side} Current.Receive used`)
	end
end

do
	local W = World(true, true)
	CheckWorld(W, Drive(W, 30), "hooks")

	-- a packet the server drops is reported, with its sender
	local Player = W.Players[1]
	local Junk = buffer.create(10)
	buffer.fill(Junk, 0, 255)
	W.ServerRemotes.CURRENT_RELIABLE_REMOTE.OnServerEvent:Fire(Player, Junk)
	local Dropped = W.ServerFake.Net["in"].Dropped
	Check(Dropped and Dropped.By[Player] == 10, "dropped packet reported")
	Check(W.ServerFake.Depth == 0, "probes balanced after a dropped packet")
end

for _, Case in { { false, false, "no shared" }, { true, false, "no shared.Lighthouse" } } do
	local W = World(Case[1], Case[2])
	local Got = Drive(W, 10)
	Check(Got.Score > 0 and Got.Ask > 0, `{Case[3]}: traffic arrived`)
	Check(W.ServerFake.Calls == 0, `{Case[3]}: nothing reported`)
end

if Failures > 0 then
	print(`{Failures} failure(s)`)
	process.exit(1)
end
print("lighthouse hook test OK")
