# Security

Current is built on one rule: **everything a client sends is hostile**. An exploiter controls their
own client completely. They can call `FireServer` on Current's remotes with any arguments, any
bytes and any instance list, as often as they like, and they can read every line of the client
module. Data the server sends to clients is trusted (only your server can send it).

This page describes what the generated server module checks for you, the limits it enforces, how
to hear about bad packets, and what is still your game's job.

## What the server checks

Every packet a client sends goes through these steps before any listener runs:

1. **Arguments.** The remote must be called with a `buffer` and, optionally, a table of
   instances. Anything else (no arguments, a string, a number, a table instead of a buffer) is
   dropped.
2. **Size.** At most `MaxPacketBytes` bytes and `MaxPacketInstances` instances per packet.
3. **Rate.** Each player has two token buckets, one for bytes and one for events per second. A
   packet the player cannot afford is dropped.
4. **Decoding, under protection.** The packet is decoded inside one protected call. Any error
   (a truncated packet, a value outside its range, an unknown enum value, a wrong instance class)
   drops the rest of that packet. Nothing is thrown into the engine and no error spam reaches
   your output.
5. **Event indexes.** An index the server does not listen to (an unknown index, or an event
   that only the server sends) drops the rest of the packet.
6. **Events per packet.** More than `MaxEventsPerPacket` events in one packet drops the rest.

While decoding, the server also checks the values themselves, beyond what Blink checked:

