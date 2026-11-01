#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
#
# MPRIS integration tests: fake players (and mpv with mpv-mpris, when both
# are installed) on a PRIVATE session bus, so your real players are never
# touched. Runs the helper tests, then the QML test with Plasma's MPRIS
# module when it is installed.
#
#   tests/integration/run.sh
#
# Needs: dbus-run-session, busctl (systemd), python3 with PyGObject.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ "${NPV_PRIVATE_BUS:-}" != 1 ]; then
    export NPV_PRIVATE_BUS=1
    exec dbus-run-session -- "$0" "$@"
fi

logs=$(mktemp -d)
export NPV_PLAYER_LOGS=$logs
pids=()
cleanup() {
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    rm -rf "$logs"
}
trap cleanup EXIT

start() {
    local name=$1; shift
    python3 tests/integration/fake_player.py "$name" "$@" >"$logs/$name.log" 2>&1 &
    pids+=($!)
}
start spotifake Spotifake --playing
start zenfake Zenfake --no-shuffle-loop
start lockedfake Lockedfake --no-control
for name in spotifake zenfake lockedfake; do
    for _ in $(seq 50); do grep -q READY "$logs/$name.log" 2>/dev/null && break; sleep 0.1; done
    grep -q READY "$logs/$name.log" || { echo "fake player $name did not start:"; cat "$logs/$name.log"; exit 1; }
done

mpris_so=""
for f in /usr/lib/mpv-mpris/mpris.so /etc/mpv/scripts/mpris.so /usr/lib/mpv/mpris.so; do
    [ -e "$f" ] && mpris_so=$f && break
done
if command -v mpv >/dev/null && [ -n "$mpris_so" ]; then
    python3 -I -c 'import wave; w = wave.open("'"$logs"'/silence.wav", "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000); w.writeframes(bytes(16000 * 30)); w.close()'
    mpv --no-config --script="$mpris_so" --ao=null --vo=null --idle=yes --pause --loop-file=inf \
        "$logs/silence.wav" >"$logs/mpv.log" 2>&1 &
    pids+=($!)
    for _ in $(seq 50); do busctl --user list | grep -q org.mpris.MediaPlayer2.mpv && break; sleep 0.1; done
    busctl --user list | grep -q org.mpris.MediaPlayer2.mpv && export NPV_MPV=1
fi
[ "${NPV_MPV:-}" = 1 ] && echo "mpv with mpv-mpris: running" || echo "mpv with mpv-mpris: not available, skipped"

python3 tests/integration/test_mpris.py

qmltestrunner=$(command -v qmltestrunner6 || command -v qmltestrunner || echo /usr/lib/qt6/bin/qmltestrunner)
QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} "$qmltestrunner" -input tests/integration
