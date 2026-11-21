#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""nowplaying-viz: command line for Now Playing Visualizer.

  nowplaying-viz check [--json]             validate ~/.config/nowplaying-viz/config.json
  nowplaying-viz settings                   open the settings window
  nowplaying-viz doctor [--json] [--notify] diagnose programs, QML modules, the helper,
                                            players, per-app links and whether CAVA hears sound

Both only read: check never creates or rewrites the config file, and doctor
never subscribes to bars (so it cannot start CAVA or make links).
check exit codes: 0 clean (or no file yet), 1 issues, 2 the file is not valid JSON.
doctor exit codes: 0 nothing failed, 1 something failed, 2 doctor itself crashed.
doctor --notify runs after every pacman transaction (nowplaying-viz-check.service)
and sends one desktop notification only when the install is broken (programs,
QML modules, config, the service or the helper; not players, links or sound).
"""

import copy
import gettext
import http.client
import json
import os
import shutil
import subprocess
import sys
import tempfile
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
DOMAIN = "plasma_applet_com.github.mobailc.nowplayingvisualizer"
_ = gettext.translation(DOMAIN, HERE.parent / "locale", fallback=True).gettext
sys.path.insert(0, str(HERE))  # runs under python3 -I: no script folder on sys.path
try:
    import helper
    HELPER_ERROR = None
except Exception as e:  # a half-finished update; run() reports it
    helper, HELPER_ERROR = None, e
QML = shutil.which("qml6") or "/usr/lib/qt6/bin/qml"

# what --notify reports; players, links and audio depend on the moment, not the install
INTEGRITY = ("commands", "cava_version", "qml_modules", "config", "service", "helper")
HYPR_START = "exec-once = systemctl --user start nowplaying-viz"

# module -> (what breaks, has a fallback?, host that needs it: "all", "plasma" or "quickshell")
QML_MODULES = {
    "QtQuick": (_("the whole widget"), False, "all"),
    "QtQuick.Layouts": (_("the whole widget"), False, "all"),
    "QtQuick.Effects": (_("rounded cover art and glow"), False, "all"),
    "QtWebSockets": (_("connection to the helper (no bars)"), False, "all"),
    "org.kde.plasma.plasmoid": (_("the whole widget"), False, "plasma"),
    "org.kde.plasma.core": (_("the whole widget"), False, "plasma"),
    # Card.qml, shared with the quickshell card, imports Kirigami
    "org.kde.kirigami": (_("the whole widget"), False, "all"),
    "org.kde.kcmutils": (_("settings pages"), False, "plasma"),
    "QtQuick.Dialogs": (_("color picker in Design"), False, "plasma"),
    # the card falls back to D-Bus without it; Hyprland rarely has plasma-workspace
    "org.kde.plasma.private.mpris": (_("reading the song (D-Bus is used instead)"), True, "plasma"),
    "org.kde.plasma.plasma5support": (_("starting the helper from the widget (systemd starts it)"), True, "plasma"),
    "Quickshell": (_("the whole desktop card"), False, "quickshell"),
    "Quickshell.Wayland": (_("the whole desktop card"), False, "quickshell"),
}

COMMANDS = {
    "cava": _("audio bars"),
    "pw-dump": _("list of audio apps"),
    "pw-link": _("per-app audio"),
    "busctl": _("reading the song over D-Bus"),
    "wpctl": _("volume for players without MPRIS volume"),
}


def issue(code, option, value=None, used=None, **extra):
    return {"code": code, "option": option, "value": value, "used": used, **extra}


def hypr_monitors():
    """Monitor names from hyprctl, or None when it is missing or does not answer."""
    if not shutil.which("hyprctl"):
        return None
    try:
        r = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=5)
        return [m["name"] for m in json.loads(r.stdout)]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return None


def check(config_file):
    report = {"ok": True, "config": str(config_file), "exists": config_file.exists(), "issues": []}
    if not report["exists"]:
        return 0, report
    try:
        user = json.loads(config_file.read_text())
    except OSError as e:
        report.update(ok=False, issues=[issue("config_unreadable", "", str(e))])
        return 2, report
    except json.JSONDecodeError as e:
        report.update(ok=False, issues=[issue("config_parse", "", e.msg, line=e.lineno, column=e.colno)])
        return 2, report
    if not isinstance(user, dict):
        report.update(ok=False, issues=[issue("config_parse", "", "not a JSON object", line=1, column=1)])
        return 2, report
    helper.migrate(user)  # on our copy only
    schema = helper.load_schema()
    issues = report["issues"]
    # Drop structurally wrong sections (reported once) so the merge cannot crash or flood.
    for name in ("overrides", "presets", "audio"):
        if name in user and not isinstance(user[name], dict):
            issues.append(issue("invalid_option", name, user[name], {}))
            user[name] = {}
    for n in [n for n, p in user.get("presets", {}).items() if not isinstance(p, dict)]:
        issues.append(issue("invalid_option", f"presets.{n}", user["presets"].pop(n), {}))
    for name, sec in [("overrides", user.get("overrides", {}))] + \
            [(f"presets.{n}", p) for n, p in user.get("presets", {}).items()]:
        for k in [k for k, v in sec.items() if not isinstance(v, dict)
                  and any(o.startswith(k + ".") for o in schema["options"])]:
            issues.append(issue("invalid_option", k if name == "overrides" else f"{name}.{k}", sec.pop(k), {}))
    eff, found = helper.resolve_config(user, schema, helper.load_builtin_presets())
    for i in found:
        if i["code"] == "preset_missing":
            issues.append(issue("preset_missing", "preset", i["detail"], "lookas"))
        else:
            issues.append(issue(i["code"], i["detail"], i["value"], i["used"]))
    sections = {"overrides": user.get("overrides", {})}
    sections.update({f"presets.{n}": p for n, p in user.get("presets", {}).items()})
    for prefix, sec in sections.items():
        for path in helper.leaves(sec):
            if path not in schema["options"]:
                shown = path if prefix == "overrides" else f"{prefix}.{path}"
                issues.append(issue("unknown_option", shown, helper.get_path(sec, path)))
    monitor = helper.get_path(eff, "desktop.monitor")
    names = hypr_monitors() if monitor else None
    if names is not None and monitor not in names:
        issues.append(issue("unknown_monitor", "desktop.monitor", monitor, ""))
    report["ok"] = not issues
    return (0 if report["ok"] else 1), report


def describe(i):
    opt, val, used = i["option"], json.dumps(i["value"], ensure_ascii=False), json.dumps(i["used"], ensure_ascii=False)
    code = i["code"]
    if code == "config_unreadable":
        return _("config.json could not be read: {value}").format(**i)
    if code == "config_parse":
        return _("config.json is not valid JSON (line {line}, column {column}): {value}").format(**i)
    if code == "preset_missing":
        return _('preset {value} does not exist, using {used}').format(value=val, used=used)
    if code == "unknown_option":
        return _("{option}: not an option, ignored").format(option=opt)
    if code == "unknown_monitor":
        return _("{option}: {value} is not a connected monitor, using the first one").format(option=opt, value=val)
    if code == "out_of_range":
        return _("{option}: {value} is out of range, using {used}").format(option=opt, value=val, used=used)
    return _("{option}: {value} is not valid, using {used}").format(option=opt, value=val, used=used)


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


def detect_host():
    if "KDE" in os.environ.get("XDG_CURRENT_DESKTOP", ""):
        return "plasma"
    try:
        if subprocess.run(["pgrep", "-x", "-u", str(os.getuid()), "plasmashell"],
                          capture_output=True).returncode == 0:
            return "plasma"
    except OSError:
        pass
    return "quickshell" if shutil.which("quickshell") else "none"


def fetch_status():
    """The helper's /status. OSError when nothing listens, ValueError for an answer that is not it."""
    conn = http.client.HTTPConnection("127.0.0.1", helper.PORT, timeout=3)  # sends Host: 127.0.0.1:<port>
    try:
        conn.request("GET", "/status")
        r = conn.getresponse()
        body = r.read()
    except http.client.HTTPException as e:
        raise ValueError(str(e)) from e
    finally:
        conn.close()
    if r.status != 200:
        raise ValueError(f"HTTP {r.status}")
    status = json.loads(body)  # JSONDecodeError is a ValueError
    if not isinstance(status, dict):
        raise ValueError("not a status object")
    return status


