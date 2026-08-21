#!/usr/bin/env bash
# pack-from-stage.sh — Pack all staged directories into .kpkg files
#
# This script scans 'work/stage/' and creates .kpkg files for any directory
# that doesn't already have one in the stable repository.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGE_DIR="$REPO_ROOT/work/stage"
REPO_PKGS="$REPO_ROOT/repository/x86_64/stable/packages"
HOST_PACK="$SCRIPT_DIR/kratos-pack"

mkdir -p "$REPO_PKGS"

echo "========================================"
echo "    KRATOSOS MASS PACKING FROM STAGE"
echo "========================================"
echo

# 1. Scan recipes to get metadata (more reliable than directory names)
declare -A RECIPES
while IFS= read -r recipe_file; do
    name=$(grep "^name=" "$recipe_file" | cut -d= -f2 | tr -d '"')
    version=$(grep "^version=" "$recipe_file" | cut -d= -f2 | tr -d '"')
    if [ -n "$name" ] && [ -n "$version" ]; then
        RECIPES["$name"]="$recipe_file"
    fi
done < <(find "$REPO_ROOT/packages" -name "recipe")

# 2. Iterate through directories in work/stage
for dir in "$STAGE_DIR"/*/; do
    [ -d "$dir" ] || continue
    dir_name=$(basename "$dir")

    # Try to parse name-version from directory name (e.g. bash-5.3)
    if [[ "$dir_name" =~ ^(.*)-([0-9]+\.[0-9].*)$ ]]; then
        name="${BASH_REMATCH[1]}"
        version="${BASH_REMATCH[2]}"
    else
        # Metapackages often don't have a version in the dir name or it's fixed
        name=$(echo "$dir_name" | cut -d- -f1)
        version=$(echo "$dir_name" | cut -d- -f2)
    fi

    # Check if we have a recipe for this name to get better metadata
    recipe="${RECIPES[$name]:-}"
    description="KratosOS Package"
    depends=""
    release="1"
    license="GPL-3.0"

    if [ -n "$recipe" ]; then
        # Override with actual recipe data
        version=$(grep "^version=" "$recipe" | cut -d= -f2 | tr -d '"')
        release=$(grep "^release=" "$recipe" | cut -d= -f2 | tr -d '"' || echo "1")
        description=$(grep "^description=" "$recipe" | cut -d= -f2 | tr -d '"')
        depends=$(grep "^depends=" "$recipe" | cut -d= -f2 | tr -d '"')
        license=$(grep "^license=" "$recipe" | cut -d= -f2 | tr -d '"')
    fi

    OUTPUT_KPKG="$REPO_PKGS/${name}-${version}-${release}-x86_64.kpkg"

    if [ ! -f "$OUTPUT_KPKG" ]; then
        echo "[+] Packing $name-$version from $dir_name..."
        "$HOST_PACK" \
            --name "$name" \
            --version "$version" \
            --release "${release:-1}" \
            --arch "x86_64" \
            --description "$description" \
            --license "$license" \
            --deps "$depends" \
            --dir "${dir%/}" \
            --out "$OUTPUT_KPKG"
    else
        echo "[~] Skipping $name-$version (already exists in repo)"
    fi
done

# 3. Update the index
echo
echo "[+] Generating repository index..."
python3 "$SCRIPT_DIR/generate-index.sh"
python3 "$SCRIPT_DIR/generate-lists.sh"

echo
echo "[✓] Mass packing complete."
