#!/usr/bin/env bash
# Blink adapter build step.
#   adapters/blink/build.sh <blinkRepoDir> <outDir>
#
# Compiles every adapters/blink/schemas/<schema>.blink with the Blink compiler
# at <blinkRepoDir>/src/CLI/init.luau (run through Lune) into
# <outDir>/<schema>/{server,client}.luau, and marks each schema dir with `ok`
# or `failed` (+ compile.log), as every adapter build must.
#
# Output paths are injected as absolute paths (Blink resolves relative output
# paths against the .blink file), by substituting the @SERVER_OUTPUT@ /
# @CLIENT_OUTPUT@ placeholders in a per-schema copy of the IDL.
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
		touch "$dir/ok"
		echo "compiled  $name"
	else
		touch "$dir/failed"
		echo "FAILED    $name (see $dir/compile.log)"
	fi
done