def list_players():
    return [{"identity": helper.busctl_prop(n, "org.mpris.MediaPlayer2", "Identity", n.split(".")[-1]),
             "playing": helper.busctl_prop(n, "org.mpris.MediaPlayer2.Player", "PlaybackStatus", "") == "Playing"}
            for n in helper.mpris_names()]


def effective_config():
    """The config the helper would use, read-only; defaults when the file is broken,
    {} when schema.json or a preset is (the config check reports both)."""
    try:
        user = helper.read_user()
    except helper.ConfigUnreadable:
        user = helper.default_user_config()
    for u in (user, helper.default_user_config()):
        try:
            u = copy.deepcopy(u)
            helper.migrate(u)
            return helper.resolve_config(u, helper.load_schema(), helper.load_builtin_presets())[0]
        except (OSError, AttributeError, KeyError, TypeError, ValueError):
            pass
    return {}


def links_check():
    """Per-app audio: is a stream of the followed player (or a selected app) linked into
    CAVA's capture stream? Same matching as helper.sync_links; any channel linked into
    CAVA counts (a stereo stream into a MONO input is how channels=mono works)."""
    if not helper.per_app_audio():
        return "skip", _("all system audio is captured (no per-app links needed)"), ""
    nodes, ports, links = {}, {}, set()
    for o in helper.pw_dump():
        t, info = o.get("type"), o.get("info") or {}
        p = info.get("props") or {}
        if t == "PipeWire:Interface:Node":
            nodes[o["id"]] = p
        elif t == "PipeWire:Interface:Port":
            ports[o["id"]] = (info.get("direction"), p)
        elif t == "PipeWire:Interface:Link":
            links.add((info.get("output-port-id"), info.get("input-port-id")))
    capture = {i for i, p in nodes.items() if p.get("target.object") == helper.CAPTURE_TARGET}
    if not capture:
        return "skip", _("CAVA is not capturing (no card or widget is running)"), ""
    wanted = helper.link_filter()
    cava_in = {i: p.get("audio.channel") for i, (d, p) in ports.items() if d == "input" and p.get("node.id") in capture}
    outs = {i: p.get("audio.channel") for i, (d, p) in ports.items() if d == "output"
            and nodes.get(p.get("node.id"), {}).get("media.class") == "Stream/Output/Audio"
            and wanted(nodes[p["node.id"]])}
    if not outs:
        return "skip", _("the followed player or selected apps have no audio stream right now"), ""
    linked = {o for o, i in links if o in outs and i in cava_in}
    if linked:
        return "ok", _("{n} channel(s) linked into CAVA").format(n=len(linked)), ""
    return ("fail", _("not linked into CAVA: stream channels {out}, CAVA input channels {inp}").format(
        out=",".join(sorted({str(c) for c in outs.values()})), inp=",".join(sorted({str(c) for c in cava_in.values()}))),
        "systemctl --user restart nowplaying-viz")


