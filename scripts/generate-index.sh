#!/usr/bin/env python3

# generate-index.sh — Generate package repository index.json for KratosOS

import os
import json
import tarfile
import hashlib
import sys

def sha256sum(filename):
    h = hashlib.sha256()
    with open(filename, 'rb') as f:
        for chunk in iter(lambda: f.read(65536), b''):
            h.update(chunk)
    return h.hexdigest()

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    repo_dir = os.path.join(repo_root, "repository/x86_64/stable")
    pkgs_dir = os.path.join(repo_dir, "packages")
    
    if not os.path.exists(pkgs_dir):
        print(f"[!] Error: Packages directory {pkgs_dir} does not exist.")
        sys.exit(1)

    packages = []
    print(f"[+] Scanning {pkgs_dir} for packages...")

    for fname in sorted(os.listdir(pkgs_dir)):
        if not fname.endswith(".kpkg"):
            continue
        pkg_path = os.path.join(pkgs_dir, fname)
        
        # Read size and SHA-256 of the package archive
        size = os.path.getsize(pkg_path)
        sha256 = sha256sum(pkg_path)
        
        metadata = {}
        installed_size = 0
        
        try:
            with tarfile.open(pkg_path, "r") as tar:
                # 1. Read metadata file
                meta_member = None
                for m in tar.getmembers():
                    if m.name == "metadata" or m.name.endswith("/metadata"):
                        meta_member = m
                        break
                
                if meta_member:
                    fmeta = tar.extractfile(meta_member)
                    if fmeta:
                        for line in fmeta.read().decode('utf-8', errors='replace').splitlines():
                            if '=' in line:
                                k, v = line.split('=', 1)
                                metadata[k.strip()] = v.strip()
                
                # 2. Extract payload.tar.gz size details to estimate installed size
                payload_member = None
                for m in tar.getmembers():
                    if m.name == "payload.tar.gz" or m.name.endswith("/payload.tar.gz"):
                        payload_member = m
                        break
                
                if payload_member:
                    fpayload = tar.extractfile(payload_member)
                    if fpayload:
                        with tarfile.open(fileobj=fpayload, mode="r:gz") as ptar:
                            for pm in ptar.getmembers():
                                if pm.isreg() or pm.islnk() or pm.issym():
                                    installed_size += pm.size
        except Exception as e:
            print(f"[!] Error reading {fname}: {e}")
            continue

        if not metadata.get("name"):
            print(f"[!] Warning: Could not parse metadata from package {fname}")
            continue
            
        pkg_info = {
            "name": metadata.get("name"),
            "version": metadata.get("version"),
            "release": int(metadata.get("release", "1")),
            "arch": metadata.get("arch", "x86_64"),
            "description": metadata.get("description", ""),
            "license": metadata.get("license", ""),
            "sha256": sha256,
            "url": f"packages/{fname}",
            "depends": metadata.get("dependencies", ""),
            "size": size,
            "installed_size": installed_size
        }
        packages.append(pkg_info)
        print(f"  [+] Found package: {pkg_info['name']}-{pkg_info['version']}-{pkg_info['release']} ({pkg_info['arch']})")

    index_data = {
        "version": 1,
        "packages": packages
    }

    index_path = os.path.join(repo_dir, "index.json")
    with open(index_path, "w") as f:
        json.dump(index_data, f, indent=2)
        
    print(f"\n[✓] Successfully generated index.json at {index_path} ({len(packages)} packages).")

if __name__ == "__main__":
    main()
