#!/usr/bin/env bash
# run.sh <blinkRepoDir> <label> [extra run.py options]
# Compiles all scenario IDLs with the given Blink, runs every scenario in
# interpreter and native mode, and writes results/<label>.json.
# Example: ./run.sh $HOME/src/blink-stock stock
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/run.py" "$@"
