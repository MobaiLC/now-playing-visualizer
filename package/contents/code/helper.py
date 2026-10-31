#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 MobaiLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Now Playing Visualizer helper.

Runs a small WebSocket server on localhost that the plasmoid connects to. It:
  * reads ~/.config/nowplaying-viz/config.json, merges it with the built-in
    presets and pushes the result to the widget whenever the file changes;
  * routes the audio of the selected applications into a private PipeWire
    null sink (in parallel, the apps still play through your speakers);
  * runs CAVA on that sink (or on the whole system) and streams the bars.

Only one instance runs at a time (the port is the lock). It exits by itself
when no widget has been connected for a while.
"""

import asyncio
import base64
import copy
import hashlib
import json
import os
import re
import signal
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOST = "127.0.0.1"
PORT = int(os.environ.get("NPV_PORT", "47811"))
# CAVA asks PipeWire for this (non-existent) target in per-app mode, which
# also lets us find its capture stream among the nodes.
CAPTURE_TARGET = "nowplaying-viz-capture"
HERE = Path(__file__).resolve().parent
PRESETS_FILE = HERE / "presets.json"
SCHEMA_FILE = HERE / "schema.json"
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "nowplaying-viz"
CONFIG_FILE = CONFIG_DIR / "config.json"
CONFIG_VERSION = 2
IDLE_EXIT_SECONDS = 60
# --service: started by systemd, stays up (CAVA still only runs while needed)
SERVICE = "--service" in sys.argv
COLOR_RE = re.compile(r"^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
# our own messages are a few KB; anything bigger is not from the widget
MAX_MESSAGE = 256 * 1024
MAX_NAME = 128
MAX_APPS = 64

clients = set()
state = {
    "config": {},
    # problems shown on the widget: {"code": ..., "detail": ...}
    "issues": [],
    "runtime": {},
    "last_client": time.monotonic(),
}
cava_proc = None
cava_key = None
stop_future = None


def log(*args):
    print("[npv]", *args, file=sys.stderr, flush=True)


def deep_merge(base, extra):
    out = copy.deepcopy(base)
    for k, v in (extra or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def get_path(d, path, default=None):
    for k in path.split("."):
        if not isinstance(d, dict) or k not in d:
            return default
        d = d[k]
    return d


def set_path(d, path, value):
    keys = path.split(".")
    for k in keys[:-1]:
        if not isinstance(d.get(k), dict):
            d[k] = {}
        d = d[k]
    d[keys[-1]] = value


# ------------------------------------------------------------------ Schema --

def load_schema():
    return json.loads(SCHEMA_FILE.read_text())


def schema_defaults(schema):
    out = {}
    for key, spec in schema["options"].items():
        set_path(out, key, copy.deepcopy(spec["default"]))
    return out


def schema_for_clients():
    """Options as an ordered list: QML turns JSON objects into maps sorted by key."""
    schema = load_schema()
    return {
        "version": schema["version"],
        "tabs": schema["tabs"],
        "groups": schema["groups"],
        "options": [dict(spec, key=key) for key, spec in schema["options"].items()],
    }


_INVALID = object()


def coerce(value, spec):
    """Returns the value fixed to fit spec (clamped), or _INVALID."""
    t = spec["type"]
    if t == "bool":
        return value if isinstance(value, bool) else _INVALID
    if t in ("int", "real"):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return _INVALID
        if t == "int":
            value = int(round(value))
        lo, hi = spec.get("min"), spec.get("max")
        if lo is not None:
            value = max(lo, value)
        if hi is not None:
            value = min(hi, value)
        return value
    if t == "enum":
        return value if value in [v["value"] for v in spec["values"]] else _INVALID
    if t == "color":
        return value if isinstance(value, str) and COLOR_RE.match(value) else _INVALID
    if t == "colorOrAuto":
        ok = value == spec.get("auto") or (isinstance(value, str) and COLOR_RE.match(value))
        return value if ok else _INVALID
    if t == "colorList":
        ok = isinstance(value, list) and all(isinstance(c, str) and COLOR_RE.match(c) for c in value)
        return value if ok else _INVALID
    if t == "string":
        return value if isinstance(value, str) else _INVALID
    if t == "stringList":
        ok = isinstance(value, list) and all(isinstance(x, str) for x in value)
        return value if ok else _INVALID
    return value


def validate(eff, schema, issues):
    for key, spec in schema["options"].items():
        value = get_path(eff, key)
        fixed = coerce(value, spec)
        if fixed is _INVALID:
            issues.append({"code": "invalid_option", "detail": key})
            set_path(eff, key, copy.deepcopy(spec["default"]))
        elif fixed != value:
            issues.append({"code": "out_of_range", "detail": key})
            set_path(eff, key, fixed)


def migrate(user):
    """Upgrades an older config.json in place, one version at a time.
    Returns True if it changed. Add a step here whenever an option is renamed
    or its meaning changes, and bump CONFIG_VERSION."""
    version = user.get("version", 0)
    if version == CONFIG_VERSION:
        return False
    if version < 2:
        # panel.hideWhenNoPlayer (bool) became panel.whenIdle (enum). true was
        # the old default, so only an explicit false is carried over.
        sections = [user.get("overrides", {})] + list(user.get("presets", {}).values())
        for sec in sections:
            panel = sec.get("panel", {})
            if panel.pop("hideWhenNoPlayer", True) is False:
                panel["whenIdle"] = "last"
    user["version"] = CONFIG_VERSION
    return True


def default_user_config():
    return {
        "version": CONFIG_VERSION,
        "preset": "lookas",
        "audio": {"apps": []},
        "overrides": {},
        "presets": {},
    }


def to_qml_colors(v):
    """JSON uses web-style #RRGGBBAA; Qt wants #AARRGGBB."""
    if isinstance(v, dict):
        return {k: to_qml_colors(x) for k, x in v.items()}
    if isinstance(v, list):
        return [to_qml_colors(x) for x in v]
    if isinstance(v, str) and len(v) == 9 and v.startswith("#"):
        try:
            int(v[1:], 16)
            return "#" + v[7:] + v[1:7]
        except ValueError:
            pass
    return v


