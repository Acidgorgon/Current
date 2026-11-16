#!/usr/bin/env bash
# Zap adapter build step.
#   adapters/zap/build.sh <zapDir> <outDir>
#
# <zapDir> is a Zap checkout with a built CLI at target/release/zap (or a
# directory containing the `zap` binary itself). Compiles every
# adapters/zap/schemas/<schema>.zap into <outDir>/<schema>/{server,client}.luau
# and marks each schema dir with `ok` or `failed` (+ compile.log).
#
# Output paths are injected as absolute paths by substituting the
# @SERVER_OUTPUT@ / @CLIENT_OUTPUT@ placeholders in a per-schema copy of the
# config (like the Blink adapter).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZAP_DIR="$(cd "$1" && pwd)"
OUT_DIR="$2"

ZAP=""
for candidate in "$ZAP_DIR/target/release/zap" "$ZAP_DIR/zap"; do
	if [ -f "$candidate" ] && [ -x "$candidate" ]; then
		ZAP="$candidate"
		break
	fi
done
if [ -z "$ZAP" ]; then
	echo "zap adapter: no zap binary in $ZAP_DIR (expected target/release/zap)" >&2
	exit 1
fi

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
echo "using $("$ZAP" --version)"

for idl in "$HERE"/schemas/*.zap; do
	name="$(basename "$idl" .zap)"
	dir="$OUT_DIR/$name"
	rm -rf "$dir"
	mkdir -p "$dir"
	sed -e "s#@SERVER_OUTPUT@#$dir/server.luau#" -e "s#@CLIENT_OUTPUT@#$dir/client.luau#" "$idl" > "$dir/$name.zap"
	if "$ZAP" "$dir/$name.zap" > "$dir/compile.log" 2>&1 \
		&& [ -s "$dir/server.luau" ] && [ -s "$dir/client.luau" ]; then
		touch "$dir/ok"
		echo "compiled  $name"
	else
		touch "$dir/failed"
		echo "FAILED    $name (see $dir/compile.log)"
	fi
done
