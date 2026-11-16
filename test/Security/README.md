# Hostile-client test

`Hostile.luau` compiles `Hostile.blink` in-process with the compiler in `src/`, loads the
generated server (and an honest client) in a mock Roblox environment, and attacks the server
the way an exploiter can: random and mutated packets (truncated, flipped bytes, forged lengths,
NaN/inf floats, invalid UTF-8, junk instance lists, wrong argument types), unknown and
server-only event indexes, oversized packets, floods, runaway function calls, and a 300-event
schema for the u16 index path. It checks that no error escapes into the engine, that listeners
only ever see values the schema allows, that the invalid packet handler is told why, and that
every limit triggers.

Run it with [Lune](https://github.com/lune-org/lune) from this directory:

```sh
lune run Hostile              # 20000 fuzz packets, seed 1
lune run Hostile 100000 7     # more packets, another seed
```

It exits with status 1 and prints `FAIL:` lines when a check fails.
