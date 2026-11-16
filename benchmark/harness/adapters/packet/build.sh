#!/usr/bin/env bash
# Packet adapter build step (Suphi Kaner's Packet 1.7, a ModuleScript tree:
# init.luau + Signal, Task, Types/{init, Characters, Static1-3, Enums}).
#   adapters/packet/build.sh <dir containing init.luau, e.g. .../Packet/MainModule> <outDir>
#
# Copies the module tree into <outDir>/_shared/Packet (server copy + static
# metrics) and <outDir>/_client/Packet (client copy, see
# adapters/bytenet/adapter.luau), the per-schema packet modules into
# <outDir>/<schema>/net.luau, and marks every schema `ok`. Changes applied to
# the COPY (never the source):
#
# 1. Inbound cap lifted, as BlinkBlox's benchmark/download.luau does:
#      init.luau "if bytes > 8_000 then" -> "if bytes > math.huge then"
#    Packet's server charges each packet from a player at least 800 bytes and
#    drops whatever that player sends past 8000 bytes per server heartbeat; a
#    constant with no option to change it.
# 2. Types/Static1.luau (Packet's user-editable list of up to 255 "static"
#    values, sent as a u8 index) is set to the scenario enum names
#    (adapters/packet/Static1.luau). This is how Packet expresses an enum, and
#    gives Blink's 1-byte enum encoding. Static2/3 and Enums keep their
#    shipped contents (unused).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$1" && pwd)"
OUT_DIR="$2"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
[ -f "$SRC/init.luau" ] || { echo "packet: $SRC/init.luau not found (pass the MainModule directory)" >&2; exit 1; }

rm -rf "$OUT_DIR/_shared" "$OUT_DIR/_client"
mkdir -p "$OUT_DIR/_shared" "$OUT_DIR/_client"
cp -r "$SRC" "$OUT_DIR/_shared/Packet"
LIB="$OUT_DIR/_shared/Packet"

python3 -I - "$LIB/init.luau" "if bytes > 8_000 then" "if bytes > math.huge then" <<'PY'
import sys
path, find, new = sys.argv[1:4]
src = open(path).read()
n = src.count(find)
if n != 1:
    sys.exit(f"patch: {path} contains {find!r} {n} times (expected 1)")
open(path, "w").write(src.replace(find, new))
PY
cp "$HERE/Static1.luau" "$LIB/Types/Static1.luau"
cp -r "$LIB" "$OUT_DIR/_client/Packet"

for idl in "$HERE"/schemas/*.luau; do
	name="$(basename "$idl" .luau)"
	rm -rf "$OUT_DIR/$name" "$OUT_DIR/_client/$name"
	mkdir -p "$OUT_DIR/$name" "$OUT_DIR/_client/$name"
	cp "$idl" "$OUT_DIR/$name/net.luau"
	cp "$idl" "$OUT_DIR/_client/$name/net.luau"
	touch "$OUT_DIR/$name/ok"
	echo "prepared  $name"
done
