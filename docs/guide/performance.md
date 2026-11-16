# Performance

Current exists to make Blink's generated code faster without changing what it sends. Lower bandwidth means lower ping for players; lower CPU means more frame budget for your game. This page summarises the benchmark; the full tables are in [RESULTS.md](https://github.com/Acidgorgon/Current/blob/main/benchmark/harness/RESULTS.md).

## The benchmark

The harness in [`benchmark/harness/`](https://github.com/Acidgorgon/Current/tree/main/benchmark/harness) runs football-game traffic with **44 clients** through ten networking setups and measures every phase of a frame: CPU (native code and interpreter), exact Luau allocations, module memory and wire bytes. It also checks that every value received equals the value sent, and every library passed in every scenario it can express.

| Label | Library |
|---|---|
| current | Current |
| blinkblox | BlinkBlox 1.4.0, another Blink fork |
| bytenet | ByteNet 0.4.3 |
| zap | Zap 0.6.29 |
| stock | upstream Blink 0.18.9 |
| quicknet | QuickNet 0.4.0 |
| packet | Packet 1.7 |
| warp | Warp 1.1.0-pre8 |
| lync | Lync 4.0 |
| remotes | plain RemoteEvents, one per event, no serialization |

Everything runs in a plain Luau 0.700 VM with a Roblox mock: 7 runs per library (median shown), 600 frames after 120 warm-up frames.

## CPU per frame

Server plus all 44 clients, native codegen, in microseconds. Lower is better; **bold** is the best serializing library.

| Scenario | current | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | **58.3** | 74.5 | 112.0 | 154.8 | 130.7 | 147.0 | 236.2 | 198.3 | 243.2 |
| burst_sync | **37.4** | 62.5 | 111.6 | 114.2 | 87.2 | 123.7 | 242.3 | 196.4 | 231.8 |
| client_input | **91.6** | 107.4 | 116.7 | 99.3 | 99.2 | 137.0 | 184.5 | 197.0 | 622.4 |
| many_events | **198.4** | 291.7 | 659.2 | 551.1 | 616.3 | 932.5 | 1,251.8 | 1,247.7 | 4,470.4 |
| match_state_reliable | **204.1** | 214.5 | 339.7 | 518.8 | 518.5 | 457.2 | 966.2 | 1,234.4 | 1,308.1 |
| match_state_unreliable | **195.8** | 202.3 | 364.3 | 441.3 | 455.3 | 418.2 | 928.2 | 1,265.0 | 1,332.3 |
| per_player | **121.7** | 155.3 | 242.8 | 194.3 | 170.6 | 289.8 | 486.7 | 408.7 | 1,184.8 |
| two_way | **59.3** | 78.6 | 73.0 | 71.0 | n/a | 104.0 | 148.9 | 171.8 | 592.2 |

`n/a`: upstream Blink has no two-way events. Plain RemoteEvents are left out of this table because the mock cannot time Roblox's own C++ serialization of the tables they send, so their CPU numbers are only a lower bound.

## Summary

- **CPU.** Current is the fastest library in every scenario, in native and interpreted mode. BlinkBlox is closest: 3–5% behind on the match snapshots and 17–67% behind elsewhere. Against upstream Blink, Current is **2.5x faster** on the match snapshot, **3.1x** on 120 events per frame and **2.3x** on a 200-event burst.
- **Server cost.** The server part of the frame drops furthest, because a broadcast is written once whatever the player count: 6.8x less than upstream Blink for the snapshot to 44 players, 20x for 120 events (1.5x for per-player sends, the weakest case).
- **Allocations.** Tied with BlinkBlox for the least among the buffer libraries; half of upstream Blink's on the snapshot, and almost none for many small events. [`ReuseSendBuffers`](/reference/options#reusesendbuffers) and [`ReuseReceiveTables`](/reference/options#reusereceivetables) remove most of what is left in steady traffic.
- **Bandwidth.** Tied for the smallest snapshot with upstream Blink and BlinkBlox (16-bit float velocities). Libraries without `f16` send about 25% more. Plain RemoteEvents send 3–4x more bytes, and their unreliable snapshot (about 2 KB per call) is over Roblox's unreliable size limit, so every one would be dropped.
- **Memory.** Current's modules are smaller than upstream Blink's and far smaller than BlinkBlox, Warp, QuickNet and Lync. Zap's client modules are a little smaller still.

::: info Reading the numbers
Runs are interleaved library by library, so ratios between libraries are reliable. Absolute microseconds are only comparable within one run.
:::

## Where the speed comes from

- **A broadcast log.** `FireAll` writes the event once into a shared log; at the end of the frame one `FireAllClients` sends it to everyone, unless some player also has private data that frame.
- **Zero-garbage writers.** Per-player writers are reused across frames, with `ReuseSendBuffers` so are the outgoing buffers, and with `ReuseReceiveTables` so are the decoded tables.
- **Table dispatch.** Received packets jump straight to each event's handler by index, and read their data inline.
- **Reused listener threads** for async listeners, and **shared fire functions** instead of one closure per event and method, which keeps native code small.
- **Less dead code.** Generated modules leave out runtime helpers and enum tables they never use.

## Run it yourself

You need cmake and a C++17 compiler (the host builds itself on first run), python3, `lune` and `luau-compile`. The other libraries are not bundled: clone each one and pass its folder with `--variant`.

```sh
cd benchmark/harness

# One build -> results/<label>.json
./run.sh ../.. current

# Several libraries, runs interleaved (use this for comparisons)
./run.sh --variant stock=blink:$HOME/src/blink-stock \
         --variant current=blink:../..

# Markdown comparison of two result files
python3 compare.py results/stock.json results/current.json --mode both
```

Options include `--runs 7`, `--frames 600`, `--warmup 120`, `--scenarios a,b` and `--modes interp,native`. The harness [README](https://github.com/Acidgorgon/Current/blob/main/benchmark/harness/README.md) explains every scenario, what each phase measures, and how each library's schema differs.
