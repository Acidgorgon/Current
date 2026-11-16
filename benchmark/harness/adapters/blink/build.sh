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
#
# Options injected after the output options, depending on the compiler:
#
# * Current (detected by `MaxBytesPerSecond` in src/Parser.luau): the
#   per-player per-second limits are turned off with
#   `option MaxBytesPerSecond = 0` and `option MaxEventsPerSecond = 0`. They
#   are refilled from os.clock, and the harness runs frames much faster than
#   30 Hz of wall-clock time, so honest traffic would trip them (the same
#   reason the BlinkBlox adapter raises BlinkBlox's limits). Everything else
#   stays at its default: the packet size/count limits, value validation and
#   the per-packet xpcall still run.
# * Variant flags (BENCH_FLAGS, from `--variant label=blink+flag:source`):
#   `reuse` adds `option ReuseReceiveTables = true` (the compiler must
#   support it). Unknown flags fail the build.
#
# A compiler without these options (stock Blink) compiles the schemas as they are.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLINK_DIR="$(cd "$1" && pwd)"
OUT_DIR="$2"
export PATH="${BENCH_TOOLS:-/tmp/claude-0/tools}:$PATH"

supports() { grep -q "$1" "$BLINK_DIR/src/Parser.luau" 2>/dev/null; }

EXTRA=""
if supports MaxBytesPerSecond; then
	EXTRA+="option MaxBytesPerSecond = 0"$'\n'"option MaxEventsPerSecond = 0"$'\n'
fi
FLAGS="${BENCH_FLAGS:-}"
for flag in ${FLAGS//,/ }; do
	case "$flag" in
	reuse)
		if ! supports ReuseReceiveTables; then
			echo "blink adapter: flag 'reuse' needs a compiler with ReuseReceiveTables ($BLINK_DIR)" >&2
			exit 1
		fi
		EXTRA+="option ReuseReceiveTables = true"$'\n'
		;;
	*)
		echo "blink adapter: unknown flag '$flag' (known: reuse)" >&2
		exit 1
		;;
	esac
done
if [ -n "$EXTRA" ]; then
	printf 'blink adapter: injecting options:\n%s' "$EXTRA"
fi

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

for idl in "$HERE"/schemas/*.blink; do
	name="$(basename "$idl" .blink)"
	dir="$OUT_DIR/$name"
	rm -rf "$dir"
	mkdir -p "$dir"
	sed -e "s#@SERVER_OUTPUT@#$dir/server.luau#" -e "s#@CLIENT_OUTPUT@#$dir/client.luau#" "$idl" \
		| EXTRA="$EXTRA" awk '{ print } /^option ServerOutput/ { printf "%s", ENVIRON["EXTRA"] }' > "$dir/$name.blink"
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
