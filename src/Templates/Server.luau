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

--> Unreliable sends: the event was serialized into Scratch.
--> Every send leaves out the instance array when it is empty: an empty table would still
--> be serialized by the remote and rebuilt by the receiver on every packet.
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local SendUnreliable
SendUnreliable = function(Player: Player)
    Save(Scratch)
    if #SendInstances > 0 then
        Unreliable:FireClient(Player, Pack(Scratch), SendInstances)
    else
        Unreliable:FireClient(Player, Pack(Scratch))
    end
    EndScratch()
end

--> Declared then assigned so the compiler does not inline it into every event (native code size)
local SendUnreliableAll
SendUnreliableAll = function()
    Save(Scratch)
    if #SendInstances > 0 then
        Unreliable:FireAllClients(Pack(Scratch), SendInstances)
    else
        Unreliable:FireAllClients(Pack(Scratch))
    end
    EndScratch()
end

--> Declared then assigned so the compiler does not inline it into every event (native code size)
local SendUnreliableList
SendUnreliableList = function(List: {Player})
    Save(Scratch)
    local Buffer = Pack(Scratch)
    local Instances = if #SendInstances > 0 then SendInstances else nil
    for _, Player in List do
        if Instances then
            Unreliable:FireClient(Player, Buffer, Instances)
        else
            Unreliable:FireClient(Player, Buffer)
        end
    end
    EndScratch()
end

--> Declared then assigned so the compiler does not inline it into every event (native code size)
local SendUnreliableExcept
SendUnreliableExcept = function(Except: Player)
    Save(Scratch)
    local Buffer = Pack(Scratch)
    local Instances = if #SendInstances > 0 then SendInstances else nil
    for _, Player in Players:GetPlayers() do
        if Player ~= Except then
            if Instances then
                Unreliable:FireClient(Player, Buffer, Instances)
            else
                Unreliable:FireClient(Player, Buffer)
            end
        end
    end
    EndScratch()
end

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
        CatchUp(Writer)
    end
end

--> Cold path of a send to one player: their writer is not the loaded one.
--> Same as Switch, with the catch-up skipped when there is nothing new.
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
    Save(Current)
    Load(Writer :: Writer)
    Current = Writer :: Writer
    CurrentPlayer = Player
    Private = true
    if (Writer :: Writer).Synced ~= Home.Cursor or (Writer :: Writer).SyncedInstances ~= #Home.Instances then
        CatchUp(Writer :: Writer)
    end
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
