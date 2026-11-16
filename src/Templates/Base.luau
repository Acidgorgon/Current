return [[local Invocations = 0

--> Send state. The Send* upvalues are the "loaded" writer that the generated
--> serializers write into. A Writer record holds a writer's state while it is
--> not loaded. Load/Save copy fields in and out and never allocate.
--> Home is the reliable outbox on the client and the broadcast log shared by
--> every player on the server. Current is the writer whose state is in the
--> Send* upvalues: always Home on the client; on the server the writer of the
--> last player sent to stays loaded until a send needs another one, so a run
--> of Fire calls to one player pays for one switch instead of one per call.
local SendSize = 64
local SendOffset = 0
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
    SendOffset = Writer.Cursor
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

--> Cold path of Allocate: grows the loaded writer geometrically so it can hold InUse bytes.
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

    SendOffset = Offset
    SendCursor = InUse

    return Offset
end

--> ReuseSendBuffers: one outgoing buffer per size, shared by every send of that size
--> (remotes copy their arguments when fired), up to OUT_POOL_LIMIT bytes in total.
local OUT_POOL_LIMIT = 65536
local OutPool: {[number]: buffer} = {}
local OutPoolBytes = 0

--> Exact-size copy of a saved writer's contents, ready to hand to a remote.
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local Pack
Pack = function(Writer: Writer): buffer
    local Cursor = Writer.Cursor
    local Out: buffer
    if REUSE_SEND_BUFFERS then
        Out = OutPool[Cursor]
        if Out == nil then
            Out = buffer.create(Cursor)
            if OutPoolBytes + Cursor <= OUT_POOL_LIMIT then
                OutPool[Cursor] = Out
                OutPoolBytes += Cursor
            end
        end
    else
        Out = buffer.create(Cursor)
    end

    buffer.copy(Out, 0, Writer.Buffer, 0, Cursor)
    return Out
end

--> Unreliable sends, FireList and exports serialize into the Scratch writer.
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
        warn(`[Blink]: Event queue of "{Name}" exceeded 256, did you forget to implement a listener?`)
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

]]
