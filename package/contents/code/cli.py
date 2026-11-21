#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""nowplaying-viz: command line for Now Playing Visualizer.

  nowplaying-viz check [--json]    validate ~/.config/nowplaying-viz/config.json

check only reads: it never creates or rewrites the config file.
Exit codes: 0 clean (or no file yet), 1 issues, 2 the file is not valid JSON.
"""

import gettext
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # runs under python3 -I: no script folder on sys.path
import helper  # noqa: E402

DOMAIN = "plasma_applet_com.github.mobailc.nowplayingvisualizer"
_ = gettext.translation(DOMAIN, HERE.parent / "locale", fallback=True).gettext


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
        report.update(ok=False, issues=[issue("config_parse", "", str(e), line=None, column=None)])
        return 2, report
    except json.JSONDecodeError as e:
        report.update(ok=False, issues=[issue("config_parse", "", e.msg, line=e.lineno, column=e.colno)])
        return 2, report
    if not isinstance(user, dict):
        report.update(ok=False, issues=[issue("config_parse", "", "not a JSON object", line=1, column=1)])
        return 2, report
    helper.migrate(user)  # on our copy only
    schema = helper.load_schema()
    eff, found = helper.resolve_config(user, schema, helper.load_builtin_presets())
    issues = report["issues"]
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
    if args == ["doctor"]:
        print(_("doctor is not available yet"), file=sys.stderr)
        return 2
    print(_("usage: nowplaying-viz check|doctor [--json]"), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