| Type | Check |
|---|---|
| integers | the declared range (and the type's own range) |
| `f16`, `f32`, `f64` | the declared range; NaN and ±inf are rejected unless `ValidateFloats = false` |
| `vector`, `CFrame` | every float component is finite (same option), magnitude ranges |
| `DateTime`, `DateTimeMillis` | the timestamp is finite (same option) |
| `string` | the declared length, and valid UTF-8 unless `ValidateStrings = false` |
| `buffer`, arrays | the declared length; a length read from the packet must fit in the bytes that are left **before** anything is allocated, so a forged length cannot make the server allocate a huge table or buffer |
| `Instance(Class)` | the value is an `Instance` and `IsA(Class)` |
| `Instance?` | anything that is not an `Instance` becomes `nil` |
| enums, tagged enums | the index is one of the variants |
| maps | the declared size, and every key and value as above |

These checks are generated **only in the server module**. The client trusts the server and its
decoders are unchanged, so they cost the client nothing.

A listener only ever receives values that match the schema. If a packet holds three events and
the second is malformed, the first is delivered, and the second and third are not.

## Limits

All limits are per player and are on by default. They are set with options at the top of the
schema. `0` turns a limit off.

| Option | Default | What it limits |
|---|---|---|
| `MaxPacketBytes` | `16384` (16 KB) | bytes in one packet (one `FireServer` call) |
| `MaxPacketInstances` | `256` | instances in one packet |
| `MaxEventsPerPacket` | `256` | events and function calls in one packet |
| `MaxBytesPerSecond` | `65536` (64 KB/s) | bytes per second; each instance counts as 8 bytes |
| `MaxEventsPerSecond` | `1024` | events and function calls per second (an empty packet counts as one) |

```blink
option MaxPacketBytes = 32768
option MaxEventsPerSecond = 2048
```

The defaults are meant to be far above what a real game sends, so that only abusive traffic is
dropped:

- A client sends one reliable packet per frame, holding every reliable event it fired that
  frame, plus one packet per unreliable `Fire`. Typical games send well under 2 KB per second
  from a client; Roblox's own guidance puts a client's upstream budget around 50 KB/s.
  64 KB/s is above that.
- 1024 events per second is 17 events in every frame at 60 FPS, sustained. Typical games send a
  handful.
- The buckets hold one second of their rate (and always at least one full packet), so a burst
  after a hitch goes through.
- For comparison, BlinkBlox's defaults are 64 events and 8 KB per packet and 64 KB/s per player.
  Current's per-packet limits are looser because a reliable packet carries a whole frame of
  events.

If your game legitimately sends more (large blobs, a chatty build tool), raise the limit, and
watch the invalid packet handler during testing to find out.

### Per-event rates

Events and functions can declare their own rate, in calls per second per player:

```blink
event PlaceBlock {
    From: Client,
    Type: Reliable,
    Call: SingleSync,
    Data: vector,
    Rate: 10
}

function Purchase {
    Yield: Coroutine,
    Data: u16,
    Return: boolean,
    Rate: 2
}
```

The bucket holds one second of the rate (at least 1). An event over its rate is decoded and then
dropped (its listeners do not run) and reported as `RateLimited`; the rest of the packet goes on.
A function call over its rate is answered with an error, so the caller's `Invoke` does not hang.
`Rate` is only enforced by the server, on what clients send.

### Functions

- A client picks its own call ids, but the server only ever answers the player who made the
  call, through that player's own stream. A forged or repeated id can only confuse the client
  that sent it.
- At most 256 calls per player may wait for an answer at once (an honest client never has more
  than 255). More are dropped as `TooManyInvocations`. This stops a client from piling up
  threads behind a listener that yields.
- Calls made before the server connects a listener are queued, at most 1024 per function;
  calls beyond that are answered with an error. Events queued before a listener connects are
  capped at 1024 as well.
- Function calls count against the packet and per-second limits like events.

### Players that leave

A player's buckets and counters are removed when they leave (`PlayerRemoving`), and are held in
a weak table, so a late packet cannot keep them alive.

## The invalid packet handler

Every dropped packet is reported. By default the server warns, at most once per player every
10 seconds:

```
[Current]: Dropped a packet from Name (12345): Malformed: Expected a finite number
```

Set your own handler to log, count or kick:

```lua
local Net = require(ReplicatedStorage.Network.Server)

local Strikes = {}

Net.SetInvalidPacketHandler(function(Player: Player, Reason: Net.InvalidPacketReason, Detail: string)
    if Reason == "RateLimited" then
        return -- can happen to a lagging player, do not punish it
    end
    Strikes[Player] = (Strikes[Player] or 0) + 1
    if Strikes[Player] >= 10 then
        Player:Kick("Invalid network traffic")
    end
end)
```

Pass `nil` to go back to the default warning. The handler runs on its own thread, so it may
yield, and an error in it does not affect the server's networking. It is called for every
dropped packet, so keep it cheap.

| Reason | Meaning |
|---|---|
| `InvalidArguments` | the remote was called with something other than `(buffer, {Instance}?)` |
| `TooLarge` | over `MaxPacketBytes` or `MaxPacketInstances` |
| `TooManyEvents` | over `MaxEventsPerPacket` |
| `RateLimited` | over the bytes or events per second, or an event's own `Rate` (the detail names it) |
| `UnknownEvent` | an event index the server does not listen to |
| `Malformed` | the packet did not decode; the detail is the decoder's message |
| `TooManyInvocations` | more than 256 function calls waiting for an answer |

`Malformed`, `UnknownEvent`, `InvalidArguments`, `TooManyEvents` and `TooManyInvocations` are
never produced by an unmodified client. `TooLarge` and `RateLimited` can be, if your limits are
too tight for your game.

## Listener errors

An error in your own listener is not the client's fault, and is not reported as an invalid
packet. For `Async` listeners nothing changes: each runs on its own thread. A `Sync` listener
runs inside the packet's protected call. When it errors, the error is reported with its
traceback like any script error, and the server carries on with the next event in the packet.
(The other `Sync` listeners of that same event are skipped for that one event.)

As before, do not yield in a `Sync` listener.

## Shuffled event indexes

Each event's index on the wire is assigned by a fixed shuffle seeded from your schema. The same
schema always compiles to the same output; when you add, remove or rename an event the order
changes. Scripts made for one version of your game that hardcode "byte N is event X" stop
working on the next.

Be clear about what this is: **obscurity, not security**. It costs nothing at run time and
raises the bar for copy-pasted scripts, but anyone can read the indexes out of the client module.
The server's validation and limits are what actually protect you.

```blink
option ShuffleEventIds = false   -- keep declaration order
option EventIdSeed = "season-4"  -- reshuffle without changing events
```

## What is still your job

Current guarantees that what reaches a listener has the shape your schema describes. It cannot
know whether it makes sense for your game:

- **Keep the server authoritative.** The client asks, the server decides. Do not let the client
  send its health, its currency, the damage it dealt or the item it received. Send intents
  ("I want to buy item 12", "I fired in this direction") and check them on the server.
- **Check values against game state.** A position can be finite and still be inside a wall or
  200 studs from where the player was a moment ago. A valid item id can be one the player does
  not own.
- **Instances can be any instance the server can see.** `Instance(BasePart)` only promises a
  `BasePart`: it may be another player's character, a part in a place they cannot reach, or
  something outside the area you expect. Check ownership and distance.
- **Instances the server cannot see arrive as `nil`.** A part created only on the client, or one
  streamed out, cannot be sent. A non-optional `Instance` field then fails to decode and the
  packet is reported as `Malformed`. Use `Instance?` where that can happen honestly.
- **`unknown` is unchecked.** It carries whatever the client put there. Validate it yourself, or
  use a precise type instead.
- **Limit actions, not just traffic.** The network limits stop floods. "Can this player swing
  their sword again yet" is a game rule; use a per-event `Rate` or a cooldown in your listener.
- **Drain polled events every frame.** Polled events wait in a queue until you call `Iter`;
  the per-player rate limits bound how fast it fills.
- **Treat strings as user input.** Valid UTF-8 can still be offensive, very long (up to its
  declared range), or full of rich-text tags. Filter text that other players will see.
