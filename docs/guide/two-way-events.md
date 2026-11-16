# Two-way events

In Blink, every event goes one way: `From: Server` events are fired by the server and heard by clients, `From: Client` events the other way round. When the same message travels in both directions (a ping, a chat line, a ready check, a trade offer) you had to declare two events with two names and keep their types in sync.

Current adds a third value, `From: Both`:

```blink
event Ping {
    From: Both,
    Type: Reliable,
    Call: ManyAsync,
    Data: u32
}
```

One declaration, one name, one type. Both generated modules get the full sending API and the full listening API for it.

## What each side gets

| | Server module | Client module |
|---|---|---|
| Send | `Fire(Player, …)`, `FireAll(…)`, `FireList(Players, …)`, `FireExcept(Player, …)` | `Fire(…)` |
| Receive | `On(function(Player, …))`, or `Iter()` when polling | `On(function(…))`, or `Iter()` when polling |

`Call` picks the listening API on both sides, exactly as for one-way events: `SingleSync`, `ManySync`, `SingleAsync`, `ManyAsync` or `Polling` (see [Events](/reference/events#call)).

## Example: round trip

::: code-group

```lua [server.luau]
local Net = require(ReplicatedStorage.Shared.net.server)

Net.Ping.On(function(Player, SentAt)
    local RoundTrip = os.clock() - SentAt / 1000
    print(Player.Name, "round trip:", RoundTrip)
end)

-- Every few seconds, ping everyone
while true do
    Net.Ping.FireAll(math.floor(os.clock() * 1000))
    task.wait(5)
end
```

```lua [client.luau]
local Net = require(ReplicatedStorage.Shared.net.client)

-- Echo every ping straight back on the same event
Net.Ping.On(function(SentAt)
    Net.Ping.Fire(SentAt)
end)
```

:::

## Example: chat

```blink
struct ChatLine {
    Channel: enum { All, Team },
    Text: string(1..200)
}

event Chat {
    From: Both,
    Type: Reliable,
    Call: ManyAsync,
    Data: ChatLine
}
```

```lua
-- server: filter, then relay to everyone
Net.Chat.On(function(Player, Line)
    Line.Text = FilterFor(Player, Line.Text)
    Net.Chat.FireAll(Line)
end)

-- client: send and display
Net.Chat.Fire({ Channel = "All", Text = TextBox.Text })
Net.Chat.On(function(Line)
    AddToChatWindow(Line)
end)
```

## Cost and safety

- **No extra cost.** Both directions share one event index on the same remote, so a two-way event uses the same bytes and the same table slots as a one-way one. In the benchmark's `two_way` scenario Current is the fastest library tested ([results](./performance)).
- **Same validation.** Data that a client sends on a two-way event is validated on the server exactly like a `From: Client` event: wrong types, out-of-range numbers and over-long strings or arrays are rejected before your listener runs.
- **The server still decides.** A client firing `Chat` only reaches the server's listener. Nothing goes to other clients unless the server fires it on.

::: warning Not in upstream Blink
`From: Both` is Current only. Upstream Blink rejects it with `Unknown option "Both"`, so a schema that uses it needs the `current` compiler.
:::
