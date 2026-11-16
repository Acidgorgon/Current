#!/usr/bin/env bash
# Lync adapter build step.
#   adapters/lync/build.sh <lyncCheckout> <outDir>
#
# Lync (Axp3cter, 3dbcbd3, 4.0.x) is a runtime-schema library. This copies
# src/ into <outDir>/_shared/Lync (server copy + static metrics) and
# <outDir>/_client/Lync (client copy, see adapters/bytenet/adapter.luau), the
# per-schema definition modules into <outDir>/<schema>/net.luau, and marks
# every schema `ok`. No patches: Lync's limits (1 MB per remote call, 1000 B
# worst case for unreliable packets, set budgets) are not reached by these
# scenarios, and it has no inbound byte cap or rate limit.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$1" && pwd)"
OUT_DIR="$2"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

rm -rf "$OUT_DIR/_shared" "$OUT_DIR/_client"
mkdir -p "$OUT_DIR/_shared" "$OUT_DIR/_client"
cp -r "$SRC/src" "$OUT_DIR/_shared/Lync"
cp -r "$SRC/src" "$OUT_DIR/_client/Lync"

for idl in "$HERE"/schemas/*.luau; do
	name="$(basename "$idl" .luau)"
	rm -rf "$OUT_DIR/$name" "$OUT_DIR/_client/$name"
	mkdir -p "$OUT_DIR/$name" "$OUT_DIR/_client/$name"
	cp "$idl" "$OUT_DIR/$name/net.luau"
	cp "$idl" "$OUT_DIR/_client/$name/net.luau"
	touch "$OUT_DIR/$name/ok"
	echo "prepared  $name"
done
