# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for package/contents/code/helper.py (standard library only).

Run from the repository root:  python3 -m unittest discover -s tests -v

The helper reads XDG_CONFIG_HOME when it is imported, so every test runs
against a throwaway config folder and never touches the real one.
"""

import asyncio
import base64
import importlib
import json
import os
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
CODE = ROOT / "package" / "contents" / "code"
TMP = tempfile.TemporaryDirectory()
os.environ["XDG_CONFIG_HOME"] = TMP.name
sys.path.insert(0, str(CODE))
helper = importlib.import_module("helper")


def write_user(user):
    helper.CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    helper.CONFIG_FILE.write_text(json.dumps(user))


def read_user():
    return json.loads(helper.CONFIG_FILE.read_text())


class PortTests(unittest.TestCase):
    """NPV_PORT: the same cases as tests/qml/tst_net.qml, so the helper and
    the widget always agree on the port."""

    def test_valid_ports(self):
        for text, port in (("47811", 47811), ("47899", 47899), ("1024", 1024), ("65535", 65535)):
            self.assertEqual(helper.parse_port(text), port, text)

    def test_anything_else_is_refused(self):
        for text in ("", "80", "0", "65536", " 47899", "47899\n", "+47899", "-1", "47899.5",
                     "0xbb1b", "4e4", "4_7899", "047899", "٤٧٨٩٩", "47899; rm -rf ~", None, 47899):
            self.assertIsNone(helper.parse_port(text), repr(text))

    def test_bad_value_falls_back_to_the_default(self):
        code = f"import sys; sys.path.insert(0, {str(CODE)!r}); import helper; print(helper.PORT)"
        for env, want in (({"NPV_PORT": "47899"}, "47899"), ({"NPV_PORT": "80"}, "47811"), ({}, "47811")):
            out = subprocess.run([sys.executable, "-I", "-c", code], capture_output=True, text=True,
                                 env={k: v for k, v in os.environ.items() if k != "NPV_PORT"} | env)
            self.assertEqual(out.stdout.strip(), want, env)


class SchemaTests(unittest.TestCase):
    """schema.json is the single source of truth, so it must be consistent."""

    @classmethod
    def setUpClass(cls):
        cls.schema = helper.load_schema()
        cls.options = cls.schema["options"]

    def test_every_default_is_valid(self):
        for key, spec in self.options.items():
            with self.subTest(key=key):
                self.assertEqual(helper.coerce(spec["default"], spec), spec["default"])

    def test_groups_tabs_and_conditions_point_to_real_things(self):
        groups = {g["id"] for g in self.schema["groups"]}
        tabs = {t["id"] for t in self.schema["tabs"]}
        for g in self.schema["groups"]:
            self.assertIn(g["tab"], tabs, g["id"])
        for key, spec in self.options.items():
            with self.subTest(key=key):
                self.assertIn(spec["group"], groups)
                for cond in ("when", "whenNot"):
                    for other in spec.get(cond, {}):
                        self.assertIn(other, self.options, f"{cond} refers to unknown {other}")

    def test_numbers_have_sane_ranges(self):
        for key, spec in self.options.items():
            if spec["type"] in ("int", "real"):
                with self.subTest(key=key):
                    self.assertLessEqual(spec["min"], spec["default"])
                    self.assertLessEqual(spec["default"], spec["max"])

    def test_config_version_matches_schema(self):
        self.assertEqual(self.schema["version"], helper.CONFIG_VERSION)


class PresetTests(unittest.TestCase):
    def test_every_builtin_preset_is_valid(self):
        schema = helper.load_schema()
        presets = helper.load_builtin_presets()
        self.assertIn("lookas", presets)
        for name, preset in presets.items():
            with self.subTest(preset=name):
                eff = helper.deep_merge(helper.schema_defaults(schema), preset)
                issues = []
                helper.validate(eff, schema, issues)
                self.assertEqual(issues, [])
                # a preset may only use keys that exist in the schema
                for key in flatten(preset):
                    self.assertIn(key, schema["options"])


def flatten(d, prefix=""):
    for k, v in d.items():
        if isinstance(v, dict):
            yield from flatten(v, f"{prefix}{k}.")
        else:
            yield f"{prefix}{k}"


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.schema = helper.load_schema()

    def test_bad_values_fall_back_or_get_clamped(self):
        eff = helper.schema_defaults(self.schema)
        eff["bars"]["count"] = 999
        eff["bars"]["style"] = "nope"
        eff["panel"]["color"] = "red"
        eff["bars"]["show"] = "yes"
        issues = []
        helper.validate(eff, self.schema, issues)
        codes = {(i["code"], i["detail"]) for i in issues}
        self.assertIn(("out_of_range", "bars.count"), codes)
        self.assertIn(("invalid_option", "bars.style"), codes)
        self.assertIn(("invalid_option", "panel.color"), codes)
        self.assertIn(("invalid_option", "bars.show"), codes)
        self.assertEqual(eff["bars"]["count"], 128)
        self.assertEqual(eff["bars"]["style"], "bars")

    def test_booleans_are_not_numbers(self):
        spec = {"type": "int", "min": 0, "max": 10}
        self.assertIs(helper.coerce(True, spec), helper._INVALID)

    def test_colour_conversion_to_qt(self):
        self.assertEqual(helper.to_qml_colors("#11223344"), "#44112233")
        self.assertEqual(helper.to_qml_colors("#112233"), "#112233")
        self.assertEqual(helper.to_qml_colors({"a": ["#11223344"]}), {"a": ["#44112233"]})

    def test_deep_merge_does_not_modify_inputs(self):
        a = {"x": {"y": 1, "z": 2}}
        b = {"x": {"y": 3}}
        self.assertEqual(helper.deep_merge(a, b), {"x": {"y": 3, "z": 2}})
        self.assertEqual(a, {"x": {"y": 1, "z": 2}})


class MigrationTests(unittest.TestCase):
    def test_v1_hide_option_becomes_when_idle(self):
        user = {"version": 1, "overrides": {"panel": {"hideWhenNoPlayer": False}},
                "presets": {"mine": {"panel": {"hideWhenNoPlayer": True}}}}
        self.assertTrue(helper.migrate(user))
        self.assertEqual(user["version"], helper.CONFIG_VERSION)
        self.assertEqual(user["overrides"]["panel"], {"whenIdle": "last"})
        self.assertEqual(user["presets"]["mine"]["panel"], {})

    def test_current_version_is_left_alone(self):
        self.assertFalse(helper.migrate({"version": helper.CONFIG_VERSION}))


class DesignEditTests(unittest.TestCase):
    def setUp(self):
        write_user(helper.default_user_config())

    def test_set_design_only_accepts_known_valid_options(self):
        helper.apply_design({"type": "setDesign", "changes": {
            "bars.count": 40, "bars.style": "nope", "not.an.option": 1, "panel.color": "#000000aa"}})
        o = read_user()["overrides"]
        self.assertEqual(o["bars"], {"count": 40})
        self.assertEqual(o["panel"], {"color": "#000000aa"})
        self.assertNotIn("not", o)

    def test_switching_preset_drops_bar_overrides_only(self):
        helper.apply_design({"type": "setDesign", "changes": {"bars.count": 40, "header.show": False}})
        helper.apply_design({"type": "setPreset", "name": "neon"})
        user = read_user()
        self.assertEqual(user["preset"], "neon")
        self.assertEqual(user["overrides"], {"header": {"show": False}})

    def test_save_and_delete_preset(self):
        helper.apply_design({"type": "setDesign", "changes": {"bars.gap": 9}})
        helper.apply_design({"type": "savePreset", "name": "mine"})
        user = read_user()
        self.assertEqual(user["preset"], "mine")
        self.assertEqual(user["presets"]["mine"]["bars"]["gap"], 9)
        helper.apply_design({"type": "deletePreset", "name": "mine"})
        self.assertEqual(read_user()["preset"], "lookas")

    def test_preset_limit_refuses_new_names_only(self):
        user = helper.default_user_config()
        user["presets"] = {f"p{i}": {} for i in range(helper.MAX_PRESETS)}
        write_user(user)
        self.assertEqual(helper.apply_design({"type": "savePreset", "name": "new"}), "preset_limit")
        self.assertNotIn("new", read_user()["presets"])
        self.assertIsNone(helper.apply_design({"type": "savePreset", "name": "p0"}))
        self.assertEqual(len(read_user()["presets"]), helper.MAX_PRESETS)

    def test_undo_and_cancel(self):
        ws = object()
        helper.begin_edit(ws)
        helper.push_history("setPreset")
        helper.apply_design({"type": "setPreset", "name": "neon"})
        self.assertTrue(helper.edit_state()["dirty"])
        helper.restore_design(helper.edit["history"].pop())  # Undo
        self.assertEqual(read_user()["preset"], "lookas")
        helper.apply_design({"type": "setPreset", "name": "teal"})
        helper.restore_design(helper.edit["snapshot"])  # what Cancel does
        self.assertEqual(read_user()["preset"], "lookas")
        self.assertFalse(helper.edit_state()["dirty"])


class WebSocketTests(unittest.IsolatedAsyncioTestCase):
    """The helper must talk to the widget and refuse web pages."""

    async def asyncSetUp(self):
        write_user(helper.default_user_config())
        helper.state["config"] = helper.load_config()
        self.server = await asyncio.start_server(helper.accept, helper.HOST, 0)
        self.port = self.server.sockets[0].getsockname()[1]
        self.old_port, helper.PORT = helper.PORT, self.port
        self.writers = []

    async def asyncTearDown(self):
        helper.PORT = self.old_port
        for writer in self.writers:
            writer.close()
        self.server.close()
        # never hang the suite on a connection a failing test left open
        await asyncio.wait_for(self.server.wait_closed(), 3)

    async def handshake(self, extra=""):
        reader, writer = await asyncio.open_connection(helper.HOST, self.port)
        self.writers.append(writer)
        key = base64.b64encode(os.urandom(16)).decode()
        writer.write((f"GET / HTTP/1.1\r\nHost: {helper.HOST}:{self.port}\r\nUpgrade: websocket\r\n"
                      f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
                      f"{extra}\r\n").encode())
        await writer.drain()
        status = (await asyncio.wait_for(reader.readline(), 2)).decode()
        return status, reader, writer

    async def test_widget_style_client_gets_schema_first(self):
        status, reader, writer = await self.handshake()
        self.assertIn("101", status)
        await reader.readuntil(b"\r\n\r\n")
        b1, b2 = await reader.readexactly(2)
        n = b2 & 0x7F
        if n == 126:
            n = int.from_bytes(await reader.readexactly(2), "big")
        elif n == 127:
            n = int.from_bytes(await reader.readexactly(8), "big")
        first = json.loads(await reader.readexactly(n))
        self.assertEqual(first["type"], "schema")

    async def test_browser_origin_is_refused(self):
        status, _, writer = await self.handshake("Origin: https://example.com\r\n")
        self.assertIn("403", status)

    async def test_unexpected_host_is_refused(self):
        reader, writer = await asyncio.open_connection(helper.HOST, self.port)
        self.writers.append(writer)
        writer.write(b"GET / HTTP/1.1\r\nHost: evil.example\r\nUpgrade: websocket\r\n"
                     b"Connection: Upgrade\r\nSec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n\r\n")
        await writer.drain()
        status = (await asyncio.wait_for(reader.readline(), 2)).decode()
        self.assertIn("403", status)


class LocalUserTests(unittest.IsolatedAsyncioTestCase):
    """Only our own user may talk to the helper (the kernel says who owns a socket)."""

    TABLE = ("  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n"
             "   0: {a}:1234 {b}:B893 01 00000000:00000000 00:00000000 00000000  {uid}        0 1 1\n"
             "   1: {b}:B893 {a}:1234 01 00000000:00000000 00:00000000 00000000  {me}        0 2 1\n"
             "   2: {b}:B893 00000000:0000 0A 00000000:00000000 00:00000000 00000000  {uid}        0 3 1\n")

    def fake_proc(self, uid):
        a = helper.proc_addr(("127.0.0.1", 0)).split(":")[0]
        f = Path(TMP.name) / "tcp"
        f.write_text(self.TABLE.format(a=a, b=a, uid=uid, me=os.getuid()))
        return mock.patch.object(helper, "PROC_NET_TCP", str(f))

    def test_owner_of_the_client_end_is_read(self):
        with self.fake_proc(4321):
            # client 127.0.0.1:0x1234 -> server :0xB893, not the server's own end
            self.assertEqual(helper.socket_uid(("127.0.0.1", 0x1234), ("127.0.0.1", 0xB893)), 4321)
            self.assertEqual(helper.socket_uid(("127.0.0.1", 0xB893), None, listening=True), 4321)
            self.assertIsNone(helper.socket_uid(("127.0.0.1", 0x9999), ("127.0.0.1", 0xB893)))
        with mock.patch.object(helper, "PROC_NET_TCP", "/nonexistent"):
            self.assertIsNone(helper.socket_uid(("127.0.0.1", 1), ("127.0.0.1", 2)))

    async def test_real_connection_from_us_is_accepted_and_others_refused(self):
        uids = []
        server = await asyncio.start_server(helper.accept, helper.HOST, 0)
        port = server.sockets[0].getsockname()[1]
        try:
            for fake_uid in (None, os.getuid() + 1):
                with mock.patch.object(helper, "socket_uid", return_value=fake_uid), \
                        mock.patch.object(helper, "log"):
                    reader, writer = await asyncio.open_connection(helper.HOST, port)
                    # refused before the handshake: the server just hangs up
                    self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
                    writer.close()
            reader, writer = await asyncio.open_connection(helper.HOST, port)
            await asyncio.sleep(0.1)
            # the real /proc/net/tcp says this socket is ours
            uids.append(helper.socket_uid(writer.get_extra_info("sockname"), writer.get_extra_info("peername")))
            writer.close()
        finally:
            server.close()
            await asyncio.wait_for(server.wait_closed(), 3)
        self.assertEqual(uids, [os.getuid()])


class ShutdownTests(unittest.IsolatedAsyncioTestCase):
    async def test_stops_promptly_with_a_widget_connected(self):
        # systemd used to SIGKILL the service after its stop timeout
        with socket.socket() as s:
            s.bind((helper.HOST, 0))
            port = s.getsockname()[1]
        old_port, helper.PORT = helper.PORT, port
        try:
            with mock.patch.object(helper, "remove_legacy_sink"):
                main = asyncio.create_task(helper.main())
                for _ in range(50):
                    try:
                        reader, writer = await asyncio.open_connection(helper.HOST, port)
                        break
                    except OSError:
                        await asyncio.sleep(0.05)
                writer.write((f"GET / HTTP/1.1\r\nHost: {helper.HOST}:{port}\r\nUpgrade: websocket\r\n"
                              "Connection: Upgrade\r\nSec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n"
                              "Sec-WebSocket-Version: 13\r\n\r\n").encode())
                await writer.drain()
                await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 2)
                helper.stop_future.set_result(None)
                await asyncio.wait_for(main, 3)
                writer.close()
        finally:
            helper.PORT = old_port


class FollowPlayerTests(unittest.TestCase):
    def setUp(self):
        self.saved = helper.state["config"]
        helper.state["config"] = {"panel": {"preferredPlayers": []}, "audio": {"apps": ["liner"], "followPlayer": True}}

    def tearDown(self):
        helper.state["config"] = self.saved

    def test_playing_player_wins_over_paused_one(self):
        players = [{"bus": "org.mpris.MediaPlayer2.elisa", "identity": "Elisa", "playing": False},
                   {"bus": "org.mpris.MediaPlayer2.chromium.instance42", "identity": "Riff", "playing": True}]
        self.assertEqual(helper.pick_player(players)["identity"], "Riff")
        self.assertIsNone(helper.pick_player([]))

    def test_streams_match_by_pid_or_name(self):
        riff = {"application.name": "Riff", "application.process.binary": "riff", "application.process.id": 42}
        chromium = {"application.name": "Chromium", "application.process.binary": "chromium", "application.process.id": 7}
        self.assertTrue(helper.player_stream(riff, 42, "riff"))
        self.assertTrue(helper.player_stream(riff, None, "riff"))
        self.assertTrue(helper.player_stream(chromium, 7, "riff"))
        self.assertFalse(helper.player_stream(chromium, 42, "riff"))

    def test_follow_player_overrides_the_app_list(self):
        liner = {"application.process.binary": "liner"}
        riff = {"application.name": "Riff", "application.process.id": 42}
        with mock.patch.object(helper, "followed_player", return_value=(42, "riff")):
            wanted = helper.link_filter()
        self.assertTrue(wanted(riff))
        self.assertFalse(wanted(liner))
        with mock.patch.object(helper, "followed_player", return_value=None):
            self.assertFalse(helper.link_filter()(riff))
        helper.state["config"]["audio"]["followPlayer"] = False
        self.assertTrue(helper.link_filter()(liner))
        self.assertFalse(helper.link_filter()(riff))

    def test_active_player_is_reused_for_a_while(self):
        helper.forget_followed_player()
        with mock.patch.object(helper, "active_player", return_value=(42, "riff")) as ask:
            self.assertEqual(helper.followed_player(), (42, "riff"))
            self.assertEqual(helper.followed_player(), (42, "riff"))
            self.assertEqual(ask.call_count, 1)
            helper.forget_followed_player()
            helper.followed_player()
            self.assertEqual(ask.call_count, 2)
        helper.forget_followed_player()

    def test_capture_mode_when_following(self):
        cfg = {"audio": {"apps": [], "followPlayer": True}, "bars": {}}
        self.assertIn("source=" + helper.CAPTURE_TARGET, helper.cava_config(cfg))
        cfg["audio"]["followPlayer"] = False
        self.assertIn("source=auto", helper.cava_config(cfg))


GETALL_PLAYER = {"type": "a{sv}", "data": [{
    "CanControl": {"type": "b", "data": True}, "CanPause": {"type": "b", "data": True},
    "CanGoNext": {"type": "b", "data": True}, "PlaybackStatus": {"type": "s", "data": "Playing"},
    "Position": {"type": "x", "data": 5000000}, "Rate": {"type": "d", "data": 1.0},
    "Metadata": {"type": "a{sv}", "data": {
        "xesam:title": {"type": "s", "data": "AURORA"}, "xesam:artist": {"type": "as", "data": ["Mora"]},
        "mpris:length": {"type": "x", "data": 192853333}}}}]}


class CavaConfigTests(unittest.TestCase):
    # what 0.2.0 sent CAVA with every option at its default: new options must
    # not change it, or every user's bars would change after an update
    DEFAULT_CONFIG = (
        "[general]\nframerate=60\nbars=24\nlower_cutoff_freq=50\nhigher_cutoff_freq=12000\n"
        "autosens=1\nsensitivity=100\nsleep_timer=0\n[input]\nmethod=pipewire\nsource=auto\n"
        "virtual=1\n[output]\nmethod=raw\nraw_target=/dev/stdout\ndata_format=ascii\n"
        "ascii_max_range=1000\nchannels=mono\nmono_option=average\n[smoothing]\n"
        "noise_reduction=77\nmonstercat=0\n")

    def defaults(self):
        return helper.schema_defaults(helper.load_schema())

    def test_defaults_give_the_same_config_as_before(self):
        self.assertEqual(helper.cava_config(self.defaults()), self.DEFAULT_CONFIG)

    def test_config_from_an_older_helper_still_works(self):
        # a config without the new keys, as an older schema would build it
        cfg = self.defaults()
        del cfg["audio"]["eq"], cfg["audio"]["autoSensitivity"]
        self.assertEqual(helper.cava_config(cfg), self.DEFAULT_CONFIG)

    def test_equalizer(self):
        cfg = self.defaults()
        cfg["audio"]["eq"]["bass"] = 1.5
        conf = helper.cava_config(cfg)
        self.assertTrue(conf.endswith("[eq]\n1=1.50\n2=1.00\n3=1.00\n"), conf)

    def test_fixed_sensitivity(self):
        cfg = self.defaults()
        cfg["audio"]["autoSensitivity"] = False
        cfg["audio"]["sensitivity"] = 150
        conf = helper.cava_config(cfg)
        self.assertIn("autosens=0\nsensitivity=150\n", conf)


class CavaRestartTests(unittest.TestCase):
    """CAVA is restarted once its config settles, not on every slider step."""

    def setUp(self):
        self.proc = mock.Mock(returncode=None)
        cfg = helper.schema_defaults(helper.load_schema())
        state = {"config": cfg}
        patches = [mock.patch.object(helper, "cava_proc", self.proc),
                   mock.patch.object(helper, "cava_key", helper.cava_config(cfg)),
                   mock.patch.dict(helper.state, state)]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.cfg = cfg

    def set_sensitivity(self, value):
        self.cfg["audio"]["sensitivity"] = value

    def test_unchanged_config_never_restarts(self):
        for t in range(10):
            helper.restart_cava_if_needed(t)
        self.proc.terminate.assert_not_called()

    def test_restarts_once_the_change_settles(self):
        self.set_sensitivity(120)
        helper.restart_cava_if_needed(0.0)
        self.proc.terminate.assert_not_called()
        helper.restart_cava_if_needed(0.5)
        self.proc.terminate.assert_called_once()

    def test_a_drag_restarts_only_at_the_end(self):
        for i, t in enumerate((0.0, 0.5, 1.0, 1.5)):
            self.set_sensitivity(110 + i * 10)
            helper.restart_cava_if_needed(t)
        self.proc.terminate.assert_not_called()
        helper.restart_cava_if_needed(2.0)
        self.proc.terminate.assert_called_once()

    def test_going_back_to_the_running_config_cancels_the_restart(self):
        self.set_sensitivity(120)
        helper.restart_cava_if_needed(0.0)
        self.set_sensitivity(100)
        helper.restart_cava_if_needed(0.5)
        helper.restart_cava_if_needed(1.0)
        self.proc.terminate.assert_not_called()


class MediaReaderTests(unittest.TestCase):
    """The D-Bus fallback reads each MPRIS interface with one GetAll."""

    def test_getall_gives_the_media_message(self):
        def fake(*args):
            if args[0] == "call" and args[-1] == "org.mpris.MediaPlayer2.Player":
                return [GETALL_PLAYER]
            if args[0] == "call" and args[-1] == "org.mpris.MediaPlayer2":
                return [{"type": "a{sv}", "data": [{"Identity": {"type": "s", "data": "Riff"}}]}]
            raise AssertionError("no per-property calls when GetAll works: %r" % (args,))
        with mock.patch.object(helper, "busctl_json", side_effect=fake):
            n = "org.mpris.MediaPlayer2.chromium.instance1"
            m = helper.media_of(n, helper.player_props(n, "org.mpris.MediaPlayer2"),
                                helper.player_props(n, "org.mpris.MediaPlayer2.Player"))
        self.assertEqual((m["track"], m["artist"], m["identity"]), ("AURORA", "Mora", "Riff"))
        self.assertEqual((m["position"], m["length"]), (5000000, 192853333))
        self.assertTrue(m["playing"] and m["canPlayPause"] and m["canGoNext"])
        self.assertFalse(m["canSeek"] or m["canRaise"])

    def test_players_without_getall_are_read_one_by_one(self):
        def fake(*args):
            if args[0] == "call":
                return []
            return [{"type": "s", "data": "Paused"}] if args[-1] == "PlaybackStatus" else []
        with mock.patch.object(helper, "busctl_json", side_effect=fake):
            get = helper.player_props("org.mpris.MediaPlayer2.x", "org.mpris.MediaPlayer2.Player")
            self.assertEqual(get("PlaybackStatus", ""), "Paused")
            self.assertEqual(get("Rate", 1), 1)


class CachingTests(unittest.TestCase):
    def setUp(self):
        write_user(helper.default_user_config())

    def test_preset_thumbnails_are_reused_when_only_overrides_change(self):
        helper.load_config()
        before = helper.state["presets"]
        helper.apply_design({"type": "setDesign", "changes": {"bars.count": 40}})
        helper.load_config()
        self.assertIs(helper.state["presets"], before)
        helper.apply_design({"type": "savePreset", "name": "mine"})
        helper.load_config()
        self.assertIn("mine", [p["name"] for p in helper.state["presets"]])

    def test_schema_is_read_again_when_it_changes(self):
        self.assertIs(helper.load_schema(), helper.load_schema())
        with mock.patch.object(helper, "SCHEMA_FILE", Path(TMP.name) / "schema.json"):
            helper.SCHEMA_FILE.write_text('{"v": 1}')
            self.assertEqual(helper.load_schema(), {"v": 1})
            helper.SCHEMA_FILE.write_text('{"v": 2}')
            os.utime(helper.SCHEMA_FILE, ns=(0, 1))  # a different mtime even on coarse clocks
            self.assertEqual(helper.load_schema(), {"v": 2})


class FakeTransport:
    def __init__(self, queued=0):
        self.queued = queued

    def is_closing(self):
        return False

    def get_write_buffer_size(self):
        return self.queued


class BarStreamTests(unittest.TestCase):
    def make_client(self, queued=0):
        writer = mock.Mock()
        writer.transport = FakeTransport(queued)
        return helper.WsConn(None, writer)

    def test_slow_clients_skip_frames_and_repeats_are_not_sent(self):
        fast, slow = self.make_client(), self.make_client(helper.BAR_BACKLOG + 1)
        with mock.patch.object(helper, "clients", {fast, slow}):
            helper.state["last_bars"] = None
            helper.send_bars("B1;2")
            helper.send_bars("B1;2")
            helper.send_bars("B3;4")
        self.assertEqual([c.args[0] for c in fast.writer.write.call_args_list],
                         [helper.ws_frame(1, b"B1;2"), helper.ws_frame(1, b"B3;4")])
        slow.writer.write.assert_not_called()


class MediaActionTests(unittest.TestCase):
    def test_no_player_means_nothing_happens(self):
        helper.state["media_player"] = None
        helper.media_action("next", None)  # must not raise

    def test_player_values_never_become_busctl_options(self):
        helper.state["media_player"] = {"bus": "org.mpris.MediaPlayer2.x", "identity": "x",
                                        "trackId": "--address=unix:path=/tmp/evil"}
        with mock.patch.object(helper, "run") as run:
            helper.media_action("seek", 1000)
            run.assert_not_called()  # not an object path: no SetPosition at all
            helper.media_action("next", None)
        cmd = run.call_args.args[0]
        self.assertEqual(cmd[:4], ["busctl", "--user", "call", "--"])
        with mock.patch.object(helper, "run") as run:
            run.return_value.stdout = ""
            helper.busctl_json("get-property", "-x", "/p", "i", "P")
        self.assertEqual(run.call_args.args[0][:5], ["busctl", "--user", "--json=short", "get-property", "--"])

    def test_icon_names_only(self):
        self.assertEqual(helper.icon_name("spotify"), "spotify")
        self.assertEqual(helper.icon_name("/etc/passwd"), "")
        self.assertEqual(helper.icon_name("https://example.com/x.png"), "")


class FakeWs:
    """A client for handler(): yields the given messages, records replies."""
    def __init__(self, *messages, topics=None):
        self.messages = [json.dumps(m) for m in messages]
        self.sent = []
        self.topics = topics
        self.pinned = ""
        self.media_player = None

    def __aiter__(self):
        return self

    async def __anext__(self):
        if not self.messages:
            raise StopAsyncIteration
        return self.messages.pop(0)

    async def send(self, text):
        self.sent.append(json.loads(text))

    def close(self):
        pass

    def replies(self, kind):
        return [m for m in self.sent if m.get("type") == kind]


def player(identity, playing=False, bus=None, **extra):
    p = {"bus": bus or "org.mpris.MediaPlayer2." + identity.lower(), "identity": identity,
         "playing": playing, "trackId": "/t/1", "canControl": True, "shuffle": None, "loop": None}
    p.update(extra)
    return p


class PinnedPlayerTests(unittest.IsolatedAsyncioTestCase):
    """The player picked in the widget's menu wins while it is open."""

    def setUp(self):
        write_user(helper.default_user_config())
        helper.state["config"] = helper.load_config()

    def test_pinned_wins_over_the_playing_one(self):
        players = [player("Spotify", playing=True), player("Zen")]
        self.assertEqual(helper.pick_player(players, "zen")["identity"], "Zen")
        self.assertEqual(helper.pick_player(players, "")["identity"], "Spotify")

    def test_pinned_but_closed_falls_back_to_automatic(self):
        players = [player("Spotify", playing=True), player("Zen")]
        self.assertEqual(helper.pick_player(players, "Liner")["identity"], "Spotify")

    def test_pinned_is_matched_exactly(self):
        # "Zen" must not catch "Zen Browser Nightly": the menu lists exact names
        players = [player("Zen Browser Nightly", playing=True), player("Spotify")]
        self.assertEqual(helper.pick_player(players, "Zen")["identity"], "Zen Browser Nightly")
        self.assertIsNone(helper.pick_player([], "Zen"))

    def test_bad_pin_values_are_ignored(self):
        players = [player("Spotify", playing=True)]
        for bad in (None, 7, ["Spotify"], {"a": 1}):
            self.assertEqual(helper.pick_player(players, bad)["identity"], "Spotify")

    async def test_each_client_gets_its_own_pick_and_the_list(self):
        a, b = FakeWs(), FakeWs()
        a.pinned, b.pinned = "Zen", ""
        players = [player("Spotify", playing=True), player("Zen")]
        with mock.patch.object(helper, "clients", {a, b}):
            await helper.send_media(players)
        self.assertEqual(a.sent[0]["data"]["identity"], "Zen")
        self.assertEqual(b.sent[0]["data"]["identity"], "Spotify")
        self.assertEqual(a.sent[0]["players"], [{"identity": "Spotify", "playing": True},
                                                {"identity": "Zen", "playing": False}])
        self.assertEqual(a.media_player["identity"], "Zen")

    async def test_schema_says_which_protocol_and_whether_it_is_the_service(self):
        ws = FakeWs()
        await helper.handler(ws)
        schema = ws.replies("schema")[0]
        self.assertEqual(schema["protocol"], helper.PROTOCOL)
        self.assertIs(schema["service"], helper.SERVICE)

    async def test_pin_message(self):
        ws = FakeWs({"type": "pinPlayer", "identity": "Zen"}, {"type": "pinPlayer", "identity": 42},
                    {"type": "pinPlayer", "identity": "x" * 1000})
        with mock.patch.dict(helper.state, {"pinned_player": ""}):
            await helper.handler(ws)
            self.assertEqual(ws.pinned, "x" * helper.MAX_NAME)
            self.assertEqual(helper.state["pinned_player"], ws.pinned)

    def test_follow_player_uses_the_pin(self):
        players = {"org.mpris.MediaPlayer2.spotify": ("Spotify", "Playing"),
                   "org.mpris.MediaPlayer2.zen": ("Zen", "Paused")}
        def prop(name, iface, key, default=None):
            return players[name][0] if key == "Identity" else players[name][1]
        with mock.patch.object(helper, "mpris_names", return_value=list(players)), \
             mock.patch.object(helper, "busctl_prop", side_effect=prop), \
             mock.patch.object(helper, "bus_pid", return_value=99), \
             mock.patch.dict(helper.state, {"pinned_player": "zen"}):
            self.assertEqual(helper.active_player(), (99, "zen"))


