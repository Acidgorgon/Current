return [[local Invocations = 0

--> Send state. The Send* upvalues are the "loaded" writer that the generated
--> serializers write into. A Writer record holds a writer's state while it is
--> not loaded. Load/Save copy fields in and out and never allocate.
--> At rest the Home writer is always loaded: on the client it is the reliable
--> outbox, on the server it is the broadcast log shared by every player.
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
    --> Cached exact-size outgoing buffer (only reused when ReuseSendBuffers is on)
    Out: buffer?,
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
        Out = nil,
        Synced = 0,
        SyncedInstances = 0,
    }
end

local Home: Writer = NewWriter()
local Scratch: Writer = NewWriter()

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

local function Allocate(Bytes: number)
    local InUse = (SendCursor + Bytes)
    if InUse > SendSize then
        --> Grow geometrically; writers keep their capacity between frames
        local Size = SendSize
        while InUse > Size do
            Size *= 2
        end

        local Buffer = buffer.create(Size)
        buffer.copy(Buffer, 0, SendBuffer, 0, SendCursor)
        SendBuffer = Buffer
        SendSize = Size
    end

    SendOffset = SendCursor
    SendCursor = InUse

    return SendOffset
end

--> Exact-size copy of a saved writer's contents, ready to hand to a remote.
local function Pack(Writer: Writer): buffer
    local Cursor = Writer.Cursor
    local Out = Writer.Out
    if Out == nil or buffer.len(Out) ~= Cursor then
        Out = buffer.create(Cursor)
        if REUSE_SEND_BUFFERS then
            Writer.Out = Out
        end
    end

    buffer.copy(Out :: buffer, 0, Writer.Buffer, 0, Cursor)
    return Out :: buffer
end

--> Unreliable sends, FireList and exports serialize into the Scratch writer.
local function BeginScratch()
    Save(Home)
    Load(Scratch)
end

local function EndScratch()
    Scratch.Cursor = 0
    Scratch.Size = SendSize
    Scratch.Buffer = SendBuffer
    table.clear(Scratch.Instances)
    Load(Home)
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

local function Spawn(Listener: (...any) -> (), ...)
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

local ReliableHandlers: {[number]: (...any) -> ()} = {}
local UnreliableHandlers: {[number]: (...any) -> ()} = {}

]]
