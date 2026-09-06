#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

make -j$(sysctl -n hw.ncpu)

if [ -f out/macsteam.dylib ]; then
    echo "[build] OK: out/macsteam.dylib"
else
    echo "[build] FAILED"
    exit 1
fi
