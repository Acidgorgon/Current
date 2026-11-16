<div align="center">
  <img src="./docs/public/Logo.png" class="center">
</div>

[![GitHub License](https://img.shields.io/github/license/1Axen/blink?style=flat-square&color=%23a350af)](LICENSE)
[![GitHub Release](https://img.shields.io/github/v/release/1Axen/blink?style=flat-square&color=%23a350af)](https://github.com/1Axen/blink/releases/latest)

An IDL compiler written in Luau for ROBLOX buffer networking

blink-plus is a fork of [Blink](https://github.com/1Axen/blink) by 1Axen.

# Install
With [rokit](https://github.com/rojo-rbx/rokit), add this line under `[tools]` in your `rokit.toml` (or run `rokit add Acidgorgon/blink-plus blink`):

```toml
blink = "Acidgorgon/blink-plus@0.19.0"
```

Or download the archive for your platform from the [Releases](https://github.com/Acidgorgon/blink-plus/releases) page, extract it and put the `blink` executable on your `PATH`. The Studio plugin is attached to each release as `blink-plugin.rbxm`.

blink-plus is a drop-in replacement for the `blink` CLI: the executable has the same name, it takes the same arguments and the same schema language, and it adds `From: Both` events. Run it the same way, e.g. `blink events.blink`.

# Performance
Blink aims to generate the most performant and bandwidth-efficient code for your specific experience, but what does this mean?  

It means lower bandwidth usage directly resulting in **lower ping\*** experienced by players and secondly, it means **lower CPU usage** compared to more generalized networking solutions.

*\* In comparison to standard ROBLOX networking, this may not always be the case but should never result in increased ping times.*

Upstream Blink's Studio benchmarks are [here](./benchmark/Benchmarks.md).

## blink-plus benchmarks

`benchmark/harness/` compares blink-plus with upstream Blink, BlinkBlox, Zap, ByteNet, QuickNet, Packet, Warp, Lync and plain RemoteEvents on football-game traffic with 44 clients, measuring CPU (native and interpreted), exact allocations, module memory and wire bytes. Results: [benchmark/harness/RESULTS.md](./benchmark/harness/RESULTS.md).

# Security
Blink does two things to combat bad actors:
1. Data sent by clients will be **validated** on the receiving side before  reaching any critical game code.
2. As a result of the compression done by Blink it becomes **significantly harder** to snoop on your game's network traffic. Long gone are the days of skids using RemoteSpy to snoop on your game's traffic.

# Get Started
Head over to the [installation](https://1axen.github.io/blink/getting-started/1-installation) page to get started with Blink.

# Credits
Credits to [Zap](https://zap.redblox.dev/) for the range and array syntax  
Credits to [ArvidSilverlock](https://github.com/ArvidSilverlock) for the float16 implementation  
Studio plugin auto completion icons are sourced from [Microsoft](https://github.com/microsoft/vscode-icons) and are under the [CC BY 4.0](https://github.com/microsoft/vscode-icons/blob/main/LICENSE) license.  
<a href="https://www.flaticon.com/free-icons/speed" title="speed icons">Speed icons created by alkhalifi design - Flaticon</a>
