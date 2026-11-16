# Introduction

Current is a networking compiler for Roblox. You describe your events, functions and types in a schema file, and Current generates two typed Luau modules from it: one for the server and one for the client (plus TypeScript definitions if you use roblox-ts). The generated code packs everything into buffers, batches it, and sends it through a single pair of remotes.

```blink
event DamageDealt {
    From: Server,
    Type: Reliable,
    Call: ManyAsync,
    Data: (Instance(Player), u8(0..100))
}
```

```lua
-- server
Net.DamageDealt.FireAll(Attacker, 25)

-- client
Net.DamageDealt.On(function(Attacker, Amount)
    print(Attacker.Name, "hit for", Amount)
end)
```

## Why a compiler?

Hand-written `RemoteEvent` code sends Luau tables through Roblox's generic serializer: every event is a separate remote call, every key and type tag goes over the wire, and the server has to check by hand that whatever a client sent is what it expected.

Because Current knows the exact shape of every message ahead of time, it can:

- **Use fewer bytes.** A `u8(0..100)` is one byte; a `vector<i16>` is six. Lower bandwidth means lower ping for players.
- **Use less CPU.** Reads and writes are straight-line buffer code generated for each event, with no reflection and no per-call allocation.
- **Validate client data.** Everything a client sends is checked against the schema (types, number ranges, string and array lengths, instance classes) before your listener runs. See [Security](./security).
- **Type everything.** Listener parameters and fire arguments are fully typed in Luau and TypeScript.

## What Current adds to Blink

Current is a fork of [Blink](https://github.com/1Axen/blink) by [1Axen](https://github.com/1Axen). The schema language, the compiler design, the Studio plugin and most of this documentation come from Blink, under the MIT license. Current keeps the language compatible, so existing `.blink` files compile unchanged, and adds:

- **[Two-way events](./two-way-events).** `From: Both` declares one event that the server and clients can both fire and listen to.
- **[Faster generated code](./performance).** A broadcast log on the server (a `FireAll` is written once whatever the player count), zero-garbage writers, table dispatch of received events, reused listener threads and shared fire functions. In the benchmark harness Current is the fastest of the nine serializing libraries tested, in every scenario.
- **[A hardened server](./security).** The server treats every client packet as hostile: per-player limits on packet size, bytes and events per second (and an optional `Rate` per event or function), finite floats and valid UTF-8 on top of the schema's checks, and decoding under one protected call per packet, so a bad packet is dropped and reported to your [handler](/reference/generated-api#invalid-packets) instead of throwing. Event indexes are shuffled per schema. None of this costs the client anything.
- **Garbage-free steady traffic.** [`ReuseSendBuffers`](/reference/options#reusesendbuffers) reuses outgoing buffers and [`ReuseReceiveTables`](/reference/options#reusereceivetables) decodes into the previous value's tables, so traffic that repeats every frame allocates almost nothing.

See [Migrating from Blink](./migrating-from-blink) for the full list of differences.

## Where to go next

- [Install Current](./installation) with rokit, from GitHub Releases, or as a Studio plugin.
- [Getting started](./getting-started) walks through a first schema and the generated modules.
- The [reference](/reference/schema) covers every type, option and generated function.

::: info Credits
Credits to [Zap](https://zap.redblox.dev/) for the range and array syntax, and to [ArvidSilverlock](https://github.com/ArvidSilverlock) for the float16 implementation (both via Blink).
:::
