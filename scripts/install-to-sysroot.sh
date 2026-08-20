#!/usr/bin/env bash
# install-to-sysroot.sh — Extract a .kpkg into the KratosOS sysroot for building dependencies

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <package.kpkg>"
    exit 1
fi

KPKG="$1"
if [ ! -f "$KPKG" ]; then
    echo "[!] Error: File $KPKG not found."
    exit 1
fi

# Locate Kratos-OS root
if [ -z "${KRATOS_ROOT:-}" ]; then
    KRATOS_ROOT="$(cd "$(dirname "$0")/../../Kratos-OS" && pwd)"
fi

SYSROOT="$KRATOS_ROOT/build/sysroot"
if [ ! -d "$SYSROOT" ]; then
    echo "[!] Error: Sysroot not found at $SYSROOT"
    exit 1
fi

echo "[+] Installing $(basename "$KPKG") to sysroot..."

# Create a temporary directory
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Extract payload.tar.gz from kpkg
tar -xf "$KPKG" -C "$TMP" payload.tar.gz

# Extract payload into sysroot
tar -xzf "$TMP/payload.tar.gz" -C "$SYSROOT"

# Remove .la files to avoid libtool cross-compilation issues
find "$SYSROOT/usr/lib" -name "*.la" -delete

echo "[✓] Done."
