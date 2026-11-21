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


STEREO_DUMP = [  # a playing stereo stream and CAVA's capture stream with a MONO input, no links
    {"id": 50, "type": "PipeWire:Interface:Node", "info": {"props": {
        "media.class": "Stream/Output/Audio", "application.name": "Spotify", "application.process.id": 77}}},
    {"id": 51, "type": "PipeWire:Interface:Port", "info": {"direction": "output", "props": {"node.id": 50, "audio.channel": "FL"}}},
    {"id": 52, "type": "PipeWire:Interface:Port", "info": {"direction": "output", "props": {"node.id": 50, "audio.channel": "FR"}}},
    {"id": 60, "type": "PipeWire:Interface:Node", "info": {"props": {
        "media.class": "Stream/Input/Audio", "target.object": cli.helper.CAPTURE_TARGET}}},
    {"id": 61, "type": "PipeWire:Interface:Port", "info": {"direction": "input", "props": {"node.id": 60, "audio.channel": "MONO"}}},
]
PLASMA_ONLY = {m for m, (_w, _f, hosts) in cli.QML_MODULES.items() if hosts == "plasma"}


class DoctorTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.file = Path(tmp.name) / "config.json"
        # doctor sets the effective config in helper.state for per-app audio
        self.addCleanup(cli.helper.state.__setitem__, "config", cli.helper.state["config"])
        self.missing_qml = set()
        self.calls = []
        self.status = {"protocol": cli.helper.PROTOCOL, "service": True, "clients": 1, "barClients": 1,
                       "cava": {"running": True, "peak": 40, "age": 0.1}}
        self.players = [{"identity": "Spotify", "playing": True}]
        self.dump = []

    def fake_run(self, cmd, **kw):
        self.calls.append(cmd)
        if cmd[0] == "systemctl":
            return mock.Mock(stdout="active\n", stderr="", returncode=0)
        if cmd[0] == "cava":
            return mock.Mock(stdout="cava 1.0.0\n", stderr="", returncode=0)
        if cmd[0] == cli.QML:
            src = Path(cmd[-1]).read_text()
            if any(f"import {m}\n" in src for m in self.missing_qml):
                return mock.Mock(stdout="", stderr='module "x" is not installed', returncode=1)
        return mock.Mock(stdout="", stderr="", returncode=0)

    def fetch(self):
        if isinstance(self.status, Exception):
            raise self.status
        return self.status

    def run_doctor(self, host="plasma", notify=False, user=None, doctor=cli.doctor):
        if user is not None:
            self.file.write_text(json.dumps(user))
        with mock.patch.object(cli, "detect_host", return_value=host), \
                mock.patch.object(cli, "QML", sys.executable), \
                mock.patch.object(cli.shutil, "which", side_effect=lambda c: "/usr/bin/" + c), \
                mock.patch.object(cli.subprocess, "run", side_effect=self.fake_run), \
                mock.patch.object(cli, "fetch_status", side_effect=self.fetch), \
                mock.patch.object(cli, "list_players", side_effect=lambda: self.players), \
                mock.patch.object(cli.helper, "active_player",
                                  side_effect=lambda: (77, "spotify") if self.players else None), \
                mock.patch.object(cli.helper, "pw_dump", side_effect=lambda: self.dump), \
                mock.patch.object(cli.helper, "CONFIG_FILE", self.file):
            return doctor(notify)

    def by_id(self, rep):
        return {c["id"]: c for c in rep["checks"]}

    def notified(self):
        return [c for c in self.calls if c[0] == "notify-send"]

    def test_all_good(self):
        code, rep = self.run_doctor()
        self.assertEqual(code, 0, rep)
        self.assertTrue(all(c["status"] in ("ok", "skip") for c in rep["checks"]), rep)

    def test_doctor_helper_down(self):
        self.status = ConnectionRefusedError(111, "Connection refused")
        code, rep = self.run_doctor()
        helper_check = self.by_id(rep)["helper"]
        self.assertEqual((code, rep["ok"], helper_check["status"]), (1, False, "fail"))
        self.assertEqual(helper_check["hint"], "systemctl --user start nowplaying-viz")

    def test_outdated_helper(self):
        self.status = dict(self.status, protocol=cli.helper.PROTOCOL - 1)
        code, rep = self.run_doctor()
        self.assertEqual(self.by_id(rep)["helper"]["status"], "fail")
        self.assertEqual(self.by_id(rep)["helper"]["hint"], "systemctl --user restart nowplaying-viz")
        self.status = ValueError("not JSON")
        self.assertEqual(self.by_id(self.run_doctor()[1])["helper"]["hint"], "systemctl --user restart nowplaying-viz")

    def test_quickshell_host_ignores_plasma_modules(self):
        self.missing_qml = set(PLASMA_ONLY)
        code, rep = self.run_doctor(host="quickshell", notify=True)
        self.assertEqual(code, 0, rep)
        self.assertNotIn("fail", [c["status"] for c in rep["checks"]])
        self.assertEqual(self.notified(), [])

    def test_quickshell_host_requires_quickshell_modules(self):
        self.missing_qml = {"Quickshell.Wayland"}
        self.assertEqual(self.by_id(self.run_doctor(host="quickshell")[1])["qml_modules"]["status"], "fail")
        self.assertEqual(self.by_id(self.run_doctor(host="plasma")[1])["qml_modules"]["status"], "ok")

    def test_plasma_host_requires_plasmoid_module(self):
        self.missing_qml = {"org.kde.plasma.plasmoid"}
        code, rep = self.run_doctor(host="plasma", notify=True)
        self.assertEqual((code, self.by_id(rep)["qml_modules"]["status"]), (1, "fail"))
        self.assertIn("org.kde.plasma.plasmoid", self.by_id(rep)["qml_modules"]["message"])
        self.assertEqual(len(self.notified()), 1)
        self.assertIn("critical", self.notified()[0])

    def test_warn_notifies_normal(self):
        self.missing_qml = {"org.kde.plasma.private.mpris"}  # has a fallback
        code, rep = self.run_doctor(notify=True)
        self.assertEqual((code, self.by_id(rep)["qml_modules"]["status"]), (0, "warn"))
        self.assertEqual(len(self.notified()), 1)
        self.assertIn("normal", self.notified()[0])

    def test_service_inactive(self):
        orig = self.fake_run
        self.fake_run = lambda cmd, **kw: (mock.Mock(stdout="inactive\n", returncode=3)
                                           if cmd[0] == "systemctl" else orig(cmd, **kw))
        svc = self.by_id(self.run_doctor(host="quickshell")[1])["service"]
        self.assertEqual((svc["status"], svc["hint"]), ("fail", "systemctl --user enable --now nowplaying-viz"))
        self.assertEqual(self.by_id(self.run_doctor(host="plasma")[1])["service"]["status"], "warn")

    def test_audio_skipped_without_card(self):
        self.status = dict(self.status, barClients=0, cava={"running": False, "peak": None, "age": None})
        code, rep = self.run_doctor()
        self.assertEqual((code, self.by_id(rep)["audio"]["status"]), (0, "skip"))

    def test_silent_cava_fails(self):
        self.status = dict(self.status, cava={"running": True, "peak": 0, "age": 0.1})
        code, rep = self.run_doctor()
        self.assertEqual((code, self.by_id(rep)["audio"]["status"]), (1, "fail"))
        self.assertEqual(self.by_id(rep)["audio"]["message"], "CAVA hears silence")
        self.players = [{"identity": "Spotify", "playing": False}]
        self.assertEqual(self.by_id(self.run_doctor()[1])["audio"]["status"], "skip")

    def test_unlinked_stereo_stream_fails(self):
        self.dump = list(STEREO_DUMP)
        user = {"version": cli.helper.CONFIG_VERSION, "preset": "lookas", "overrides": {},
                "audio": {"followPlayer": True}}
        links = self.by_id(self.run_doctor(user=user)[1])["links"]
        self.assertEqual(links["status"], "fail")
        self.assertIn("FL", links["message"])
        self.assertIn("MONO", links["message"])
        # a stereo stream linked into the MONO input is correct
        self.dump.append({"id": 70, "type": "PipeWire:Interface:Link",
                          "info": {"output-port-id": 51, "input-port-id": 61}})
        self.assertEqual(self.by_id(self.run_doctor()[1])["links"]["status"], "ok")

    def test_links_skipped_without_per_app_audio(self):
        self.dump = list(STEREO_DUMP)
        self.assertEqual(self.by_id(self.run_doctor()[1])["links"]["status"], "skip")

    def test_doctor_json_shape(self):
        with mock.patch.object(cli, "doctor", side_effect=lambda notify: self.run_doctor(notify=notify)), \
                mock.patch("sys.stdout") as out:
            rc = cli.main(["doctor", "--json"])
        rep = json.loads("".join(c.args[0] for c in out.write.call_args_list))
        self.assertEqual(rc, 0)
        self.assertEqual(set(rep), {"ok", "host", "checks"})
        self.assertEqual([c["id"] for c in rep["checks"]],
                         ["commands", "cava_version", "qml_modules", "config", "service",
                          "helper", "players", "links", "audio"])
        for c in rep["checks"]:
            self.assertEqual(set(c), {"id", "status", "message", "hint"})
            self.assertIn(c["status"], ("ok", "warn", "fail", "skip"))
        self.assertEqual(self.notified(), [])

    def test_text_output(self):
        self.status = ConnectionRefusedError()
        with mock.patch.object(cli, "doctor", side_effect=lambda notify: self.run_doctor(notify=notify)), \
                mock.patch("sys.stdout") as out:
            rc = cli.main(["doctor"])
        text = "".join(c.args[0] for c in out.write.call_args_list)
        self.assertEqual(rc, 1)
        self.assertIn("✗ ", text)
        self.assertIn("\n  → systemctl --user start nowplaying-viz\n", text)

    def test_detect_host(self):
        with mock.patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "KDE"}):
            self.assertEqual(cli.detect_host(), "plasma")
        none = mock.Mock(returncode=1)
        with mock.patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": "Hyprland"}), \
                mock.patch.object(cli.subprocess, "run", return_value=none):
            with mock.patch.object(cli.shutil, "which", return_value="/usr/bin/quickshell"):
                self.assertEqual(cli.detect_host(), "quickshell")
            with mock.patch.object(cli.shutil, "which", return_value=None):
                self.assertEqual(cli.detect_host(), "none")


if __name__ == "__main__":
    unittest.main()
