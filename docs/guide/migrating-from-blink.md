# Migrating from Blink

Current is a drop-in replacement for [Blink](https://github.com/1Axen/blink) 0.18. It reads the same schema language and the same `.blink` files, generates modules with the same API, and uses the same remotes. Your game code does not change.

## Steps

1. **Swap the tool.** In `rokit.toml`, replace the Blink line with Current and run `rokit install`:

   ```toml [rokit.toml]
   [tools]
   # blink = "1Axen/blink@0.18.9"
   current = "Acidgorgon/current@0.1.0"
   ```

2. **Call `current` instead of `blink`.** Arguments are the same, so `blink net --watch` becomes `current net --watch`. Update any scripts that call the compiler (dev scripts, CI, Makefiles).

3. **Recompile.** Run `current <schema>` once and commit the regenerated modules.

That's it. If you used the Studio plugin, install `current-plugin.rbxm` instead of the Blink plugin; your saved schemas carry over (see [Studio plugin](/reference/plugin)).

## What stays the same

- **Schema language.** Every type, option, event and function field that Blink accepts, Current accepts with the same meaning. `.blink` files compile unchanged; `.current` is accepted as an extra extension.
- **Generated API.** `Fire`, `FireAll`, `FireList`, `FireExcept`, `On`, `Iter`, `Invoke`, `StepReplication`, exports' `Read`/`Write`, and the `Casing` option all work as before. TypeScript output has the same shape.
- **Remotes and runtime names.** The generated modules still create `BLINK_RELIABLE_REMOTE` and `BLINK_UNRELIABLE_REMOTE` (prefixed by `RemoteScope`), register in `_G._BLINK`, and tag their warnings `[Blink]`. This keeps old and new modules compatible and means a Current module and a Blink module in the same game need different `RemoteScope`s, just as two Blink modules did.
- **CLI flags.** `--watch`, `--yes`, `--quiet`, `--compact`, `--help`, `--version` (see [CLI](/reference/cli)).

## What is new or different

| | Blink 0.18 | Current |
|---|---|---|
| Command | `blink` | `current` |
| Schema extensions | none, `.txt`, `.blink` | none, `.txt`, `.blink`, `.current` |
| Two-way events | no | [`From: Both`](./two-way-events) |
| Reusing send buffers | no | [`option ReuseSendBuffers`](/reference/options#reusesendbuffers) |
| Reusing received tables | no | [`option ReuseReceiveTables`](/reference/options#reusereceivetables), per event [`ReuseTables`](/reference/events#reusetables) |
| Event indexes | one byte | one byte, two bytes when a channel has more than 256 events |
| Reliable broadcasts (`FireAll`) | copied into every player's buffer | written once into a shared log, whatever the player count |
| Reliable sends to a player who left | re-add them to the send map (kept for good) | dropped |
| Studio plugin | toolbar "Blink", output folder `Blink` | toolbar "Current", output folder `Current` |

Behaviour your code relies on is unchanged:

- Reliable events reach each player in the order they were fired, whichever mix of `Fire`, `FireAll`, `FireList` and `FireExcept` sent them.
- Reliable sends are batched and go out on `Heartbeat`, or when you call `StepReplication` with `ManualReplication` on. Unreliable events are sent immediately.
- Client data is validated on the server exactly as before.

The generated code inside the modules is different (and faster): see [Performance](./performance). Don't depend on its internals, only on the returned table.

## Going back

A schema that does not use `From: Both`, `ReuseSendBuffers`, `ReuseReceiveTables` or `ReuseTables` still compiles with upstream Blink. Put the `blink` line back in `rokit.toml` and recompile.
