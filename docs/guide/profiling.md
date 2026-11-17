# Profiling with Lighthouse

[Lighthouse](https://acidgorgon.github.io/Lighthouse/) is the family's profiler. The modules Current
generates have its hooks built in: require Lighthouse and start it on the server and the client,
and every event's bytes and Current's frame work show up in its overlay under **Current**. There is
nothing to add to your schema.

```lua
local Lighthouse = require(ReplicatedStorage.Lighthouse)
Lighthouse.start()
```

Each generated module reads `shared.Lighthouse` once per frame, at the end of `StepReplication`.
Without Lighthouse that lookup and an `if` per event are all it costs: no counters, no allocations.
With `ManualReplication = true` the module only notices Lighthouse when you call `StepReplication`.

## Network channels

There is one channel per event and per function, named as in the schema. An event in a scope is
named `Scope.Name` (for example `Shop.Buy`).

| Direction | When it is reported | Player |
|---|---|---|
| out (server) | once per frame, summed per event | `Fire(player)` (reliable and unreliable) and function returns carry the player they went to; `FireAll`, `FireList` and `FireExcept` are counted once per receiver and carry no player |
| out (client) | once per frame, summed per event | none |
| in (server) | once per packet, per event in it | the player who sent it |
| in (client) | once per packet, per event in it | none |

The bytes are the event's own bytes in the packet: its index, its arguments and, for a function,
the call id. A packet's bytes that belong to no event (a packet the server dropped, or the rest of
one after a bad event) are reported on the `Dropped` channel, so the `in` totals add up to the bytes
that arrived.

## Probes

| Probe | Side | Covers |
|---|---|---|
| `Current.Flush` | both | `StepReplication`: sending the frame's packets |
| `Current.Receive` | both | one incoming packet, including its listeners (and `Sync` callbacks) |
