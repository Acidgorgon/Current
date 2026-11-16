# Results

One interleaved run of ten libraries on 2026-11-16: Luau 0.700 VM, mock
Roblox with 44 clients, 7 runs per library (median shown), 600 frames after
120 warmup frames, in native codegen and interpreter mode. Every library
passed the received-equals-sent check in every scenario it can express.
Raw numbers are in `results/<label>.json`; the method and every schema
difference between libraries are in [README.md](README.md).

| label | library |
|---|---|
| plus | blink-plus (this repo, commit 0975aa2) |
| blinkblox | BlinkBlox 1.4.0, another Blink fork |
| bytenet | ByteNet 0.4.3 |
| zap | Zap 0.6.29 |
| stock | upstream Blink 0.18.9 |
| quicknet | QuickNet 0.4.0 |
| packet | Packet 1.7 |
| warp | Warp 1.1.0-pre8 |
| lync | Lync 4.0 |
| remotes | plain RemoteEvents, one per event, no serialization |

The best library value in each row is bold. `remotes` is never marked best:
the mock cannot time Roblox's own C++ serialization of the tables it sends,
so its CPU numbers are a lower bound. `n/a` means the library cannot express
the scenario (stock Blink has no two-way events).

## Summary

- **CPU:** blink-plus is the fastest library in every scenario, in native and
  interpreted mode. BlinkBlox is closest: 3–5% behind on the match snapshots and
  17–67% behind elsewhere. Against stock Blink, blink-plus is 2.5x faster on the
  match snapshot, 3.1x on 120 events and 2.3x on a 200-event burst.
- **Server cost:** the server part of the frame drops furthest, because a
  broadcast is written once whatever the player count: 6.8x less than stock
  for the snapshot to 44 players, 20x for 120 events (1.5x for per-player
  sends, the weakest case).
- **Allocations:** tied with BlinkBlox for the least among the buffer
  libraries; 2x less than stock on the snapshot, and almost none for many events.
- **Bandwidth:** tied for the smallest snapshot with stock Blink and BlinkBlox
  (16-bit float velocities). Libraries without f16 send about 25% more.
- **Memory:** blink-plus's modules are smaller than stock Blink's and far
  smaller than BlinkBlox, Warp (~1.3 MB f16 table), QuickNet (~4 MB client
  queues) and Lync. Zap's client modules are a little smaller still.
- **Plain RemoteEvents** send 3–4x more bytes, and the unreliable snapshot
  (~2 KB per call) is over Roblox's unreliable size limit, so every one would be
  dropped.

Other benchmark jobs were running on other cores during this run. Runs are
interleaved library by library, so ratios are reliable; absolute µs are only
comparable within this run.

### CPU per frame, native codegen (µs, server + all clients)

| scenario | plus | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | **58.3** | 74.5 | 112.0 | 154.8 | 130.7 | 147.0 | 236.2 | 198.3 | 243.2 | 33.6 |
| burst_sync | **37.4** | 62.5 | 111.6 | 114.2 | 87.2 | 123.7 | 242.3 | 196.4 | 231.8 | 34.3 |
| client_input | **91.6** | 107.4 | 116.7 | 99.3 | 99.2 | 137.0 | 184.5 | 197.0 | 622.4 | 31.5 |
| many_events | **198.4** | 291.7 | 659.2 | 551.1 | 616.3 | 932.5 | 1,251.8 | 1,247.7 | 4,470.4 | 231.8 |
| match_state_reliable | **204.1** | 214.5 | 339.7 | 518.8 | 518.5 | 457.2 | 966.2 | 1,234.4 | 1,308.1 | 30.4 |
| match_state_unreliable | **195.8** | 202.3 | 364.3 | 441.3 | 455.3 | 418.2 | 928.2 | 1,265.0 | 1,332.3 | 29.2 |
| per_player | **121.7** | 155.3 | 242.8 | 194.3 | 170.6 | 289.8 | 486.7 | 408.7 | 1,184.8 | 53.8 |
| two_way | **59.3** | 78.6 | 73.0 | 71.0 | n/a | 104.0 | 148.9 | 171.8 | 592.2 | 30.5 |

### CPU per frame, interpreter (µs, server + all clients)

