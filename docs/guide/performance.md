# Performance

Current exists to make Blink's generated code faster without making it send more. Lower bandwidth means lower ping for players; lower CPU means more frame budget for your game. This page summarises the benchmark; the full tables are in [RESULTS.md](https://github.com/Acidgorgon/Current/blob/main/benchmark/harness/RESULTS.md).

## The benchmark

The harness in [`benchmark/harness/`](https://github.com/Acidgorgon/Current/tree/main/benchmark/harness) runs football-game traffic with **44 clients** through ten networking setups and measures every phase of a frame: CPU (native code and interpreter), exact Luau allocations, module memory and wire bytes. It also checks that every value received equals the value sent, and every library passed in every scenario it can express.

| Label | Library |
|---|---|
| current | Current, default options |
| current-reuse | Current with [`ReuseReceiveTables`](/reference/options#reusereceivetables) on |
| blinkblox | BlinkBlox 1.4.0, another Blink fork |
| bytenet | ByteNet 0.4.3 |
| zap | Zap 0.6.29 |
| stock | upstream Blink 0.18.9 |
| quicknet | QuickNet 0.4.0 |
| packet | Packet 1.7 |
| warp | Warp 1.1.0-pre8 |
| lync | Lync 4.0 |
| remotes | plain RemoteEvents, one per event, no serialization |

Everything runs in a plain Luau 0.700 VM with a Roblox mock: 7 runs per library (median shown), 600 frames after 120 warm-up frames. Current runs with its [server hardening](./security) on (packet limits, value checks, one protected call per packet); only the per-second budgets are off, because the harness runs frames much faster than real time.

## CPU per frame

Server plus all 44 clients, native codegen, in microseconds. Lower is better; **bold** is the best serializing library.

| Scenario | current | current-reuse | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | 54.7 | **43.0** | 73.5 | 109.4 | 157.7 | 135.5 | 147.9 | 224.8 | 189.7 | 229.0 |
| burst_sync | 32.3 | **27.1** | 55.8 | 116.6 | 112.4 | 89.8 | 133.5 | 235.9 | 190.3 | 242.3 |
| client_input | 92.5 | **82.3** | 129.9 | 133.3 | 108.1 | 106.5 | 146.8 | 208.0 | 203.9 | 674.7 |
| many_events | **206.2** | 211.4 | 363.8 | 676.4 | 667.8 | 695.7 | 967.0 | 1,264.6 | 1,306.1 | 5,378.7 |
| match_state_reliable | 185.8 | **84.2** | 216.3 | 341.7 | 509.1 | 525.9 | 441.5 | 937.4 | 1,232.6 | 1,341.2 |
| match_state_unreliable | 176.4 | **76.9** | 205.4 | 346.0 | 445.0 | 484.0 | 430.3 | 933.2 | 1,298.2 | 1,343.8 |
| per_player | 105.5 | **95.6** | 169.2 | 302.6 | 235.3 | 175.0 | 288.3 | 474.6 | 394.4 | 1,340.3 |
| two_way | **70.2** | 80.4 | 81.4 | 74.1 | 71.7 | n/a | 117.0 | 167.7 | 211.3 | 598.1 |

`n/a`: upstream Blink has no two-way events. On `two_way` nothing is reused, so `current-reuse` runs exactly the same code as `current`: the gap between them there is run-to-run noise. Plain RemoteEvents are left out of this table because the mock cannot time Roblox's own C++ serialization of the tables they send, so their CPU numbers are only a lower bound.

## Summary

- **CPU.** With default options Current is the fastest of the nine serializing libraries in every scenario, in native and interpreted mode (by 2% over Zap on `two_way` and 4% over upstream Blink on interpreted `client_input`, the two close calls). Against upstream Blink it is **2.8x faster** on the match snapshot, **3.4x** on 120 events per frame and 2.5–2.8x on a 200-event burst. BlinkBlox is the closest other library: 16% behind on the match snapshots and `two_way`, 34–76% behind elsewhere.
- **ReuseReceiveTables.** When clients receive the same shape every frame, reusing their tables removes most of what is left: the match snapshot drops from 186 to 84 µs per frame, **6.2x faster than upstream Blink** and 2.6x faster than BlinkBlox, and allocates 513 bytes per frame instead of 328 KB.
- **Server and client.** The server part of the frame drops furthest, because a broadcast is written once whatever the player count: 31.8x less than upstream Blink for 120 events and 7.1x for the reliable snapshot to 44 players. Each client decodes the snapshot 2.8–3.0x faster than upstream Blink, and 6.8–7.6x with `ReuseReceiveTables`.
- **Allocations.** About the same as BlinkBlox and 2.1x less than upstream Blink on the reliable snapshot with default options; with [`ReuseSendBuffers`](/reference/options#reusesendbuffers) and [`ReuseReceiveTables`](/reference/options#reusereceivetables) steady traffic allocates almost nothing.
- **Bandwidth.** The smallest snapshot (16-bit float velocities, like upstream Blink and BlinkBlox, and no empty instance list). Libraries without `f16` send about 26% more. Plain RemoteEvents send 3–5x more bytes, and their unreliable snapshot (about 2 KB per call) is over Roblox's unreliable size limit, so every one would be dropped.
- **Memory.** Current's client modules are smaller than upstream Blink's and far smaller than BlinkBlox, Warp, QuickNet and Lync; Zap's are a little smaller still. Server modules include the security checks, so on small schemas they are up to 17 KB larger than upstream Blink's.

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
         --variant current=blink:../.. \
         --variant current-reuse=blink+reuse:../..

# Markdown comparison of two result files
python3 compare.py results/stock.json results/current.json --mode both
```

Options include `--runs 7`, `--frames 600`, `--warmup 120`, `--scenarios a,b` and `--modes interp,native`. The harness [README](https://github.com/Acidgorgon/Current/blob/main/benchmark/harness/README.md) explains every scenario, what each phase measures, and how each library's schema differs.
