return [[local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- SPLIT --
if not RunService:IsClient() then
    error("Client network module can only be required from the client.")
end

local Reliable: RemoteEvent = ReplicatedStorage:WaitForChild(BASE_EVENT_NAME .. "_RELIABLE_REMOTE") :: RemoteEvent
local Unreliable: UnreliableRemoteEvent = ReplicatedStorage:WaitForChild(BASE_EVENT_NAME .. "_UNRELIABLE_REMOTE") :: UnreliableRemoteEvent

--> Unreliable sends: the event was serialized past the end of the outbox, from Start.
--> The instance array is left out when empty (see the server's sends).
--> Declared then assigned so the compiler does not inline it into every event (native code size)
local SendUnreliable
SendUnreliable = function(Start: number, InstanceStart: number)
    local Packet, Instances = Cut(Start, InstanceStart)
    if Instances then
        Unreliable:FireServer(Packet, Instances)
    else
        Unreliable:FireServer(Packet)
    end
end

local function StepReplication()
    if SendCursor <= 0 then
        return
    end

    Save(Home)
    if #SendInstances > 0 then
        Reliable:FireServer(Pack(Home), SendInstances)
    else
        Reliable:FireServer(Pack(Home))
    end

    Home.Cursor = 0
    table.clear(Home.Instances)
    Load(Home)
end
]]
