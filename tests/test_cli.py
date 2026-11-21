# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for package/contents/code/cli.py (the `nowplaying-viz check` command)."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
CODE = ROOT / "package" / "contents" / "code"
TMP = tempfile.TemporaryDirectory()
if "helper" not in sys.modules:  # test_helper does the same; whoever imports first wins
    os.environ["XDG_CONFIG_HOME"] = TMP.name
sys.path.insert(0, str(CODE))
import cli  # noqa: E402  (imports helper; config paths are never used by check)


class CheckTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.file = Path(tmp.name) / "config.json"

    def run_check(self, user=None, text=None, hypr=None):
        if user is not None:
            self.file.write_text(json.dumps(user))
        if text is not None:
            self.file.write_text(text)
        out = (mock.Mock(stdout=json.dumps(hypr)) if hypr is not None else None)
        with mock.patch.object(cli.shutil, "which", return_value="/usr/bin/hyprctl" if out else None), \
                mock.patch.object(cli.subprocess, "run", return_value=out):
            return cli.check(self.file)

    def user(self, **kw):
        return {"version": cli.helper.CONFIG_VERSION, "preset": "lookas", "overrides": {}, **kw}

    def test_clean_config_passes(self):
        code, rep = self.run_check(cli.helper.default_user_config())
        self.assertEqual((code, rep["ok"], rep["issues"]), (0, True, []))

    def test_invalid_value_reports_value_and_used(self):
        code, rep = self.run_check(self.user(overrides={"bars": {"style": "wavy"}}))
        default = cli.helper.load_schema()["options"]["bars.style"]["default"]
        self.assertEqual(code, 1)
        self.assertEqual(rep["issues"], [{"code": "invalid_option", "option": "bars.style",
                                          "value": "wavy", "used": default}])

    def test_unknown_option_is_reported(self):
        code, rep = self.run_check(self.user(overrides={"bars": {"styel": "x"}}))
        self.assertEqual(code, 1)
        self.assertEqual([(i["code"], i["option"]) for i in rep["issues"]],
                         [("unknown_option", "bars.styel")])

    def test_wrong_section_types_are_reported(self):
        for name in ("overrides", "presets", "audio"):
            code, rep = self.run_check(self.user(**{name: [1]}))
            self.assertEqual(code, 1, name)
            self.assertEqual([(i["code"], i["option"]) for i in rep["issues"]],
                             [("invalid_option", name)])
        code, rep = self.run_check(self.user(presets={"mine": [1]}))
        self.assertEqual([(i["code"], i["option"]) for i in rep["issues"]],
                         [("invalid_option", "presets.mine")])

    def test_wrong_sections_without_version_do_not_crash(self):
        for user, option in (({"overrides": [1]}, "overrides"), ({"presets": [1]}, "presets"),
                             ({"presets": {"x": 5}}, "presets.x")):
            code, rep = self.run_check(user)
            self.assertEqual(code, 1, user)
            self.assertEqual([(i["code"], i["option"]) for i in rep["issues"]],
                             [("invalid_option", option)])

    def test_leaf_where_section_expected_is_one_issue(self):
        code, rep = self.run_check(self.user(overrides={"bars": 5}))
        self.assertEqual(code, 1)
        self.assertEqual([(i["code"], i["option"], i["value"]) for i in rep["issues"]],
                         [("invalid_option", "bars", 5)])

    def test_audio_is_not_unknown(self):
        code, _ = self.run_check(self.user(audio={"apps": ["x"]}))
        self.assertEqual(code, 0)

    def test_missing_preset(self):
        code, rep = self.run_check(self.user(preset="nope"))
        self.assertEqual(code, 1)
        self.assertEqual(rep["issues"][0]["code"], "preset_missing")

    def test_broken_json_gives_line(self):
        code, rep = self.run_check(text='{\n "a": ,\n}')
        self.assertEqual(code, 2)
        self.assertEqual((rep["issues"][0]["code"], rep["issues"][0]["line"]), ("config_parse", 2))

    def test_check_does_not_create_config(self):
        code, rep = self.run_check()
        self.assertEqual((code, rep["exists"], self.file.exists()), (0, False, False))

    def test_unknown_monitor(self):
        user = self.user(overrides={"desktop": {"monitor": "HDMI-A-9"}})
        code, rep = self.run_check(user, hypr=[{"name": "DP-1"}])
        self.assertEqual((code, rep["issues"][0]["code"]), (1, "unknown_monitor"))
        self.assertEqual(self.run_check(user)[0], 0)  # no hyprctl, no issue

    def test_main_json_and_exit_code(self):
        self.file.write_text(json.dumps(self.user(overrides={"bars": {"style": "wavy"}})))
        with mock.patch.object(cli.helper, "CONFIG_FILE", self.file), \
                mock.patch("sys.stdout") as out:
            rc = cli.main(["check"])
        self.assertEqual(rc, 1)
        self.assertIn('✗ bars.style: "wavy" is not valid, using', "".join(c.args[0] for c in out.write.call_args_list))


if __name__ == "__main__":
    unittest.main()