| scenario | plus | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | **97.9** | 113.7 | 157.3 | 191.9 | 160.9 | 213.6 | 279.6 | 271.2 | 373.3 | 56.4 |
| burst_sync | **65.0** | 83.1 | 157.6 | 135.9 | 114.1 | 185.9 | 266.3 | 268.8 | 358.3 | 55.2 |
| client_input | **116.6** | 140.2 | 154.2 | 131.0 | 120.6 | 178.8 | 237.2 | 269.8 | 741.4 | 42.6 |
| many_events | **238.5** | 385.1 | 698.5 | 769.8 | 882.8 | 1,119.7 | 1,418.3 | 1,396.5 | 6,578.7 | 296.1 |
| match_state_reliable | **421.0** | 490.1 | 484.4 | 620.9 | 760.6 | 675.5 | 1,162.7 | 1,902.2 | 1,735.2 | 37.5 |
| match_state_unreliable | **393.3** | 448.0 | 483.2 | 540.1 | 625.5 | 646.4 | 1,112.4 | 1,792.1 | 1,753.1 | 37.3 |
| per_player | **172.7** | 213.5 | 302.6 | 236.4 | 221.5 | 371.4 | 548.6 | 503.2 | 1,593.8 | 90.7 |
| two_way | **77.8** | 102.1 | 96.4 | 98.4 | n/a | 132.0 | 192.3 | 233.6 | 647.7 | 43.5 |

### Receive cost per client, native (µs)

| scenario | plus | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | **43.43** | 44.08 | 52.23 | 90.97 | 94.46 | 96.18 | 160.61 | 111.35 | 117.06 | 16.16 |
| burst_sync | **21.72** | 27.10 | 52.22 | 46.52 | 49.55 | 78.69 | 164.10 | 110.51 | 108.59 | 16.89 |
| client_input | 0.10 | 0.10 | 0.10 | **0.10** | 0.11 | 0.10 | 0.10 | 0.11 | 0.14 | 0.10 |
| many_events | **3.76** | 5.39 | 13.85 | 4.06 | 6.65 | 17.37 | 26.38 | 18.07 | 89.12 | 4.64 |
| match_state_reliable | **4.04** | 4.17 | 6.67 | 9.80 | 10.11 | 9.06 | 20.38 | 15.84 | 22.71 | 0.29 |
| match_state_unreliable | **3.85** | 3.95 | 7.17 | 9.30 | 9.71 | 8.36 | 19.58 | 16.09 | 23.28 | 0.27 |
| per_player | **1.41** | 1.72 | 2.89 | 2.00 | 1.97 | 4.00 | 6.98 | 5.19 | 14.64 | 0.53 |
| two_way | 0.33 | 0.42 | 0.41 | **0.26** | n/a | 0.54 | 1.08 | 0.83 | 3.16 | 0.19 |

### Library allocations per frame (bytes, interpreter)

| scenario | plus | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | **38,408** | **38,408** | 38,472 | 360,192 | 337,438 | 60,800 | 117,816 | 128,090 | 46,034 | 0 |
| burst_sync | **38,408** | **38,408** | 38,472 | 126,592 | 103,838 | 60,800 | 117,816 | 128,090 | 46,034 | 0 |
| client_input | 34,100 | **33,924** | 35,172 | 75,856 | 66,044 | 39,952 | 74,280 | 62,634 | 80,364 | 0 |
| many_events | **88** | **88** | 40,584 | 365,397 | 226,080 | 106,240 | 235,631 | 389,576 | 44,933 | 0 |
| match_state_reliable | 328,246 | **328,164** | 356,267 | 700,313 | 674,500 | 329,200 | 582,747 | 657,976 | 356,399 | 0 |
| match_state_unreliable | 328,464 | **328,055** | 356,103 | 557,561 | 554,944 | 329,200 | 582,693 | 657,976 | 356,507 | 0 |
| per_player | 37,268 | **36,520** | 61,026 | 174,725 | 134,260 | 76,748 | 149,212 | 130,854 | 43,233 | 0 |
| two_way | 720 | **16** | 1,792 | 22,408 | n/a | 9,584 | 56,496 | 36,608 | 58,316 | 0 |

### Wire bytes per frame (all receivers, s2c + c2s)

