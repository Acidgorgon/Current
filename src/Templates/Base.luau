return [[local Invocations = 0

--> Send state. The Send* upvalues are the "loaded" writer that the generated
--> serializers write into. A Writer record holds a writer's state while it is
--> not loaded. Loading and saving a writer copy its fields in and out and never allocate.
--> Home is the reliable outbox on the client and the broadcast log shared by
--> every player on the server. Current is the writer whose state is in the
--> Send* upvalues: always Home on the client; on the server the writer of the
--> last player sent to stays loaded until a send needs another one, so a run
--> of Fire calls to one player pays for one switch instead of one per call.
local SendSize = 64
local SendCursor = 0
local SendBuffer = buffer.create(64)
local SendInstances = {}

local RecieveCursor = 0
local RecieveBuffer = buffer.create(64)

local RecieveInstances = {}
local RecieveInstanceCursor = 0

local Null = newproxy()

type Entry = {
    value: any,
    next: Entry?
}

type Queue = {
    head: Entry?,
    tail: Entry?
}

type Writer = {
    Size: number,
    Cursor: number,
    Buffer: buffer,
    Instances: {any},
    --> Server only: how many bytes/instances of the broadcast log this writer already holds
    Synced: number,
    SyncedInstances: number,
}

local function NewWriter(): Writer
    return {
        Size = 64,
        Cursor = 0,
        Buffer = buffer.create(64),
        Instances = {},
        Synced = 0,
        SyncedInstances = 0,
    }
end

local Home: Writer = NewWriter()
local Scratch: Writer = NewWriter()
local Current: Writer = Home

SendBuffer = Home.Buffer
SendInstances = Home.Instances

local function Read(Bytes: number)
    local Offset = RecieveCursor
    RecieveCursor += Bytes
    return Offset
end

local function Load(Writer: Writer)
    SendSize = Writer.Size
    SendCursor = Writer.Cursor
    SendBuffer = Writer.Buffer
    SendInstances = Writer.Instances
end

local function Save(Writer: Writer)
    Writer.Size = SendSize
    Writer.Cursor = SendCursor
    Writer.Buffer = SendBuffer
end

local function Invoke()
    if Invocations == 255 then
        Invocations = 0
    end

    local Invocation = Invocations
    Invocations += 1
    return Invocation
end

--> Cold path of the allocator below: grows the loaded writer geometrically to hold InUse bytes.
--> Writers keep their capacity between frames.
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local Grow
Grow = function(InUse: number)
    local Size = SendSize
    while InUse > Size do
        Size *= 2
    end

    local Buffer = buffer.create(Size)
    buffer.copy(Buffer, 0, SendBuffer, 0, SendCursor)
    SendBuffer = Buffer
    SendSize = Size
end

local function Allocate(Bytes: number)
    local Offset = SendCursor
    local InUse = Offset + Bytes
    if InUse > SendSize then
        Grow(InUse)
    end

    SendCursor = InUse

    return Offset
end

--> ReuseSendBuffers: one outgoing buffer per size, shared by every send of that size
--> (remotes copy their arguments when fired), up to OUT_POOL_LIMIT bytes in total.
local OUT_POOL_LIMIT = 65536
local OutPool: {[number]: buffer} = {}
local OutPoolBytes = 0

--> New exact-size outgoing buffer
local function NewOut(Size: number): buffer
    if REUSE_SEND_BUFFERS then
        local Out = OutPool[Size]
        if Out == nil then
            Out = buffer.create(Size)
            if OutPoolBytes + Size <= OUT_POOL_LIMIT then
                OutPool[Size] = Out
                OutPoolBytes += Size
            end
        end
        return Out
    end
    return buffer.create(Size)
end

--> Exact-size copy of a saved writer's contents, ready to hand to a remote.
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local Pack
Pack = function(Writer: Writer): buffer
    local Cursor = Writer.Cursor
    local Out = NewOut(Cursor)
    buffer.copy(Out, 0, Writer.Buffer, 0, Cursor)
    return Out
end

--> Unreliable sends serialize past the end of the loaded writer (its unsent data before
--> Start is left as it was), then Cut takes the event back out as a packet of its own:
--> no writer switch. Returns the packet and its instances (nil when there are none).
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local Cut
Cut = function(Start: number, InstanceStart: number): (buffer, {any}?)
    local Size = SendCursor - Start
    local Out = NewOut(Size)
    buffer.copy(Out, 0, SendBuffer, Start, Size)
    SendCursor = Start

    local Count = #SendInstances
    if Count == InstanceStart then
        return Out, nil
    end

    local Instances = table.move(SendInstances, InstanceStart + 1, Count, 1, {})
    for Index = Count, InstanceStart + 1, -1 do
        SendInstances[Index] = nil
    end
    return Out, Instances
end

--> Reliable FireList and exports serialize into the Scratch writer.
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local BeginScratch
BeginScratch = function()
    Save(Current)
    Load(Scratch)
end

--> Declared then assigned so the compiler does not inline it into every event (native code size)
local EndScratch
EndScratch = function()
    Scratch.Cursor = 0
    Scratch.Size = SendSize
    Scratch.Buffer = SendBuffer
    table.clear(Scratch.Instances)
    Load(Current)
end

--> Async listeners run on a reused thread instead of a new coroutine per event.
local FreeThread: thread? = nil

local function RunListener(Listener: (...any) -> (), ...)
    local Acquired = FreeThread
    FreeThread = nil
    Listener(...)
    FreeThread = Acquired
end

local function ListenerLoop()
    while true do
        RunListener(coroutine.yield())
    end
end

--> Declared then assigned so the compiler does not inline it into every event (native code size)
local Spawn
Spawn = function(Listener: (...any) -> (), ...)
    if FreeThread == nil then
        FreeThread = coroutine.create(ListenerLoop)
        coroutine.resume(FreeThread :: thread)
    end

    task.spawn(FreeThread :: thread, Listener, ...)
end

local function CreateQueue(): Queue
    return {
        head = nil,
        tail = nil
    }
end

local function Pop(queue: Queue): any
    local head = queue.head
    if head == nil then
        return
    end

    queue.head = head.next
    if queue.head == nil then
        queue.tail = nil
    end

    return head.value
end

local function Push(queue: Queue, value: any)
    local entry: Entry = {
        value = value,
        next = nil
    }

    if queue.tail ~= nil then
        queue.tail.next = entry
    end

    queue.tail = entry

    if queue.head == nil then
        queue.head = entry
    end
end

local Calls = {}

local Events: any = {
    Reliable = {},
    Unreliable = {}
}

local Queue: any = {
    Reliable = {},
    Unreliable = {}
}

--> Cold path: an event arrived before any listener was connected
local QueueEvent
QueueEvent = function(EventQueue: {any}, Name: string, ...: any)
    if #EventQueue > 256 then
        warn(`[Current]: Event queue of "{Name}" exceeded 256, did you forget to implement a listener?`)
    end
    --> On the server clients fill the queue: it is bounded so nobody can grow it forever
    if #EventQueue >= QUEUE_LIMIT then
        return
    end
    table.insert(EventQueue, table.pack(...))
end

local function FlushQueue(Channel: string, Index: number, Listener: (...any) -> (), Sync: boolean)
    local EventQueue = Queue[Channel][Index]
    if EventQueue == nil or #EventQueue == 0 then
        return
    end

    Queue[Channel][Index] = {}
    for _, Arguments in EventQueue do
        if Sync then
            Listener(table.unpack(Arguments, 1, Arguments.n))
        else
            Spawn(Listener, table.unpack(Arguments, 1, Arguments.n))
        end
    end
end

--> On() for every event is built from these two factories at load time, so all events
--> share one function prototype instead of compiling their own copy.
local function ConnectMany(Channel: string, Index: number, Sync: boolean): any
    return function(Listener: (...any) -> ()): () -> ()
        local Listeners = Events[Channel][Index]
        table.insert(Listeners, Listener)
        FlushQueue(Channel, Index, Listener, Sync)
        return function()
            local Position = table.find(Listeners, Listener)
            if Position ~= nil then
                table.remove(Listeners, Position)
            end
        end
    end
end

local function ConnectSingle(Channel: string, Index: number, Sync: boolean): any
    return function(Listener: (...any) -> ()): () -> ()
        local Listeners = Events[Channel]
        Listeners[Index] = Listener
        FlushQueue(Channel, Index, Listener, Sync)
        return function()
            if Listeners[Index] == Listener then
                Listeners[Index] = nil
            end
        end
    end
end

local ReliableHandlers: {[number]: (...any) -> ()} = {}
local UnreliableHandlers: {[number]: (...any) -> ()} = {}

--> Lighthouse hooks (https://acidgorgon.github.io/Lighthouse/). Lighthouse sets shared.Lighthouse;
--> StepReplication reads it once per frame (LhFrame). Only while it is set: every send reports the
--> size of the record it wrote (LhWrote: the server's Fire methods, the client's serializers), each
--> receive loop the size of every event it read (LhRead), and the totals go to Lighthouse.net once
--> per frame (sends) or per packet (receives), one channel per event. Without Lighthouse the cost
--> is that lookup and an `if` per event.
local Lh: any = nil
local LhSeen: any = nil
local LhFlush: any = nil
local LhReceive: any = nil
--> Bytes per event name since the last report, and the names that have some
local LhOut: {[string]: number} = {}
local LhOutNames: {string} = {}
local LhOutCount = 0
--> Server: bytes per player and event name (one table per player, kept while the player is)
local LhPrivate: {[any]: {[string]: number}} = setmetatable({} :: any, { __mode = "k" })
local LhPrivatePlayers: {any} = {}
local LhPrivateNames: {string} = {}
local LhPrivateCount = 0
--> Receive: bytes per event name in the packet being read, and where the last event ended
local LhIn: {[string]: number} = {}
local LhInNames: {string} = {}
local LhInCount = 0
local LhInTotal = 0
local LhPosition = 0
--> Event names by channel and wire index (filled by the generated code)
local LhNamesReliable: {[number]: string} = {}
local LhNamesUnreliable: {[number]: string} = {}
local LhNames = { [ReliableHandlers] = LhNamesReliable, [UnreliableHandlers] = LhNamesUnreliable }

--> Once per frame, at the end of StepReplication. Probes are fetched again only when
--> shared.Lighthouse changes.
--> Declared then assigned so the compiler does not inline it (native code size)
local LhFrame
LhFrame = function()
    local Shared = shared
    local Api = if Shared ~= nil then Shared.Lighthouse else nil
    if Api ~= LhSeen then
        LhSeen = Api
        LhFlush = nil
        LhReceive = nil
        if Api ~= nil then
            local Ok, Flush, Receive = pcall(function()
                return Api.probe("Current.Flush"), Api.probe("Current.Receive")
            end)
            if Ok then
                LhFlush = Flush
                LhReceive = Receive
            end
        end
    end
    Lh = if LhFlush ~= nil then Api else nil
end

--> Adds Bytes to Totals[Name]; a name that had none goes on Names. Returns the new count of Names.
--> Declared then assigned so the compiler does not inline it (native code size)
local LhAdd
LhAdd = function(Totals: {[string]: number}, Names: {string}, Count: number, Name: string, Bytes: number): number
    local Old = Totals[Name]
    if Old == nil or Old == 0 then
        Count += 1
        Names[Count] = Name
        Totals[Name] = Bytes
    else
        Totals[Name] = Old + Bytes
    end
    return Count
end

--> Reports and clears Totals for the first Count names of Names
--> Declared then assigned so the compiler does not inline it (native code size)
local LhSend
LhSend = function(Api: any, Totals: {[string]: number}, Names: {string}, Count: number, Direction: string, Player: any)
    for Index = 1, Count do
        local Name = Names[Index]
        local Bytes = Totals[Name]
        if Bytes > 0 then
            Totals[Name] = 0
            Api.net("Current", Name, Direction, Bytes, Player)
        end
    end
end

--> A record of Bytes bytes for event Name was written for one player (To), or for Times players
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local LhWrote
LhWrote = function(Name: string, Bytes: number, To: any, Times: number)
    if To == nil then
        if Bytes * Times > 0 then
            LhOutCount = LhAdd(LhOut, LhOutNames, LhOutCount, Name, Bytes * Times)
        end
        return
    end
    local Totals = LhPrivate[To]
    if Totals == nil then
        Totals = {}
        LhPrivate[To] = Totals
    end
    local Old = Totals[Name]
    if Old == nil or Old == 0 then
        LhPrivateCount += 1
        LhPrivatePlayers[LhPrivateCount] = To
        LhPrivateNames[LhPrivateCount] = Name
        Totals[Name] = Bytes
    else
        Totals[Name] = Old + Bytes
    end
end

--> Sends the bytes written since the last report (once per frame, from StepReplication)
--> Declared then assigned so the compiler does not inline it (native code size)
local LhReport
LhReport = function()
    local Api = Lh
    LhSend(Api, LhOut, LhOutNames, LhOutCount, "out", nil)
    LhOutCount = 0
    for Index = 1, LhPrivateCount do
        local Player = LhPrivatePlayers[Index]
        LhPrivatePlayers[Index] = nil
        local Totals = LhPrivate[Player]
        if Totals ~= nil then
            local Name = LhPrivateNames[Index]
            local Bytes = Totals[Name]
            if Bytes > 0 then
                Totals[Name] = 0
                Api.net("Current", Name, "out", Bytes, Player)
            end
        end
    end
    LhPrivateCount = 0
end

--> A receive loop read an event that ends at Cursor
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local LhRead
LhRead = function(Handlers: any, Index: number, Cursor: number)
    local Bytes = Cursor - LhPosition
    LhPosition = Cursor
    LhInTotal += Bytes
    LhInCount = LhAdd(LhIn, LhInNames, LhInCount, LhNames[Handlers][Index] or "?", Bytes)
end

--> A packet of Size bytes was read: report its events. Bytes no event accounts for (a packet
--> that was dropped or failed to decode) go to the "Dropped" channel.
--> Declared then assigned so the compiler does not inline it (native code size)
local LhReceived
LhReceived = function(Api: any, Size: number, Player: any)
    LhSend(Api, LhIn, LhInNames, LhInCount, "in", Player)
    LhInCount = 0
    local Rest = Size - LhInTotal
    LhInTotal = 0
    LhPosition = 0
    if Rest > 0 then
        Api.net("Current", "Dropped", "in", Rest, Player)
    end
end

]]