class ShuffleRepeatTests(unittest.TestCase):
    def media(self, props):
        root = lambda k, d: {"Identity": "P"}.get(k, d)
        base = {"CanControl": True, "PlaybackStatus": "Playing", "Metadata": {}}
        base.update(props)
        return helper.media_of("org.mpris.MediaPlayer2.p", root, lambda k, d: base.get(k, d))

    def test_read_when_the_player_has_them(self):
        m = self.media({"Shuffle": True, "LoopStatus": "Track"})
        self.assertIs(m["shuffle"], True)
        self.assertEqual(m["loop"], "Track")

    def test_none_when_missing_or_invalid(self):
        m = self.media({})
        self.assertIsNone(m["shuffle"])
        self.assertIsNone(m["loop"])
        m = self.media({"Shuffle": "yes", "LoopStatus": "Forever"})
        self.assertIsNone(m["shuffle"])
        self.assertIsNone(m["loop"])

    def commands(self, action, value, **p):
        with mock.patch.object(helper, "run") as run:
            helper.media_action(action, value, player("P", **p))
        return [c.args[0] for c in run.call_args_list]

    def test_set_shuffle_and_loop(self):
        cmd = self.commands("shuffle", True, shuffle=False)
        self.assertEqual(cmd, [["busctl", "--user", "set-property", "--", "org.mpris.MediaPlayer2.p",
                                helper.MPRIS_PATH, "org.mpris.MediaPlayer2.Player", "Shuffle", "b", "true"]])
        cmd = self.commands("loop", "Playlist", loop="None")
        self.assertEqual(cmd[0][-3:], ["LoopStatus", "s", "Playlist"])

    def test_only_valid_values_reach_busctl(self):
        for value in ("true", 1, None, ["x"]):
            self.assertEqual(self.commands("shuffle", value, shuffle=False), [], value)
        for value in ("Shuffle", "none", "--help", 1, None):
            self.assertEqual(self.commands("loop", value, loop="None"), [], value)

    def test_nothing_for_players_without_them(self):
        self.assertEqual(self.commands("shuffle", True), [])
        self.assertEqual(self.commands("loop", "Track"), [])
        self.assertEqual(self.commands("shuffle", True, shuffle=False, canControl=False), [])

    def test_the_clients_own_player_is_used(self):
        helper.state["media_player"] = player("Other", shuffle=False)
        cmd = self.commands("shuffle", True, shuffle=False)
        self.assertIn("org.mpris.MediaPlayer2.p", cmd[0])


