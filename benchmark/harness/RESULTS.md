# Results

One interleaved run of ten libraries on 2026-11-16 (Current twice: default
options, and with `ReuseReceiveTables`): Luau 0.700 VM, mock Roblox with 44
clients, 7 runs per library (median shown), 600 frames after 120 warmup
frames, in native codegen and interpreter mode, every process pinned to one
core (`--cpu 2`) with nothing else running. Every library passed the
received-equals-sent check in every scenario it can express. Raw numbers are
in `results/<label>.json`; the method and every schema difference between
libraries are in [README.md](README.md).

| label | library |
|---|---|
| current | Current (this repo, commit bedcb9b), default options |
| current-reuse | the same commit with `option ReuseReceiveTables = true` (adapter flag `blink+reuse`) |
| blinkblox | BlinkBlox 1.4.0, another Blink fork |
| bytenet | ByteNet 0.4.3 |
| zap | Zap 0.6.29 |
| stock | upstream Blink 0.18.9 |
| quicknet | QuickNet 0.4.0 |
| packet | Packet 1.7 |
| warp | Warp 1.1.0-pre8 |
| lync | Lync 4.0 |
| remotes | plain RemoteEvents, one per event, no serialization |

Both Current builds run with the server hardening on: packet size and count
limits, value checks (finite floats, UTF-8) and one `xpcall` per received
packet. Only the per-player per-second budgets are turned off, because they
refill from `os.clock` and the harness runs frames far faster than real time
(BlinkBlox's limits are raised for the same reason; see the README's schema
differences).

The best library value in each row is bold. `remotes` is never marked best:
the mock cannot time Roblox's own C++ serialization of the tables it sends,
so its CPU numbers are a lower bound. `n/a` means the library cannot express
the scenario (stock Blink has no two-way events).

## Summary

- **CPU:** with default options Current is the fastest of the nine
  serializing libraries in every scenario, in native and interpreted mode.
  Two margins are small: `two_way` in native mode (Zap 2% behind, well inside
  run-to-run noise) and `client_input` interpreted (stock Blink 4% behind).
  Against stock Blink, Current is 2.8x faster on the match snapshot (2.83x
  reliable, 2.74x unreliable), 3.4x on 120 events per frame and 2.5–2.8x on
  a 200-event burst (native). BlinkBlox is the closest other library: 16%
  behind on the match snapshots and `two_way`, 34–76% behind elsewhere.
- **ReuseReceiveTables:** where clients receive tables every frame it removes
  most of the remaining cost. The match snapshot drops from 186 to 84 µs per
  frame (native), **6.2–6.3x faster than stock Blink** and 2.6–2.7x faster
  than BlinkBlox; a 200-event burst is 3.1–3.3x faster than stock. Where nothing
  is reused (`many_events`, `two_way`) the generated code does the same work
  as `current`'s; for `two_way` it is byte for byte identical, so the 70 vs
  80 µs there shows this run's noise (min–max over 7 runs: 66–92 and
  67–114 µs).
- **Server cost:** the server part of the frame drops furthest, because a
  broadcast is written once whatever the player count: 31.8x less than stock
  for 120 events and 7.1x for the reliable snapshot to 44 players (see the
  breakdown below).
- **Allocations:** with default options 2.1x less than stock on the reliable
  snapshot (1.7x unreliable), and about the same as BlinkBlox. With
  `ReuseReceiveTables` the snapshot allocates 513 bytes per frame instead of
  328 KB, the least of any library in every scenario except `two_way`
  (`many_events` is tied at 88 bytes with `current` and BlinkBlox).
- **Bandwidth:** the smallest snapshot (22,352 bytes per frame, 16-bit float
  velocities like stock Blink and BlinkBlox). Current also leaves out the
  instance list when a packet has none, which saves 2 bytes per remote call
  in the mock's estimate. Libraries without f16 send about 26% more.
- **Memory:** Current's client modules are smaller than stock Blink's (0.3 KB
  larger on `client_input`) and far smaller than BlinkBlox, Warp (~1.3 MB f16 table),
  QuickNet (~4 MB client queues) and Lync; Zap's are a little smaller still.
  The server modules carry the security checks: 8–17 KB larger than stock's
  for `burst` and the match snapshot, 1–10 KB smaller for `client_input` and
  `per_player`, and 249 KB instead of 926 KB on `many_events`.
