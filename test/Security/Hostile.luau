--!nocheck
--[[
	Hostile-client test: compiles Hostile.blink in-process, loads the generated server module
	in a mock Roblox environment and throws random and crafted packets at it as an exploiter
	would (any arguments, any bytes, any instance list, at any rate).

	Asserts that no error escapes into the engine, that listeners only ever see values the
	schema allows, that the invalid packet handler is told why each packet was dropped, that
	the limits trigger, and that a packet's decode time stays bounded.

	Run from this directory:  lune run Hostile [iterations] [seed]
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Parser = require("../../src/Parser")
local Generator = require("../../src/Generator")

local ITERATIONS = tonumber(process.args[1]) or 20000
local SEED = tonumber(process.args[2]) or 1

local Failures = 0
local function Check(Condition: any, Message: string)
	if not Condition then
		Failures += 1
		print(`FAIL: {Message}`)
	end
end

---- Deterministic random numbers ----

local RandomState = SEED
local function Random(): number
	RandomState = (RandomState * 1103515245 + 12345) % 2147483648
	return RandomState / 2147483648
end
local function RandomInteger(Min: number, Max: number): number
	return Min + math.floor(Random() * (Max - Min + 1))
end
local function Pick<T>(List: { T }): T
	return List[RandomInteger(1, #List)]
end

---- Compile ----

local function Compile(Source: string): (string, string)
	local Tree = Parser.new("./", "Hostile.blink"):Parse(Source)
	return Generator.Generate("Server", Tree), Generator.Generate("Client", Tree)
end

local Schema = fs.readFile("Hostile.blink")
local ServerSource, ClientSource = Compile(Schema)

---- Mock Roblox ----

local Now = 1000 --> what os.clock returns inside the modules
local Spawned: { string } = {} --> errors raised on threads made by task.spawn (listener errors)
local Warnings: { string } = {}

local Task = {}
function Task.spawn(Callback: any, ...)
	local Thread = if type(Callback) == "thread" then Callback else coroutine.create(Callback)
	local Success, Error = coroutine.resume(Thread, ...)
	if not Success then
		--> The engine reports an error on a spawned thread and the spawner carries on
		table.insert(Spawned, tostring(Error))
	end
	return Thread
end

local function Signal()
	local Connections = {}
	return {
		Connections = Connections,
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

local DateTime = {
	fromUnixTimestamp = function(Value: number)
		return { UnixTimestamp = Value, UnixTimestampMillis = Value * 1000 }
	end,
	fromUnixTimestampMillis = function(Value: number)
		return { UnixTimestamp = Value / 1000, UnixTimestampMillis = Value }
	end,
}

local function CopyBuffer(Source: buffer): buffer
	local Copy = buffer.create(buffer.len(Source))
	buffer.copy(Copy, 0, Source)
	return Copy
end

local Players = {}

--> Server remotes: what the server sends is kept per player
local ToClient: { [any]: { { Remote: string, Buffer: buffer, Instances: { any } } } } = {}
local function ServerRemote(Name: string)
	local Remote = { OnServerEvent = Signal() }
	function Remote:FireClient(Player, Buffer, Instances)
		ToClient[Player] = ToClient[Player] or {}
		table.insert(ToClient[Player], { Remote = Name, Buffer = CopyBuffer(Buffer), Instances = table.clone(Instances) })
	end
	function Remote:FireAllClients(Buffer, Instances)
		for _, Player in Players do
			self:FireClient(Player, Buffer, Instances)
		end
	end
	return Remote
end

for Index = 1, 6 do
	Players[Index] = { Name = `Player{Index}`, UserId = Index }
end
local PlayersService = {
	PlayerAdded = Signal(),
	PlayerRemoving = Signal(),
	GetPlayers = function()
		return table.clone(Players)
	end,
}

local Remotes = {
	BLINK_RELIABLE_REMOTE = ServerRemote("Reliable"),
	BLINK_UNRELIABLE_REMOTE = ServerRemote("Unreliable"),
}

--> Client side: what the honest client sends is captured, not delivered
local Outbox: { { Remote: string, Buffer: buffer, Instances: { any } } } = {}
local ClientRemotes = {}
for Name, Channel in { BLINK_RELIABLE_REMOTE = "Reliable", BLINK_UNRELIABLE_REMOTE = "Unreliable" } do
	ClientRemotes[Name] = {
		OnClientEvent = Signal(),
		FireServer = function(_, Buffer, Instances)
			table.insert(Outbox, { Remote = Channel, Buffer = CopyBuffer(Buffer), Instances = table.clone(Instances) })
		end,
	}
end

local function Load(Source: string, IsServer: boolean)
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
				return ClientRemotes[Name]
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
			table.insert(Warnings, table.concat({ ... }, " "))
		end,
		os = setmetatable({
			clock = function()
				return Now
			end,
		}, { __index = os }),
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		BrickColor = roblox.BrickColor,
		DateTime = DateTime,
		Instance = roblox.Instance,
	}

	local Bytecode = luau.compile(Source, { optimizationLevel = 2, debugLevel = 1 })
	return luau.load(Bytecode, { debugName = IsServer and "Server" or "Client", environment = Environment })()
end

local Server = Load(ServerSource, true)
local Client = Load(ClientSource, false)

---- Instances ----

local Part = roblox.Instance.new("Part")
local Wedge = roblox.Instance.new("WedgePart")
local Model = roblox.Instance.new("Model")
local Folder = roblox.Instance.new("Folder")
local InstancePool = { Part, Wedge, Model, Folder }

---- Schema checks: what a listener may legally receive ----

local Violations: { string } = {}
local function Violation(Event: string, Message: string)
	table.insert(Violations, `{Event}: {Message}`)
end

local function IsInteger(Value: any, Min: number, Max: number): boolean
	return type(Value) == "number" and Value % 1 == 0 and Value >= Min and Value <= Max
end
local function IsFinite(Value: any): boolean
	return type(Value) == "number" and Value - Value == 0
end
local function IsString(Value: any, Min: number, Max: number): boolean
	return type(Value) == "string" and #Value >= Min and #Value <= Max and utf8.len(Value) ~= nil
end
local function IsVector(Value: any): boolean
	return typeof(Value) == "Vector3" and IsFinite(Value.X) and IsFinite(Value.Y) and IsFinite(Value.Z)
end
local function IsInstance(Value: any, Class: string): boolean
	return typeof(Value) == "Instance" and Value:IsA(Class)
end
local function IsOneOf(Value: any, List: { string }): boolean
	return table.find(List, Value) ~= nil
end

local SMALL = { "A", "B", "C" }
local BIG = { "V0", "V1", "V2", "V3", "V4", "V5", "V6", "V7" }

local function CheckInner(Value: any): string?
	if type(Value) ~= "table" then
		return "Inner is not a table"
	elseif not IsInteger(Value.Id, 1, 1000) then
		return "Inner.Id"
	elseif not IsString(Value.Name, 1, 16) then
		return "Inner.Name"
	elseif type(Value.Tags) ~= "table" or #Value.Tags > 4 then
		return "Inner.Tags"
	end
	for _, Tag in Value.Tags do
		if not IsOneOf(Tag, SMALL) then
			return "Inner.Tags item"
		end
	end
	return nil
end

local function CheckShape(Value: any): string?
	if type(Value) ~= "table" then
		return "Shape is not a table"
	elseif Value.Type == "Circle" then
		return if IsFinite(Value.Radius) then nil else "Circle.Radius"
	elseif Value.Type == "Square" then
		if not IsInteger(Value.Side, 0, 65535) then
			return "Square.Side"
		end
		return if typeof(Value.Corner) == "Vector3" then nil else "Square.Corner"
	elseif Value.Type == "Label" then
		if not IsString(Value.Text, 0, 32) then
			return "Label.Text"
		end
		return if Value.Inner == nil then nil else CheckInner(Value.Inner)
	end
	return "Shape tag"
end

local function CheckEverything(V: any): string?
	local Checks = {
		U8 = IsInteger(V.U8, 0, 255),
		U16 = IsInteger(V.U16, 10, 20),
		U32 = IsInteger(V.U32, 0, 4294967295),
		I8 = IsInteger(V.I8, -128, 127),
		I16 = IsInteger(V.I16, -5, 5),
		I32 = IsInteger(V.I32, -2147483648, 2147483647),
		F16 = IsFinite(V.F16),
		F32 = IsFinite(V.F32),
		F64 = IsFinite(V.F64),
		Bounded = IsFinite(V.Bounded) and V.Bounded >= -1 and V.Bounded <= 1,
		Bool = type(V.Bool) == "boolean",
		Str = IsString(V.Str, 0, 65535),
		Fixed = IsString(V.Fixed, 4, 4),
		Bytes = type(V.Bytes) == "buffer" and buffer.len(V.Bytes) <= 64,
		Vec = IsVector(V.Vec),
		VecI = typeof(V.VecI) == "Vector3",
		VecR = IsVector(V.VecR) and V.VecR.Magnitude <= 10,
		Frame = typeof(V.Frame) == "CFrame" and IsVector(V.Frame.Position),
		Color = typeof(V.Color) == "Color3",
		When = type(V.When) == "table" and IsFinite(V.When.UnixTimestamp),
		WhenMs = type(V.WhenMs) == "table" and IsFinite(V.WhenMs.UnixTimestampMillis),
		Brick = typeof(V.Brick) == "BrickColor",
		Part = IsInstance(V.Part, "BasePart"),
		Any = typeof(V.Any) == "Instance",
		MaybePart = V.MaybePart == nil or IsInstance(V.MaybePart, "BasePart"),
		Kind = IsOneOf(V.Kind, SMALL),
		Wide = IsOneOf(V.Wide, BIG),
		Flags = type(V.Flags) == "table",
		Map = type(V.Map) == "table",
		Nested = type(V.Nested) == "table" and #V.Nested <= 8,
		Three = type(V.Three) == "table" and #V.Three == 3,
		Opt = V.Opt == nil or IsInteger(V.Opt, 0, 255),
	}
	for Name, Passed in Checks do
		if not Passed then
			return Name
		end
	end
	for Key, Item in V.Map do
		if not IsString(Key, 1, 8) or not IsInteger(Item, 0, 255) then
			return "Map entry"
		end
	end
	for _, Item in V.Nested do
		local Problem = CheckInner(Item)
		if Problem then
			return Problem
		end
	end
	for _, Item in V.Three do
		if not IsFinite(Item) then
			return "Three item"
		end
	end
	if V.OptInner ~= nil then
		local Problem = CheckInner(V.OptInner)
		if Problem then
			return Problem
		end
	end
	return CheckShape(V.Shape)
end

---- Server listeners ----

local Received: { [string]: number } = {}
local function Got(Event: string)
	Received[Event] = (Received[Event] or 0) + 1
end
local LastBoom: { number } = {}
local LastLimited = 0

Server.Everything.On(function(Player, Value)
	Got("Everything")
	local Problem = CheckEverything(Value)
	if Problem then
		Violation("Everything", Problem)
	end
end)
Server.Input.On(function(Player, A, B, C)
	Got("Input")
	if not (IsInteger(A, 0, 255) and IsVector(B) and IsFinite(C)) then
		Violation("Input", "tuple")
	end
end)
Server.Chat.On(function(Player, Text)
	Got("Chat")
	if not IsString(Text, 0, 200) then
		Violation("Chat", "text")
	end
end)
Server.Shapes.On(function(Player, List)
	Got("Shapes")
	if type(List) ~= "table" or #List > 4 then
		Violation("Shapes", "list")
		return
	end
	for _, Shape in List do
		local Problem = CheckShape(Shape)
		if Problem then
			Violation("Shapes", Problem)
		end
	end
end)
Server.Arr.On(function(Player, List)
	Got("Arr")
	if type(List) ~= "table" or #List > 60000 then
		Violation("Arr", "list")
	end
end)
Server.Blob.On(function(Player, Blob)
	Got("Blob")
	if type(Blob) ~= "buffer" or buffer.len(Blob) > 60000 then
		Violation("Blob", "buffer")
	end
end)
Server.Touch.On(function(Player, Value)
	Got("Touch")
	if not IsInstance(Value, "BasePart") then
		Violation("Touch", "instance")
	end
end)
Server.Thing.On(function(Player, Value)
	--> unknown: anything at all may arrive, the game must check it
	Got("Thing")
end)
Server.Boom.On(function(Player, Value)
	Got("Boom")
	table.insert(LastBoom, Value)
	if not IsInteger(Value, 0, 255) then
		Violation("Boom", "value")
	end
	if Value == 13 then
		error("boom")
	end
end)
Server.Limited.On(function(Player, Value)
	Got("Limited")
	LastLimited += 1
end)
Server.Ask.On(function(Player, Value)
	Got("Ask")
	if not IsInteger(Value, 0, 255) then
		Violation("Ask", "value")
	end
	return (Value + 1) % 256
end)
Server.Slow.On(function(Player, Value)
	Got("Slow")
	coroutine.yield() --> never answers
	return 0
end)

local function DrainPolled()
	for _, Player, Value in Server.Polled.Iter() do
		Got("Polled")
		if not IsInteger(Value, 0, 1000) then
			Violation("Polled", "value")
		end
	end
end

---- Invalid packet handler ----

local Reports: { { Player: any, Reason: string, Detail: string } } = {}
local ReasonCounts: { [string]: number } = {}
local function OnInvalid(Player, Reason, Detail)
	table.insert(Reports, { Player = Player, Reason = Reason, Detail = Detail })
	ReasonCounts[Reason] = (ReasonCounts[Reason] or 0) + 1
	if type(Detail) ~= "string" then
		Violation("Handler", "detail is not a string")
	end
end
Server.SetInvalidPacketHandler(OnInvalid)

---- Delivery ----

local Escaped = 0
local Delivered = 0
local MaxPacketTime = 0
local TotalPacketTime = 0

local function Deliver(Player: any, Remote: string, ...)
	local Signal = Remotes[if Remote == "Reliable" then "BLINK_RELIABLE_REMOTE" else "BLINK_UNRELIABLE_REMOTE"].OnServerEvent
	local Start = os.clock()
	local Success, Error = pcall(Signal.Fire, Signal, Player, ...)
	local Elapsed = os.clock() - Start
	Delivered += 1
	TotalPacketTime += Elapsed
	MaxPacketTime = math.max(MaxPacketTime, Elapsed)
	if not Success then
		Escaped += 1
		if Escaped <= 5 then
			print(`error escaped into the engine: {Error}`)
		end
	end
end

local function Reset()
	table.clear(Reports)
	table.clear(ReasonCounts)
	table.clear(Spawned)
end

--> The last reason reported, for crafted single-packet checks
local function LastReason(): (string?, string?)
	local Last = Reports[#Reports]
	if Last then
		return Last.Reason, Last.Detail
	end
	return nil, nil
end

local function Bytes(List: { number }): buffer
	local Result = buffer.create(#List)
	for Index, Byte in List do
		buffer.writeu8(Result, Index - 1, Byte)
	end
	return Result
end

--> Runs Send (which fires on the honest client), flushes, returns the captured packets
local function Capture(Send: () -> ()): { { Remote: string, Buffer: buffer, Instances: { any } } }
	table.clear(Outbox)
	Send()
	Client.StepReplication()
	local Packets = table.clone(Outbox)
	table.clear(Outbox)
	return Packets
end

local function IndexOf(Send: () -> ()): number
	local Packets = Capture(Send)
	assert(#Packets == 1, "expected one packet")
	return buffer.readu8(Packets[1].Buffer, 0)
end

---- Honest values ----

local function RandomString(Min: number, Max: number): string
	local Characters = {}
	for Index = 1, RandomInteger(Min, Max) do
		Characters[Index] = string.char(RandomInteger(97, 122))
	end
	return table.concat(Characters)
end

local function RandomInner()
	local Tags = {}
	for Index = 1, RandomInteger(0, 4) do
		Tags[Index] = Pick(SMALL)
	end
	return { Id = RandomInteger(1, 1000), Name = RandomString(1, 16), Tags = Tags }
end

local function RandomShape()
	local Kind = RandomInteger(1, 3)
	if Kind == 1 then
		return { Type = "Circle", Radius = Random() * 10 }
	elseif Kind == 2 then
		return { Type = "Square", Side = RandomInteger(0, 65535), Corner = roblox.Vector3.new(1, -2, 3) }
	end
	return { Type = "Label", Text = RandomString(0, 32), Inner = if Random() < 0.5 then RandomInner() else nil }
end

local function RandomEverything()
	local Nested = {}
	for Index = 1, RandomInteger(0, 8) do
		Nested[Index] = RandomInner()
	end
	local Map = {}
	for _ = 1, RandomInteger(0, 3) do
		Map[RandomString(1, 8)] = RandomInteger(0, 255)
	end
	return {
		U8 = RandomInteger(0, 255),
		U16 = RandomInteger(10, 20),
		U32 = RandomInteger(0, 4294967295),
		I8 = RandomInteger(-128, 127),
		I16 = RandomInteger(-5, 5),
		I32 = RandomInteger(-2147483648, 2147483647),
		F16 = Random() * 100,
		F32 = Random() * 1000,
		F64 = Random() * 1e9,
		Bounded = Random() * 2 - 1,
		Bool = Random() < 0.5,
		Str = RandomString(0, 40),
		Fixed = RandomString(4, 4),
		Bytes = buffer.create(RandomInteger(0, 64)),
		Vec = roblox.Vector3.new(Random(), Random(), Random()),
		VecI = roblox.Vector3.new(1, 2, 3),
		VecR = roblox.Vector3.new(1, 1, 1),
		Frame = roblox.CFrame.new(1, 2, 3),
		Color = roblox.Color3.fromRGB(10, 20, 30),
		When = DateTime.fromUnixTimestamp(1700000000),
		WhenMs = DateTime.fromUnixTimestampMillis(1700000000000),
		Brick = roblox.BrickColor.new(1001),
		Part = Pick({ Part, Wedge }),
		Any = Pick(InstancePool),
		MaybePart = if Random() < 0.5 then Part else nil,
		Kind = Pick(SMALL),
		Wide = Pick(BIG),
		Flags = { F1 = true, F7 = Random() < 0.5 },
		Map = Map,
		Nested = Nested,
		Three = { Random(), Random(), Random() },
		Opt = if Random() < 0.5 then RandomInteger(0, 255) else nil,
		OptInner = if Random() < 0.5 then RandomInner() else nil,
		Shape = RandomShape(),
	}
end

--> One honest packet of a random kind
local function HonestPacket()
	local Kind = RandomInteger(1, 9)
	local Packets = Capture(function()
		if Kind == 1 then
			Client.Everything.Fire(RandomEverything())
		elseif Kind == 2 then
			Client.Input.Fire(RandomInteger(0, 255), roblox.Vector3.new(Random(), 2, 3), Random())
		elseif Kind == 3 then
			Client.Chat.Fire(RandomString(0, 200))
		elseif Kind == 4 then
			local List = {}
			for Index = 1, RandomInteger(0, 4) do
				List[Index] = RandomShape()
			end
			Client.Shapes.Fire(List)
		elseif Kind == 5 then
			local List = {}
			for Index = 1, RandomInteger(0, 50) do
				List[Index] = RandomInteger(0, 65535)
			end
			Client.Arr.Fire(List)
		elseif Kind == 6 then
			Client.Touch.Fire(Pick({ Part, Wedge }))
		elseif Kind == 7 then
			for _ = 1, RandomInteger(1, 5) do
				Client.Boom.Fire(RandomInteger(0, 12))
			end
		elseif Kind == 8 then
			Client.Polled.Fire(RandomInteger(0, 1000))
		else
			Client.Everything.Fire(RandomEverything())
			Client.Chat.Fire(RandomString(0, 20))
			Client.Boom.Fire(1)
		end
	end)
	return Packets[1]
end

---- 1. Honest traffic gets through untouched ----

do
	Reset()
	for _ = 1, 500 do
		Now += 1
		local Packet = HonestPacket()
		Deliver(Pick(Players), Packet.Remote, Packet.Buffer, Packet.Instances)
		DrainPolled()
	end
	Check(#Reports == 0, `honest traffic was reported invalid: {Reports[1] and Reports[1].Reason .. " " .. Reports[1].Detail}`)
	Check(Escaped == 0, "honest traffic raised an error")
	print(`honest: {Delivered} packets, Everything x{Received.Everything or 0}, no reports`)
end

---- 2. Random and mutated packets ----

do
	Reset()
	local Kinds = {}
	local function Mutate(Packet): (buffer, any)
		local Source = Packet.Buffer
		local Length = buffer.len(Source)
		local Instances: any = Packet.Instances
		local Strategy = RandomInteger(1, 8)
		if Strategy == 1 and Length > 1 then
			--> truncated
			local Cut = buffer.create(RandomInteger(1, Length - 1))
			buffer.copy(Cut, 0, Source, 0, buffer.len(Cut))
			return Cut, Instances
		elseif Strategy == 2 then
			--> random bytes flipped
			local Copy = CopyBuffer(Source)
			for _ = 1, RandomInteger(1, 4) do
				if Length > 0 then
					buffer.writeu8(Copy, RandomInteger(0, Length - 1), RandomInteger(0, 255))
				end
			end
			return Copy, Instances
		elseif Strategy == 3 then
			--> garbage appended
			local Extra = RandomInteger(1, 64)
			local Copy = buffer.create(Length + Extra)
			buffer.copy(Copy, 0, Source)
			for Index = Length, Length + Extra - 1 do
				buffer.writeu8(Copy, Index, RandomInteger(0, 255))
			end
			return Copy, Instances
		elseif Strategy == 4 then
			--> lengths and counts maxed out
			local Copy = CopyBuffer(Source)
			for Index = 1, Length - 1 do
				if Random() < 0.2 then
					buffer.writeu8(Copy, Index, 255)
				end
			end
			return Copy, Instances
		elseif Strategy == 5 then
			--> NaN / inf written over a random aligned spot
			local Copy = CopyBuffer(Source)
			if Length >= 5 then
				local Offset = RandomInteger(1, Length - 4)
				buffer.writef32(Copy, Offset, Pick({ 0 / 0, math.huge, -math.huge }))
			end
			return Copy, Instances
		elseif Strategy == 6 then
			--> instance list swapped for junk
			local Junk = {}
			for Index = 1, RandomInteger(0, 8) do
				Junk[Index] = Pick({ Part, Model, Folder, "Part", 5, {}, true, Wedge })
			end
			return Source, Junk
		elseif Strategy == 7 then
			--> invalid UTF-8 bytes sprinkled in
			local Copy = CopyBuffer(Source)
			for _ = 1, 3 do
				if Length > 1 then
					buffer.writeu8(Copy, RandomInteger(1, Length - 1), Pick({ 0xFF, 0xC0, 0x80, 0xED }))
				end
			end
			return Copy, Instances
		end
		--> fully random
		local Noise = buffer.create(RandomInteger(0, 300))
		for Index = 0, buffer.len(Noise) - 1 do
			buffer.writeu8(Noise, Index, RandomInteger(0, 255))
		end
		return Noise, if Random() < 0.5 then {} else { Part, "x" }
	end

	local WrongArguments = {
		function() return end,
		function() return "buffer" end,
		function() return 42, {} end,
		function() return {}, {} end,
		function() return buffer.create(4), "instances" end,
		function() return buffer.create(4), 7 end,
		function() return nil, nil end,
	}

	local Before = Delivered
	for Iteration = 1, ITERATIONS do
		Now += 1 --> a second between packets: the fuzz tests decoding, not rate limits
		local Player = Pick(Players)
		local Roll = Random()
		if Roll < 0.05 then
			table.insert(Kinds, "arguments")
			Deliver(Player, Pick({ "Reliable", "Unreliable" }), Pick(WrongArguments)())
		elseif Roll < 0.1 then
			local Junk = {}
			for Index = 1, RandomInteger(250, 600) do
				Junk[Index] = Part
			end
			Deliver(Player, "Reliable", buffer.create(1), Junk)
		else
			local Packet = HonestPacket()
			local Mutated, Instances = Mutate(Packet)
			local Remote = if Random() < 0.1 then Pick({ "Reliable", "Unreliable" }) else Packet.Remote
			Deliver(Player, Remote, Mutated, Instances)
		end
		DrainPolled()
	end

	print(`fuzz: {Delivered - Before} packets, reasons:`)
	for Reason, Count in ReasonCounts do
		print(`  {Reason}: {Count}`)
	end
	for _, Reason in { "InvalidArguments", "TooLarge", "UnknownEvent", "Malformed" } do
		Check((ReasonCounts[Reason] or 0) > 0, `fuzz never produced {Reason}`)
	end
	for _, Error in Spawned do
		Check(string.find(Error, "boom", 1, true), `unexpected error on a spawned thread: {Error}`)
	end
end

---- 3. Crafted attacks ----

local Attacker, Bystander = Players[1], Players[2]
--> Players the fuzz never used, so no earlier state skews the counts
local function FreshPlayer(Name: string)
	return { Name = Name, UserId = #Name }
end

local function Expect(Name: string, ExpectedReason: string?, DetailPattern: string?)
	local Reason, Detail = LastReason()
	if ExpectedReason == nil then
		Check(Reason == nil, `{Name}: expected no report, got {Reason} ({Detail})`)
	else
		Check(Reason == ExpectedReason, `{Name}: expected {ExpectedReason}, got {Reason} ({Detail})`)
		if DetailPattern and Detail then
			Check(string.find(Detail, DetailPattern, 1, true), `{Name}: detail "{Detail}" lacks "{DetailPattern}"`)
		end
	end
	Reset()
end

local INPUT = IndexOf(function()
	Client.Input.Fire(1, roblox.Vector3.new(1, 2, 3), 1)
end)
local CHAT = IndexOf(function()
	Client.Chat.Fire("hi")
end)
local ARR = IndexOf(function()
	Client.Arr.Fire({})
end)
local BLOB = IndexOf(function()
	Client.Blob.Fire(buffer.create(0))
end)
local TOUCH = IndexOf(function()
	Client.Touch.Fire(Part)
end)
local BOOM = IndexOf(function()
	Client.Boom.Fire(1)
end)
local LIMITED = IndexOf(function()
	Client.Limited.Fire(1)
end)
local UNHEARD = IndexOf(function()
	Client.Unheard.Fire(1)
end)
local function InvokeIndex(Function): number
	local Packets = Capture(function()
		Task.spawn(function()
			Function.Invoke(1)
		end)
	end)
	return buffer.readu8(Packets[1].Buffer, 0)
end
local ASK = InvokeIndex(Client.Ask)
local SLOW = InvokeIndex(Client.Slow)
local UNANSWERED = InvokeIndex(Client.Unanswered)

table.clear(ToClient)
Server.ServerOnly.FireAll(7)
Server.StepReplication()
local SERVER_ONLY = buffer.readu8(ToClient[Players[1]][1].Buffer, 0)
table.clear(ToClient)

do
	Reset()
	Now += 10

	--> Arguments
	Deliver(Attacker, "Reliable")
	Expect("no arguments", "InvalidArguments")
	Deliver(Attacker, "Reliable", "not a buffer", {})
	Expect("string buffer", "InvalidArguments", "string")
	Deliver(Attacker, "Unreliable", buffer.create(2), "not a table")
	Expect("string instances", "InvalidArguments")
	Deliver(Attacker, "Reliable", Bytes({ BOOM, 1 }), nil)
	Expect("nil instance list is fine", nil)

	--> Sizes
	Deliver(Attacker, "Reliable", buffer.create(16385), {})
	Expect("oversized packet", "TooLarge")
	local Many = {}
	for Index = 1, 257 do
		Many[Index] = Part
	end
	Deliver(Attacker, "Reliable", Bytes({ TOUCH }), Many)
	Expect("too many instances", "TooLarge")

	--> Indexes
	Deliver(Attacker, "Reliable", Bytes({ SERVER_ONLY, 7 }), {})
	Expect("server-only event index", "UnknownEvent")
	Deliver(Attacker, "Reliable", Bytes({ 250 }), {})
	Expect("unknown event index", "UnknownEvent")

	--> Values
	local Input = Bytes({ INPUT, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
	buffer.writef32(Input, 14, 0 / 0)
	local Count = Received.Input or 0
	Deliver(Attacker, "Unreliable", Input, {})
	Expect("NaN float", "Malformed", "finite")
	buffer.writef32(Input, 14, 1)
	buffer.writef32(Input, 6, math.huge)
	Deliver(Attacker, "Unreliable", Input, {})
	Expect("inf vector component", "Malformed", "finite")
	buffer.writef32(Input, 6, 2)
	Deliver(Attacker, "Unreliable", Input, {})
	Expect("valid input", nil)
	Check(Received.Input == Count + 1, "only the valid input reached the listener")

	Deliver(Attacker, "Reliable", Bytes({ CHAT, 2, 0xFF, 0xFE }), {})
	Expect("invalid UTF-8", "Malformed", "UTF-8")
	Deliver(Attacker, "Reliable", Bytes({ CHAT, 201 }), {})
	Expect("string longer than its range", "Malformed")
	Deliver(Attacker, "Reliable", Bytes({ CHAT, 50, 65, 65 }), {})
	Expect("truncated string", "Malformed")

	Deliver(Attacker, "Reliable", Bytes({ ARR, 0x60, 0xEA }), {})
	Expect("forged array length", "Malformed", "Array length exceeds")
	Deliver(Attacker, "Reliable", Bytes({ BLOB, 0x60, 0xEA }), {})
	Expect("forged buffer length", "Malformed", "Buffer length exceeds")

	Deliver(Attacker, "Reliable", Bytes({ TOUCH }), { Model })
	Expect("wrong instance class", "Malformed", "BasePart")
	Deliver(Attacker, "Reliable", Bytes({ TOUCH }), { "Part" })
	Expect("string instead of an instance", "Malformed", "Instance")
	Deliver(Attacker, "Reliable", Bytes({ TOUCH }), {})
	Expect("missing instance", "Malformed")
	Deliver(Attacker, "Reliable", Bytes({ TOUCH }), { Wedge })
	Expect("subclass instance", nil)

	--> A malformed event drops the rest of its packet, earlier events stand
	table.clear(LastBoom)
	Deliver(Attacker, "Reliable", Bytes({ BOOM, 1, CHAT, 1, 0xFF, BOOM, 2 }), {})
	Expect("malformed in the middle", "Malformed")
	Check(#LastBoom == 1 and LastBoom[1] == 1, "events after a malformed one must not be delivered")

	--> A listener error is the game's bug, not the player's: reported as an error, packet goes on
	table.clear(LastBoom)
	Deliver(Attacker, "Reliable", Bytes({ BOOM, 1, BOOM, 13, BOOM, 2 }), {})
	Check(#Reports == 0, "a listener error must not count against the player")
	Check(#LastBoom == 3 and LastBoom[3] == 2, "events after a listener error must still be delivered")
	Check(#Spawned == 1 and string.find(Spawned[1], "boom", 1, true), "the listener error must be reported")
	Check(Spawned[1] and string.find(Spawned[1], "Hostile", 1, true), "the listener error keeps its traceback")
	Reset()

	--> Events per packet
	table.clear(LastBoom)
	local Packets = Capture(function()
		for _ = 1, 300 do
			Client.Boom.Fire(3)
		end
	end)
	Deliver(Attacker, "Reliable", Packets[1].Buffer, Packets[1].Instances)
	Expect("events per packet", "TooManyEvents")
	Check(#LastBoom == 256, `the first 256 events of a long packet are delivered, got {#LastBoom}`)
end

do
	--> Rates: the clock stands still, so buckets do not refill
	Reset()
	Now += 100
	local Accepted = 0
	local Big = Capture(function()
		Client.Blob.Fire(buffer.create(10000))
	end)[1]
	for _ = 1, 20 do
		local Count = Received.Blob or 0
		Deliver(Attacker, "Reliable", Big.Buffer, Big.Instances)
		if (Received.Blob or 0) > Count then
			Accepted += 1
		end
	end
	Check(Accepted == 6, `bytes per second: expected 6 packets of 10 KB in the 64 KB burst, got {Accepted}`)
	Check(ReasonCounts.RateLimited == 14, "bytes per second reported")
	local Count = Received.Blob or 0
	Deliver(Bystander, "Reliable", Big.Buffer, Big.Instances)
	Check(Received.Blob == Count + 1, "one player's flood does not limit another")
	Now += 1
	Deliver(Attacker, "Reliable", Big.Buffer, Big.Instances)
	Check(Received.Blob == Count + 2, "the byte budget refills with time")
	Reset()

	Now += 100
	local Leaver = FreshPlayer("Leaver")
	local Before = Received.Boom or 0
	for _ = 1, 1500 do
		Deliver(Leaver, "Reliable", Bytes({ BOOM, 4 }), {})
	end
	Check((Received.Boom or 0) - Before == 1024, `events per second: expected 1024 delivered, got {(Received.Boom or 0) - Before}`)
	Check(ReasonCounts.RateLimited == 1500 - 1024, "events per second reported")
	Reset()

	--> A player who leaves takes their budget with them
	PlayersService.PlayerRemoving:Fire(Leaver)
	Before = Received.Boom or 0
	Deliver(Leaver, "Reliable", Bytes({ BOOM, 4 }), {})
	Check(Received.Boom == Before + 1, "budget state is dropped when the player leaves")
	Reset()

	--> An event's own Rate (5 per second)
	Now += 100
	LastLimited = 0
	for _ = 1, 20 do
		Deliver(Attacker, "Reliable", Bytes({ LIMITED, 1 }), {})
	end
	Check(LastLimited == 5, `Rate: 5 lets 5 through at once, got {LastLimited}`)
	Check(ReasonCounts.RateLimited == 15, "event rate reported")
	Check(Reports[1] and string.find(Reports[1].Detail, "Limited", 1, true), "event rate names the event")
	Now += 1
	Deliver(Attacker, "Reliable", Bytes({ LIMITED, 1, LIMITED, 1 }), {})
	Check(LastLimited == 7, "event rate refills")
	Reset()
end

do
	--> Functions
	Now += 100
	table.clear(ToClient)
	Deliver(Attacker, "Reliable", Bytes({ ASK, 77, 41 }), {})
	Server.StepReplication()
	local Answer = ToClient[Attacker] and ToClient[Attacker][1]
	Check(Answer ~= nil, "the caller gets an answer")
	Check(ToClient[Bystander] == nil, "no other player sees an answer")
	if Answer then
		Check(buffer.readu8(Answer.Buffer, 0) == ASK and buffer.readu8(Answer.Buffer, 1) == 77, "answer carries the caller's id")
		Check(buffer.readu8(Answer.Buffer, 2) == 1 and buffer.readu8(Answer.Buffer, 3) == 42, "answer carries the result")
	end
	table.clear(ToClient)

	--> Calls that never finish: an honest client has at most 255 waiting
	local Caller = FreshPlayer("Caller")
	for Id = 1, 300 do
		Now += 1
		Deliver(Caller, "Reliable", Bytes({ SLOW, Id % 256, 0 }), {})
	end
	Check(ReasonCounts.TooManyInvocations == 300 - 256, `calls in flight capped at 256, {ReasonCounts.TooManyInvocations} refused`)
	Reset()

	--> A function nobody listens to: queued calls are bounded, overflow is answered with an error
	table.clear(ToClient)
	local Callers = {}
	for Index = 1, 6 do
		Callers[Index] = FreshPlayer(`Queued{Index}`)
	end
	for _, Caller in Callers do
		for Id = 1, 200 do
			Now += 1
			Deliver(Caller, "Reliable", Bytes({ UNANSWERED, Id, 0 }), {})
		end
	end
	Server.StepReplication()
	local Failed = 0
	for _, Packets in ToClient do
		for _, Packet in Packets do
			for Offset = 0, buffer.len(Packet.Buffer) - 3, 3 do
				if buffer.readu8(Packet.Buffer, Offset) == UNANSWERED and buffer.readu8(Packet.Buffer, Offset + 2) == 0 then
					Failed += 1
				end
			end
		end
	end
	--> The fuzz may have queued a few calls of its own, which only adds failures
	Check(Failed >= 6 * 200 - 1024 and Failed < 6 * 200 - 1024 + 50, `calls beyond the queue limit are answered with an error, got {Failed}`)
	Reset()

	--> An event nobody listens to: its queue is bounded too
	for _ = 1, 1500 do
		Now += 1
		Deliver(Bystander, "Reliable", Bytes({ UNHEARD, 9 }), {})
	end
	local Flushed = 0
	Server.Unheard.On(function()
		Flushed += 1
	end)
	Check(Flushed == 1024, `queued events are capped at 1024, got {Flushed}`)
	Reset()
end

do
	--> The default handler warns, at most once per player every 10 seconds
	Server.SetInvalidPacketHandler(nil)
	table.clear(Warnings)
	Now += 100
	for _ = 1, 50 do
		Deliver(Attacker, "Reliable", Bytes({ 250 }), {})
	end
	Check(#Warnings == 1, `default handler is rate limited, warned {#Warnings} times`)
	Now += 11
	Deliver(Attacker, "Reliable", Bytes({ 250 }), {})
	Check(#Warnings == 2 and string.find(Warnings[2], "49 more", 1, true), "suppressed warnings are counted")
	Server.SetInvalidPacketHandler(OnInvalid)
end

---- 4. Wide schemas (u16 indexes), scopes, two-way events and functions, determinism ----

do
	local Lines = { "option ManualReplication = true", "option ServerOutput = \"a\"", "option ClientOutput = \"b\"" }
	for Index = 1, 300 do
		table.insert(Lines, `event E{Index} \{ From: Client, Type: Reliable, Call: SingleSync, Data: u16 \}`)
	end
	table.insert(Lines, "scope Inside {")
	table.insert(Lines, "\tevent Both { From: Both, Type: Reliable, Call: SingleSync, Data: u8 }")
	table.insert(Lines, "\tfunction Call { Yield: Coroutine, Data: u8, Return: u8 }")
	table.insert(Lines, "}")
	table.insert(Lines, "event Last { From: Server, Type: Reliable, Call: SingleSync, Data: u8 }")
	local WideSource = table.concat(Lines, "\n")
	local WideServer, WideClient = Compile(WideSource)

	local Again = Compile(WideSource)
	Check(Again == WideServer, "the same schema compiles to the same output")
	local Spaced = Compile(string.gsub(WideSource, "\n", "\n\n  -- a comment\n"))
	Check(Spaced == WideServer, "comments and whitespace do not move indexes")
	local Seeded = Compile("option EventIdSeed = \"other\"\n" .. WideSource)
	Check(Seeded ~= WideServer, "EventIdSeed changes the indexes")
	local Ordered = Compile("option ShuffleEventIds = false\n" .. WideSource)
	Check(string.find(Ordered, "ReliableHandlers[0] = function", 1, true) ~= nil, "ShuffleEventIds = false keeps declaration order")
	Check(string.find(WideServer, "buffer.readu16(RecieveBuffer, RecieveCursor)", 1, true) ~= nil, "u16 indexes past 256 events")

	--> Reload both sides of the wide schema and round-trip through them
	local SavedServer, SavedClient = Server, Client
	Remotes.BLINK_RELIABLE_REMOTE = ServerRemote("Reliable")
	Remotes.BLINK_UNRELIABLE_REMOTE = ServerRemote("Unreliable")
	for _, Remote in ClientRemotes do
		Remote.OnClientEvent = Signal()
	end
	local WideS = Load(WideServer, true)
	local WideC = Load(WideClient, false)
	WideS.SetInvalidPacketHandler(OnInvalid)
	local Seen = {}
	for _, Index in { 1, 150, 300 } do
		WideS[`E{Index}`].On(function(_, Value)
			Seen[Index] = Value
		end)
	end
	local BothSeen = nil
	WideS.Inside.Both.On(function(_, Value)
		BothSeen = Value
	end)
	WideS.Inside.Call.On(function(_, Value)
		return Value * 2
	end)
	Now += 100
	Reset()
	table.clear(Outbox)
	WideC.E1.Fire(11)
	WideC.E150.Fire(22)
	WideC.E300.Fire(33)
	WideC.Inside.Both.Fire(44)
	WideC.StepReplication()
	for _, Packet in Outbox do
		Deliver(Attacker, Packet.Remote, Packet.Buffer, Packet.Instances)
	end
	Check(Seen[1] == 11 and Seen[150] == 22 and Seen[300] == 33 and BothSeen == 44, "wide schema round trip")
	Check(#Reports == 0, "wide schema honest traffic is valid")

	--> Server to client on the wide schema, including the function answer
	local ClientSeen = nil
	WideC.Inside.Both.On(function(Value)
		ClientSeen = Value
	end)
	local Answer = nil
	table.clear(Outbox)
	Task.spawn(function()
		Answer = WideC.Inside.Call.Invoke(21)
	end)
	WideC.StepReplication()
	table.clear(ToClient)
	for _, Packet in Outbox do
		Deliver(Attacker, Packet.Remote, Packet.Buffer, Packet.Instances)
	end
	WideS.Inside.Both.Fire(Attacker, 55)
	WideS.StepReplication()
	for _, Packet in ToClient[Attacker] or {} do
		ClientRemotes[if Packet.Remote == "Reliable" then "BLINK_RELIABLE_REMOTE" else "BLINK_UNRELIABLE_REMOTE"].OnClientEvent:Fire(Packet.Buffer, Packet.Instances)
	end
	Check(ClientSeen == 55, "wide schema server to client")
	Check(Answer == 42, `wide schema function answer, got {Answer}`)

	Deliver(Attacker, "Reliable", Bytes({ 0xFF, 0xFF }), {})
	Expect("u16 unknown index", "UnknownEvent")
	Deliver(Attacker, "Reliable", Bytes({ 0x01 }), {})
	Expect("truncated u16 index", "Malformed")
	Server, Client = SavedServer, SavedClient
end

---- Summary ----

Check(Escaped == 0, `{Escaped} errors escaped into the engine`)
Check(#Violations == 0, `listeners saw values outside the schema: {Violations[1]}`)
local Average = TotalPacketTime / math.max(Delivered, 1)
print(string.format("packets: %d, mean %.1f us, max %.2f ms per packet", Delivered, Average * 1e6, MaxPacketTime * 1e3))
Check(MaxPacketTime < 0.05, "a packet took longer than 50 ms to handle")

if Failures > 0 then
	print(`{Failures} check(s) failed`)
	process.exit(1)
end
print("hostile client test OK")
