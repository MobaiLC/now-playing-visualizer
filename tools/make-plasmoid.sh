#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds build/now-playing-visualizer-<version>.plasmoid: the package folder
# with compiled translations, zipped the way the KDE Store and
# "kpackagetool6 -i file.plasmoid" expect.
set -euo pipefail
cd "$(dirname "$0")/.."

tools/build-translations.sh
version=$(python3 -c 'import json; print(json.load(open("package/metadata.json"))["KPlugin"]["Version"])')
mkdir -p build
out="build/now-playing-visualizer-$version.plasmoid"
python3 -I - "$out" <<'PY'
import os, sys, zipfile
from pathlib import Path
root = Path("package")
# followlinks: contents/quickshell/ui is a symlink to ../ui; the zip gets a real copy
files = sorted(Path(d, f) for d, _, fs in os.walk(root, followlinks=True) for f in fs)
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if "__pycache__" not in f.parts:
            z.write(f, f.relative_to(root))
PY
echo "built $out"