- **Plain RemoteEvents** send 3–5x more bytes (1.3x on `two_way`), and the
  unreliable snapshot (~2 KB per call) is over Roblox's unreliable size
  limit, so every one would be dropped.

Runs are interleaved library by library, so ratios are reliable; absolute µs
are only comparable within this run.

## Server and client, against stock Blink

`server` is the server's whole frame (`server_send + server_step +
server_recv`), `client` is one client's receive cost
(`client_recv_per_client`), both native, in µs. Ratios are stock / Current
(higher is better for Current).

| scenario | server: current | server: stock | ratio | client: current | client: current-reuse | client: stock | ratio (current) | ratio (current-reuse) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | 11.6 | 35.7 | 3.08x | 42.50 | 31.29 | 98.01 | 2.31x | 3.13x |
| burst_sync | 11.4 | 37.9 | 3.33x | 20.26 | 15.51 | 51.47 | 2.54x | 3.32x |
| client_input | 46.9 | 52.4 | 1.12x | 0.11 | 0.11 | 0.11 | 1.04x | 1.03x |
| many_events | 10.8 | 343.7 | 31.78x | 4.07 | 4.13 | 7.32 | 1.80x | 1.77x |
| match_state_reliable | 7.9 | 55.7 | 7.09x | 3.64 | 1.49 | 10.20 | 2.80x | 6.83x |
| match_state_unreliable | 7.7 | 10.5 | 1.37x | 3.42 | 1.35 | 10.31 | 3.01x | 7.63x |
| per_player | 36.0 | 71.6 | 1.99x | 1.26 | 1.02 | 2.04 | 1.61x | 2.00x |

The server ratios are largest for broadcasts: `many_events` (24 `FireAll`
per frame) is 31.8x cheaper on the server and the reliable snapshot 7.1x,
because Current writes each broadcast once into a shared log instead of once
per player. The unreliable snapshot goes out with one `FireAllClients` in both
libraries, so there the server gains less (1.37x). Per-player sends gain 2x,
and `client_input`, where only the server receives, 1.12x even with the
security checks every client packet goes through. On the client, Current decodes
the snapshot 2.8–3.0x faster than stock, and 6.8–7.6x with
`ReuseReceiveTables`. `current-reuse`'s server code is the same as
`current`'s for the snapshot, so it is not listed on the server side.

### CPU per frame, native codegen (µs, server + all clients)

| scenario | current | current-reuse | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | 54.7 | **43.0** | 73.5 | 109.4 | 157.7 | 135.5 | 147.9 | 224.8 | 189.7 | 229.0 | 32.5 |
| burst_sync | 32.3 | **27.1** | 55.8 | 116.6 | 112.4 | 89.8 | 133.5 | 235.9 | 190.3 | 242.3 | 33.4 |
| client_input | 92.5 | **82.3** | 129.9 | 133.3 | 108.1 | 106.5 | 146.8 | 208.0 | 203.9 | 674.7 | 30.3 |
| many_events | **206.2** | 211.4 | 363.8 | 676.4 | 667.8 | 695.7 | 967.0 | 1,264.6 | 1,306.1 | 5,378.7 | 235.4 |
| match_state_reliable | 185.8 | **84.2** | 216.3 | 341.7 | 509.1 | 525.9 | 441.5 | 937.4 | 1,232.6 | 1,341.2 | 29.6 |
| match_state_unreliable | 176.4 | **76.9** | 205.4 | 346.0 | 445.0 | 484.0 | 430.3 | 933.2 | 1,298.2 | 1,343.8 | 30.6 |
| per_player | 105.5 | **95.6** | 169.2 | 302.6 | 235.3 | 175.0 | 288.3 | 474.6 | 394.4 | 1,340.3 | 66.5 |
| two_way | **70.2** | 80.4 | 81.4 | 74.1 | 71.7 | n/a | 117.0 | 167.7 | 211.3 | 598.1 | 30.4 |

### CPU per frame, interpreter (µs, server + all clients)

| scenario | current | current-reuse | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | 89.2 | **79.2** | 112.0 | 162.4 | 188.8 | 168.2 | 226.1 | 307.0 | 287.3 | 385.0 | 58.1 |
| burst_sync | 55.3 | **54.1** | 83.8 | 160.7 | 137.4 | 116.4 | 191.6 | 272.9 | 278.2 | 380.4 | 55.5 |
| client_input | 116.6 | **101.6** | 139.2 | 161.3 | 132.2 | 121.5 | 185.2 | 271.8 | 282.1 | 759.8 | 43.5 |
| many_events | 287.7 | **285.6** | 390.4 | 930.9 | 851.3 | 894.7 | 1,296.7 | 1,511.4 | 1,608.2 | 7,376.3 | 293.1 |
| match_state_reliable | 363.7 | **251.0** | 497.4 | 512.4 | 616.9 | 690.5 | 684.1 | 1,118.7 | 1,842.9 | 1,658.3 | 36.7 |
| match_state_unreliable | 349.7 | **240.5** | 464.7 | 523.8 | 538.7 | 657.7 | 656.7 | 1,131.3 | 1,860.9 | 1,677.5 | 38.6 |
| per_player | 148.8 | **136.9** | 210.7 | 293.1 | 234.2 | 230.7 | 362.0 | 607.2 | 527.8 | 1,623.8 | 83.5 |
| two_way | **92.1** | 93.3 | 128.5 | 107.3 | 120.1 | n/a | 133.6 | 200.5 | 244.1 | 631.0 | 45.9 |

### Receive cost per client, native (µs)

| scenario | current | current-reuse | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | 42.50 | **31.29** | 43.44 | 51.51 | 92.70 | 98.01 | 99.67 | 151.47 | 106.76 | 111.98 | 15.62 |
| burst_sync | 20.26 | **15.51** | 24.03 | 53.77 | 45.92 | 51.47 | 85.04 | 159.11 | 106.86 | 114.71 | 16.46 |
| client_input | **0.11** | 0.11 | 0.11 | 0.11 | 0.11 | 0.11 | 0.11 | 0.11 | 0.11 | 0.14 | 0.10 |
| many_events | **4.07** | 4.13 | 6.75 | 14.10 | 4.74 | 7.32 | 17.82 | 26.55 | 19.04 | 108.38 | 4.68 |
| match_state_reliable | 3.64 | **1.49** | 4.19 | 6.75 | 9.63 | 10.20 | 8.77 | 19.73 | 15.74 | 23.28 | 0.27 |
| match_state_unreliable | 3.42 | **1.35** | 4.00 | 6.82 | 9.39 | 10.31 | 8.51 | 19.65 | 16.77 | 23.56 | 0.28 |
| per_player | 1.26 | **1.02** | 1.87 | 3.72 | 2.38 | 2.04 | 3.96 | 6.77 | 5.01 | 16.76 | 0.63 |
| two_way | 0.32 | 0.35 | 0.43 | 0.42 | **0.27** | n/a | 0.61 | 1.24 | 1.05 | 3.11 | 0.19 |

### Library allocations per frame (bytes, interpreter)

| scenario | current | current-reuse | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | 38,408 | **3,208** | 38,408 | 38,472 | 360,192 | 337,438 | 60,800 | 117,816 | 128,090 | 46,034 | 0 |
| burst_sync | 38,408 | **3,208** | 38,408 | 38,472 | 126,592 | 103,838 | 60,800 | 117,816 | 128,090 | 46,034 | 0 |
| client_input | 24,244 | **1,188** | 33,924 | 35,172 | 75,856 | 66,044 | 39,952 | 74,280 | 62,634 | 80,364 | 0 |
| many_events | **88** | **88** | **88** | 40,584 | 365,397 | 226,080 | 106,240 | 235,631 | 389,576 | 44,933 | 0 |
| match_state_reliable | 328,492 | **513** | 328,273 | 356,103 | 700,204 | 674,500 | 329,200 | 582,802 | 657,976 | 356,289 | 0 |
| match_state_unreliable | 328,273 | **513** | 328,000 | 356,103 | 557,424 | 555,217 | 329,200 | 582,693 | 657,976 | 356,395 | 0 |
| per_player | 37,268 | **2,778** | 36,520 | 61,026 | 174,725 | 134,260 | 76,667 | 149,212 | 130,854 | 43,233 | 0 |
| two_way | 720 | 720 | **16** | 1,792 | 22,408 | n/a | 9,584 | 56,496 | 36,608 | 58,318 | 0 |

### Wire bytes per frame (all receivers, s2c + c2s)

| scenario | current | current-reuse | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | 3,203 | 3,203 | 3,205 | 3,204 | 3,205 | 3,205 | 3,205 | 3,203 | 3,207 | **3,007** | 10,000 |
| burst_sync | 3,203 | 3,203 | 3,205 | 3,204 | 3,205 | 3,205 | 3,205 | 3,203 | 3,207 | **3,007** | 10,000 |
| client_input | **858** | **858** | 968 | 913 | 924 | 968 | 968 | 1,056 | 1,023 | 913 | 4,578 |
| many_events | **3,608** | **3,608** | 3,696 | 3,652 | 3,696 | 3,696 | 3,696 | **3,608** | 3,740 | 3,652 | 12,672 |
| match_state_reliable | **22,352** | **22,352** | 22,440 | 28,248 | 28,248 | 22,440 | 22,484 | 25,300 | 22,484 | 28,204 | 86,981 |
| match_state_unreliable | **22,352** | **22,352** | 22,440 | 28,248 | 28,204 | 22,440 | 22,484 | 25,300 | 22,484 | 28,204 | 86,981 |
| per_player | **2,507** | **2,507** | 2,551 | 2,639 | 2,551 | 2,595 | 2,639 | 2,771 | 2,595 | **2,507** | 8,931 |
| two_way | **616** | **616** | 792 | 704 | 792 | n/a | 792 | **616** | 880 | 704 | 792 |

### Client module memory (KB, code + state)

| scenario | current | current-reuse | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | 21.0 | 21.3 | 59.7 | 128.9 | **16.1** | 34.4 | 4,178.1 | 196.0 | 1,278.7 | 827.0 | 7.0 |
| burst_sync | 21.0 | 21.3 | 59.7 | 128.9 | **16.1** | 34.4 | 4,178.1 | 196.0 | 1,278.7 | 827.0 | 7.0 |
| client_input | 17.2 | 17.3 | 45.5 | 143.0 | **14.9** | 16.9 | 4,181.5 | 197.3 | 1,284.7 | 852.5 | 5.1 |
| many_events | 196.3 | **196.3** | 926.2 | 271.4 | 235.6 | 824.6 | 4,464.0 | 280.0 | 1,322.7 | 1,622.1 | 139.6 |
| match_state_reliable | 29.4 | 30.8 | 67.6 | 144.9 | **20.8** | 38.9 | 4,184.5 | 198.8 | 1,286.5 | 882.0 | 5.2 |
| match_state_unreliable | 29.4 | 30.8 | 67.6 | 144.9 | **20.8** | 38.9 | 4,184.5 | 198.8 | 1,286.5 | 882.0 | 5.2 |
| per_player | 28.8 | 29.7 | 87.6 | 146.1 | **20.0** | 60.2 | 4,189.0 | 200.2 | 1,285.3 | 871.7 | 9.1 |
| two_way | 18.7 | 18.8 | 56.7 | 135.8 | **12.9** | n/a | 4,175.0 | 194.0 | 1,278.9 | 831.9 | 3.9 |

### Server module memory (KB, code + state)

| scenario | current | current-reuse | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | 39.5 | 39.5 | 67.6 | 135.9 | 34.4 | **31.1** | 307.3 | 205.4 | 1,291.7 | 889.7 | 5.8 |
| burst_sync | 39.5 | 39.5 | 67.6 | 135.9 | 34.4 | **31.1** | 307.3 | 205.4 | 1,291.7 | 889.7 | 5.8 |
| client_input | 33.5 | 34.7 | 78.1 | 139.5 | **20.0** | 34.6 | 310.0 | 206.7 | 1,295.1 | 891.1 | 5.8 |
| many_events | **249.2** | 249.2 | 612.4 | 323.3 | 1,261.4 | 926.4 | 647.5 | 292.9 | 1,505.2 | 1,679.3 | 143.5 |
| match_state_reliable | 54.9 | 54.9 | 83.2 | 141.3 | 63.9 | **38.1** | 313.0 | 207.9 | 1,296.8 | 922.3 | 5.8 |
| match_state_unreliable | 54.9 | 54.9 | 83.2 | 141.3 | 63.9 | **38.1** | 313.0 | 207.9 | 1,296.8 | 922.3 | 5.8 |
| per_player | **44.7** | 44.7 | 83.3 | 143.5 | 68.8 | 54.7 | 318.9 | 209.7 | 1,299.7 | 910.8 | 10.8 |
| two_way | 46.3 | 46.3 | 86.0 | 131.8 | **24.1** | n/a | 303.0 | 203.5 | 1,287.8 | 870.0 | 4.2 |
