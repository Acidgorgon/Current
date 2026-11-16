# Installation

Current is a command-line compiler (`current`) plus an optional Roblox Studio plugin. The recommended way to install the compiler is [Rokit](https://github.com/rojo-rbx/rokit), so every collaborator on a project uses the same version.

## Rokit

Run this in your project folder:

```sh
rokit add Acidgorgon/current
```

Or add the line yourself under `[tools]` in `rokit.toml` and run `rokit install`:

```toml [rokit.toml]
[tools]
current = "Acidgorgon/current@0.1.0"
```

Check that it works:

```sh
current --version
```

To update later:

```sh
rokit update Acidgorgon/current
```

::: tip Switching a project from Blink
If the project pins upstream Blink (`blink = "1Axen/blink@…"`), replace that line with the `current` line above and run `rokit install`. Your `.blink` files compile unchanged; see [Migrating from Blink](./migrating-from-blink).
:::

## GitHub Releases

Pre-built binaries are attached to every [GitHub release](https://github.com/Acidgorgon/current/releases). Download the archive for your platform, extract it, and put the `current` executable (`current.exe` on Windows) somewhere on your `PATH`.

| Platform | Archive |
|---|---|
| Windows x64 | `current-windows-x86_64.tar.gz` |
| macOS Apple silicon | `current-macos-aarch64.tar.xz` |
| macOS Intel | `current-macos-x86_64.tar.xz` |
| Linux x64 | `current-linux-x86_64.tar.xz` |
| Linux ARM64 | `current-linux-aarch64.tar.xz` |

## Studio plugin

The plugin lets you write schemas and generate the modules inside Roblox Studio, without any external tools.

1. Download `current-plugin.rbxm` from [GitHub Releases](https://github.com/Acidgorgon/current/releases).
2. Put it in your Studio plugins folder (in Studio: **Plugins → Plugins Folder**).
3. Restart Studio. The plugin shows up in the Plugins tab as **Current**.

See [Studio plugin](/reference/plugin) for how to use it.

## Next steps

Head to [Getting started](./getting-started) to write your first schema.
