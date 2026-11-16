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

--> Reliable traffic. FireAll only appends to the broadcast log (the Home writer),
--> so its cost does not grow with the player count. A player's own writer only
--> holds private events, plus the slice of the broadcast log that came before
--> them (copied in lazily by CatchUp) so ordering is preserved.
local PlayersMap: {[Player]: Writer} = {}

local function CreateWriter(Player: Player, Synced: number, SyncedInstances: number): Writer
    local Writer = NewWriter()
    Writer.Synced = Synced
    Writer.SyncedInstances = SyncedInstances
    PlayersMap[Player] = Writer
    return Writer
end

local function GetWriter(Player: Player): Writer
    return PlayersMap[Player] or CreateWriter(Player, 0, 0)
end

--> Appends the part of the broadcast log the loaded writer has not seen yet.
--> Home must be saved before calling.
local function CatchUp(Writer: Writer)
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

--> Loads a player's writer with the broadcast log caught up. Pair with EndPlayer.
local function BeginPlayer(Player: Player): Writer
    Save(Home)
    local Writer = PlayersMap[Player] or CreateWriter(Player, 0, 0)
    Load(Writer)
    CatchUp(Writer)
    return Writer
end

local function EndPlayer(Writer: Writer)
    Save(Writer)
    Load(Home)
end

for _, Player in Players:GetPlayers() do
    if PlayersMap[Player] == nil then
        CreateWriter(Player, 0, 0)
    end
end

Players.PlayerAdded:Connect(function(Player)
    --> Players that join mid-frame skip broadcasts sent before they joined
    if PlayersMap[Player] == nil then
        CreateWriter(Player, SendCursor, #SendInstances)
    end
end)

Players.PlayerRemoving:Connect(function(Player)
    PlayersMap[Player] = nil
end)

local function StepReplication()
    Save(Home)

    local BroadcastSize = Home.Cursor
    local BroadcastInstances = Home.Instances

    --> If nobody has private data this frame, one FireAllClients covers everyone
    local Private = false
    for _, Writer in PlayersMap do
        if Writer.Cursor > 0 or Writer.Synced > 0 then
            Private = true
            break
        end
    end

    if not Private then
        if BroadcastSize > 0 then
            Reliable:FireAllClients(Pack(Home), BroadcastInstances)
        end
    else
        local Broadcast: buffer? = nil
        for Player, Writer in PlayersMap do
            if Writer.Cursor == 0 and Writer.Synced == 0 then
                if BroadcastSize > 0 then
                    if Broadcast == nil then
                        Broadcast = Pack(Home)
                    end
                    Reliable:FireClient(Player, Broadcast, BroadcastInstances)
                end
                continue
            end

            Load(Writer)
            CatchUp(Writer)
            Save(Writer)

            if Writer.Cursor > 0 then
                Reliable:FireClient(Player, Pack(Writer), Writer.Instances)
            end

            Writer.Cursor = 0
            Writer.Synced = 0
            Writer.SyncedInstances = 0
            table.clear(Writer.Instances)
        end
    end

    Home.Cursor = 0
    table.clear(BroadcastInstances)
    Load(Home)
end
]]
