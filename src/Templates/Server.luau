return [[local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- SPLIT --
if not RunService:IsServer() then
    error("Server network module can only be required from the server.")
end

local Reliable: RemoteEvent = ReplicatedStorage:FindFirstChild(BASE_EVENT_NAME .. "_RELIABLE_REMOTE") :: RemoteEvent
if not Reliable then
    local RemoteEvent = Instance.new("RemoteEvent")
    RemoteEvent.Name = BASE_EVENT_NAME .. "_RELIABLE_REMOTE"
    RemoteEvent.Parent = ReplicatedStorage
    Reliable = RemoteEvent
end

local Unreliable: UnreliableRemoteEvent = ReplicatedStorage:FindFirstChild(BASE_EVENT_NAME .. "_UNRELIABLE_REMOTE") :: UnreliableRemoteEvent
if not Unreliable then
    local UnreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")
    UnreliableRemoteEvent.Name = BASE_EVENT_NAME .. "_UNRELIABLE_REMOTE"
    UnreliableRemoteEvent.Parent = ReplicatedStorage
    Unreliable = UnreliableRemoteEvent
end

--> Unreliable sends: the event was serialized past the end of the loaded writer, from Start.
--> Every send leaves out the instance array when it is empty: an empty table would still
--> be serialized by the remote and rebuilt by the receiver on every packet.
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local SendUnreliable
SendUnreliable = function(Player: Player, Start: number, InstanceStart: number)
    local Packet, Instances = Cut(Start, InstanceStart)
    if Instances then
        Unreliable:FireClient(Player, Packet, Instances)
    else
        Unreliable:FireClient(Player, Packet)
    end
end

--> Declared then assigned so the compiler does not inline it into every event (native code size)
local SendUnreliableAll
SendUnreliableAll = function(Start: number, InstanceStart: number)
    local Packet, Instances = Cut(Start, InstanceStart)
    if Instances then
        Unreliable:FireAllClients(Packet, Instances)
    else
        Unreliable:FireAllClients(Packet)
    end
end

--> Declared then assigned so the compiler does not inline it into every event (native code size)
local SendUnreliableList
SendUnreliableList = function(List: {Player}, Start: number, InstanceStart: number)
    local Packet, Instances = Cut(Start, InstanceStart)
    for _, Player in List do
        if Instances then
            Unreliable:FireClient(Player, Packet, Instances)
        else
            Unreliable:FireClient(Player, Packet)
        end
    end
end

--> Declared then assigned so the compiler does not inline it into every event (native code size)
local SendUnreliableExcept
SendUnreliableExcept = function(Except: Player, Start: number, InstanceStart: number)
    local Packet, Instances = Cut(Start, InstanceStart)
    for _, Player in Players:GetPlayers() do
        if Player ~= Except then
            if Instances then
                Unreliable:FireClient(Player, Packet, Instances)
            else
                Unreliable:FireClient(Player, Packet)
            end
        end
    end
end

--> SECURITY. Everything a client sends is hostile: an exploiter can call FireServer with any arguments,
--> any bytes and any instance list, as often as it likes. Every packet goes through Admit
--> (argument types, size caps, per-player byte and event budgets) before any of it is read,
--> then is decoded under one xpcall per packet (see Recover), so a malformed packet is dropped and
--> reported instead of throwing into the engine. Limits are the MAX_* and *_PER_SECOND constants.
export type InvalidPacketReason =
    "InvalidArguments" --> the remote was called with something other than (buffer, {Instance}?)
    | "TooLarge" --> more than MaxPacketBytes bytes or MaxPacketInstances instances
    | "TooManyEvents" --> more than MaxEventsPerPacket events in one packet
    | "RateLimited" --> over the player's bytes/events per second, or an event's own Rate
    | "UnknownEvent" --> an event index the server does not listen to
    | "Malformed" --> did not decode: truncated, out of range, bad enum, NaN, bad UTF-8, wrong instance...
    | "TooManyInvocations" --> more than 256 function calls waiting for an answer

--> Per player: [1] byte tokens, [2] event tokens, [3] refill clock, [4] function calls in flight,
--> [5] clock of the last default warning, [6] warnings suppressed since, [7...] per-event Rate
--> buckets (tokens, clock). Removed on PlayerRemoving; weak keys catch a packet that arrives later.
local Budgets: {[Player]: {number}} = setmetatable({} :: any, { __mode = "k" })
local CurrentBudget: {number} = {}
local EventCount = 0
local EventLimit = 0
--> True while a Sync listener runs inside the packet's xpcall: its errors are the game's, not the packet's
local ListenerRunning = false
local NoInstances = table.freeze({})
local InvalidHandler: ((Player: Player, Reason: InvalidPacketReason, Detail: string) -> ())? = nil

local function SetInvalidPacketHandler(Handler: ((Player: Player, Reason: InvalidPacketReason, Detail: string) -> ())?)
    InvalidHandler = Handler
end

--> A dropped packet. The game's handler runs on its own thread (it may yield, kick or error);
--> without one, at most one warning per player every 10 seconds.
local function Invalid(Player: Player, Reason: InvalidPacketReason, Detail: string)
    local Handler = InvalidHandler
    if Handler ~= nil then
        task.spawn(Handler, Player, Reason, Detail)
        return
    end

    local Budget = Budgets[Player]
    local Now = os.clock()
    if Budget ~= nil then
        if Now - Budget[5] < 10 then
            Budget[6] += 1
            return
        end
        Budget[5] = Now
    end

    local Suppressed = if Budget ~= nil and Budget[6] > 0 then ` ({Budget[6]} more since the last warning)` else ""
    if Budget ~= nil then
        Budget[6] = 0
    end
    warn(`[Current]: Dropped a packet from {Player.Name} ({Player.UserId}): {Reason}: {Detail}{Suppressed}`)
end

--> Admit's slow path: a player's first packet, wrong argument types, or a packet over a limit.
--> Same checks as Admit, in order, and reports the first one that fails.
local function Screen(Player: Player, Buffer: any, Instances: any): {number}?
    local Now = os.clock()
    local Budget = Budgets[Player]
    if Budget == nil then
        Budget = { BYTES_BURST, EVENTS_BURST, Now, 0, -math.huge, 0 }
        Budgets[Player] = Budget
    end

    if type(Buffer) ~= "buffer" then
        Invalid(Player, "InvalidArguments", `Expected a buffer, got {typeof(Buffer)}`)
        return nil
    end

    local InstanceCount = 0
    if Instances ~= nil then
        if type(Instances) ~= "table" then
            Invalid(Player, "InvalidArguments", `Expected an instance list, got {typeof(Instances)}`)
            return nil
        end
        InstanceCount = #Instances
    end

    local Size = buffer.len(Buffer)
    if Size > MAX_PACKET_BYTES or InstanceCount > MAX_PACKET_INSTANCES then
        Invalid(Player, "TooLarge", `{Size} bytes, {InstanceCount} instances`)
        return nil
    end

    --> Token buckets, refilled by the time since this player's last packet
    local Elapsed = Now - Budget[3]
    Budget[3] = Now
    local Bytes = math.min(BYTES_BURST, Budget[1] + Elapsed * BYTES_PER_SECOND)
    local Events = math.min(EVENTS_BURST, Budget[2] + Elapsed * EVENTS_PER_SECOND)
    Budget[2] = Events
    local Cost = Size + InstanceCount * INSTANCE_BYTES
    if Cost > Bytes or Events < 1 then
        Budget[1] = Bytes
        Invalid(Player, "RateLimited", if Events < 1 then "Events per second" else "Bytes per second")
        return nil
    end
    Budget[1] = Bytes - Cost

    EventCount = 0
    EventLimit = math.min(Events, MAX_EVENTS_PER_PACKET)
    CurrentBudget = Budget
    return Budget
end

--> Checks a packet before any of it is read. Returns the player's budget, or nil to drop it.
--> The common case (a known player, the right types, within every limit) changes nothing
--> until it has passed every check; anything else goes to Screen, which repeats them and reports.
local function Admit(Player: Player, Buffer: any, Instances: any): {number}?
    ListenerRunning = false
    local Budget = Budgets[Player]
    if Budget == nil or type(Buffer) ~= "buffer" or (Instances ~= nil and type(Instances) ~= "table") then
        return Screen(Player, Buffer, Instances)
    end

    local Size = buffer.len(Buffer)
    local InstanceCount = if Instances then #Instances else 0
    local Now = os.clock()
    local Elapsed = Now - Budget[3]
    local Bytes = math.min(BYTES_BURST, Budget[1] + Elapsed * BYTES_PER_SECOND)
    local Events = math.min(EVENTS_BURST, Budget[2] + Elapsed * EVENTS_PER_SECOND)
    local Cost = Size + InstanceCount * INSTANCE_BYTES
    if Size > MAX_PACKET_BYTES or InstanceCount > MAX_PACKET_INSTANCES or Cost > Bytes or Events < 1 then
        return Screen(Player, Buffer, Instances)
    end

    Budget[1] = Bytes - Cost
    Budget[2] = Events
    Budget[3] = Now
    EventCount = 0
    EventLimit = math.min(Events, MAX_EVENTS_PER_PACKET)
    CurrentBudget = Budget
    return Budget
end

--> xpcall message handler: a listener's error keeps its traceback, a decode error its message
local function Traceback(Message: any): any
    if ListenerRunning then
        return debug.traceback(tostring(Message), 2)
    end
    return Message
end

--> An event's own Rate (events per second per player). Over it, the event is dropped and reported.
local function Allow(Player: Player, Slot: number, Rate: number, Burst: number, Name: string): boolean
    local Budget = CurrentBudget
    local Now = os.clock()
    local Tokens = Budget[Slot]
    if Tokens == nil then
        Tokens = Burst
    else
        Tokens = math.min(Burst, Tokens + (Now - Budget[Slot + 1]) * Rate)
    end
    Budget[Slot + 1] = Now
    if Tokens < 1 then
        Budget[Slot] = Tokens
        Invalid(Player, "RateLimited", `Event "{Name}"`)
        return false
    end
    Budget[Slot] = Tokens - 1
    return true
end

--> A function call was answered: give its in-flight slot back
local function Release(Player: Player)
    local Budget = Budgets[Player]
    if Budget ~= nil and Budget[4] > 0 then
        Budget[4] -= 1
    end
end

Players.PlayerRemoving:Connect(function(Player)
    Budgets[Player] = nil
end)

-- RELIABLE --
--> Reliable traffic. FireAll only appends to the broadcast log (the Home writer),
--> so its cost does not grow with the player count. A player's own writer only
--> holds private events, plus the slice of the broadcast log that came before
--> them (copied in lazily by CatchUp) so ordering is preserved.
local PlayersMap: {[Player]: Writer} = {}

--> Declared then assigned so the compiler does not inline it into every event (native code size)
local CreateWriter
CreateWriter = function(Player: Player, Synced: number, SyncedInstances: number): Writer
    local Writer = NewWriter()
    Writer.Synced = Synced
    Writer.SyncedInstances = SyncedInstances
    PlayersMap[Player] = Writer
    return Writer
end

--> Set when any player's writer may hold something the broadcast log does not
--> (a private event, a FireExcept mark, a mid-frame join). While it is false,
--> StepReplication sends the log to everyone with one FireAllClients.
local Private = false

--> Players that left. A send to one after PlayerRemoving goes to a detached
--> writer that is dropped, instead of re-adding them to PlayersMap for good.
local Departed: {[Player]: boolean} = setmetatable({} :: any, { __mode = "k" })

--> Appends the part of the broadcast log the loaded writer has not seen yet.
--> Home must be saved before calling.
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local CatchUp
CatchUp = function(Writer: Writer)
    local Synced = Writer.Synced
    local Count = Home.Cursor - Synced
    if Count > 0 then
        local Position = Allocate(Count)
        buffer.copy(SendBuffer, Position, Home.Buffer, Synced, Count)
        Writer.Synced = Home.Cursor
    end

    local HomeInstances = Home.Instances
    local InstanceCount = #HomeInstances
    local SyncedInstances = Writer.SyncedInstances
    if InstanceCount > SyncedInstances then
        table.move(HomeInstances, SyncedInstances + 1, InstanceCount, #SendInstances + 1, SendInstances)
        Writer.SyncedInstances = InstanceCount
    end
end

--> The player whose writer is loaded (Current), or nil. Sends to that player only
--> compare it, without looking up their writer.
local CurrentPlayer: Player? = nil

--> Makes Writer the loaded writer. A player's writer is caught up with the
--> broadcast log first, so events stay in the order they were sent.
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local Switch
Switch = function(Writer: Writer)
    Save(Current)
    Load(Writer)
    Current = Writer
    CurrentPlayer = nil
    if Writer ~= Home then
        Private = true
        if Writer.Synced ~= Home.Cursor or Writer.SyncedInstances ~= #Home.Instances then
            CatchUp(Writer)
        end
    end
end

--> Cold path of a send to one player: their writer is not the loaded one.
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local UsePlayer
UsePlayer = function(Player: Player)
    local Writer = PlayersMap[Player]
    if Writer == nil then
        Writer = CreateWriter(Player, 0, 0)
        if Departed[Player] then
            PlayersMap[Player] = nil
        end
    end
    Switch(Writer)
    CurrentPlayer = Player
end

--> FireExcept: catch the excluded player up to the log, then mark them as past the new event
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local BeginExcept
BeginExcept = function(Except: Player): Writer?
    local Writer = PlayersMap[Except]
    if Writer ~= nil and Writer ~= Current then
        Switch(Writer)
    end
    if Current ~= Home then
        Switch(Home)
    end
    return Writer
end

--> Declared then assigned so the compiler does not inline it into every event (native code size)
local EndExcept
EndExcept = function(Writer: Writer?)
    if Writer ~= nil then
        Writer.Synced = SendCursor
        Writer.SyncedInstances = #SendInstances
    end
end

--> FireList (reliable): the event was serialized once into Scratch, append it to each player
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local SendReliableList
SendReliableList = function(List: {Player})
    Save(Scratch)
    local Size, Source, Instances = SendCursor, SendBuffer, SendInstances
    local InstanceCount = #Instances
    Load(Current)
    for _, Player in List do
        if Player ~= CurrentPlayer then
            UsePlayer(Player)
        end
        local Position = Allocate(Size)
        buffer.copy(SendBuffer, Position, Source, 0, Size)
        if InstanceCount > 0 then
            table.move(Instances, 1, InstanceCount, #SendInstances + 1, SendInstances)
        end
    end
    Scratch.Cursor = 0
    table.clear(Instances)
end

--> In a function: a loop in the module's main chunk would make it compile natively
local function AddExistingPlayers()
    for _, Player in Players:GetPlayers() do
        if PlayersMap[Player] == nil then
            CreateWriter(Player, 0, 0)
        end
    end
end
AddExistingPlayers()

Players.PlayerAdded:Connect(function(Player)
    --> Players that join mid-frame skip broadcasts sent before they joined
    if PlayersMap[Player] == nil then
        Save(Current)
        CreateWriter(Player, Home.Cursor, #Home.Instances)
        if CurrentPlayer == Player then
            CurrentPlayer = nil
        end
        if Home.Cursor > 0 then
            Private = true
        end
    end
end)

Players.PlayerRemoving:Connect(function(Player)
    PlayersMap[Player] = nil
    if CurrentPlayer == Player then
        CurrentPlayer = nil
    end
    Departed[Player] = true
end)

local function StepReplication()
    Save(Current)
    Current = Home
    CurrentPlayer = nil

    local BroadcastSize = Home.Cursor
    local BroadcastInstances = Home.Instances

    if not Private then
        --> Nobody has private data this frame: one FireAllClients covers everyone
        if BroadcastSize > 0 then
            if #BroadcastInstances > 0 then
                Reliable:FireAllClients(Pack(Home), BroadcastInstances)
            else
                Reliable:FireAllClients(Pack(Home))
            end
        end
    else
        Private = false
        local Broadcast: buffer? = nil
        local BroadcastInstanceCount = #BroadcastInstances
        for Player, Writer in PlayersMap do
            local Cursor = Writer.Cursor
            local Synced = Writer.Synced
            if Cursor == 0 and Synced == 0 then
                if BroadcastSize > 0 then
                    if Broadcast == nil then
                        Broadcast = Pack(Home)
                    end
                    if BroadcastInstanceCount > 0 then
                        Reliable:FireClient(Player, Broadcast, BroadcastInstances)
                    else
                        Reliable:FireClient(Player, Broadcast)
                    end
                end
                continue
            end

            --> Append the end of the broadcast log this writer has not seen yet
            if Synced ~= BroadcastSize or Writer.SyncedInstances ~= BroadcastInstanceCount then
                Load(Writer)
                CatchUp(Writer)
                Save(Writer)
                Cursor = SendCursor
            end
            Writer.Synced = 0
            Writer.SyncedInstances = 0

            if Cursor > 0 then
                local Out: buffer
                if REUSE_SEND_BUFFERS then
                    Out = Pack(Writer)
                else
                    Out = buffer.create(Cursor)
                    buffer.copy(Out, 0, Writer.Buffer, 0, Cursor)
                end
                Writer.Cursor = 0
                local Instances = Writer.Instances
                if #Instances > 0 then
                    Reliable:FireClient(Player, Out, Instances)
                    table.clear(Instances)
                else
                    Reliable:FireClient(Player, Out)
                end
            end
        end
    end

    Home.Cursor = 0
    table.clear(BroadcastInstances)
    Load(Home)
end
-- RELIABLE --
]]
