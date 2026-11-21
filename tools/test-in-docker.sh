#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Every test on a clean Arch Linux, as a fresh user would have it: helper
# and QML unit tests, translations, shell scripts, the MPRIS integration
# tests with mpv + mpv-mpris and Plasma's own MPRIS module, then both AUR
# packages built with makepkg (the -git one installed and checked, namcap on
# both). Your checkout is mounted read-only and copied inside, uncommitted
# changes included; nothing on your system is touched.
#
#   tools/test-in-docker.sh            (uses docker; sudo docker works too)
set -euo pipefail
cd "$(dirname "$0")/.."

# the same image CI uses for the QML tests, pinned by digest
image=archlinux:base@sha256:e82623936fa1a69700b48e98b058df6eaab18b737c27473a7234a40fdecb9413
docker=${DOCKER:-docker}

# the script below runs inside the container, as root
exec $docker run --rm -i -v "$PWD":/src:ro "$image" bash -euo pipefail -s <<'EOF'
# what the package must provide (AGENTS.md and the READMEs point here)
required_paths=(
    /usr/bin/nowplaying-viz
    /usr/share/now-playing-visualizer/quickshell/shell.qml
    /usr/share/now-playing-visualizer/quickshell/ui/Card.qml
    /usr/share/now-playing-visualizer/skill/SKILL.md
    /usr/share/doc/now-playing-visualizer/README.md
    /usr/share/doc/now-playing-visualizer/AGENTS.md
    /usr/share/doc/now-playing-visualizer/CONFIG.md
    /usr/lib/systemd/user/nowplaying-viz.service
    /usr/share/applications/now-playing-visualizer-settings.desktop
)

as_tester() {  # run one of the functions below as the unprivileged user
    runuser -u tester -- bash -euo pipefail -c "$(declare -p required_paths; declare -f "$1"); cd ~/src; $1"
}

setup() {
    pacman -Syu --noconfirm --needed >/dev/null \
        python python-gobject dbus systemd mpv mpv-mpris gettext shellcheck \
        qt6-declarative qt6-websockets plasma-workspace plasma5support \
        base-devel namcap git desktop-file-utils
    # the image skips docs on install, ours must be checked
    sed -i 's|usr/share/doc/\*||' /etc/pacman.conf
    useradd -m tester
    # makepkg -si calls sudo pacman; this container only
    echo 'tester ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/tester
    cp -r /src /home/tester/src
    chown -R tester: /home/tester/src
}

unit_tests() {
    XDG_RUNTIME_DIR=$(mktemp -d)
    export QT_QPA_PLATFORM=offscreen PYTHONDONTWRITEBYTECODE=1 XDG_RUNTIME_DIR
    echo ===== helper unit tests; python3 -m unittest discover -s tests
    echo ===== QML unit tests; /usr/lib/qt6/bin/qmltestrunner -input tests/qml 2>&1 | grep -E "^(SKIP|FAIL)|Totals" -A1
    echo ===== docs and translations; python3 tools/gen-config-doc.py --check
    for po in translate/*.po; do msgfmt --check -o /dev/null "$po"; done
    echo ===== launcher entry; desktop-file-validate packaging/now-playing-visualizer-settings.desktop
    echo ===== shell scripts; shellcheck tools/*.sh tools/nowplaying-viz packaging/install.sh tests/integration/run.sh
    echo ===== MPRIS integration; tests/integration/run.sh 2>&1 | grep -vE ^PASS
}

srcinfo_up_to_date() {
    echo ===== .SRCINFO
    local d
    for d in packaging/aur/*/; do
        (cd "$d" && makepkg --printsrcinfo | diff -u .SRCINFO -) || { echo "stale $d.SRCINFO"; return 1; }
    done
}

snapshot() {  # the packages build from git: commit the checkout as it is
    git add -A
    git -c user.name=test -c user.email=test@localhost commit -qm snapshot --allow-empty
}

build_git() {
    echo ===== build and install now-playing-visualizer-git
    cp -r packaging/aur/now-playing-visualizer-git ~/build-git
    cd ~/build-git || return
    # GitHub does not have this checkout: build from the local copy instead
    # shellcheck disable=SC2016  # $_pkgname is for the PKGBUILD
    sed -i 's|^source=.*|source=("$_pkgname::git+file:///home/tester/src")|' PKGBUILD
    makepkg -si --noconfirm
}

build_release() {
    echo ===== build now-playing-visualizer from a tarball of the checkout
    cp -r packaging/aur/now-playing-visualizer ~/build-release
    cd ~/build-release || return
    # makepkg uses a source file already in place instead of downloading it,
    # this one stands in for GitHub's tag tarball
    # shellcheck source=/dev/null disable=SC2154  # pkgname, pkgver come from the PKGBUILD
    (. ./PKGBUILD && git -C ~/src archive --prefix="$pkgname-$pkgver/" -o ~/build-release/"$pkgname-$pkgver.tar.gz" HEAD)
    makepkg --noconfirm --skipchecksums # the PKGBUILD checksum is for the real v0.4.0 tarball; this one is `git archive HEAD`, so the release checksum is deliberately not tested here
}

verify_installed() {
    echo ===== installed package
    local p
    for p in "${required_paths[@]}"; do test -e "$p" || { echo "missing $p"; return 1; }; done
    nowplaying-viz --help
    nowplaying-viz check
}

lint_packages() {
    echo ===== namcap
    local f out
    for f in ~tester/build-*/PKGBUILD ~tester/build-*/*.pkg.tar.zst; do
        out=$(namcap "$f")
        echo "$f:${out:+$'\n'}$out"
        if grep -q ' E: ' <<<"$out"; then return 1; fi
    done
}

setup
as_tester unit_tests
as_tester srcinfo_up_to_date
as_tester snapshot
as_tester build_git
as_tester build_release
as_tester verify_installed
lint_packages
echo ===== all passed
EOF
