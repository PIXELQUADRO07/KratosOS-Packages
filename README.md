# Official Kratos-OS packets repository

all packets are already in kpg format ready to be installed and decompressed in the system with:

- `kratos update` (update the local repository with the online packages)
- `kratos install "name"` (for install packages)
- `kratos list` (for listing installed packages)


## To add new packages:

1. First clone kratos-OS repo and build the pkg part with `make pkg`
2. clone this repo and in the root do this command to export Kratos-OS dir. `export KRATOS_ROOT=/path/to/Kratos-OS`
3. create the directory for the pacakge that you want to add (Look the subfolder first)
4. Create the recipe file, Example:

```sh
name=live
version=1.0.0
release=1
arch=x86_64
license="GPL-3.0"
description="Live ISO environment with XFCE and Calamares Installer"
source=""
sha256=""
depends="desktop,calamares,wireless-regdb,mkfontscale"

build() {
    :
}

package() {
    :
}
```

5. Add the name of the package to the group recipe that you chose
6. Execute the build-pacakges.sh script with the path to the package, Example:

```sh
./scripts/build-packages.sh xorg/mkfontscale/1.2.4
```

7. If it build correctly check again the pacakge recipe and look for the sha256checksum and make sure it is not a placeholder.
8. Exec the script `generate-index.py` to add the new packages to the index
9. Commit and push
