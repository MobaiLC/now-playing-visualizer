#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Every test on a clean Arch Linux, as a fresh user would have it: helper
# and QML unit tests, translations, shell scripts, and the MPRIS integration
# tests with mpv + mpv-mpris and Plasma's own MPRIS module. Your checkout is
# mounted read-only and copied inside; nothing on your system is touched.
#
#   tools/test-in-docker.sh            (uses docker; sudo docker works too)
set -euo pipefail
cd "$(dirname "$0")/.."

# the same image CI uses for the QML tests, pinned by digest
image=archlinux:base@sha256:e82623936fa1a69700b48e98b058df6eaab18b737c27473a7234a40fdecb9413
docker=${DOCKER:-docker}

# the script below runs inside the container: its $variables are meant to
# expand there, not here
# shellcheck disable=SC2016
exec $docker run --rm -v "$PWD":/src:ro "$image" bash -euo pipefail -c '
pacman -Syu --noconfirm --needed >/dev/null \
    python python-gobject dbus systemd mpv mpv-mpris gettext shellcheck \
    qt6-declarative qt6-websockets plasma-workspace plasma5support
useradd -m tester
cp -r /src /home/tester/src
chown -R tester: /home/tester/src
cd /home/tester/src
su tester -c "
set -euo pipefail
export QT_QPA_PLATFORM=offscreen PYTHONDONTWRITEBYTECODE=1 XDG_RUNTIME_DIR=\$(mktemp -d)
echo ===== helper unit tests; python3 -m unittest discover -s tests
echo ===== QML unit tests; /usr/lib/qt6/bin/qmltestrunner -input tests/qml 2>&1 | grep -E \"^(SKIP|FAIL)|Totals\" -A1
echo ===== docs and translations; python3 tools/gen-config-doc.py --check
for po in translate/*.po; do msgfmt --check -o /dev/null \$po; done
echo ===== shell scripts; shellcheck tools/*.sh tests/integration/run.sh
echo ===== MPRIS integration; tests/integration/run.sh 2>&1 | grep -vE ^PASS
"
'
