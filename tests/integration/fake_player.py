#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""A minimal MPRIS player for the integration tests, on the session bus.

    fake_player.py NAME IDENTITY [--playing] [--no-shuffle-loop] [--no-control]

--no-shuffle-loop leaves the Shuffle and LoopStatus properties out entirely,
like Firefox, Zen and Chromium do. Writes to Shuffle / LoopStatus are kept
and announced with PropertiesChanged, like a real player. Each write is also
printed to stdout as "SET <property> <value>", so a test can see it.

Needs PyGObject (python-gobject). Runs until killed.
"""
import argparse
import sys

from gi.repository import Gio, GLib

ROOT = "org.mpris.MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
PATH = "/org/mpris/MediaPlayer2"


def introspection(shuffle_loop):
    extra = ""
    if shuffle_loop:
        extra = """
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="LoopStatus" type="s" access="readwrite"/>"""
    return f"""
<node>
  <interface name="{ROOT}">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="{PLAYER}">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
    <method name="SetPosition"><arg name="TrackId" type="o" direction="in"/><arg name="Position" type="x" direction="in"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="read"/>
    <property name="Metadata" type="a{{sv}}" access="read"/>
    <property name="Volume" type="d" access="read"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>{extra}
  </interface>
</node>"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("identity")
    ap.add_argument("--playing", action="store_true")
    ap.add_argument("--no-shuffle-loop", action="store_true")
    ap.add_argument("--no-control", action="store_true")
    args = ap.parse_args()

    shuffle_loop = not args.no_shuffle_loop
    control = not args.no_control
    state = {
        "PlaybackStatus": GLib.Variant("s", "Playing" if args.playing else "Paused"),
        "Shuffle": GLib.Variant("b", False),
        "LoopStatus": GLib.Variant("s", "None"),
    }
    metadata = GLib.Variant("a{sv}", {
        "mpris:trackid": GLib.Variant("o", "/org/mpris/MediaPlayer2/track/1"),
        "mpris:length": GLib.Variant("x", 180_000_000),
        "xesam:title": GLib.Variant("s", f"{args.identity} song"),
        "xesam:artist": GLib.Variant("as", [f"{args.identity} artist"]),
        "xesam:album": GLib.Variant("s", "Album"),
    })
    fixed = {
        ROOT: {
            "Identity": GLib.Variant("s", args.identity),
            "DesktopEntry": GLib.Variant("s", args.name),
            "CanRaise": GLib.Variant("b", False),
            "CanQuit": GLib.Variant("b", False),
            "HasTrackList": GLib.Variant("b", False),
            "SupportedUriSchemes": GLib.Variant("as", []),
            "SupportedMimeTypes": GLib.Variant("as", []),
        },
        PLAYER: {
            "Rate": GLib.Variant("d", 1.0),
            "Metadata": metadata,
            "Volume": GLib.Variant("d", 1.0),
            "Position": GLib.Variant("x", 1_000_000),
            "MinimumRate": GLib.Variant("d", 1.0),
            "MaximumRate": GLib.Variant("d", 1.0),
            "CanGoNext": GLib.Variant("b", control),
            "CanGoPrevious": GLib.Variant("b", control),
            "CanPlay": GLib.Variant("b", control),
            "CanPause": GLib.Variant("b", control),
            "CanSeek": GLib.Variant("b", control),
            "CanControl": GLib.Variant("b", control),
        },
    }
    node = Gio.DBusNodeInfo.new_for_xml(introspection(shuffle_loop))
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def changed(prop):
        conn.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                         GLib.Variant("(sa{sv}as)", (PLAYER, {prop: state[prop]}, [])))

    def on_call(conn, sender, path, iface, method, params, invocation):
        if method == "PlayPause":
            playing = state["PlaybackStatus"].unpack() == "Playing"
            state["PlaybackStatus"] = GLib.Variant("s", "Paused" if playing else "Playing")
            changed("PlaybackStatus")
        print("CALL", method, flush=True)
        invocation.return_value(None)

    def on_get(conn, sender, path, iface, prop):
        if prop in state and iface == PLAYER:
            return state[prop]
        return fixed[iface].get(prop)

    def on_set(conn, sender, path, iface, prop, value):
        if prop == "LoopStatus" and value.unpack() not in ("None", "Playlist", "Track"):
            return False
        state[prop] = value
        print("SET", prop, value.unpack(), flush=True)
        changed(prop)
        return True

    for iface in node.interfaces:
        conn.register_object(PATH, iface, on_call, on_get, on_set)
    Gio.bus_own_name_on_connection(conn, "org.mpris.MediaPlayer2." + args.name, Gio.BusNameOwnerFlags.NONE, None, None)
    print("READY", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    sys.exit(main())