def doctor(notify):
    host = detect_host()
    checks = []
    # Hyprland without uwsm never reaches graphical-session.target, where the service is wanted
    hypr = "; " + _("without uwsm, also add to hyprland.conf: {line}").format(line=HYPR_START) \
        if host == "quickshell" else ""

    def add(id_, status, message, hint=""):
        checks.append({"id": id_, "status": status, "message": message, "hint": hint})

    missing = [c for c in COMMANDS if not shutil.which(c)]
    if missing:
        add("commands", "fail", "; ".join(_("Missing «{cmd}» → {what}").format(cmd=c, what=COMMANDS[c]) for c in missing),
            _("install the missing programs"))
    else:
        add("commands", "ok", _("all programs found: {list}").format(list=", ".join(COMMANDS)))

    if "cava" in missing:
        add("cava_version", "skip", _("cava is not installed"))
    else:
        try:
            r = subprocess.run(["cava", "-v"], capture_output=True, text=True, timeout=5)
            version = (r.stdout + r.stderr).strip().splitlines()[0] if r.returncode == 0 else ""
        except (OSError, subprocess.SubprocessError, IndexError):
            version = ""
        if version:
            add("cava_version", "ok", version)
        else:
            add("cava_version", "warn", _("could not read the cava version"), "cava -v")

    if not os.path.exists(QML):
        add("qml_modules", "warn", _("Qt 6 «qml» tool not found; QML modules could not be checked"),
            _("install qt6-declarative"))
    else:
        broken, degraded = [], []
        for module, (what, has_fallback, need) in QML_MODULES.items():
            if need in ("all", host) and check_qml(module):
                (degraded if has_fallback else broken).append(
                    _("QML module {module} → {what}").format(module=module, what=what))
        if broken:
            add("qml_modules", "fail", "; ".join(broken + degraded), _("install the packages that provide them"))
        elif degraded:
            add("qml_modules", "warn", "; ".join(degraded))
        else:
            add("qml_modules", "ok", _("QML modules for {host} found").format(host=host))

    try:  # a broken update: schema.json or a preset that does not parse (helper.py compiled, it is imported)
        if not isinstance(helper.load_schema().get("options"), dict) or not helper.load_builtin_presets():
            raise ValueError("schema.json has no options or there are no presets")
        code, rep = check(helper.CONFIG_FILE)
    except (OSError, AttributeError, KeyError, TypeError, ValueError) as e:
        code, rep = None, str(e)
    if code is None:
        add("config", "fail", _("schema.json or a preset is broken: {error}").format(error=rep),
            _("reinstall Now Playing Visualizer"))
    elif code == 0:
        add("config", "ok", _("config OK") if rep["exists"] else _("no config file yet, defaults are used"))
    elif code == 1:
        add("config", "warn", _("{n} config issue(s), defaults are used for them").format(n=len(rep["issues"])),
            "nowplaying-viz check")
    else:
        add("config", "fail", describe(rep["issues"][0]), "nowplaying-viz check")

    try:
        active = subprocess.run(["systemctl", "--user", "is-active", "nowplaying-viz"],
                                capture_output=True, text=True).stdout.strip() == "active"
    except OSError:
        active = False
    if active:
        add("service", "ok", _("the nowplaying-viz service is running"))
    elif host == "quickshell":
        add("service", "fail", _("the nowplaying-viz service is not running"),
            "systemctl --user enable --now nowplaying-viz" + hypr)
    else:
        add("service", "warn", _("the nowplaying-viz service is not running (the widget starts the helper itself)"),
            "systemctl --user enable --now nowplaying-viz")

    try:
        status = fetch_status()
    except OSError:
        status = None
        add("helper", "fail", _("the helper is not running (nothing on port {port})").format(port=helper.PORT),
            "systemctl --user start nowplaying-viz" + hypr)
    except ValueError as e:
        status = None
        add("helper", "fail", _("port {port} does not answer like the helper: {error}").format(
            port=helper.PORT, error=e), "systemctl --user restart nowplaying-viz")
    if status is not None:
        got = status.get("protocol")
        if got == helper.PROTOCOL:
            add("helper", "ok", _("helper answers on port {port}").format(port=helper.PORT))
        else:
            newer = isinstance(got, int) and got > helper.PROTOCOL
            add("helper", "fail", (_("a newer helper (protocol {got}, this widget needs {want}) is running on port {port}")
                                   if newer else
                                   _("an outdated helper (protocol {got}, this widget needs {want}) is running on port {port}")
                                   ).format(got=json.dumps(got), want=helper.PROTOCOL, port=helper.PORT),
                "systemctl --user restart nowplaying-viz")
            status = None

    helper.state["config"] = effective_config()  # this process only: what per-app audio follows
    helper.forget_followed_player()
    players = list_players() if "busctl" not in missing else []
    if not players:
        add("players", "skip", _("no MPRIS player is running"))
    else:
        followed = helper.followed_player()
        add("players", "ok", _("players: {list}; shown: {followed}").format(
            list=", ".join(p["identity"] + (" ▶" if p["playing"] else "") for p in players),
            followed=followed[1] if followed else "-"))

    if "pw-dump" in missing or "busctl" in missing:  # busctl: following the player asks D-Bus
        add("links", "skip", _("pw-dump or busctl is not installed"))
    else:
        add("links", *links_check())

    cava = (status or {}).get("cava")
    cava = cava if isinstance(cava, dict) else {}
    peak, age = cava.get("peak"), cava.get("age")
    number = (int, float)
    peak = peak if isinstance(peak, number) and not isinstance(peak, bool) else 0
    age = age if isinstance(age, number) and not isinstance(age, bool) else 99
    if status is None:
        add("audio", "skip", _("not checked: the helper is not reachable"),
            _("start the helper, then run nowplaying-viz doctor again"))
    elif not status.get("barClients"):
        add("audio", "skip", _("not checked: no card or widget is running"),
            _("open the card or widget, then run nowplaying-viz doctor again"))
    elif not cava.get("running"):
        add("audio", "fail", _("CAVA is not running"), "journalctl --user -u nowplaying-viz")
    elif peak > 0 and age < 2:
        add("audio", "ok", _("CAVA hears sound"))
    elif any(p["playing"] for p in players):
        add("audio", "fail", _("CAVA hears silence"),
            _("see the links check") if helper.per_app_audio() else "wpctl status")
    else:
        add("audio", "skip", _("nothing is playing"))

    statuses = [c["status"] for c in checks]
    bad = [c for c in checks if c["id"] in INTEGRITY and c["status"] in ("fail", "warn")]
    if notify and bad:
        failed = any(c["status"] == "fail" for c in bad)
        title = _("Now Playing Visualizer: something broke") if failed else _("Now Playing Visualizer: compatibility mode")
        send_notification(title, "\n".join(c["message"] for c in bad), failed)
    ok = "fail" not in statuses
    return (0 if ok else 1), {"ok": ok, "host": host, "checks": checks}


