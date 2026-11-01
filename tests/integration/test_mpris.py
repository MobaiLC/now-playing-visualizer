# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""The helper against real MPRIS players on a private session bus.

Run through tests/integration/run.sh, which starts the bus and the players.
It refuses to run on your normal session bus: it changes the players'
shuffle and repeat.
"""
import importlib
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

if os.environ.get("NPV_PRIVATE_BUS") != "1":
    raise SystemExit("run this through tests/integration/run.sh (it needs a private D-Bus session)")

ROOT = Path(__file__).resolve().parent.parent.parent
os.environ["XDG_CONFIG_HOME"] = tempfile.mkdtemp()
sys.path.insert(0, str(ROOT / "package" / "contents" / "code"))
helper = importlib.import_module("helper")

LOG_DIR = Path(os.environ["NPV_PLAYER_LOGS"])


def by_identity(identity):
    return next(p for p in helper.read_players() if p["identity"] == identity)


def wait_for(check, timeout=5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if check():
            return True
        time.sleep(0.1)
    return False


class MprisIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        helper.CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        helper.write_user(helper.default_user_config())
        helper.state["config"] = helper.load_config()

    def test_every_player_is_listed(self):
        names = {p["identity"] for p in helper.read_players()}
        self.assertTrue({"Spotifake", "Zenfake", "Lockedfake"} <= names, names)

    def test_shuffle_and_repeat_only_where_the_player_has_them(self):
        spotify, zen = by_identity("Spotifake"), by_identity("Zenfake")
        self.assertIs(spotify["shuffle"], False)
        self.assertEqual(spotify["loop"], "None")
        self.assertIsNone(zen["shuffle"])
        self.assertIsNone(zen["loop"])

    def test_shuffle_and_repeat_reach_the_player(self):
        helper.media_action("shuffle", True, by_identity("Spotifake"))
        self.assertTrue(wait_for(lambda: by_identity("Spotifake")["shuffle"] is True))
        for mode in ("Playlist", "Track", "None"):
            helper.media_action("loop", mode, by_identity("Spotifake"))
            self.assertTrue(wait_for(lambda: by_identity("Spotifake")["loop"] == mode), mode)
        helper.media_action("shuffle", False, by_identity("Spotifake"))
        self.assertTrue(wait_for(lambda: by_identity("Spotifake")["shuffle"] is False))

    def test_nothing_is_sent_to_players_without_them_or_without_control(self):
        helper.media_action("shuffle", True, by_identity("Zenfake"))
        helper.media_action("loop", "Track", by_identity("Zenfake"))
        helper.media_action("shuffle", True, by_identity("Lockedfake"))
        time.sleep(0.5)
        for name in ("zenfake", "lockedfake"):
            self.assertNotIn("SET", (LOG_DIR / f"{name}.log").read_text(), name)

    def test_pinned_player_is_picked(self):
        players = helper.read_players()
        self.assertEqual(helper.pick_player(players, "")["identity"], "Spotifake")  # the playing one
        self.assertEqual(helper.pick_player(players, "zenfake")["identity"], "Zenfake")

    def test_play_pause_goes_to_the_clients_player(self):
        helper.state["media_player"] = by_identity("Spotifake")
        helper.media_action("playPause", None, by_identity("Zenfake"))
        self.assertTrue(wait_for(lambda: "CALL PlayPause" in (LOG_DIR / "zenfake.log").read_text()))
        self.assertNotIn("CALL PlayPause", (LOG_DIR / "spotifake.log").read_text())
        helper.media_action("playPause", None, by_identity("Zenfake"))  # back to paused

    @unittest.skipUnless(os.environ.get("NPV_MPV") == "1", "mpv with mpv-mpris is not running")
    def test_real_mpv(self):
        mpv = by_identity("mpv")
        self.assertIsInstance(mpv["shuffle"], bool)
        self.assertIn(mpv["loop"], helper.LOOP_STATUSES)
        helper.media_action("loop", "Playlist", mpv)
        self.assertTrue(wait_for(lambda: by_identity("mpv")["loop"] == "Playlist"))
        helper.media_action("loop", "None", by_identity("mpv"))
        self.assertTrue(wait_for(lambda: by_identity("mpv")["loop"] == "None"))
        helper.media_action("shuffle", not mpv["shuffle"], by_identity("mpv"))
        self.assertTrue(wait_for(lambda: by_identity("mpv")["shuffle"] is (not mpv["shuffle"])))


if __name__ == "__main__":
    unittest.main(verbosity=2)
