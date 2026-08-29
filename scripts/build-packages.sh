#!/usr/bin/env bash

# build-packages.sh — Cross-compile and build packages for KratosOS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 1. Locate Kratos-OS root directory
if [ -z "${KRATOS_ROOT:-}" ]; then
    if [ -d "$REPO_ROOT/../Kratos-OS" ]; then
        KRATOS_ROOT="$(cd "$REPO_ROOT/../Kratos-OS" && pwd)"
    else
        echo "[!] Error: Kratos-OS directory not found at $REPO_ROOT/../Kratos-OS."
        echo "    Please set KRATOS_ROOT environment variable."
        exit 1
    fi
fi

# 2. Source KratosOS build configs
source "$KRATOS_ROOT/build/config/build.conf"
source "$KRATOS_ROOT/build/config/versions.conf"

# Define directories
DOWNLOADS="$REPO_ROOT/downloads"
SOURCES_DIR="$REPO_ROOT/work/src"
STAGE_ROOT="$REPO_ROOT/work/stage"
REPO_PKGS="$REPO_ROOT/repository/x86_64/stable/packages"

mkdir -p "$DOWNLOADS" "$SOURCES_DIR" "$STAGE_ROOT" "$REPO_PKGS"

# 3. Build host-native kratos-pack if it does not exist
HOST_PACK="$SCRIPT_DIR/kratos-pack"
if [ ! -f "$HOST_PACK" ]; then
    echo "[+] Compiling host-native kratos-pack..."
    gcc -O2 -Wall -std=gnu11 \
        -I"$KRATOS_ROOT/pkg" \
        -DHOST_BUILD \
        -o "$HOST_PACK" \
        "$KRATOS_ROOT/pkg/kratos-pack.c" \
        "$KRATOS_ROOT/pkg/kratos-tar.c" \
        "$KRATOS_ROOT/pkg/kratos-sha256.c"
    echo "[✓] host-native kratos-pack compiled successfully."
fi

