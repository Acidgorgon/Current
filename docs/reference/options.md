# Options

Options configure the generated code. They go at the top of a schema file, one per line:

```blink
option Casing = Camel
option ServerOutput = "../src/shared/net/server.luau"
option ClientOutput = "../src/shared/net/client.luau"
```

Strings are in double quotes, booleans are `true` or `false`, numbers are written bare, as whole numbers, and `Casing` takes a bare name. An unknown option name is an error.

| Option | Type | Default |
|---|---|---|
| [`ServerOutput`](#serveroutput-clientoutput-typesoutput) | string | required (CLI) |
| [`ClientOutput`](#serveroutput-clientoutput-typesoutput) | string | required (CLI) |
| [`TypesOutput`](#serveroutput-clientoutput-typesoutput) | string | none |
| [`Typescript`](#typescript) | boolean | `false` |
| [`Casing`](#casing) | `Pascal`, `Camel`, `Snake` | `Pascal` |
| [`UsePolling`](#usepolling) | boolean | `false` |
| [`FutureLibrary`](#futurelibrary-and-promiselibrary) | string | none |
| [`PromiseLibrary`](#futurelibrary-and-promiselibrary) | string | none |
| [`SyncValidation`](#syncvalidation) | boolean | `true` |
| [`WriteValidations`](#writevalidations) | boolean | `false` |
| [`ManualReplication`](#manualreplication) | boolean | `false` |
| [`ReuseSendBuffers`](#reusesendbuffers) | boolean | `false` |
| [`ReuseReceiveTables`](#reusereceivetables) | boolean | `false` |
| [`RemoteScope`](#remotescope) | string | `""` |
| [`UseColon`](#usecolon) | boolean | `false` |
| [`ShuffleEventIds`](#shuffleeventids) | boolean | `true` |
| [`EventIdSeed`](#eventidseed) | string | `""` |
| [`ValidateFloats`](#validatefloats) | boolean | `true` |
| [`ValidateStrings`](#validatestrings) | boolean | `true` |
| [`MaxPacketBytes`](#limits) | number | `16384` |
| [`MaxPacketInstances`](#limits) | number | `256` |
| [`MaxEventsPerPacket`](#limits) | number | `256` |
| [`MaxBytesPerSecond`](#limits) | number | `65536` |
| [`MaxEventsPerSecond`](#limits) | number | `1024` |

## `ServerOutput`, `ClientOutput`, `TypesOutput`

Where the CLI writes the generated modules, relative to the schema file (or absolute). `ServerOutput` and `ClientOutput` are required by the CLI; the [Studio plugin](./plugin) ignores them and asks where to put the modules instead. The `.luau` extension is added if you leave it out.

`TypesOutput` is optional. When set, Current also writes a shared module with only the types and the `Read`/`Write` functions of [exported](./schema#exports) types, which both sides can require.

```blink
option ServerOutput = "../Network/Server.luau"
option ClientOutput = "../Network/Client.luau"
option TypesOutput = "../Network/Types.luau"
```

## `Typescript`

Also write TypeScript declaration files (`.d.ts`) for [roblox-ts](https://roblox-ts.com/), next to the server and client outputs and with the same names (`init.luau` gets `index.d.ts`).

```blink
option Typescript = true
```

## `Casing`

The casing of the generated method names.

| Casing | Methods |
|---|---|
| `Pascal` | `Fire`, `FireAll`, `FireList`, `FireExcept`, `On`, `Iter`, `Invoke`, `StepReplication`, `SetInvalidPacketHandler`, `Read`, `Write` |
| `Camel` | `fire`, `fireAll`, `fireList`, `fireExcept`, `on`, `iter`, `invoke`, `stepReplication`, `setInvalidPacketHandler`, `read`, `write` |
| `Snake` | `fire`, `fire_all`, `fire_list`, `fire_except`, `on`, `iter`, `invoke`, `step_replication`, `set_invalid_packet_handler`, `read`, `write` |

```blink
option Casing = Camel
```

Event, function and type names are kept exactly as written in the schema.

## `UsePolling`

Generate every event with the [polling](./events#polling) API (`Iter`) instead of listeners, whatever its `Call`.

```blink
option UsePolling = true
```

## `FutureLibrary` and `PromiseLibrary`

Functions with `Yield: Future` or `Yield: Promise` need the library to use. The value is a Luau expression that the generated module passes to `require`:

```blink
option FutureLibrary = "ReplicatedStorage.Packages.Future"
option PromiseLibrary = "ReplicatedStorage.Packages.Promise"
```

Compiling a `Future` or `Promise` function without the matching option is an error.

## `SyncValidation`

Default `true`. Check whether a `SingleSync` or `ManySync` listener yielded. When one did, Current warns (`Yielded in a Sync call. Event "…" uses a Sync call, consider using an Async call instead.`) and closes the yielded thread. Turn it off to save the check on very hot sync events once you are sure none of their listeners yield.

## `WriteValidations`

Default `false`. Check the types of the values you pass when firing an event or invoking a function, and error with a clear message when they don't match the schema. Useful while developing; it costs some performance, so turn it off in production.

::: info
Only built-in primitives are checked (for example that a number was passed where a number is expected). Structs, maps, enums and other composite types are not.
:::

Data received from the other side is always validated when it is read, whatever this option says.

## `ManualReplication`

Default `false`. Reliable events and function calls are batched and sent once per frame, on `RunService.Heartbeat`. With `ManualReplication = true` nothing is sent automatically: call the module's `StepReplication()` yourself, as often as you like (for example at the end of your own frame loop or tick).

```lua
local Net = require(ReplicatedStorage.Shared.net.server)

RunService.PostSimulation:Connect(function()
    Simulate()
    Net.StepReplication()
end)
```

Unreliable events are sent immediately in either mode.

## `ReuseSendBuffers`

Default `false`.

When `true`, outgoing packets are copied into a pool that keeps one exact-size buffer per packet size (up to 64 KB of buffers in total), instead of a new buffer per remote call. Every send of a given size reuses the same buffer, so steady traffic (a fixed-size match state broadcast, per-player packets whose sizes repeat from frame to frame) creates almost no garbage. It relies on Roblox copying a buffer's contents when a remote is fired, which is how remotes serialize their arguments.

```blink
option ReuseSendBuffers = true
```

This option is Current only; upstream Blink rejects it.

## `ReuseReceiveTables`

Default `false`.

When `true`, a listened event decodes each value into the tables of its previous value instead of allocating new ones: structs, arrays, maps and sets, and those nested inside them, are overwritten in place. For steady traffic (for example a match state received every frame) this removes all the garbage the receiving side makes. It can be turned on or off for a single event with the [`ReuseTables`](./events#reusetables) field.

```blink
option ReuseReceiveTables = true
```

::: warning The next value overwrites the table
A listener receives a table that **the next value of the same event overwrites**. Read what you need while the listener runs, and copy anything you keep (`table.clone`, or the fields themselves) instead of storing the table or any table inside it. Do not modify it.
:::

When the table stays valid:

- `Sync` listeners: until the listener returns.
- `Async` listeners: until the listener returns. If it yields, Current sees that its thread did not come back and leaves that value alone: the next value gets new tables, so the yielded listener's value stays intact until it finishes (but the value is still overwritten if you store it and read it after the listener finished).
- Values that arrive before a listener is connected are queued with their own tables.
- `Polling` events never reuse tables: their values wait in a queue.
- Every listener of a `Many` event receives the same table, as without this option.
- On the server each player has their own tables: a value is only overwritten by the same player's next value of the event, not by another player's.

How values are updated:

- Arrays keep their table: items are overwritten, and a shorter array has its tail removed.
- Maps keep their table: it is emptied and refilled, so keys that are no longer sent are gone.
- Optional fields are set to `nil` when absent.
- Tagged enums keep their table only while the variant stays the same.
- Tables that leave a value (the tail of an array that got shorter, the values of a map, an optional struct that became `nil`) are kept and used for later values, so a value whose shape changes does not allocate either.
- Values that are not tables (numbers, strings, vectors, enums, instances) are unaffected. `buffer` values and Roblox types such as `CFrame` are still created for every value.

This option is Current only; upstream Blink rejects it.

## `RemoteScope`

Default `""`. A prefix for the remotes the generated modules create in `ReplicatedStorage`. Without it they are `CURRENT_RELIABLE_REMOTE` and `CURRENT_UNRELIABLE_REMOTE`; with `option RemoteScope = "PACKAGE"` they are `PACKAGE_CURRENT_RELIABLE_REMOTE` and `PACKAGE_CURRENT_UNRELIABLE_REMOTE`.

```blink
option RemoteScope = "PACKAGE"
```

Use it when Current runs inside a package (or a game has several schemas compiled separately), so the modules don't collide with the game's own. Two Current modules with the same scope running at once is an error.

Current's remotes and its `_G._CURRENT` registry have different names from Blink's (`BLINK_RELIABLE_REMOTE`, `_G._BLINK`), so a Current module and a Blink module can run in the same game without setting a scope.

## `UseColon`

Accepted for compatibility with older Blink schemas. It has no effect on the generated code.

## `ShuffleEventIds`

Default `true`. Event indexes on the wire are a deterministic permutation per channel, seeded by a hash of the schema (whitespace and comments don't affect it). Client and server built from the same schema always agree. This is obscurity, not security; see [Security](../guide/security#shuffled-event-indexes). `false` uses declaration order.

```blink
option ShuffleEventIds = false
```

## `EventIdSeed`

Default `""`. Mixed into the shuffle seed. Change it to reshuffle indexes without changing the schema.

```blink
option EventIdSeed = "season-4"
```

## `ValidateFloats`

Default `true`. The server rejects NaN and ±infinity in client data (`f16`/`f32`/`f64`, `vector`, `CFrame`, `DateTime`). Floats with a finite range are already checked by the range. `false` lets them through. The client never pays for this.

## `ValidateStrings`

Default `true`. The server rejects client strings that aren't valid UTF-8. `false` skips the check (for example, for strings used as raw bytes).

## `MaxPacketBytes`, `MaxPacketInstances`, `MaxEventsPerPacket`, `MaxBytesPerSecond`, `MaxEventsPerSecond` {#limits}

Defaults `16384`, `256`, `256`, `65536` and `1024`. Per-player limits on what a client may send; see [Security](../guide/security#limits). Whole numbers; `0` turns a limit off. Each instance reference counts as 8 bytes against `MaxBytesPerSecond`. Each bucket's burst is one second of its rate, but never less than one packet at the packet limit.

```blink
option MaxPacketBytes = 32768
option MaxEventsPerSecond = 2048
```

These options are Current only; upstream Blink rejects them.