def send_notification(title, body, critical):
    if shutil.which("notify-send"):
        body += "\n\n" + _("Details:") + " nowplaying-viz doctor"
        subprocess.run(["notify-send", "-a", "Now Playing Visualizer", "-i", "view-media-visualization",
                        "-u", "critical" if critical else "normal", title, body])


QT6_QML = "/usr/lib/qt6/qml"


def qml_runtime():
    # a bare "qml" may be Qt 5, so the Qt 6 path comes first
    return shutil.which("qml6") or (
        "/usr/lib/qt6/bin/qml" if os.path.exists("/usr/lib/qt6/bin/qml") else None) or shutil.which("qml")


def settings_env(env):
    env = dict(env)
    env.setdefault("QT_QUICK_CONTROLS_STYLE",
                   "org.kde.desktop" if os.path.isdir(f"{QT6_QML}/org/kde/desktop") else "Fusion")
    return env


def settings_main():
    runtime = qml_runtime()
    if not runtime:
        print("No Qt QML runtime found (install qt6-declarative).", file=sys.stderr)
        return 1
    # after "--" the window reads --port itself (NPV_PORT reaches it)
    try:
        os.execvpe(runtime, [runtime, str(HERE.parent / "settings" / "settings.qml"),
                             "--", "--port", str(helper.PORT)], settings_env(os.environ))
    except OSError as e:
        print(f"Can't run {runtime}: {e} (install qt6-declarative).", file=sys.stderr)
        return 1


