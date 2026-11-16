# Roblox networking benchmark harness

Latest numbers: [RESULTS.md](RESULTS.md).

Measures the CPU time, exact Luau heap allocations, module memory footprint and
wire size of Roblox networking libraries on football-game-shaped traffic
(40-50 player servers), and checks that every value received equals the value
sent. Libraries plug in through **adapters**; the first adapter is
[Blink](https://github.com/1Axen/blink) (stock v0.18.9 and the blink-plus
fork). Further adapters: Zap, BlinkBlox, ByteNet, Warp, QuickNet, Lync, Packet and a
plain-RemoteEvent baseline (`remotes`); see [Adapters](#adapters) for what each one does and how its
schemas differ from Blink's, and [Adding a library](#adding-a-library).

Everything runs in a plain Luau 0.700 VM (no Roblox, no Lune at run time)
with a Roblox mock, in both interpreter (`-O2`) and native codegen mode.

## Quick start

```sh
# one library build -> results/<label>.json
./run.sh $HOME/src/blink-stock stock

# several variants, runs interleaved A,B,A,B... (use this for comparisons:
# machine drift then affects every variant equally)
./run.sh --variant stock=blink:$HOME/src/blink-stock \
         --variant plus=blink:../..

# markdown comparison (ratios baseline/candidate, > 1 = candidate better)
python3 compare.py results/stock.json results/plus.json [--mode interp|native|both]
```

Options: `--runs 7` (median is reported), `--frames 600` (multiplied per
scenario by `frames_scale` in `scenarios/manifest.json`), `--warmup 120`,
`--scenarios a,b`, `--modes interp,native`, `--cpu N` (taskset pin; `-1` off),
`--adapter NAME` (single-variant form).

Requirements: cmake + a C++17 compiler (the host builds itself on first run),
python3, `lune` (for the Blink compiler) and `luau-compile`, either on `PATH`
or in the directory named by `BENCH_TOOLS`. The other libraries are not
bundled: clone or download each one and pass its directory to `--variant`
(`$HOME/src/blink-stock` is a checkout of upstream Blink v0.18.9; `../..` is this repo).

Exit status is non-zero if any scenario failed verification or did not build.

## Layout

```
host/                luau-bench: Luau 0.700 host (allocation counting, codegen)
third_party/         vendored Luau 0.700 sources (from the luau0-src crate)
lib/mock.luau        Roblox mock: instances, replication, remotes, require, task
lib/run_scenario.luau   runs ONE scenario once, prints a JSON line
lib/static_metrics.luau native code size / chunk heap of generated modules
lib/json.luau        JSON encoder
scenarios/           traffic drivers (library-agnostic) + manifest.json
adapters/<name>/     build.sh + adapter.luau (+ schemas) per library
run.py / run.sh      build, run, aggregate -> results/<label>.json
compare.py           markdown comparison of two result files
RESULTS.md           latest results table
results/<label>.json raw results of the latest run
gen/<label>/         build output per variant (generated code)
```

## What is measured, and how

Per frame (30 Hz, `dt = 1/30`), each phase is measured separately with
`os.clock` and with the host's exact allocation counters:

| phase | what runs |
|---|---|
| `prepare` | driver mutates its payload tables (untimed, allocation-free) |
| `server_send` | driver calls the server API (`Fire`, `FireAll`, ...) |
| `client_send` | driver calls each client's API |
| `server_step` | server RunService signals (Blink: `StepReplication` on Heartbeat) |
| `client_step` | every client's RunService signals |
| `network` | **mock only**: deep-copies remote arguments into inboxes, counts wire bytes |
| `client_recv` | every client's `OnClientEvent` handlers: decode + dispatch + listeners (+ deferred threads) |
| `server_recv` | server `OnServerEvent` handlers |
| `verify` | driver compares received values with sent ones (untimed) |

`phases.total` sums every phase except `network`: the cost the library adds
to one frame, summed over the server and all clients. `client_recv_per_client`
divides by the client count; `client_recv_max_client_us` is the average over
frames of the slowest client.

Reported per scenario × mode (median over runs; min/max of timings in `spread`):

* `phases.<phase>.{us, alloc_bytes, allocs}` per frame.
* `wire`: `s2c_bytes_per_frame` / `c2s_bytes_per_frame` (all receivers summed),
  call counts, number of unreliable calls over 1000 bytes (Roblox drops them).
* `heap` (live bytes after a full GC):
  `server_code` / `client_code` = compiled chunk (bytecode protos etc.),
  `server_state` / `client_state` = what starting the library leaves alive,
  `client_module` = code + state of ONE client machine,
  `steady_growth` = whole-VM live heap growth while running frames.
* `load`: compile/init time and allocations.
* `native_code_bytes`, `warnings` (library `warn()` calls), `verify_checks`.

Static metrics per generated/library file (`results/<label>.json` → `static`):
source bytes and lines, bytecode bytes (`luau-compile --binary -O2` with
Roblox's vector settings), native code bytes and compiled-chunk heap
(`luau-bench --codegen`).

### Allocation measurement

`host/` builds `luau-bench`, a minimal Luau 0.700 host (the Luau CLI sources
are not in the vendored crate, so this replaces the patched `luau` CLI). It
installs `lua_callbacks(L)->onallocate`, which Luau calls from
`luaM_new_`/`luaM_newgco_`/`luaM_realloc_` for **every** object and array
allocation (the `lua_newstate` allocator only sees 16 KB size-class pages, so
it is not usable for this). Globals:

* `__alloc_bytes()` total bytes allocated, `__alloc_count()` number of
  allocations (a growing realloc counts as a new allocation of the new size,
  which is what Luau's size-class allocator does), `__live_bytes()` the VM's
  live heap (`lua_gc COUNT`), `__gc("collect"|"stop"|"restart"|"step")`,
  `__trace_alloc(true)` prints each allocation to stderr (debugging),
  `__native()`, `__native_code_bytes()`, `__optlevel()`.
* `loadstring(src, chunkname)` compiles at the process's `-O` level with
  Roblox's vector settings (`vectorLib = "Vector3"`, `vectorCtor = "new"`), and
  native-compiles the chunk under `--codegen`. Unlike the stock CLI it keeps the
  environment "safe", so imports and builtin fastcalls stay enabled.
* `readfile`, `writefile`, `listdir`, `arg`.
* All non-experimental `Luau*` fast flags are enabled, like the stock CLI.
* VM patch (compile definition `LUAU_BENCH_NO_STACK_SHRINK`): the GC does not
  shrink thread stacks, so stack shrink/regrow reallocations are not
  attributed to whatever code happens to run after a GC step.

Allocation numbers are deterministic (identical across runs); timings are
noisy on shared VMs (±10-20% between whole runs here), hence medians,
CPU pinning and interleaved variants.

### The Roblox mock and how it is injected

`lib/mock.luau` simulates one server and N client machines in one VM. Each
machine (environment) has its own DataModel (`game` with ReplicatedStorage,
Workspace, Players, RunService, ...), `_G`, `shared` and module cache.
Modules are compiled once (`Mock.compileFile`) and **instantiated per
machine**: one extra line is inserted after the leading `--!` directives,

```lua
local game, workspace, Instance, task, warn, typeof, _G, shared, script, require = ...
```

and the chunk is called with that machine's values. No `setfenv`, so the
global environment stays safe (GETIMPORT/FASTCALL keep working, `--!native`
and `--!optimize 2` still apply). All clients share one compiled copy of the
client code, like N machines each holding one copy (compiling 44 copies would
put 44× the native code in the instruction cache and penalize codegen
unrealistically). `Vector3` (native `vector`: `.X/.Y/.Z` work, `.Magnitude`
does not), `tick` and `time` are real globals.

* Instances: `Name`, `ClassName`, `Parent` (reparenting maintained),
  `FindFirstChild(name, recursive)`, `WaitForChild` (errors instead of
  yielding forever), `GetChildren`, `GetDescendants`, `IsA`, `Destroy`,
  attributes, `inst.ChildName`. `Instance.new` makes RemoteEvent /
  UnreliableRemoteEvent (server only) and plain instances (Folder, ...).
* Replication: server instances under ReplicatedStorage / Workspace appear
  in every client's tree as lazily created replicas; a replicated RemoteEvent
  gives each client its own `OnClientEvent` and `FireServer`. Player objects
  are shared identities (`Players.LocalPlayer` on clients).
* Remotes: `FireClient`, `FireAllClients`, `FireServer` with any arguments.
  Firing only queues the call into pre-sized flat arrays (no allocation in
  steady state). The network phase deep-copies arguments (buffers and tables
  are copied, instances mapped to the receiver's replicas) and estimates wire
  bytes: 1 type byte + payload (number 8, vector 12, Instance 4, string/buffer
  varint length + bytes, table varint count + entries, array keys omitted).
  Roblox's per-packet framing is not modelled; call counts are reported.
* `Players:GetPlayers()` returns a fresh table each call (a real cost in
  Roblox too). `PlayerAdded` fires when the harness adds players (after the
  server module started, before clients start).
* `task.spawn(fn)` creates a new coroutine per call (like Roblox);
  `task.defer` queues to the end of the phase; `task.wait`/`delay` error.
  Errors in spawned threads abort the run (they mean a failed check).
* `typeof` returns `"Vector3"` for vectors and `"Instance"` for mock instances.
* Modules: `env:requireFile(path)`, `require(moduleScript)`, string requires
  (`"./x"`, `"../x"`, `"@self/x"`), and `env:mountTree(dir, parent, name)` to
  expose a Rojo-layout library as ModuleScripts/Folders (so `script.Parent.X`
  works).

### Caveats: how the mock differs from real Roblox costs

* Signal connections are called directly on the calling thread; Roblox
  dispatches remote events through engine threads. That engine cost is
  identical for every library and is left out, so receive numbers are pure
  library cost.
* No real serialization: Roblox's C++ cost of encoding/decoding remote
  arguments (large for table-heavy payloads, tiny for one buffer) is not
  timed; only the estimated wire bytes reflect it. This matters when comparing
  buffer libraries against plain-RemoteEvent tables: compare wire bytes and
  call counts too.
* For the `remotes` baseline this means its CPU numbers are a **lower bound**:
  Roblox's C++ cost of serializing (sender) and deserializing (receiver) its
  table arguments is not measured, and the Luau tables the receiver gets are
  built by the mock in the `network` phase, which is left out of `total` (so
  its `alloc_bytes` are ~0 where a buffer library's decode allocations are
  counted; compare `phases.network.alloc_bytes` for the receive-side tables).
  Its wire bytes are the mock's estimate of Roblox's encoding (dictionary keys
  sent as strings, 9 bytes per number, 13 per vector), not a measurement.
* Mock instances (including Players) are Luau tables, not userdata, so
  `type(player) == "table"` is true; a library that tells instances apart
  from tables with `type` misbehaves (the BlinkBlox build patches its one such
  guard, see `adapters/blinkblox/build.sh`).
* Luau 0.700 open-source VM, not Roblox's build; Roblox's VM, GC pacing and
  codegen settings differ somewhat. Absolute µs are only comparable within one
  machine; ratios are what matter.
* Unreliable remotes never drop (oversized payloads are only counted).
* Each client is simulated in turn on one core; per-client receive time is
  what one real client would spend.

## Adapters

| adapter | source dir | what it does |
|---|---|---|
| `blink` | Blink checkout | `.blink` schemas in `adapters/blink/schemas/`, compiled with `lune run init` from `src/CLI`. The reference definitions. |
| `zap` | Zap checkout with `target/release/zap` (or a dir holding `zap`) | `.zap` schemas in `adapters/zap/schemas/`, compiled with the Zap CLI. Single* events expose `SetCallback`, Many* events `On`; both are handed out directly. |
| `blinkblox` | BlinkBlox checkout | the Blink schemas with BlinkBlox's inbound limits raised (below), compiled from source with `lune run init` from `src/CLI`. Same public API as Blink. |
| `bytenet` | ByteNet 0.4.x release (v0.4.3; `main` is an unfinished rewrite and is refused) | packets defined in `adapters/bytenet/schemas/<schema>.luau`. Enums and sets are custom `{read, write}` types (u8 index / u8 bitfield). |
| `warp` | Warp 1.1.0-pre8 | schemas via `Schema.*`; enum and set via `Schema.custom_datatype`. The client pumps Warp's startup handshake inside `start()`. |
| `quicknet` | QuickNet 0.4.0 | `D.literal` enums, `D.custom` u8 bitfield sets, `Vector3F16`. Rate limit raised with `:SetRateLimit(math.huge, 1)`. |
| `lync` | Lync 4.0.x | int ranges, `enum`, `bitfield`, `str(0, 64)`, arrays and optionals. The client pumps Lync's hello/verdict handshake inside `start()`. |
| `packet` | Packet 1.7 `MainModule` directory | Packet types; enums as `Types/Static1` u8 static indexes (the list is replaced at build time by `adapters/packet/Static1.luau`). |
| `remotes` | none (`-`) | "no library" baseline: hand-written modules in `adapters/remotes/modules/<schema>/` make one RemoteEvent (UnreliableRemoteEvent where Blink's is Unreliable) per event under `ReplicatedStorage.Remotes` and fire the Luau values as they are. No serialization, no batching. |

```sh
./run.sh --variant stock=blink:$HOME/src/blink-stock \
         --variant plus=blink:../.. \
         --variant zap=zap:$HOME/src/zap \
         --variant blinkblox=blinkblox:$HOME/src/BlinkBlox \
         --variant bytenet=bytenet:$HOME/src/ByteNet \
         --variant warp=warp:$HOME/src/Warp \
         --variant quicknet=quicknet:$HOME/src/QuickNet \
         --variant lync=lync:$HOME/src/Lync \
         --variant packet=packet:$HOME/src/Packet/MainModule \
         --variant remotes=remotes:-
```

Libraries are copied into `gen/<label>/` and patched there, never in their
source directory. Patches go through a helper that fails unless the target
text occurs exactly once. Each library is also copied a second time for the
clients so their code heap is measured separately.

Schema differences that affect wire size or work (everything else matches
Blink's types, ranges, enums, `Type` and `Call` exactly):

* **zap**: no `f16`, so `match_state` `PlayerState.Vel` is
  `vector(f32, f32, f32)` (12 bytes per player instead of 6: +132 bytes per
  snapshot). No bitfield `set` of named flags (Zap's `set` is a dynamic
  key -> true map that cannot carry `false`), so `Flags`/`Buttons` are structs
  of six booleans, which Zap packs into one bit byte like Blink's set. Strings
  are `string.binary(0..64)` (no UTF-8 check, like Blink). `opt write_checks =
  false` (Zap's default is true; its docs say to disable it in production, and
  Blink does no write-side checks). No two-way events: `two_way` uses two
  declarations, `PingDown` (server -> client) and `PingUp` (client -> server).
  The generated modules build a table of 24 `CFrame.Angles` at load; the
  adapter installs a minimal `CFrame` stand-in since the mock has none.
* **blinkblox**: identical types. Every schema raises the inbound limits
  exactly as BlinkBlox's own `benchmark/definitions/*.blink` do
  (`MaxPacketSize = 2097152`, `MaxEventsPerPacket = 2048`,
  `MaxInstancesPerPacket = 2048`, `InboundBytesPerSecond` and `InboundBurst`
  `= 1073741824`); the defaults (64 events / 8 KB per packet, 64 KB/s per
  player on an `os.clock` budget) would refuse traffic, all the more since the
  harness runs frames much faster than 30 Hz of wall-clock time. No `From:
  Both`: `two_way` uses `PingDown`/`PingUp` like Zap. The adapter sets
  `Players.MaxPlayers = 50` (read by the generated server; the mock lacks it),
  and `build.sh` patches one `type(Player) == "table"` guard (see Caveats).
* **remotes**: values are Luau tables/strings/numbers as the contract shapes
  them (enums as strings, sets as boolean tables), so the wire carries
  dictionary keys and 8-byte numbers. `two_way` is native (one RemoteEvent
  used in both directions). The unreliable match snapshot is ~2 KB per call
  by the mock's estimate, so Roblox would drop every one
  (`wire.unreliable_oversize`).

* **bytenet**: no f16, so `Vel` is an f32 vec3 (+132 bytes per snapshot);
  u16 length prefixes on arrays and strings. `many_events` `(u8, u16)` pairs
  are sent as a struct (one reused table). Every listener runs through
  `task.spawn` on a reused thread. No patches.
* **warp**: `Vel` is `Schema.vector3` (f16, like Blink). A 2-byte header and a
  varint count per batch. Pairs are sent as a struct. Patches: the
  8000-bytes-per-heartbeat inbound cap is lifted, and `const` becomes `local`
  in two files (`const` does not parse in Luau 0.700). Its ~1.3 MB module heap
  is a 65536-entry f16 lookup table.
* **quicknet**: `MaxPacketSize` and `MaxCallsPerFrame` are set to `math.huge`
  in its Config, and `const` becomes `local`. The default 2 MB client
  allocation is kept, which is most of its ~4 MB client heap. It also
  allocates about 2 MB per player on the server at join; per-player state is
  not counted in `server_module` (about 88 MB here).
* **lync**: no f16 (`Vel` is f32 vec3). Pairs are sent as a struct. Flushes from
  PostSimulation. No patches.
* **packet**: no f16 (`Vel` is `Vector3F24`, 9 bytes). No unreliable channel,
  so its "unreliable" scenarios run reliably. Sets are structs of six
  `Boolean8`; optionals use `Packet.Any`, which adds a type tag. Listener calls
  are deferred. Patch: the 8000-bytes-per-heartbeat inbound cap is lifted.
* Every library except Zap and BlinkBlox supports two-way events natively.
  `fork_only` in `scenarios/manifest.json` only means stock Blink cannot build
  `two_way`; any other library that failed to build it would also be reported
  as skipped.

## Scenarios

| scenario | schema | traffic per frame |
|---|---|---|
| `match_state_reliable` | match_state | server FireAll 22-player snapshot (Reliable, ManyAsync) to 44 clients |
| `match_state_unreliable` | match_state | same snapshot, Unreliable, SingleSync |
| `per_player` | per_player | server Fire(player) 5 small reliable events to each of 44 players |
| `client_input` | client_input | 44 clients fire Unreliable input + Reliable action every 4th frame |
| `many_events` | many_events | 120 declared events, 24 fired (FireAll) across the index range, 44 clients |
| `burst_async` / `burst_sync` | burst | 1 client receives 200 events in one frame (ManyAsync / SingleSync) |
| `two_way` | two_way | `From: Both` event: server FireAll + every client fires back (Blink: blink-plus only; Zap/BlinkBlox: two events; remotes: one RemoteEvent) |

Verification: every frame, counts of received events are checked for every
client, plus a sample of fields; every 10th frame (and for one rotating client
each frame) all fields are compared. Vectors in f32 are compared exactly, f16
fields within 1e-3 (the driver only sends f16-representable values).

## Adapter interface

A variant is `label = adapter : source`. An adapter is a directory
`adapters/<name>/` with two files.

### `build.sh <sourceDir> <outDir>`

Builds the library from `<sourceDir>` (e.g. a Blink checkout, a Zap CLI
build, a ByteNet checkout) into `<outDir>` (= `gen/<label>`). For every schema
it supports it must create `<outDir>/<schema>/ok`; for a schema it tried and
failed, `<outDir>/<schema>/failed` and optionally `compile.log`. Schemas with
neither marker are treated as not built (a skip for `fork_only` scenarios, an
error otherwise). Put generated/library `.luau` files under
`<outDir>/<schema>/` (per schema) or `<outDir>/_shared/` (library code shared
by all schemas); static metrics are taken from those directories.

### `adapter.luau`

Loaded once per run with `local A = ...`, where `A.Mock` is the mock module,
`A.outDir` the build output directory and `A.benchRoot` the harness root. It
returns:

```lua
return {
	-- Compile phase (counted as "code" heap): compile everything `side`
	-- ("server" | "client") of `schema` needs, typically with
	-- A.Mock.compileFile(path) or A.Mock.compileTree(dir). Return any handle,
	-- or nil, reason to skip the scenario (schema unsupported).
	compile = function(schema, side) ... end,

	-- Start phase (counted as "state" heap): start the library on one machine
	-- and return the contract API for that side. `env` is world.server or
	-- world.clients[i]; use env:requireFile(path), env:mountTree(dir,
	-- env.ReplicatedStorage, "Name") + require, env.ReplicatedStorage,
	-- env.Players, env.RunService, env.game, env.isServer.
	start = function(handle, env) ... return api end,
}
```

`start(server)` runs before any player joins; players are then added
(`PlayerAdded` fires on the server and on already-started clients), then each
client is started. Shared library code mounted on the server under
ReplicatedStorage is visible to clients through replication. Any per-frame
flushing must hook RunService signals (`Heartbeat`, `PostSimulation`, ...),
which the harness steps in `server_step` / `client_step`.

Return library functions directly where the signature already matches (as the
Blink adapter does), so no wrapper is timed; otherwise wrap thinly (the
wrapper's cost is then counted, which is fair when the library needs it).

### Contracts (the API each schema must expose)

Values use these shapes: vectors are native vectors (`Vector3`), enums are
strings, sets are `{[name]: boolean}` tables, optionals may be nil. Listener
callbacks receive the same shapes. A library may use any wire encoding as long
as the received values compare equal (f16 fields: within 1e-3).

| schema | server API | client API |
|---|---|---|
| match_state | `fireAllReliable(state)`, `fireAllUnreliable(state)` | `onReliable(cb(state))`, `onUnreliable(cb(state))` |
| per_player | `wallet(player, u32)`, `notify(player, string<=64)`, `inventory(player, {{Item: u16, Count: u8}} <=16)`, `flags(player, set)`, `boost(player, {Kind: u8, Duration: f32?, Source: u16?})` | `onWallet(cb)`, `onNotify(cb)`, `onInventory(cb)`, `onFlags(cb)`, `onBoost(cb)` |
| client_input | `onInput(cb(player, input))`, `onAction(cb(player, action))` | `input({Seq: u8, Dir: vector, Buttons: set})` (unreliable), `action({Kind: enum, Target: u16, Power: f32})` (reliable) |
| many_events | `fireAll[e](a[, b])`, e = 1..120 (e % 3 == 0: `(u8, u16)`, else `u16`) | `on[e](cb(a[, b]))` |
| burst | `hitAsync(player, hit)`, `hitSync(player, hit)` with `hit = {Id: u16, Pos: vector, Damage: u8}` | `onHitAsync(cb(hit))`, `onHitSync(cb(hit))` |
| two_way | `pingAll(u32)`, `onPing(cb(player, u32))` | `ping(u32)`, `onPing(cb(u32))` |

`state` = `{Ball: vector, Clock: f32, HomeScore: u8, AwayScore: u8, Phase:
"Warmup"|"Kickoff"|"Play"|"Goal"|"HalfTime"|"FullTime", Players: {{Id: u16, Pos:
vector, Vel: vector (f16 ok), Stamina: u8, State:
"Idle"|"Jogging"|"Sprinting"|"Dribbling"|"Tackling"|"Diving"}} (22 entries)}`.
Set keys: per_player flags `Muted, Spectating, Captain, Ready, Away, Premium`;
client_input buttons `Sprint, Shoot, Pass, Tackle, Jump, Dive`. Action kinds:
`Shoot, Pass, Tackle, Header, Emote`. The exact definitions are the Blink
schemas in `adapters/blink/schemas/`, and each driver in `scenarios/` lists
its contract at the top and declares `api = {server = {...}, client = {...}}`,
which the runner checks against what the adapter returns.

### Adding a library

1. `adapters/<lib>/build.sh`: fetch nothing at run time; take a checkout or
   prebuilt CLI from `<sourceDir>`, generate code per schema (e.g. Zap: one
   `.zap` file per schema under `adapters/zap/schemas/`), or copy the library
   into `<outDir>/_shared/` and mark the schemas it implements with `ok`.
2. `adapters/<lib>/adapter.luau`: per schema, map the contract onto the
   library (for ByteNet-style libraries: define the packets in a small Luau
   module per schema, mount the library with `env:mountTree`, require it).
3. Run `./run.sh --variant stock=blink:<blink-stock> --variant lib=<lib>:<src>`
   and `python3 compare.py results/stock.json results/lib.json`.

If the library needs a Roblox API the mock lacks, extend `lib/mock.luau`
(service list in `World:_newEnv`, instance methods in `Instance`).
