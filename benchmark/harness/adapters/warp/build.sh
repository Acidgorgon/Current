#!/usr/bin/env bash
# Warp adapter build step.
#   adapters/warp/build.sh <warpCheckout> <outDir>
#
# Warp (imezx, 1.1.0-pre8 / main fb28e9a) is a runtime-schema library. This
# copies src/ into <outDir>/_shared/Warp (server copy + static metrics) and
# <outDir>/_client/Warp (client copy, see adapters/bytenet/adapter.luau for
# why), the per-schema event modules into <outDir>/<schema>/net.luau, and
# marks every schema `ok`. Patches applied to the COPY (never the checkout):
#
# 1. Inbound cap lifted (as BlinkBlox's benchmark/download.luau does):
#      Server/init.luau  "if bytes > 8e3 then" -> "if bytes > math.huge then"
#    Outside Studio Warp's server charges each packet from a player at least
#    800 bytes and silently drops that player's traffic past 8000 bytes until
#    the server next sends that player something. The mock reports
#    IsStudio() == false, so client_input (10+ packets per player between
#    server sends) would lose almost everything without it.
# 2. `const NAME = value` -> `local NAME = value` (Util/Identifier.luau,
#    Util/Xor.luau): `const` is newer Luau syntax that the harness's Luau 0.700
#    cannot parse. The values are literals that are never reassigned, so the
#    compiler constant-folds the locals the same way.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$1" && pwd)"
OUT_DIR="$2"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

rm -rf "$OUT_DIR/_shared" "$OUT_DIR/_client"
mkdir -p "$OUT_DIR/_shared" "$OUT_DIR/_client"
cp -r "$SRC/src" "$OUT_DIR/_shared/Warp"
LIB="$OUT_DIR/_shared/Warp"

# replace <file> <find> <with>: exactly one occurrence, or the build fails
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
replace "$LIB/Server/init.luau" "if bytes > 8e3 then" "if bytes > math.huge then"
find "$LIB" -name '*.luau' -exec sed -i -E 's/^([[:space:]]*)const[[:space:]]/\1local /' {} +
if grep -rqE '^[[:space:]]*const[[:space:]]' "$LIB"; then echo "warp: const left after patch" >&2; exit 1; fi
cp -r "$LIB" "$OUT_DIR/_client/Warp"

for idl in "$HERE"/schemas/*.luau; do
	name="$(basename "$idl" .luau)"
	rm -rf "$OUT_DIR/$name" "$OUT_DIR/_client/$name"
	mkdir -p "$OUT_DIR/$name" "$OUT_DIR/_client/$name"
	cp "$idl" "$OUT_DIR/$name/net.luau"
	cp "$idl" "$OUT_DIR/_client/$name/net.luau"
	touch "$OUT_DIR/$name/ok"
	echo "prepared  $name"
done
