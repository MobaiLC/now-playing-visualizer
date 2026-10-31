#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Self-check for Now Playing Visualizer.

Runs automatically after every pacman transaction (systemd path unit) and can
be run by hand:  python3 <plasmoid folder>/contents/code/check.py
(~/.local/share/plasma/plasmoids/com.github.mobailc.nowplayingvisualizer when
installed with tools/install.sh, /usr/share/plasma/plasmoids/... from a package)

It verifies the programs and QML modules the widget relies on and sends a
desktop notification only when something is wrong.
"""

import gettext
import json
import py_compile
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
DOMAIN = "plasma_applet_com.github.mobailc.nowplayingvisualizer"
_ = gettext.translation(DOMAIN, HERE.parent / "locale", fallback=True).gettext
QML = shutil.which("qml6") or "/usr/lib/qt6/bin/qml"

# module -> (what breaks, has a fallback?)
QML_MODULES = {
    "QtQuick": (_("the whole widget"), False),
    "QtQuick.Layouts": (_("the whole widget"), False),
    "QtQuick.Effects": (_("rounded cover art and glow"), False),
    "QtWebSockets": (_("connection to the helper (no bars)"), False),
    "org.kde.plasma.plasmoid": (_("the whole widget"), False),
    "org.kde.plasma.core": (_("the whole widget"), False),
    "org.kde.kirigami": (_("the whole widget"), False),
    "org.kde.kcmutils": (_("settings pages"), False),
    "QtQuick.Dialogs": (_("color picker in Design"), False),
    "org.kde.plasma.private.mpris": (_("reading the song (D-Bus is used instead)"), True),
    "org.kde.plasma.plasma5support": (_("starting the helper from the widget (systemd starts it)"), True),
}

COMMANDS = {
    "cava": _("audio bars"),
    "pw-dump": _("list of audio apps"),
    "pw-link": _("per-app audio"),
    "busctl": _("reading the song over D-Bus"),
}


def check_qml(module):
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp) / "t.qml"
        f.write_text(f"import QtQuick\nimport {module}\nItem {{ Component.onCompleted: Qt.quit() }}\n")
        try:
            r = subprocess.run([QML, "-platform", "offscreen", str(f)],
                               capture_output=True, text=True, timeout=20)
        except (OSError, subprocess.TimeoutExpired) as e:
            return str(e)
        out = (r.stdout + r.stderr).strip()
        if r.returncode != 0 or "is not installed" in out or "module" in out.lower() and "error" in out.lower():
            return out.splitlines()[-1] if out else f"exit code {r.returncode}"
    return None


def main():
    broken, degraded = [], []

    for cmd, what in COMMANDS.items():
        if not shutil.which(cmd):
            broken.append(_("Missing «{cmd}» → {what}").format(cmd=cmd, what=what))

    try:
        py_compile.compile(str(HERE / "helper.py"), doraise=True)
        json.loads((HERE / "schema.json").read_text())
        for preset in (HERE / "presets").glob("*.json"):
            json.loads(preset.read_text())
    except Exception as e:
        broken.append(f"helper.py/schema.json/presets: {e}")

    if not Path(QML).exists():
        degraded.append(_("Qt 6 «qml» tool not found; QML modules could not be checked"))
    else:
        for module, (what, has_fallback) in QML_MODULES.items():
            err = check_qml(module)
            if err:
                (degraded if has_fallback else broken).append(_("QML module {module} → {what}").format(module=module, what=what))

    r = subprocess.run(["systemctl", "--user", "is-active", "nowplaying-viz.service"],
                       capture_output=True, text=True)
    if r.stdout.strip() != "active":
        degraded.append(_("The nowplaying-viz service is not running (systemctl --user status nowplaying-viz)"))

    for line in broken:
        print("ERROR  ", line)
    for line in degraded:
        print("AVISO  ", line)
    if not broken and not degraded:
        print(_("OK: everything the widget uses is still available."))

    if (broken or degraded) and "--notify" in sys.argv and shutil.which("notify-send"):
        title = _("Now Playing Visualizer: something broke") if broken else _("Now Playing Visualizer: compatibility mode")
        body = "\n".join(broken + degraded)
        # where this copy lives: ~/.local/share/... or /usr/share/... (AUR package)
        body += "\n\n" + _("Details:") + f" python3 {Path(__file__).resolve()}"
        subprocess.run(["notify-send", "-a", "Now Playing Visualizer", "-i", "view-media-visualization",
                        "-u", "critical" if broken else "normal", title, body])
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
