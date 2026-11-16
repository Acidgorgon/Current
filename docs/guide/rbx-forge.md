# Using with RBX Forge

**RBX Forge** is a desktop workspace for Roblox games built from the GenTree template. It knows about Current: it can switch a game from Blink to Current in one click and then compiles, checks and documents your events with it.

## Switch a game to Current

1. Open the game in Forge.
2. Go to **Packages → Tools**.
3. Blink and Current replace each other, so the one that is not pinned shows **Switch**. Press **Switch** on Current.

Forge rewrites that line of the game's `rokit.toml` in place:

```toml [rokit.toml]
# before
blink = "1Axen/blink@0.18.1"
# after
current = "Acidgorgon/current@0.1.0"
```

and runs `rokit install`. Current is a vetted tool in Forge, so it installs without rokit's trust prompt. Pressing **Switch** on Blink switches back the same way.

You can also do it by hand: replace the `blink` line in `rokit.toml` with the `current` line and run `rokit install`.

## What Forge does with Current

- **Compiler lookup.** For the compile check, generating the other root `.blink` files, new-project setup and the release preflight, Forge looks for `current` first and falls back to `blink`. A project whose `rokit.toml` pins only `blink` keeps using `blink`.
- **Compile on save.** Every time you save `events.blink` (or a file it imports), Forge compiles a copy into a temporary folder with the project's compiler, so your real output files are never touched. Errors show in the Events panel, as editor squiggles and in the logs.
- **Two-way events.** The editor completes and documents `From: Both`, the Events panel marks such events **S⇄C**, **Copy usage** gives both halves on each side, and the new-event dialog and the assistant's event tool can create them.
- **Status.** The Events panel, the Doctor and the release check say **Current** when it compiled. The Doctor has a row for the compiler that `rokit.toml` pins.

`events.blink` stays the entry file: the schema language is the same, so nothing else in the project has to change.

::: warning The GenTree `./dev` script still calls `blink`
A GenTree game's own dev loop (`./dev`, which runs `tools/dev.sh` or `tools/dev.ps1`) starts its own watcher, and the template's scripts look for `blink` only. Until the template is updated, edit those scripts in your game to run `current` (for example `current events.blink --watch`) after switching, or the dev loop keeps compiling with Blink, which rejects `From: Both`.
:::

New projects created by Forge still pin upstream Blink; switch them after creation if you want Current.

## If you see `Unknown option "Both"`

The schema uses a [two-way event](./two-way-events) but the project is still compiling with upstream Blink. Switch the project to Current as above. Forge's error message suggests the `rokit.toml` line too.
