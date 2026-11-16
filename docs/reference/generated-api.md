# Generated API

The compiler writes a server module and a client module (and optionally a [types module](./options#serveroutput-clientoutput-typesoutput) and [TypeScript declarations](#typescript)). Each module returns a frozen table:

```lua
local Net = require(ReplicatedStorage.Shared.net.server)

Net.StepReplication      -- function
Net.MyEvent              -- { Fire, FireAll, …, On }
Net.MyFunction           -- { On } on the server, { Invoke } on the client
Net.Combat.Hit           -- events and functions inside scopes and imports
Net.SaveData             -- { Read, Write } for exported types
```

Every type declared in the schema is also exported as a Luau type: `Net.Item`, `Net.Combat_Damage` for a type inside a scope.

The names below use the default `Pascal` [casing](./options#casing).

## Server module

### Events the server fires

For events with `From: Server` or `From: Both`. `…` stands for the event's data: one argument, or one per value of a type pack.

| Function | Sends to |
|---|---|
| `Fire(Player, …)` | one player |
| `FireAll(…)` | every player |
| `FireList(Players: { Player }, …)` | each player in the list |
| `FireExcept(Except: Player, …)` | every player but one |

```lua
Net.RoundStarted.FireAll(RoundNumber, Map)
Net.Inventory.Fire(Player, Items)
```

### Events the server receives

For events with `From: Client` or `From: Both`.

| Function | Use |
|---|---|
| `On(Listener: (Player, …) -> ()) -> () -> ()` | connect a listener; returns a function that disconnects it |
| `Iter() -> iterator of (Index, Player, …)` | polling events only (`Call: Polling`, `Poll: true` or `UsePolling`) |

```lua
local Disconnect = Net.Buy.On(function(Player, ItemId)
    -- ...
end)

for Index, Player, Direction in Net.Input.Iter() do
    -- ...
end
```

### Functions

| Function | Use |
|---|---|
| `On(Handler: (Player, …) -> (…))` | set the handler; its return values go back to the client |

## Client module

### Events the client fires

For events with `From: Client` or `From: Both`.

| Function | Sends to |
|---|---|
| `Fire(…)` | the server |

### Events the client receives

For events with `From: Server` or `From: Both`.

| Function | Use |
|---|---|
| `On(Listener: (…) -> ()) -> () -> ()` | connect a listener; returns a function that disconnects it |
| `Iter() -> iterator of (Index, …)` | polling events only |

### Functions

| Function | Returns |
|---|---|
| `Invoke(…)` | the return values (`Yield: Coroutine`, yields), a future (`Future`) or a promise (`Promise`) |

## Exported types

Types declared with [`export`](./schema#exports) get a table in both modules (and in the types module):

| Function | Use |
|---|---|
| `Write(Value) -> buffer` | serialize a value into a new buffer |
| `Read(buffer) -> Value` | read it back |

## Replication

Both modules expose `StepReplication()`.

- **Reliable events and function calls are batched.** Everything fired during a frame is packed into one buffer per destination and sent when `StepReplication` runs. By default the module connects it to `RunService.Heartbeat`, so this happens once per frame.
- **The server writes broadcasts once.** `FireAll` goes into a shared log. If no player has private data that frame, the whole frame goes out with a single `FireAllClients`; otherwise each player gets the log plus their own events, in the order they were fired.
- **Unreliable events are sent immediately**, one remote call each, and are not affected by `StepReplication`.
- **With [`ManualReplication`](./options#manualreplication)** the Heartbeat connection is not made. Call `StepReplication()` yourself whenever you want reliable traffic to go out; if you never call it, nothing reliable is sent.

## Behaviour to know

- **Wrong side.** Requiring the server module on a client (or the client module on the server) errors.
- **Edit mode.** When the game is not running (`RunService:IsRunning()` is false, for example in plugins or UI stories), the modules return the same table shape with no-op functions.
- **Two copies.** Two modules with the same [`RemoteScope`](./options#remotescope) in one game is an error, to stop them stealing each other's packets.
- **Queued events.** Reliable events and function requests that arrive before a listener exists are queued until one connects (warning after 256).
- **Players who left.** Reliable sends to a player after `PlayerRemoving` are dropped.
- **Malformed data.** If client data fails validation, reading stops with an error and the rest of that packet is dropped; no listener sees the bad value.

## TypeScript

With [`option Typescript = true`](./options#typescript) the compiler also writes `.d.ts` files next to the server and client modules, for roblox-ts. They declare the same API:

```ts
export declare const StepReplication: () => void
export declare const Ping: {
    Fire: (Player: Player, Value: number) => void
    FireAll: (Value: number) => void
    FireExcept: (Except: Player, Value: number) => void
    FireList: (List: Player[], Value: number) => void
    On: (Listener: (Player: Player, Value: number) => void) => (() => void)
}
```

Polling events declare `Iter: () => IterableFunction<…>`, and functions declare `On` (server) or `Invoke` (client).