class PresetFileTests(unittest.IsolatedAsyncioTestCase):
    """Import and export: any file may be hostile, nothing in it is trusted."""

    def setUp(self):
        write_user(helper.default_user_config())
        helper.state["config"] = helper.load_config()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)

    def file(self, name, content):
        path = self.dir / name
        path.write_text(content if isinstance(content, str) else json.dumps(content))
        return str(path)

    def read_error(self, path):
        with self.assertRaises(helper.PresetFileError) as cm:
            helper.read_preset_file(path)
        return cm.exception.code

    def test_reads_our_format_and_bare_presets(self):
        doc = {"format": helper.PRESET_FORMAT, "version": 1, "name": "Mine", "design": {"bars": {"count": 40}}}
        self.assertEqual(helper.read_preset_file(self.file("a.json", doc))["name"], "Mine")
        bare = helper.read_preset_file(self.file("b.json", {"bars": {"count": 40}}))
        self.assertEqual(bare, {"name": None, "design": {"bars": {"count": 40}}})

    def test_refuses_what_is_not_a_preset(self):
        self.assertEqual(self.read_error(self.file("x.json", "not json")), "file_not_json")
        self.assertEqual(self.read_error(self.file("x.json", "[1, 2]")), "file_not_preset")
        self.assertEqual(self.read_error(self.file("x.json", {"format": "other", "design": {}})), "file_not_preset")
        self.assertEqual(self.read_error(self.file("x.json", {"format": helper.PRESET_FORMAT, "design": 3})),
                         "file_not_preset")
        (self.dir / "bin.json").write_bytes(b"\xff\xfe{}")
        self.assertEqual(self.read_error(str(self.dir / "bin.json")), "file_not_json")
        self.assertEqual(self.read_error(self.file("deep.json", "[" * 100000 + "]" * 100000)), "file_not_json")

    def test_refuses_big_files_without_reading_them_whole(self):
        path = self.file("big.json", " " * (helper.MAX_PRESET_FILE + 10))
        self.assertEqual(self.read_error(path), "file_too_big")

    def test_refuses_bad_paths_and_special_files(self):
        for bad in (None, 3, "", "relative.json", "/tmp/a\0b.json", "/" + "a" * 5000):
            self.assertEqual(self.read_error(bad), "file_bad_path", bad)
        self.assertEqual(self.read_error(str(self.dir)), "file_unreadable")
        self.assertEqual(self.read_error(str(self.dir / "missing.json")), "file_unreadable")
        fifo = self.dir / "fifo.json"
        os.mkfifo(fifo)
        # a FIFO with no writer would block a plain open() forever
        self.assertEqual(self.read_error(str(fifo)), "file_unreadable")

    def test_only_valid_visible_options_are_kept(self):
        design = {
            "bars": {"count": 40, "colors": ["#ff0000", "red"], "glow": {"enabled": "yes"}, "style": "lasers"},
            "panel": {"color": "#00000080", "unknown": 1},
            "audio": {"apps": ["spotify"], "followPlayer": True, "sensitivity": 150},
            "header": {"text": "x" * 5000},
            "evil": {"__proto__": {"polluted": True}},
        }
        clean, dropped = helper.clean_design(design)
        self.assertEqual(clean["bars"], {"count": 40})
        self.assertEqual(clean["panel"], {"color": "#00000080"})
        # the app list and follow-the-player are personal, never imported
        self.assertEqual(clean["audio"], {"sensitivity": 150})
        self.assertEqual(len(clean["header"]["text"]), helper.MAX_IMPORT_TEXT)
        self.assertNotIn("evil", clean)
        # colors (one bad entry drops the list), glow.enabled, style, panel.unknown,
        # audio.apps, audio.followPlayer, evil.__proto__.polluted
        self.assertEqual(dropped, 7)

    def test_names_are_cleaned_and_never_clash(self):
        taken = {"lookas", "Mine", "Mine 2"}
        self.assertEqual(helper.preset_name("Mine", "f", taken), "Mine 3")
        self.assertEqual(helper.preset_name("lookas", "f", taken), "lookas 2")
        self.assertEqual(helper.preset_name("a\nb\x1b[31m", "f", set()), "ab[31m")
        self.assertEqual(helper.preset_name("", "from-file", set()), "from-file")
        self.assertEqual(helper.preset_name(None, "", set()), "Imported")
        self.assertEqual(len(helper.preset_name("n" * 500, "f", set())), 64)

    def test_export_then_import_gives_the_same_design(self):
        user = helper.read_user()
        user["preset"] = "neon"
        user["overrides"] = {"bars": {"count": 33}, "panel": {"radius": 20}}
        write_user(user)
        path = str(self.dir / "out.json")
        self.assertEqual(helper.write_preset_file(path, user), "neon")
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o644)
        before = helper.effective_design(user)
        found = helper.read_preset_file(path)
        self.assertEqual(found["design"], before)
        self.assertEqual(helper.apply_design({"type": "importPreset", **found}, user), None)
        self.assertEqual(user["preset"], "neon 2")
        self.assertEqual(user["overrides"], {})
        self.assertEqual(helper.effective_design(user), before)

    def test_export_refuses_other_files(self):
        user = helper.read_user()
        for bad in (str(self.dir / "notes.txt"), "relative.json"):
            with self.assertRaises(helper.PresetFileError) as cm:
                helper.write_preset_file(bad, user)
            self.assertEqual(cm.exception.code, "file_bad_path")
        os.mkdir(self.dir / "dir.json")
        target = self.dir / "real.json"
        target.write_text("keep")
        os.symlink(target, self.dir / "link.json")
        for special in ("dir.json", "link.json"):
            with self.assertRaises(helper.PresetFileError) as cm:
                helper.write_preset_file(str(self.dir / special), user)
            self.assertEqual(cm.exception.code, "file_unwritable")
        self.assertEqual(target.read_text(), "keep")
        self.assertEqual([f for f in os.listdir(self.dir) if f.startswith(".npv-preset-")], [])

    def test_import_respects_the_preset_limit(self):
        user = helper.read_user()
        user["presets"] = {f"p{i}": {} for i in range(helper.MAX_PRESETS)}
        self.assertEqual(helper.apply_design({"type": "importPreset", "design": {}, "name": "x"}, user),
                         "preset_limit")

    async def test_import_through_the_helper(self):
        path = self.file("Cool Look.json", {"bars": {"count": 50, "bogus": 1}})
        ws = FakeWs({"type": "importPreset", "path": path})
        await helper.handler(ws)
        result = ws.replies("presetFile")[-1]
        self.assertEqual(result, {"type": "presetFile", "op": "import", "name": "Cool Look", "ignored": 1})
        user = helper.read_user()
        self.assertEqual(user["preset"], "Cool Look")
        self.assertEqual(user["presets"]["Cool Look"], {"bars": {"count": 50}})

    async def test_a_client_cant_skip_the_file(self):
        # "design" in the message is ignored: only what is read from a file counts
        ws = FakeWs({"type": "importPreset", "design": {"bars": {"count": 99}}, "name": "x"})
        await helper.handler(ws)
        self.assertEqual(ws.replies("presetFile")[-1]["error"], "file_bad_path")
        self.assertNotIn("x", helper.read_user().get("presets", {}))

    async def test_export_through_the_helper(self):
        path = str(self.dir / "mine.json")
        ws = FakeWs({"type": "exportPreset", "path": path}, {"type": "exportPreset", "path": "/etc/x.json"})
        await helper.handler(ws)
        ok, failed = ws.replies("presetFile")
        self.assertEqual(ok, {"type": "presetFile", "op": "export", "name": "lookas"})
        self.assertEqual(json.loads(Path(path).read_text())["format"], helper.PRESET_FORMAT)
        self.assertEqual(failed["error"], "file_unwritable")


if __name__ == "__main__":
    unittest.main()