def load_config():
    schema = load_schema()
    builtin = json.loads(PRESETS_FILE.read_text())
    if not CONFIG_FILE.exists():
        CONFIG_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
        write_user(default_user_config())
    try:
        user = json.loads(CONFIG_FILE.read_text())
    except (OSError, json.JSONDecodeError) as e:
        # keep the previous config so a typo doesn't blank the widget
        state["issues"] = [{"code": "config_parse", "detail": str(e)}]
        return None
    if migrate(user):
        write_user(user)
    issues = []
    presets = deep_merge(builtin["presets"], user.get("presets", {}))
    name = user.get("preset", "lookas")
    if name not in presets:
        issues.append({"code": "preset_missing", "detail": name})
        name = "lookas"
    eff = deep_merge(schema_defaults(schema), presets[name])
    eff = deep_merge(eff, user.get("overrides", {}))
    eff["audio"] = deep_merge(eff.get("audio", {}), user.get("audio", {}))
    validate(eff, schema, issues)
    eff["presetName"] = name
    eff["presetList"] = sorted(presets)
    eff["userPresets"] = sorted(user.get("presets", {}))
    state["web"] = copy.deepcopy(eff)
    # every preset as it looks on its own, for the thumbnails in Design
    previews = []
    for pname in sorted(presets):
        pe = deep_merge(schema_defaults(schema), presets[pname])
        validate(pe, schema, [])
        previews.append({"name": pname, "user": pname in user.get("presets", {}), "config": pe})
    state["presets"] = previews
    state["issues"] = issues
    return to_qml_colors(eff)


