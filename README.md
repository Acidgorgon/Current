# Current

[![GitHub License](https://img.shields.io/github/license/Acidgorgon/current?style=flat-square&color=%23a350af)](LICENSE)
[![GitHub Release](https://img.shields.io/github/v/release/Acidgorgon/current?style=flat-square&color=%23a350af)](https://github.com/Acidgorgon/current/releases/latest)

A faster Roblox networking IDL compiler with two-way events, forked from [Blink](https://github.com/1Axen/blink).

You describe your events, functions and types in a schema file, and Current generates typed server and client Luau modules (and optional TypeScript definitions) that batch everything into buffers. Current reads Blink's schema language, so existing `.blink` files compile unchanged.

> [!NOTE]
> **Made with Claude.** Most of Current was written with [Claude](https://claude.ai), Anthropic's AI, to speed up my own Roblox workflow. Issues and pull requests are welcome.

What Current adds on top of Blink:

- **Two-way events.** `From: Both` declares one event that the server and clients can both fire and both listen to, sharing one event index:

  ```
  event Ping {
      From: Both,
      Type: Reliable,
      Call: ManyAsync,
      Data: u32
  }
  ```

  Data sent by clients is validated on the server exactly like a `From: Client` event. See [Two-way events](https://acidgorgon.github.io/Current/guide/two-way-events).
- **Faster generated code.** In the benchmark harness Current is the fastest of the nine serializing libraries tested in every scenario, and 2.8x faster than upstream Blink 0.18.9 on a 44-player match snapshot (6.2x with `ReuseReceiveTables`) and 3.4x on 120 events per frame, with its server hardening on. Results: [benchmark/harness/RESULTS.md](./benchmark/harness/RESULTS.md).

# Install

With [rokit](https://github.com/rojo-rbx/rokit), run `rokit add Acidgorgon/current`, or add this line under `[tools]` in your `rokit.toml`:

```toml
current = "Acidgorgon/current@0.1.0"
```

Or download the archive for your platform from the [Releases](https://github.com/Acidgorgon/current/releases) page, extract it and put the `current` executable (`current.exe` on Windows) on your `PATH`.

Then compile a schema:

```sh
current events
```

This looks for `events`, `events.txt`, `events.blink` or `events.current` in the current directory. Run `current --help` for the options, including `--watch`.

## Studio plugin

The Studio plugin lets you write schemas and generate modules inside Roblox Studio. Download `current-plugin.rbxm` from the [Releases](https://github.com/Acidgorgon/current/releases) page and put it in your Studio plugins folder. It shows up in the Plugins tab as **Current**.

# Performance
Current, like Blink, aims to generate the most performant and bandwidth-efficient code for your specific experience, but what does this mean?

It means lower bandwidth usage directly resulting in **lower ping\*** experienced by players and secondly, it means **lower CPU usage** compared to more generalized networking solutions.

*\* In comparison to standard ROBLOX networking, this may not always be the case but should never result in increased ping times.*

## Benchmarks

`benchmark/harness/` compares Current with upstream Blink, BlinkBlox, Zap, ByteNet, QuickNet, Packet, Warp, Lync and plain RemoteEvents on football-game traffic with 44 clients, measuring CPU (native and interpreted), exact allocations, module memory and wire bytes. Results: [benchmark/harness/RESULTS.md](./benchmark/harness/RESULTS.md).

Upstream Blink's Studio benchmarks are [here](./benchmark/Benchmarks.md).

# Security
The server treats everything a client sends as hostile:
1. **Validation.** Data sent by clients is checked against the schema before it reaches a listener: ranges, lengths, enums, instance classes, and by default finite floats and valid UTF-8. A malformed packet is dropped and reported; it never throws into the engine.
2. **Limits.** Per-player caps on packet size, events per packet, bytes and events per second, function calls in flight, and optional per-event rates, all on by default and configurable.
3. **Reporting.** `SetInvalidPacketHandler` tells your game which player sent what kind of bad packet, so it can log or kick.
4. **Obscurity, on top.** Packed buffers and per-schema shuffled event indexes make traffic harder to snoop on and break copy-pasted scripts across updates. This is not a defense on its own.

See [Security](./docs/guide/security.md) for the threat model, the checks, the limits and their defaults, and what is still your game's job.

# Get Started
Read the documentation at **https://acidgorgon.github.io/Current/**: start with [installation](https://acidgorgon.github.io/Current/guide/installation), then [getting started](https://acidgorgon.github.io/Current/guide/getting-started) and the [schema language reference](https://acidgorgon.github.io/Current/reference/schema). Coming from Blink? See [Migrating from Blink](https://acidgorgon.github.io/Current/guide/migrating-from-blink).

The site's source is in [docs/](./docs) (VitePress): `cd docs && npm ci && npm run docs:dev`.

# Credits
Current is a fork of [Blink](https://github.com/1Axen/blink) by [1Axen](https://github.com/1Axen), under the MIT license (see [LICENSE](LICENSE)). The compiler, schema language, Studio plugin and documentation all come from Blink.

Credits to [Zap](https://zap.redblox.dev/) for the range and array syntax  
Credits to [ArvidSilverlock](https://github.com/ArvidSilverlock) for the float16 implementation  
Studio plugin auto completion icons are sourced from [Microsoft](https://github.com/microsoft/vscode-icons) and are under the [CC BY 4.0](https://github.com/microsoft/vscode-icons/blob/main/LICENSE) license.  
<a href="https://www.flaticon.com/free-icons/speed" title="speed icons">Speed icons created by alkhalifi design - Flaticon</a>
