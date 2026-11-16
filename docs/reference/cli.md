# CLI

```sh
current [SCHEMA] [OPTIONS]
```

`SCHEMA` is the path to a schema file. The extension can be left out: Current tries the path as given, then with `.txt`, `.blink` and `.current`. The first argument is always the schema; options can follow in any order.

```sh
current net                 # finds net, net.txt, net.blink or net.current
current shared/net.blink --yes
current net --watch
```

Output paths come from the [`ServerOutput`, `ClientOutput` and `TypesOutput` options](./options#serveroutput-clientoutput-typesoutput) in the schema, relative to the schema file.

## Options

| Flag | Description |
|---|---|
| `-h`, `--help` | Print usage and the list of options. |
| `-v`, `--version` | Print the version (`Current 0.1.1`) and exit. |
| `-w`, `--watch` | Watch the schema and every file it imports (and their imports) and recompile whenever one changes. |
| `-y`, `--yes` | Accept every prompt, such as creating an output folder that does not exist. Use it in scripts and CI. |
| `-q`, `--quiet` | Print nothing but errors. |
| `-c`, `--compact` | Print a compact version of each error first; the full message still follows. |

Running `current` with no arguments prints the help.

## Watch mode

```sh
current net --watch
```

Watch mode compiles once, then recompiles on every change to the schema or anything it imports, and picks up imports you add or remove. It runs quietly and creates missing folders without asking. Stop it with <kbd>Ctrl</kbd>+<kbd>C</kbd>.

## In scripts and CI

```sh
# Fail the build if the schema does not compile
current net --yes --quiet
```

The exit status is non-zero when the schema has errors.

## Error messages

Errors show the code, the message and the place in the schema:

```text
[E2003] Error: Unknown option "Nowhere"
    │
004 │     From: Nowhere,
    ┆           ───┬───
    ┆              ╰── Expected one of "Client" or "Server" or "Both"
────╯
```

With `--compact`, a one-line summary is printed first.

If upstream `blink` reports `Unknown option "Both"` or an unknown `ReuseSendBuffers` option, the schema uses a Current feature: compile it with `current` instead. See [Migrating from Blink](/guide/migrating-from-blink).
