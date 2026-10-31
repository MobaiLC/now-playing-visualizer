#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Compiles translate/<lang>.po into the package's locale folder (.mo files are
# build output and are not committed).
set -euo pipefail
cd "$(dirname "$0")/.."

DOMAIN="plasma_applet_com.github.mobailc.nowplayingvisualizer"
for po in translate/*.po; do
    lang=$(basename "$po" .po)
    out="package/contents/locale/$lang/LC_MESSAGES"
    mkdir -p "$out"
    msgfmt --check -o "$out/$DOMAIN.mo" "$po"
    echo "built $lang"
done
