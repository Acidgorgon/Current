#!/usr/bin/env bash
# BlinkBlox adapter build step.
#   adapters/blinkblox/build.sh <blinkBloxRepoDir> <outDir>
#
# Compiles every adapters/blinkblox/schemas/<schema>.blink with the BlinkBlox compiler
# at <blinkBloxRepoDir>/src/CLI/init.luau (run from source through upstream
# Lune, which its CLAUDE.md says the compiler source must keep supporting;
# the generated modules do not depend on the runner) into
# <outDir>/<schema>/{server,client}.luau, and marks each schema dir with `ok`
# or `failed` (+ compile.log), as every adapter build must.
#
# Output paths are injected as absolute paths (Blink resolves relative output
# paths against the .blink file), by substituting the @SERVER_OUTPUT@ /
# @CLIENT_OUTPUT@ placeholders in a per-schema copy of the IDL.
#
# One mock-compatibility patch is applied to the generated server: its guard
# against `Net.Event:Fire(...)` (colon call) tests `type(Player) == "table"`,
# which is right in Roblox (a Player is userdata) but true for the mock's
# table-based instances, so every Fire(player) would throw. It is rewritten to
# the equivalent `typeof(Player) ~= "Instance"` (the mock's typeof returns
# "Instance" for its instances). The guard only runs on a player's first send
# (when no per-player buffer exists yet), so it does not affect timings.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLINK_DIR="$(cd "$1" && pwd)"
OUT_DIR="$2"
export PATH="${BENCH_TOOLS:-/tmp/claude-0/tools}:$PATH"

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

for idl in "$HERE"/schemas/*.blink; do
	name="$(basename "$idl" .blink)"
	dir="$OUT_DIR/$name"
	rm -rf "$dir"
	mkdir -p "$dir"
	sed -e "s#@SERVER_OUTPUT@#$dir/server.luau#" -e "s#@CLIENT_OUTPUT@#$dir/client.luau#" "$idl" > "$dir/$name.blink"
	# The CLI must be run from its own directory (it requires "@self/..." modules).
	if (cd "$BLINK_DIR/src/CLI" && lune run init "$dir/$name.blink" -- --yes) > "$dir/compile.log" 2>&1 \
		&& [ -s "$dir/server.luau" ] && [ -s "$dir/client.luau" ]; then
		sed -i 's/if type(Player) == "table" then/if typeof(Player) ~= "Instance" then -- [bench patch] mock Players are tables, see adapters\/blinkblox\/build.sh/' "$dir/server.luau"
		touch "$dir/ok"
		echo "compiled  $name"
	else
		touch "$dir/failed"
		echo "FAILED    $name (see $dir/compile.log)"
	fi
done