def read_user():
    try:
        return json.loads(CONFIG_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return default_user_config()


def write_private(path, text):
    """Atomic write readable only by us, so the watcher never sees half a file."""
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def write_user(user):
    write_private(CONFIG_FILE, json.dumps(user, indent=2, ensure_ascii=False) + "\n")


def save_user_apps(apps):
    apps = list(dict.fromkeys(str(a).lower()[:MAX_NAME] for a in apps))[:MAX_APPS] if isinstance(apps, list) else []
    user = read_user()
    user.setdefault("audio", {})["apps"] = apps
    write_user(user)


# ------------------------------------------------------------ Edit session --
# The Design page applies changes live. While it is open the helper keeps a
# snapshot of the design so Cancel (or closing without Apply) can put it
# back, plus a history for Undo. Only design keys are covered: the Audio
# page saves immediately, like a normal toggle.

DESIGN_KEYS = ("preset", "overrides", "presets")
REVERT_GRACE = 1.5  # s; lets main.qml's commit (sent via Plasma's Apply) arrive
edit = {"owner": None, "snapshot": None, "history": [], "last_push": 0.0, "revert": None}


def design_of(user):
    return {k: copy.deepcopy(user.get(k)) for k in DESIGN_KEYS}


def restore_design(design):
    user = read_user()
    for k, v in design.items():
        if v is None:
            user.pop(k, None)
        else:
            user[k] = v
    write_user(user)


def begin_edit(ws):
    if edit["revert"]:
        edit["revert"].cancel()
    edit.update(owner=ws, snapshot=design_of(read_user()), history=[], last_push=0.0, revert=None)


def commit_edit():
    if edit["owner"] is not None:
        edit.update(snapshot=design_of(read_user()), history=[])
    if edit["revert"]:
        edit["revert"].cancel()
        edit.update(owner=None, snapshot=None, revert=None)


def push_history(kind):
    """Remember the design before a change; slider drags coalesce into one step."""
    now = time.monotonic()
    if kind == "setDesign" and now - edit["last_push"] < 0.8 and edit["history"]:
        edit["last_push"] = now
        return
    edit["history"].append(design_of(read_user()))
    del edit["history"][:-50]
    edit["last_push"] = now


def edit_state():
    dirty = edit["snapshot"] is not None and design_of(read_user()) != edit["snapshot"]
    return {"type": "editState", "dirty": dirty, "canUndo": bool(edit["history"])}


def end_edit_later(ws):
    """The Design page went away: revert unless the edit gets committed."""
    if edit["owner"] is not ws:
        return

    def revert():
        if edit["snapshot"] is not None and design_of(read_user()) != edit["snapshot"]:
            log("settings closed without Apply: reverting the design")
            restore_design(edit["snapshot"])
        edit.update(owner=None, snapshot=None, history=[], revert=None)

    edit["revert"] = asyncio.get_running_loop().call_later(REVERT_GRACE, revert)


def apply_design(msg):
    """Changes coming from the Design settings page."""
    user = read_user()
    kind = msg.get("type")
    overrides = user.setdefault("overrides", {})
    if kind == "setDesign":
        # only known options with valid values reach config.json
        options = load_schema()["options"]
        changes = msg.get("changes")
        for path, value in (changes.items() if isinstance(changes, dict) else []):
            spec = options.get(path)
            if spec is None:
                continue
            fixed = coerce(value, spec)
            if fixed is not _INVALID:
                set_path(overrides, path, fixed)
    elif kind == "setPreset":
        user["preset"] = str(msg.get("name", "lookas"))[:MAX_NAME]
        # bar settings belong to the preset; keep panel tweaks like hidden header
        overrides.pop("bars", None)
    elif kind == "resetDesign":
        user["overrides"] = {}
    elif kind == "savePreset":
        name = str(msg.get("name", "")).strip()
        if not name or len(name) > MAX_NAME:
            return
        builtin = json.loads(PRESETS_FILE.read_text())
        presets = deep_merge(builtin["presets"], user.get("presets", {}))
        base = presets.get(user.get("preset", "lookas"), {})
        user.setdefault("presets", {})[name] = deep_merge(base, overrides)
        user["preset"] = name
        user["overrides"] = {}
    elif kind == "deletePreset":
        name = str(msg.get("name", ""))
        user.get("presets", {}).pop(name, None)
        if user.get("preset") == name:
            user["preset"] = "lookas"
    write_user(user)


# --------------------------------------------------------------- WebSocket --
# Minimal RFC 6455 server on the standard library only, so a Python package
# update can never break the widget.

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class WsClosed(Exception):
    pass


class WsConn:
    def __init__(self, reader, writer):
        self.reader = reader
        self.writer = writer
        self.closed = False
        self.lock = asyncio.Lock()
        # None = everything; the settings pages only ask for config/schema
        self.topics = None

    async def handshake(self):
        head = await asyncio.wait_for(self.reader.readuntil(b"\r\n\r\n"), 5)
        headers = {}
        for line in head.decode("latin-1").split("\r\n")[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        key = headers.get("sec-websocket-key")
        if not key:
            raise WsClosed("not a websocket request")
        # Browsers always send Origin and Qt's WebSocket never does: this keeps
        # web pages (and DNS rebinding) from talking to the helper.
        if "origin" in headers or headers.get("host") not in (f"{HOST}:{PORT}", f"localhost:{PORT}"):
            self.writer.write(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
            await self.writer.drain()
            raise WsClosed("rejected origin " + headers.get("origin", "") + " host " + headers.get("host", ""))
        accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
        self.writer.write(("HTTP/1.1 101 Switching Protocols\r\n"
                           "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                           f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode())
        await self.writer.drain()

    async def _frame(self, opcode, payload):
        n = len(payload)
        if n < 126:
            head = struct.pack("!BB", 0x80 | opcode, n)
        elif n < 65536:
            head = struct.pack("!BBH", 0x80 | opcode, 126, n)
        else:
            head = struct.pack("!BBQ", 0x80 | opcode, 127, n)
        async with self.lock:
            if self.closed:
                raise WsClosed()
            self.writer.write(head + payload)
            await self.writer.drain()

    async def send(self, text):
        await self._frame(0x1, text.encode())

    async def recv(self):
        message = b""
        while True:
            b1, b2 = await self.reader.readexactly(2)
            opcode, masked, n = b1 & 0x0F, b2 & 0x80, b2 & 0x7F
            if n == 126:
                n = struct.unpack("!H", await self.reader.readexactly(2))[0]
            elif n == 127:
                n = struct.unpack("!Q", await self.reader.readexactly(8))[0]
            if len(message) + n > MAX_MESSAGE:
                raise WsClosed("message too big")
            mask = await self.reader.readexactly(4) if masked else b"\0\0\0\0"
            data = await self.reader.readexactly(n)
            if masked and n:
                full = (mask * (n // 4 + 1))[:n]
                data = (int.from_bytes(data, "big") ^ int.from_bytes(full, "big")).to_bytes(n, "big")
            if opcode == 0x8:
                raise WsClosed()
            if opcode == 0x9:
                await self._frame(0xA, bytes(data))
                continue
            if opcode == 0xA:
                continue
            message += data
            if b1 & 0x80:
                return message.decode(errors="replace")

    def __aiter__(self):
        return self

    async def __anext__(self):
        try:
            return await self.recv()
        except (WsClosed, asyncio.IncompleteReadError, ConnectionError):
            raise StopAsyncIteration

    def close(self):
        self.closed = True
        try:
            self.writer.close()
        except Exception:
            pass


# ---------------------------------------------------------------- PipeWire --

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def pw_dump():
    r = run(["pw-dump"])
    if r.returncode != 0:
        return []
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return []


def app_key(props):
    return (props.get("application.process.binary") or props.get("application.name") or "").lower()


def icon_name(name):
    """Theme icon names only: a path or URL here would make the settings page
    load whatever file or address an app puts in its stream properties."""
    return name if re.fullmatch(r"[\w.+-]{1,128}", name) else ""


def list_audio_apps(objs):
    """Applications currently producing audio, one entry per app."""
    apps = {}
    for o in objs:
        if o.get("type") != "PipeWire:Interface:Node":
            continue
        p = (o.get("info") or {}).get("props") or {}
        if p.get("media.class") != "Stream/Output/Audio":
            continue
        key = app_key(p)
        if not key or key == "cava":
            continue
        apps.setdefault(key, {
            "id": key,
            "name": p.get("application.name") or key,
            "icon": icon_name(p.get("application.icon-name") or p.get("application.process.binary") or ""),
        })
    return list(apps.values())


def remove_legacy_sink():
    """Versions before 0.2 routed audio through a null sink that showed up in
    the system sound menu; unload it if it is still around."""
    r = run(["pactl", "list", "short", "modules"])
    for line in r.stdout.splitlines():
        if "module-null-sink" in line and "sink_name=nowplaying_viz" in line:
            run(["pactl", "unload-module", line.split()[0]])


def sync_links(apps):
    """Per-app audio: link the selected apps straight into CAVA's capture
    stream and drop every other link into it (WirePlumber's fallback link to
    the default microphone included). No virtual device is created."""
    objs = pw_dump()
    wanted = {a.lower() for a in apps}
    nodes, ports, links = {}, {}, []
    for o in objs:
        t, info = o.get("type"), o.get("info") or {}
        p = info.get("props") or {}
        if t == "PipeWire:Interface:Node":
            nodes[o["id"]] = p
        elif t == "PipeWire:Interface:Port":
            ports[o["id"]] = (info.get("direction"), p)
        elif t == "PipeWire:Interface:Link":
            links.append((info.get("output-port-id"), info.get("input-port-id")))
    capture = {i for i, p in nodes.items() if p.get("target.object") == CAPTURE_TARGET}
    if not capture:
        return
    cava_in = {}
    for pid, (d, p) in ports.items():
        if d == "input" and p.get("node.id") in capture:
            cava_in.setdefault(p.get("audio.channel"), []).append(pid)
    desired = set()
    for pid, (d, p) in ports.items():
        if d != "output":
            continue
        node = nodes.get(p.get("node.id"))
        if not node or node.get("media.class") != "Stream/Output/Audio" or app_key(node) not in wanted:
            continue
        ch = p.get("audio.channel")
        if ch in cava_in:
            targets = cava_in[ch]
        elif ch == "MONO":
            targets = [t for ts in cava_in.values() for t in ts]
        else:
            targets = []
        for t in targets:
            desired.add((pid, t))
    existing = set(links)
    capture_ports = {t for ts in cava_in.values() for t in ts}
    for out, inp in existing - desired:
        if inp in capture_ports:
            run(["pw-link", "-d", str(out), str(inp)])
    for out, inp in desired - existing:
        run(["pw-link", str(out), str(inp)])


# ------------------------------------------------------------ MPRIS (D-Bus) --
# Fallback used only when Plasma's private MPRIS QML module can't be loaded.

MPRIS_PATH = "/org/mpris/MediaPlayer2"


def busctl_json(*args):
    r = run(["busctl", "--user", "--json=short", *args])
    out = []
    for line in r.stdout.splitlines():
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return out


def busctl_prop(name, iface, prop, default=None):
    res = busctl_json("get-property", name, MPRIS_PATH, iface, prop)
    return res[0]["data"] if res else default


def read_media():
    names = busctl_json("call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
                        "org.freedesktop.DBus", "ListNames")
    names = [n for n in (names[0]["data"][0] if names else []) if n.startswith("org.mpris.MediaPlayer2.")]
    players = []
    for n in names:
        player_iface = "org.mpris.MediaPlayer2.Player"
        meta = busctl_prop(n, player_iface, "Metadata", {})
        meta = {k: v.get("data") for k, v in meta.items()} if isinstance(meta, dict) else {}
        artist = meta.get("xesam:artist") or []
        players.append({
            "bus": n,
            "track": meta.get("xesam:title") or "",
            "artist": ", ".join(artist) if isinstance(artist, list) else str(artist),
            "album": meta.get("xesam:album") or "",
            "artUrl": meta.get("mpris:artUrl") or "",
            "length": meta.get("mpris:length") or 0,
            "identity": busctl_prop(n, "org.mpris.MediaPlayer2", "Identity", n.split(".")[-1]),
            "position": busctl_prop(n, player_iface, "Position", 0),
            "rate": busctl_prop(n, player_iface, "Rate", 1) or 1,
            "playing": busctl_prop(n, player_iface, "PlaybackStatus", "") == "Playing",
            "trackId": meta.get("mpris:trackid") or "/org/mpris/MediaPlayer2/TrackList/NoTrack",
            "canControl": bool(busctl_prop(n, player_iface, "CanControl", False)),
            "canGoNext": bool(busctl_prop(n, player_iface, "CanGoNext", False)),
            "canGoPrevious": bool(busctl_prop(n, player_iface, "CanGoPrevious", False)),
            "canSeek": bool(busctl_prop(n, player_iface, "CanSeek", False)),
            "canRaise": bool(busctl_prop(n, "org.mpris.MediaPlayer2", "CanRaise", False)),
        })
        players[-1]["canPlayPause"] = players[-1]["canControl"] and bool(
            busctl_prop(n, player_iface, "CanPause", False) or busctl_prop(n, player_iface, "CanPlay", False))
    preferred = [p.lower() for p in state["config"].get("panel", {}).get("preferredPlayers", [])]
    is_pref = lambda p: any(x in (p["identity"] + " " + p["bus"]).lower() for x in preferred)
    for test in (lambda p: p["playing"] and is_pref(p), lambda p: p["playing"], is_pref, lambda p: True):
        for p in players:
            if test(p):
                state["media_player"] = p
                return p
    state["media_player"] = None
    return None


def media_action(action, value):
    """Player controls for the D-Bus fallback (same actions as MprisSource.qml)."""
    p = state.get("media_player")
    if not p:
        return
    iface = "org.mpris.MediaPlayer2.Player"
    call = ["busctl", "--user", "call", p["bus"], MPRIS_PATH]
    if action in ("playPause", "next", "previous"):
        method = {"playPause": "PlayPause", "next": "Next", "previous": "Previous"}[action]
        run(call + [iface, method])
    elif action == "raise":
        run(call + ["org.mpris.MediaPlayer2", "Raise"])
    elif action == "seek" and isinstance(value, (int, float)) and not isinstance(value, bool):
        run(call + [iface, "SetPosition", "ox", p["trackId"], str(max(0, int(value)))])
    elif action == "volume" and isinstance(value, (int, float)) and not isinstance(value, bool):
        vol = busctl_prop(p["bus"], iface, "Volume", None)
        if isinstance(vol, (int, float)):
            new = min(1.0, max(0.0, vol + float(value)))
            run(["busctl", "--user", "set-property", p["bus"], MPRIS_PATH, iface, "Volume", "d", str(new)])


async def media_loop():
    while True:
        if state.get("media_wanted") and clients and state["config"]:
            data = await asyncio.to_thread(read_media)
            await broadcast(json.dumps({"type": "media", "data": data}), "media")
        await asyncio.sleep(1)


# -------------------------------------------------------------------- CAVA --

def cava_config(cfg):
    a, b = cfg.get("audio", {}), cfg.get("bars", {})
    source = CAPTURE_TARGET if a.get("apps") else "auto"
    lines = [
        "[general]",
        f"framerate={int(b.get('framerate', 60))}",
        f"bars={int(b.get('count', 24))}",
        f"lower_cutoff_freq={int(a.get('lowCutoff', 50))}",
        f"higher_cutoff_freq={int(a.get('highCutoff', 12000))}",
        "autosens=1",
        f"sensitivity={int(a.get('sensitivity', 100))}",
        "sleep_timer=0",
        "[input]",
        "method=pipewire",
        f"source={source}",
        # no "recording" indicator in the system tray for our capture stream
        "virtual=1",
        "[output]",
        "method=raw",
        "raw_target=/dev/stdout",
        "data_format=ascii",
        "ascii_max_range=1000",
        f"channels={'stereo' if b.get('stereo') else 'mono'}",
        "mono_option=average",
        "[smoothing]",
        f"noise_reduction={int(a.get('noiseReduction', 77))}",
        f"monstercat={1 if b.get('monstercat') else 0}",
    ]
    return "\n".join(lines) + "\n"


def bar_clients():
    return [ws for ws in clients if ws.topics is None or "bars" in ws.topics]


async def broadcast(msg, topic):
    dead = []
    for ws in list(clients):
        if ws.topics is not None and topic not in ws.topics:
            continue
        try:
            await asyncio.wait_for(ws.send(msg), 1)
        except Exception:
            dead.append(ws)
    for ws in dead:
        clients.discard(ws)


async def set_error(code, detail=""):
    """Runtime problem with CAVA; code None clears it."""
    new = {"code": code, "detail": detail} if code else None
    if state["runtime"].get("cava") != new:
        state["runtime"]["cava"] = new
        await send_config()


async def cava_loop():
    global cava_proc, cava_key
    while True:
        cfg = state["config"]
        # CAVA only runs while some widget wants bars
        if not cfg or not bar_clients():
            await asyncio.sleep(0.5)
            continue
        conf = cava_config(cfg)
        cava_key = conf
        conf_path = CONFIG_DIR / ".cava.conf"
        write_private(conf_path, conf)
        started = time.monotonic()
        try:
            cava_proc = await asyncio.create_subprocess_exec(
                "cava", "-p", str(conf_path),
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        except FileNotFoundError:
            await set_error("cava_missing")
            await asyncio.sleep(10)
            continue
        if selected_apps():
            # drop WirePlumber's fallback link (the default mic) right away
            asyncio.get_running_loop().call_later(
                0.3, lambda: asyncio.ensure_future(asyncio.to_thread(sync_links, selected_apps())))
        got_data = False
        try:
            async for line in cava_proc.stdout:
                if not bar_clients():
                    break
                if not got_data:
                    got_data = True
                    await set_error(None)
                await broadcast("B" + line.decode().strip().rstrip(";"), "bars")
        finally:
            if cava_proc.returncode is None:
                cava_proc.kill()
            await cava_proc.wait()
            err = (await cava_proc.stderr.read()).decode().strip()
            if err and cava_key == conf:
                log("cava:", err)
                if not got_data:
                    await set_error("cava_error", err.splitlines()[-1][:120])
        # back off if CAVA keeps dying right away
        await asyncio.sleep(0.3 if time.monotonic() - started > 5 else 3)


def restart_cava_if_needed():
    if cava_proc and cava_proc.returncode is None and cava_key != cava_config(state["config"]):
        cava_proc.terminate()


async def send_config(ws=None):
    issues = state["issues"] + [v for v in state["runtime"].values() if v]
    msg = json.dumps({"type": "config", "data": state["config"], "web": state.get("web", {}), "issues": issues})
    previews = json.dumps({"type": "presets", "data": state.get("presets", [])})
    if ws:
        await ws.send(msg)
        if ws.topics is not None and "presets" in ws.topics:
            await ws.send(previews)
    else:
        await broadcast(msg, "config")
        await broadcast(previews, "presets")


async def config_watch_loop():
    mtime = None
    while True:
        try:
            m = CONFIG_FILE.stat().st_mtime if CONFIG_FILE.exists() else None
        except OSError:
            m = None
        if m != mtime or not state["config"]:
            mtime = m
            try:
                cfg = load_config()
            except Exception as e:
                # a broken config.json must never stop the watcher
                log("config:", repr(e))
                state["issues"] = [{"code": "config_parse", "detail": type(e).__name__}]
                cfg = None
            if cfg is not None:
                state["config"] = cfg
                restart_cava_if_needed()
            await send_config()
            mtime = CONFIG_FILE.stat().st_mtime if CONFIG_FILE.exists() else None
        await asyncio.sleep(0.5)


def selected_apps():
    return state["config"].get("audio", {}).get("apps", []) if state["config"] else []


async def link_loop():
    # only does work while CAVA runs in per-app mode (i.e. a widget is open)
    while True:
        if cava_proc and cava_proc.returncode is None and selected_apps():
            await asyncio.to_thread(sync_links, selected_apps())
        await asyncio.sleep(1)


async def idle_loop(stop):
    while True:
        await asyncio.sleep(5)
        if clients:
            state["last_client"] = time.monotonic()
        elif not SERVICE and time.monotonic() - state["last_client"] > IDLE_EXIT_SECONDS:
            log("no widgets connected, exiting")
            stop.set_result(None)
            return


async def accept(reader, writer):
    ws = WsConn(reader, writer)
    try:
        await ws.handshake()
    except Exception:
        ws.close()
        return
    try:
        await handler(ws)
    except (ConnectionError, WsClosed, asyncio.IncompleteReadError):
        pass  # the other side went away; nothing to clean up beyond close()
    finally:
        ws.close()


async def handler(ws):
    clients.add(ws)
    try:
        await ws.send(json.dumps({"type": "schema", "data": schema_for_clients()}))
        await send_config(ws)
        async for raw in ws:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if not isinstance(msg, dict):
                continue
            if msg.get("type") == "listApps":
                apps = await asyncio.to_thread(lambda: list_audio_apps(pw_dump()))
                await ws.send(json.dumps({"type": "apps", "data": apps}))
            elif msg.get("type") == "quit" and not SERVICE:
                log("handing over to the systemd service")
                stop_future.done() or stop_future.set_result(None)
            elif msg.get("type") == "subscribe":
                ws.topics = set(msg.get("topics") or [])
                if "presets" in ws.topics:
                    await ws.send(json.dumps({"type": "presets", "data": state.get("presets", [])}))
            elif msg.get("type") == "wantMedia":
                state["media_wanted"] = True
            elif msg.get("type") == "mediaAction" and msg.get("action") in (
                    "playPause", "next", "previous", "raise", "seek", "volume"):
                await asyncio.to_thread(media_action, msg["action"], msg.get("value"))
            elif msg.get("type") == "setApps":
                save_user_apps(msg.get("apps"))
            elif msg.get("type") in ("setDesign", "setPreset", "resetDesign", "savePreset", "deletePreset"):
                if edit["owner"] is ws:
                    push_history(msg["type"])
                apply_design(msg)
                await ws.send(json.dumps(edit_state()))
            elif msg.get("type") == "beginEdit":
                begin_edit(ws)
                await ws.send(json.dumps(edit_state()))
            elif msg.get("type") == "commitEdit":
                commit_edit()
                if edit["owner"] is ws:
                    await ws.send(json.dumps(edit_state()))
            elif msg.get("type") == "undo" and edit["owner"] is ws and edit["history"]:
                restore_design(edit["history"].pop())
                await ws.send(json.dumps(edit_state()))
    finally:
        clients.discard(ws)
        end_edit_later(ws)
        state["last_client"] = time.monotonic()


async def ask_to_quit():
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection(HOST, PORT), 2)
        key = base64.b64encode(os.urandom(16)).decode()
        writer.write((f"GET / HTTP/1.1\r\nHost: {HOST}:{PORT}\r\nUpgrade: websocket\r\n"
                      f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
                      "Sec-WebSocket-Version: 13\r\n\r\n").encode())
        await writer.drain()
        await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 2)
        payload = json.dumps({"type": "quit"}).encode()
        mask = os.urandom(4)
        writer.write(struct.pack("!BB", 0x81, 0x80 | len(payload)) + mask
                     + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))
        await writer.drain()
        # stay connected until the old helper hangs up: it only reads our
        # message after sending its greeting (schema + config)
        try:
            await asyncio.wait_for(reader.read(), 3)
        except asyncio.TimeoutError:
            pass
        writer.close()
    except Exception as e:
        log("could not ask the running helper to quit:", e)


async def main():
    global stop_future
    await asyncio.to_thread(remove_legacy_sink)
    loop = asyncio.get_running_loop()
    stop = stop_future = loop.create_future()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, lambda: stop.done() or stop.set_result(None))
    server = None
    for attempt in range(10):
        try:
            server = await asyncio.start_server(accept, HOST, PORT)
            break
        except OSError:
            if not SERVICE:
                log("already running")
                return
            # the systemd service takes over from a helper the widget started
            if attempt == 0:
                await ask_to_quit()
            await asyncio.sleep(0.5)
    if server is None:
        log("port still busy, giving up")
        sys.exit(1)
    tasks = [asyncio.create_task(c) for c in (cava_loop(), config_watch_loop(), link_loop(), media_loop(), idle_loop(stop))]
    async with server:
        await stop
    for t in tasks:
        t.cancel()
    if cava_proc and cava_proc.returncode is None:
        cava_proc.kill()


if __name__ == "__main__":
    asyncio.run(main())