# 4. Check recipe path parameter
if [ $# -lt 1 ]; then
    echo "Usage: $0 <category/package/version>"
    echo "Example: $0 base/hello/2.12"
    exit 1
fi

RECIPE_REL_PATH="$1"
RECIPE_FILE="$REPO_ROOT/packages/$RECIPE_REL_PATH/recipe"

if [ ! -f "$RECIPE_FILE" ]; then
    echo "[!] Error: Recipe file not found at $RECIPE_FILE"
    exit 1
fi

# 5. Load Recipe (source it)
# This imports variables and defines build() and package() functions
echo "[+] Sourcing recipe: $RECIPE_REL_PATH"
name=""
version=""
release="1"
arch="x86_64"
license="GPL-3.0"
description="KratosOS Package"
source=""
sha256=""
depends=""

# Clear any previously defined build/package functions
unset -f build package

source "$RECIPE_FILE"

if [ -z "$name" ] || [ -z "$version" ]; then
    echo "[!] Error: Recipe must define name and version."
    exit 1
fi

# 6. Download source tarball (skip for metapackages)
if [ -n "$source" ]; then
    TARBALL_NAME="$(basename "$source")"
    ARCHIVE="$DOWNLOADS/$TARBALL_NAME"

    if [ ! -f "$ARCHIVE" ]; then
        echo "[+] Downloading $name $version source from $source..."
        curl -L --retry 3 -o "$ARCHIVE" "$source"
    else
        echo "[~] Source tarball already downloaded: $TARBALL_NAME"
    fi

    # Verify SHA-256
    echo "[+] Verifying SHA-256 checksum..."
    ACTUAL_SHA256=$(sha256sum "$ARCHIVE" | awk '{print $1}')
    if [[ -z "$sha256" || "$sha256" == PLACEHOLDER* ]]; then
        echo "[~] Auto-updating placeholder sha256 to: $ACTUAL_SHA256"
        sed -i "s|^sha256=.*|sha256=\"$ACTUAL_SHA256\"|" "$RECIPE_FILE"
        sha256="$ACTUAL_SHA256"
    fi
    if [ "$ACTUAL_SHA256" != "$sha256" ]; then
        echo "[!] SHA-256 checksum mismatch for $TARBALL_NAME"
        echo "    Expected: $sha256"
        echo "    Actual:   $ACTUAL_SHA256"
        exit 1
    fi
    echo "[✓] SHA-256 verified successfully."

    # 7. Extract source
    SRC_DIR="$SOURCES_DIR/$name-$version"
    rm -rf "$SRC_DIR"

    echo "[+] Extracting source to $SOURCES_DIR..."
    tar -xf "$ARCHIVE" -C "$SOURCES_DIR"

    if [ ! -d "$SRC_DIR" ]; then
        TAR_STEM="${TARBALL_NAME%.tar.*}"
        if [ -d "$SOURCES_DIR/$TAR_STEM" ]; then
            echo "[~] Renaming extracted directory $SOURCES_DIR/$TAR_STEM to $SRC_DIR"
            mv "$SOURCES_DIR/$TAR_STEM" "$SRC_DIR"
        else
            EXTRACTED_DIR=$(find "$SOURCES_DIR" -maxdepth 1 -mindepth 1 -type d -name "$name-*" | head -n 1)
            if [ -n "$EXTRACTED_DIR" ]; then
                echo "[~] Renaming extracted directory $EXTRACTED_DIR to $SRC_DIR"
                mv "$EXTRACTED_DIR" "$SRC_DIR"
            else
                echo "[!] Error: Extracted directory not found at $SRC_DIR"
                exit 1
            fi
        fi
    fi
else
    echo "[~] Metapackage detected: No source to download."
    SRC_DIR="/tmp/kpm-meta-$(id -u)"
    rm -rf "$SRC_DIR"
    mkdir -p "$SRC_DIR"
fi

# 8. Setup Build Staging Area
STAGE_DIR="$STAGE_ROOT/$name-$version"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

# 9. Setup Cross-Compile Environment
export PATH="$REPO_ROOT/bin:$KRATOS_TOOLS/bin:$PATH"
export SYSROOT="$KRATOS_SYSROOT"
export PKG_CONFIG_LIBDIR="${SYSROOT}/usr/lib/pkgconfig:${SYSROOT}/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT}"
export PKG_CONFIG_PATH=""
export TARGET="x86_64-kratos-linux-gnu"
export CC="$TARGET-gcc"
export CXX="$TARGET-g++"
export AR="$TARGET-ar"
export RANLIB="$TARGET-ranlib"
export STRIP="$TARGET-strip"
export PKGDIR="$STAGE_DIR"
export MESON_CROSS="$SCRIPT_DIR/kratos-cross-file.txt"
export ac_cv_func_malloc_0_nonnull=yes
export ac_cv_func_realloc_0_nonnull=yes
export lf_cv_sane_realloc=yes
export CFLAGS="${CFLAGS:--O2 -pipe} -std=gnu17 -Wno-incompatible-pointer-types -Wno-implicit-function-declaration -Wno-error"
export CXXFLAGS="${CXXFLAGS:--O2 -pipe} -Wno-error"

echo "=================================================="
echo "   Building Package: $name-$version-$release"
echo "   Cross Compiler:   $CC"
echo "   Staging Area:     $STAGE_DIR"
echo "=================================================="

# 10. Run Build function
cd "$SRC_DIR"
echo "[+] Running build() stage..."
build

# 11. Run Package function
echo "[+] Running package() stage..."
package

# 12. Pack the staging area into a .kpkg
OUTPUT_KPKG="$REPO_PKGS/${name}-${version}-${release}-${arch}.kpkg"
echo "[+] Creating .kpkg container at $OUTPUT_KPKG..."

"$HOST_PACK" \
    --name "$name" \
    --version "$version" \
    --release "$release" \
    --arch "$arch" \
    --description "$description" \
    --license "$license" \
    --deps "$depends" \
    --dir "$STAGE_DIR" \
    --out "$OUTPUT_KPKG"

# Install immediately into sysroot so subsequent recipes find headers and libs
if [ -x "$SCRIPT_DIR/install-to-sysroot.sh" ]; then
    bash "$SCRIPT_DIR/install-to-sysroot.sh" "$OUTPUT_KPKG"
fi

echo "[✓] Package $name-$version built successfully!"
