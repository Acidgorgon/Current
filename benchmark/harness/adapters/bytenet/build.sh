#!/usr/bin/env bash
# ByteNet adapter build step.
#   adapters/bytenet/build.sh <byteNetCheckout> <outDir>
#
# ByteNet is a runtime-schema library (no IDL compiler). This copies the
# library's src/ (a Rojo tree) into <outDir>/_shared/ByteNet (server copy,
# also used for static metrics) and <outDir>/_client/ByteNet (an identical
# client copy, so the client's code heap is measured on its own; see
# adapter.luau), and each per-schema packet module adapters/bytenet/schemas/
# <schema>.luau into <outDir>/<schema>/net.luau (+ _client copy), then marks
# every schema `ok`.
#
# Use a ByteNet RELEASE (v0.4.x, src/process/bufferWriter.luau). The current
# main branch (fbdb156, "remove the extremely pathetic dev environment") is a
# half-finished rewrite that does not load: src/process/read.luau requires
# "../a" and "./readRefs", server.luau requires "./buffer_writer", and
# client.luau calls an undefined writePacket - none of which exist.
# No patches are applied: ByteNet 0.4.x has no rate or size limits.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$1" && pwd)"
OUT_DIR="$2"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

if [ ! -f "$SRC/src/process/bufferWriter.luau" ]; then
	echo "bytenet: $SRC is not a ByteNet 0.4.x release checkout (src/process/bufferWriter.luau missing;" >&2
	echo "         ByteNet main fbdb156 is an unfinished rewrite that cannot load)" >&2
	for idl in "$HERE"/schemas/*.luau; do
		name="$(basename "$idl" .luau)"; rm -rf "$OUT_DIR/$name"; mkdir -p "$OUT_DIR/$name"
		echo "not a loadable ByteNet release: $SRC" > "$OUT_DIR/$name/compile.log"; touch "$OUT_DIR/$name/failed"
	done
	exit 0
fi

rm -rf "$OUT_DIR/_shared" "$OUT_DIR/_client"
mkdir -p "$OUT_DIR/_shared" "$OUT_DIR/_client"
cp -r "$SRC/src" "$OUT_DIR/_shared/ByteNet"
cp -r "$OUT_DIR/_shared/ByteNet" "$OUT_DIR/_client/ByteNet"

for idl in "$HERE"/schemas/*.luau; do
	name="$(basename "$idl" .luau)"
	rm -rf "$OUT_DIR/$name" "$OUT_DIR/_client/$name"
	mkdir -p "$OUT_DIR/$name" "$OUT_DIR/_client/$name"
	cp "$idl" "$OUT_DIR/$name/net.luau"
	cp "$idl" "$OUT_DIR/_client/$name/net.luau"
	touch "$OUT_DIR/$name/ok"
	echo "prepared  $name"
done
