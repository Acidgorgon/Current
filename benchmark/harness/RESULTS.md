# Results

Run on 2026-11-16 with this harness: Luau 0.700 VM, mock Roblox with 44
clients, 7 interleaved runs per variant (median shown), 600 frames after 120
warmup frames. Every scenario passed the received-equals-sent check for every
library. Raw numbers are in `results/<label>.json`; the method is in
[README.md](README.md).

Variants:

- **stock**: upstream Blink v0.18.9
- **plus**: blink-plus (this repo) at commit 9a04a93
- **zap**: Zap 0.6.29, built from source
- **blinkblox**: BlinkBlox 1.4.0 (HEAD 9894b33), another Blink fork
- **remotes**: plain RemoteEvents, one per event, no serialization

ByteNet, Warp, QuickNet, Lync and Packet adapters are being added; this page
will be updated with one combined run of every library.

## Table

"native" and "interp" are server + client CPU per frame in µs (all phases
except the mock network copy). "recv" is the receive cost per client.
"alloc" is bytes allocated per frame by the library; "net alloc" is the mock
network's receive-side copy, kept apart because it is not library code.
Heap is the module's memory after load (client / server).

| scenario | variant | native µs | interp µs | recv/client nat / int µs | alloc B/f | net alloc B/f | wire B/f (s2c/c2s) | calls | heap client / server |
|---|---|---|---|---|---|---|---|---|---|
| match_state_reliable | stock | 538.7 | 729.0 | 10.57 / 14.60 | 674446 | 33971 | 22440 | 44 | 38.9K / 38.1K |
| | **plus** | **213.1** | **477.4** | **4.22 / 9.89** | 327836 | 27833 | 22440 | 44 | 37.6K / 50.4K |
| | zap | 520.1 | 680.7 | 9.93 / 12.98 | 700231 | 39888 | 28248 | 44 | 20.8K / 63.9K |
| | blinkblox | 215.8 | 496.5 | 4.20 / 10.18 | 328273 | 28106 | 22440 | 44 | 67.6K / 83.2K |
| | remotes | 36.9 | 40.0 | 0.33 / 0.40 | 0 | 586926 | 86981 | 44 | 5.2K / 5.8K |
| match_state_unreliable | stock | 456.0 | 637.8 | 9.80 / 13.65 | 555327 | 27942 | 22440 | 44 | 38.9K / 38.1K |
| | **plus** | **199.0** | **429.7** | **3.96 / 8.92** | 328164 | 28106 | 22440 | 44 | 37.6K / 50.4K |
| | zap | 436.3 | 534.6 | 9.23 / 11.31 | 557260 | 33870 | 28204 | 44 | 20.8K / 63.9K |
| | blinkblox | 195.8 | 451.0 | 3.83 / 9.29 | 328219 | 27997 | 22440 | 44 | 67.6K / 83.2K |
| | remotes | 28.2 | 35.9 | 0.26 / 0.37 | 0 | 586871 | 86981 (all oversize) | 44 | 5.2K / 5.8K |
| per_player | stock | 166.2 | 208.4 | 1.95 / 2.56 | 134260 | 14115 | 2595 | 44 | 60.2K / 54.7K |
| | **plus** | **146.0** | **198.2** | **1.51 / 2.27** | 37267 | 14115 | 2595 | 44 | 34.1K / 48.2K |
| | zap | 192.6 | 226.1 | 2.02 / 2.56 | 174724 | 14071 | 2551 | 44 | 20.0K / 68.8K |
| | blinkblox | 149.2 | 197.2 | 1.69 / 2.49 | 36519 | 14071 | 2551 | 44 | 87.6K / 83.3K |
| | remotes | 50.6 | 75.0 | 0.54 / 0.88 | 0 | 93430 | 8931 | 220 | 9.1K / 10.8K |
| client_input | stock | 94.5 | 114.3 | – | 66044 | 3828 | 0 / 968 | 55 | 16.9K / 34.6K |
| | **plus** | **85.2** | **117.4** | – | 34100 | 3828 | 0 / 968 | 55 | 24.9K / 41.4K |
| | zap | 94.5 | 118.0 | – | 75856 | 3784 | 0 / 924 | 55 | 14.9K / 20.0K |
| | blinkblox | 100.6 | 133.6 | – | 33924 | 3828 | 0 / 968 | 55 | 45.5K / 78.1K |
| | remotes | 29.0 | 41.1 | – | 0 | 38192 | 0 / 4578 | 55 | 5.1K / 5.8K |
| many_events | stock | 604.9 | 905.2 | 6.79 / 12.84 | 226080 | 15216 | 3696 | 44 | 824.6K / 926.4K |
| | **plus** | **329.6** | **436.5** | **6.38 / 8.86** | 88 | 9024 | 3696 | 44 | 245.6K / 341.4K |
| | zap | 540.7 | 779.0 | 4.13 / 9.45 | 365506 | 15243 | 3696 | 44 | 235.6K / 1261.4K |
| | blinkblox | 296.8 | 390.1 | 5.46 / 7.73 | 88 | 9024 | 3696 | 44 | 934.2K / 612.4K |
| | remotes | 230.0 | 302.7 | 4.61 / 6.03 | 0 | 71120 | 12672 | 1056 | 139.6K / 143.5K |
| burst_async | stock | 133.8 | 158.9 | 97.89 / 112.45 | 337438 | 3544 | 3205 | 1 | 34.4K / 31.1K |
| | **plus** | **85.0** | **121.0** | **48.80 / 72.21** | 38408 | 3544 | 3205 | 1 | 25.1K / 40.3K |
| | zap | 163.5 | 192.4 | 93.16 / 114.34 | 360192 | 3544 | 3205 | 1 | 16.1K / 34.4K |
| | blinkblox | 74.1 | 113.7 | 44.49 / 75.19 | 38408 | 3544 | 3205 | 1 | 59.7K / 67.6K |
| | remotes | 29.2 | 47.1 | 16.50 / 27.33 | 0 | 96080 | 10000 | 200 | 7.0K / 5.8K |
| burst_sync | stock | 81.5 | 114.7 | 47.35 / 66.84 | 103838 | 3544 | 3205 | 1 | 34.4K / 31.1K |
| | **plus** | **60.4** | **96.5** | **24.86 / 46.35** | 38408 | 3544 | 3205 | 1 | 25.1K / 40.3K |
| | zap | 111.0 | 149.6 | 46.46 / 66.72 | 126592 | 3544 | 3205 | 1 | 16.1K / 34.4K |
| | blinkblox | 52.5 | 84.7 | 22.86 / 45.78 | 38408 | 3544 | 3205 | 1 | 59.7K / 67.6K |
| | remotes | 28.9 | 48.8 | 16.11 / 28.21 | 0 | 96080 | 10000 | 200 | 7.0K / 5.8K |
| two_way | stock | not supported | | | | | | | |
| | **plus** | **59.5** | **78.1** | **0.35 / 0.53** | 720 | 8672 | 396 / 396 | 44/44 | 23.0K / 41.0K |
| | zap | 66.9 | 99.0 | 0.29 / 0.45 | 22408 | 14864 | 396 / 396 | 44/44 | 12.9K / 24.1K |
| | blinkblox | 81.3 | 99.2 | 0.44 / 0.63 | 16 | 8672 | 396 / 396 | 44/44 | 56.7K / 86.0K |
| | remotes | 30.5 | 42.9 | 0.19 / 0.28 | 0 | 3040 | 396 / 396 | 44/44 | 3.9K / 4.2K |

## Reading it

- **blink-plus vs stock Blink**: 1.1x to 2.5x less CPU in native mode,
  1.7x to 8.8x less allocation, and almost none in many_events
  (226 KB → 88 B per frame), identical wire bytes, and two-way
  events that stock cannot do.
- **blink-plus vs BlinkBlox**: about tied on CPU and allocation. BlinkBlox is a
  little faster in burst and many_events; blink-plus is faster in client_input
  and two_way. BlinkBlox's modules hold 1.5x to 3.5x more memory.
- **Zap** is close to stock Blink on CPU and allocates the most. It has no f16,
  so its match snapshot is 132 bytes bigger.
- **Plain remotes look cheapest, but the mock flatters them.** Roblox's own C++
  serialization of Luau tables is not timed, and their receive-side tables are
  built by the mock's copy, so they show up only under "net alloc" (587 KB per
  frame in match_state). They send 3x to 4x more bytes, and the unreliable match
  snapshot (about 1977 bytes per call) is over Roblox's unreliable size limit,
  so every one of those calls would be dropped.

Schema differences between libraries and the remaining caveats are listed in
[README.md](README.md#adapters).