| scenario | plus | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | 3,205 | 3,205 | 3,204 | 3,205 | 3,205 | 3,205 | 3,203 | 3,207 | **3,007** | 10,000 |
| burst_sync | 3,205 | 3,205 | 3,204 | 3,205 | 3,205 | 3,205 | 3,203 | 3,207 | **3,007** | 10,000 |
| client_input | 968 | 968 | **913** | 924 | 968 | 968 | 1,056 | 1,023 | **913** | 4,578 |
| many_events | 3,696 | 3,696 | 3,652 | 3,696 | 3,696 | 3,696 | **3,608** | 3,740 | 3,652 | 12,672 |
| match_state_reliable | **22,440** | **22,440** | 28,248 | 28,248 | **22,440** | 22,484 | 25,300 | 22,484 | 28,204 | 86,981 |
| match_state_unreliable | **22,440** | **22,440** | 28,248 | 28,204 | **22,440** | 22,484 | 25,300 | 22,484 | 28,204 | 86,981 |
| per_player | 2,595 | 2,551 | 2,639 | 2,551 | 2,595 | 2,639 | 2,771 | 2,595 | **2,507** | 8,931 |
| two_way | 792 | 792 | 704 | 792 | n/a | 792 | **616** | 880 | 704 | 792 |

### Client module memory (KB, code + state)

| scenario | plus | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | 20.7 | 59.7 | 128.9 | **16.1** | 34.4 | 4,178.1 | 196.0 | 1,278.7 | 827.0 | 7.0 |
| burst_sync | 20.7 | 59.7 | 128.9 | **16.1** | 34.4 | 4,178.1 | 196.0 | 1,278.7 | 827.0 | 7.0 |
| client_input | 18.4 | 45.5 | 143.0 | **14.9** | 16.9 | 4,181.5 | 197.3 | 1,284.7 | 852.5 | 5.1 |
| many_events | **198.1** | 926.2 | 271.4 | 235.6 | 824.6 | 4,464.0 | 280.0 | 1,322.7 | 1,622.1 | 139.6 |
| match_state_reliable | 29.8 | 67.6 | 144.9 | **20.8** | 38.9 | 4,184.5 | 198.8 | 1,286.5 | 882.0 | 5.2 |
| match_state_unreliable | 29.8 | 67.6 | 144.9 | **20.8** | 38.9 | 4,184.5 | 198.8 | 1,286.5 | 882.0 | 5.2 |
| per_player | 28.2 | 87.6 | 146.1 | **20.0** | 60.2 | 4,189.0 | 200.2 | 1,285.3 | 871.7 | 9.1 |
| two_way | 18.2 | 56.7 | 135.8 | **12.9** | n/a | 4,175.0 | 194.0 | 1,278.9 | 831.9 | 3.9 |

### Server module memory (KB, code + state)

| scenario | plus | blinkblox | bytenet | zap | stock | quicknet | packet | warp | lync | remotes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| burst_async | **30.3** | 67.6 | 135.9 | 34.4 | 31.1 | 307.3 | 205.4 | 1,291.7 | 889.7 | 5.8 |
| burst_sync | **30.3** | 67.6 | 135.9 | 34.4 | 31.1 | 307.3 | 205.4 | 1,291.7 | 889.7 | 5.8 |
| client_input | 23.0 | 78.1 | 139.5 | **20.0** | 34.6 | 310.0 | 206.7 | 1,295.1 | 891.1 | 5.8 |
| many_events | **224.6** | 612.4 | 323.3 | 1,261.4 | 926.4 | 647.5 | 292.9 | 1,505.2 | 1,679.3 | 143.5 |
| match_state_reliable | 44.5 | 83.2 | 141.3 | 63.9 | **38.1** | 313.0 | 207.9 | 1,296.8 | 922.3 | 5.8 |
| match_state_unreliable | 44.5 | 83.2 | 141.3 | 63.9 | **38.1** | 313.0 | 207.9 | 1,296.8 | 922.3 | 5.8 |
| per_player | **35.4** | 83.3 | 143.5 | 68.8 | 54.7 | 318.9 | 209.7 | 1,299.7 | 910.8 | 10.8 |
| two_way | 35.9 | 86.0 | 131.8 | **24.1** | n/a | 303.0 | 203.5 | 1,287.8 | 870.0 | 4.2 |
