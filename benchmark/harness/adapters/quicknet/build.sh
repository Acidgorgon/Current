#!/usr/bin/env bash
# QuickNet adapter build step.
#   adapters/quicknet/build.sh <quickNetCheckout> <outDir>
#
# QuickNet (v0.4.0, edba9a2) is a runtime-schema library. This copies src/
# into <outDir>/_shared/QuickNet (server copy + static metrics) and
# <outDir>/_client/QuickNet (client copy, see adapters/bytenet/adapter.luau),
# the per-schema event modules into <outDir>/<schema>/net.luau, and marks
# every schema `ok`. Patches applied to the COPY (never the checkout):
#
# 1. Limits lifted exactly as BlinkBlox's benchmark/download.luau does
#    (Config.luau): "MaxPacketSize = 50000," -> "MaxPacketSize = math.huge,"
#    and "MaxCallsPerFrame = 100," -> "MaxCallsPerFrame = math.huge,". Since
#    0.4.0 the server drops a client packet over 50 kB and the events past
#    the 100th in one packet. (No scenario here reaches either; lifted for
#    parity with BlinkBlox's setup.) The per-event rate limit (default 60 sends
#    per event per second per player, measured with os.clock, which this
#    harness runs far faster than real time) is lifted per event with
#    :SetRateLimit(math.huge, 1) in the schema modules, as BlinkBlox's modes and
#    QuickNet's own benchmark do.
# 2. `const NAME = value` -> `local NAME = value` (init.luau, Serialize.luau):
#    the harness's Luau 0.700 cannot parse `const`; same constant folding.
# Config is otherwise left at its defaults (DebugMode = true, so QuickNet's
# warnings are reported; ServerAllocationSize = 1 MB and
# ClientAllocationSize = 2 MB per queue buffer, which shows in the heap).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$1" && pwd)"
OUT_DIR="$2"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

rm -rf "$OUT_DIR/_shared" "$OUT_DIR/_client"
mkdir -p "$OUT_DIR/_shared" "$OUT_DIR/_client"
cp -r "$SRC/src" "$OUT_DIR/_shared/QuickNet"
LIB="$OUT_DIR/_shared/QuickNet"

replace() {
	python3 -I - "$1" "$2" "$3" <<'PY'
import sys
path, find, new = sys.argv[1:4]
src = open(path).read()
n = src.count(find)
if n != 1:
    sys.exit(f"patch: {path} contains {find!r} {n} times (expected 1)")
open(path, "w").write(src.replace(find, new))
PY
}
replace "$LIB/Config.luau" "MaxPacketSize = 50000," "MaxPacketSize = math.huge,"
replace "$LIB/Config.luau" "MaxCallsPerFrame = 100," "MaxCallsPerFrame = math.huge,"
find "$LIB" -name '*.luau' -exec sed -i -E 's/^([[:space:]]*)const[[:space:]]/\1local /' {} +
if grep -rqE '^[[:space:]]*const[[:space:]]' "$LIB"; then echo "quicknet: const left after patch" >&2; exit 1; fi
cp -r "$LIB" "$OUT_DIR/_client/QuickNet"

for idl in "$HERE"/schemas/*.luau; do
	name="$(basename "$idl" .luau)"
	rm -rf "$OUT_DIR/$name" "$OUT_DIR/_client/$name"
	mkdir -p "$OUT_DIR/$name" "$OUT_DIR/_client/$name"
	cp "$idl" "$OUT_DIR/$name/net.luau"
	cp "$idl" "$OUT_DIR/_client/$name/net.luau"
	touch "$OUT_DIR/$name/ok"
	echo "prepared  $name"
done