MARKS = {"ok": "✓", "warn": "!", "fail": "✗", "skip": "-"}


def main(argv):
    args = list(argv)
    as_json = "--json" in args
    args = [a for a in args if a != "--json"]
    if args == ["check"]:
        code, report = check(helper.CONFIG_FILE)
        if as_json:
            print(json.dumps(report, indent=2, ensure_ascii=False))
        else:
            for i in report["issues"]:
                print("✗ " + describe(i))
            if report["ok"]:
                print(_("config OK") if report["exists"] else _("no config file yet, defaults are used"))
        return code
    if args in (["doctor"], ["doctor", "--notify"]):
        code, report = doctor("--notify" in args)
        if as_json:
            print(json.dumps(report, indent=2, ensure_ascii=False))
        else:
            for c in report["checks"]:
                print(f"{MARKS[c['status']]} {c['message']}")
                if c["hint"]:
                    print(f"  → {c['hint']}")
        return code
    if args == ["settings"]:
        return settings_main()
    print(_("usage: nowplaying-viz check [--json] | doctor [--json] [--notify] | settings"), file=sys.stderr)
    return 2


def run(argv):
    """main() that never dies silently: a crash under --notify still reaches the desktop."""
    try:
        if HELPER_ERROR:
            raise HELPER_ERROR
        return main(argv)
    except Exception as e:
        traceback.print_exc()
        if "--notify" in argv:
            send_notification(_("Now Playing Visualizer: something broke"),
                              _("nowplaying-viz doctor crashed: {error}").format(error=f"{type(e).__name__}: {e}"), True)
        return 2


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
