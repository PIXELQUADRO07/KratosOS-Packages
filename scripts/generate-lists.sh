#!/usr/bin/env python3
"""
generate-lists.sh — KratosOS Package Lists Generator

Genera/aggiorna lists.json a partire dalle definizioni in lists/ directory
oppure direttamente dall'index.json per il gruppo "all".

Uso:
    python3 scripts/generate-lists.sh
    python3 scripts/generate-lists.sh --validate   # solo validazione
"""

import json
import os
import sys
import argparse
from datetime import datetime, timezone

# Percorso radice del repository
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(SCRIPT_DIR, "..", "repository", "x86_64", "stable")
INDEX_FILE = os.path.join(REPO_ROOT, "index.json")
LISTS_FILE = os.path.join(REPO_ROOT, "lists.json")

# Definizione delle liste — modifica qui per aggiungere/rimuovere gruppi
LISTS_DEFINITIONS = [
    {
        "name": "base",
        "description": "Sistema base minimo — shell, coreutils e strumenti fondamentali",
        "packages": [
            "bash", "coreutils", "findutils", "grep",
            "sed", "gzip", "tar", "shadow", "util-linux"
        ]
    },
    {
        "name": "utils",
        "description": "Utility di sistema per uso quotidiano",
        "packages": [
            "coreutils", "findutils", "grep", "sed",
            "gzip", "tar", "vim", "sudo", "util-linux"
        ]
    },
    {
        "name": "networking",
        "description": "Strumenti di rete e networking",
        "packages": [
            "wget", "iproute2", "libpsl", "libmnl", "libtirpc"
        ]
    },
    {
        "name": "system",
        "description": "Componenti di sistema — autenticazione, permessi, gestione utenti",
        "packages": [
            "shadow", "sudo", "util-linux",
            "libcap", "libxcrypt", "elfutils"
        ]
    },
    {
        "name": "libs",
        "description": "Librerie condivise e dipendenze runtime",
        "packages": [
            "zlib", "zstd", "libmd", "libbsd", "libtirpc",
            "libunistring", "libmnl", "libcap", "libxcrypt",
            "libpsl", "elfutils", "readline", "ncurses"
        ]
    },
    {
        "name": "editors",
        "description": "Editor di testo e strumenti di editing",
        "packages": ["vim"]
    },
    {
        "name": "all",
        "description": "Tutti i pacchetti disponibili nel repository",
        "packages": []   # Lista vuota = tutti i pacchetti dell'index
    }
]


def load_index():
    """Carica l'index.json e ritorna l'insieme dei package name disponibili."""
    if not os.path.exists(INDEX_FILE):
        print(f"[!] index.json non trovato: {INDEX_FILE}", file=sys.stderr)
        return set()
    with open(INDEX_FILE) as f:
        data = json.load(f)
    return {p["name"] for p in data.get("packages", [])}


def validate_lists(lists_defs, available_pkgs):
    """Valida che ogni pacchetto nelle liste esista nell'index."""
    errors = []
    for lst in lists_defs:
        if not lst["packages"]:
            continue  # "all" ha lista vuota: ok
        for pkg in lst["packages"]:
            if pkg not in available_pkgs:
                errors.append(f"  [!] Gruppo '{lst['name']}': pacchetto '{pkg}' non trovato nell'index")
    return errors


def generate(validate_only=False):
    available = load_index()
    if not available:
        print("[!] Nessun pacchetto trovato nell'index, abort.", file=sys.stderr)
        return 1

    errors = validate_lists(LISTS_DEFINITIONS, available)
    if errors:
        print("[!] Errori di validazione:")
        for e in errors:
            print(e)
        if validate_only:
            return 1
        print("[~] Continuo comunque con i pacchetti disponibili...")

    if validate_only:
        if not errors:
            print(f"[✓] Validazione OK: {len(LISTS_DEFINITIONS)} liste, {len(available)} pacchetti disponibili")
        return 0 if not errors else 1

    # Risolvi "all" con tutti i pacchetti dell'index
    output_lists = []
    for lst in LISTS_DEFINITIONS:
        entry = dict(lst)
        if lst["name"] == "all":
            entry["packages"] = sorted(available)
        else:
            # Filtra eventuali pacchetti non presenti nell'index (con warning già sopra)
            entry["packages"] = [p for p in lst["packages"] if p in available]
        output_lists.append(entry)

    output = {
        "version": 1,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "arch": "x86_64",
        "lists": output_lists
    }

    with open(LISTS_FILE, "w") as f:
        json.dump(output, f, indent=2)
        f.write("\n")

    print(f"[✓] Generato lists.json: {len(output_lists)} gruppi")
    for lst in output_lists:
        count = len(lst["packages"])
        label = f"({count} pacchetti)" if count > 0 else "(tutti)"
        print(f"  [+] @{lst['name']:<16} — {label}")

    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Genera lists.json per il repository KratosOS")
    parser.add_argument("--validate", action="store_true", help="Solo validazione, non scrivere")
    args = parser.parse_args()
    sys.exit(generate(validate_only=args.validate))
