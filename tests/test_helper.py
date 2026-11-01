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


if __name__ == "__main__":
    unittest.main()
