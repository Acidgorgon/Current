# Events

Events are fire-and-forget messages, Current's version of `RemoteEvent` and `UnreliableRemoteEvent`. They are the main way the server and clients talk.

```blink
event Damage {
    From: Server,
    Type: Reliable,
    Call: ManyAsync,
    Data: (Instance(Player), u8)
}
```

| Field | Values | Required |
|---|---|---|
| [`From`](#from) | `Server`, `Client`, `Both` | yes |
| [`Type`](#type) | `Reliable`, `Unreliable` | yes |
| [`Call`](#call) | `SingleSync`, `SingleAsync`, `ManySync`, `ManyAsync`, `Polling` | yes |
| [`Poll`](#polling) | `true`, `false` | no |
| [`ReuseTables`](#reusetables) | `true`, `false` | no |
| [`Data`](#data) | any type, or a type pack `(A, B, …)` | no |
| [`Rate`](#rate) | a positive number | no |

## `From`

Which side fires the event.

- `Server`: the server fires, clients listen.
- `Client`: clients fire, the server listens. The data is validated on the server before any listener runs.
- `Both`: a [two-way event](/guide/two-way-events). Both sides fire and both listen, through one event index. Data from clients is validated like a `Client` event.

## `Type`

How the event is delivered.

- `Reliable`: always arrives, in the order it was sent. Reliable events are batched and sent at the end of the frame.
- `Unreliable`: may be dropped or arrive out of order, and is sent immediately. Roblox limits unreliable payloads to about 1000 bytes; keep unreliable events small (bound strings, arrays and buffers with [ranges](./schema#ranges)).

Use `Unreliable` for state that is replaced every frame anyway (positions, aim, match clocks), and `Reliable` for everything that must arrive.

## `Call`

The listening API on the receiving side.

| Call | Listeners | Listener may yield | API |
|---|---|---|---|
| `SingleSync` | one | no | `On` |
| `ManySync` | many | no | `On` |
| `SingleAsync` | one | yes | `On` |
| `ManyAsync` | many | yes | `On` |
| `Polling` | none | n/a | `Iter` |

- **Single** keeps only the last listener connected with `On`; **Many** keeps them all.
- **Async** listeners run in their own thread (Current reuses threads between calls), so they can yield.
- **Sync** listeners are called directly, which is faster, but they must not yield or error.

::: danger Sync listeners must not yield
Yielding or erroring in a sync listener breaks the processing of the rest of that packet, which can cause undefined and sometimes game-breaking behaviour. With [`SyncValidation`](./options#syncvalidation) on (the default), Current warns and closes the thread when a sync listener yields. Prefer `Async` unless the event is on a hot path.
:::

## Polling

`Call: Polling` queues the event instead of calling listeners; read the queue with `Iter()` whenever it suits you (for example once per frame in an ECS system). `Poll: true` in an event, or [`option UsePolling = true`](./options#usepolling) for the whole file, does the same whatever `Call` says.

```blink
event Input {
    From: Client,
    Type: Unreliable,
    Call: Polling,
    Data: vector<f16>
}
```

```lua
-- server, in a system that runs every frame
for Index, Player, Direction in Net.Input.Iter() do
    Movement[Player] = Direction
end
```

## `ReuseTables`

Optional, `true` or `false`. Overrides the [`ReuseReceiveTables`](./options#reusereceivetables) option for this event: with `true` the event decodes each value into the tables of its previous value instead of allocating new ones, with `false` every value gets new tables. Read the option's notes before turning it on: the table a listener receives is overwritten by the event's next value. `Polling` events ignore it.

```blink
struct MatchSnapshot {
    Clock: f32,
    Positions: vector<f16>[..44]
}

event MatchState {
    From: Server,
    Type: Unreliable,
    Call: SingleSync,
    ReuseTables: true,
    Data: MatchSnapshot
}
```

::: warning
The listener's table is only valid until it returns. Copy what you keep.
:::

## `Data`

The payload: any [type](./schema), or a type pack of several values in parentheses. Leave `Data` out for an event that carries nothing.

```blink
event Ready {
    From: Client,
    Type: Reliable,
    Call: SingleAsync
}

event Hit {
    From: Client,
    Type: Unreliable,
    Call: SingleSync,
    Data: (u16, vector, u8(0..100))
}
```

A type pack becomes separate arguments in Luau: `Net.Hit.Fire(TargetId, Position, Damage)`.

## `Rate`

A per-player limit in calls per second for this event, enforced on the server. Burst is max(`Rate`, 1). Over it, the event is dropped and reported as `RateLimited` (see [Security](/guide/security#per-event-rates)). It only applies to what clients send (`From: Client` or `From: Both`).

```blink
event PlaceBlock {
    From: Client,
    Type: Reliable,
    Call: SingleSync,
    Data: vector,
    Rate: 10
}
```

This field is Current only; upstream Blink rejects it.

## Using events in Luau

::: code-group

```lua [server.luau]
-- Sending (From: Server or Both)
Net.Damage.Fire(Player, Attacker, 10)          -- one player
Net.Damage.FireAll(Attacker, 10)               -- everyone
Net.Damage.FireList({ PlayerA, PlayerB }, Attacker, 10)
Net.Damage.FireExcept(Attacker, Attacker, 10)  -- everyone but one

-- Receiving (From: Client or Both): the player comes first
local Disconnect = Net.Hit.On(function(Player, TargetId, Position, Damage)
    -- ...
end)
Disconnect()
```

```lua [client.luau]
-- Sending (From: Client or Both)
Net.Hit.Fire(TargetId, Position, 25)

-- Receiving (From: Server or Both)
Net.Damage.On(function(Attacker, Amount)
    -- ...
end)
```

:::

- Reliable events reach each player in the order they were fired, whichever mix of `Fire`, `FireAll`, `FireList` and `FireExcept` sent them.
- A reliable send to a player who has already left (after `Players.PlayerRemoving`) is dropped.
- A reliable event that arrives before any listener is connected is queued and delivered when the first listener connects. More than 256 queued events print a warning, which usually means a listener is missing.

Full signatures: [Generated API](./generated-api).
