#!/usr/bin/env python3
"""Control Sony WH-1000XM5 headphones (Sony MDR v2 protocol) over Bluetooth RFCOMM.

Speaks the reverse-engineered "Serial HPC" protocol exposed by Sony headphones
(service UUID 956C7B26-D49A-4BA8-B03F-B17D393CB6E2, usually RFCOMM channel 9).

Wire format (a "Tandem" frame):

    0x3E  ESCAPE( <dataType:1> <seq:1> <size:4 BE> <payload> <checksum:1> )  0x3C

* checksum = 8-bit wrapping sum of dataType .. end of payload, before escaping
* 0x3C / 0x3D / 0x3E inside the body are escaped as 0x3D 0x2C / 0x3D 0x2D / 0x3D 0x2E
* every received non-ACK frame must be ACKed with sequence 1 - receivedSeq
* the shared sequence counter follows the device (set from every received frame)

Protocol documentation and byte layouts come from the public reverse-engineering
work in mos9527/SonyHeadphonesClient (libmdr, MIT) and the mdr-protocol project.

Usage:
  xm5.py status  [--json]                 # connect, read state, print
  xm5.py noise   {off|anc|ambient}
  xm5.py ambient-level N
  xm5.py focus-on-voice on|off
  xm5.py speak-to-chat on|off
  xm5.py dsee    on|off
  xm5.py connection {quality|stable}
  xm5.py volume  N
  xm5.py power-off
  xm5.py daemon                           # long-running, serves control.sock
"""

import argparse
import errno
import json
import os
import select
import socket
import sys
import tempfile
import threading
import time

DEFAULT_ADDRESS = "AC:80:0A:87:CD:36"
DEFAULT_CHANNEL = 9
STATE_HOME = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "noctalia-xm5"
)

START, END, ESC = 0x3E, 0x3C, 0x3D
DATA_MDR = 0x0C
DATA_MDR_NO2 = 0x0E
ACK = 0x01

# Data table 1 command ids
C_CONNECT_GET_PROTOCOL_INFO = 0x00
C_CONNECT_RET_PROTOCOL_INFO = 0x01
C_CONNECT_GET_CAPABILITY_INFO = 0x02
C_CONNECT_RET_CAPABILITY_INFO = 0x03
C_CONNECT_GET_DEVICE_INFO = 0x04
C_CONNECT_RET_DEVICE_INFO = 0x05
C_CONNECT_GET_SUPPORT_FUNCTION = 0x06
C_CONNECT_RET_SUPPORT_FUNCTION = 0x07
C_POWER_GET_STATUS = 0x22
C_POWER_RET_STATUS = 0x23
C_POWER_SET_STATUS = 0x24
C_POWER_NTFY_STATUS = 0x25
C_NCASM_GET_PARAM = 0x66
C_NCASM_RET_PARAM = 0x67
C_NCASM_SET_PARAM = 0x68
C_NCASM_NTFY_PARAM = 0x69
C_AUDIO_GET_PARAM = 0xE6
C_AUDIO_RET_PARAM = 0xE7
C_AUDIO_SET_PARAM = 0xE8
C_AUDIO_NTFY_PARAM = 0xE9
C_SYSTEM_GET_PARAM = 0xF6
C_SYSTEM_RET_PARAM = 0xF7
C_SYSTEM_SET_PARAM = 0xF8
C_SYSTEM_NTFY_PARAM = 0xF9
C_SYSTEM_GET_EXT_PARAM = 0xFA
C_SYSTEM_RET_EXT_PARAM = 0xFB
C_SYSTEM_SET_EXT_PARAM = 0xFC
C_SYSTEM_NTFY_EXT_PARAM = 0xFD
C_PLAY_GET_PARAM = 0xA6
C_PLAY_RET_PARAM = 0xA7
C_PLAY_SET_PARAM = 0xA8
C_PLAY_NTFY_PARAM = 0xA9

# Support-function types (table 1)
F_BATTERY = 0x20
F_POWER_OFF = 0x23
F_AUTO_POWER_OFF_WEARING = 0x25
F_NCASM_BASE = 0x61  # .. 0x6D
F_CONNECTION_MODE = 0xE1
F_CONNECTION_MODE_LDAC = 0xE3
F_UPSCALING = 0xE2
F_SMART_TALKING1 = 0xF2
F_SMART_TALKING2 = 0xFC
F_PLAYBACK_CTRL = 0xA1

# NCASM inquired types
NCASM_NC_ON_OFF = 0x01
NCASM_ONOFF_ASM_ONOFF = 0x11
NCASM_MODESWITCH_ASM_SEAMLESS = 0x14
NCASM_DUAL_NC_MODESWITCH_ASM_SEAMLESS = 0x17
NCASM_DUAL_NC_MODESWITCH_ASM_SEAMLESS_NA = 0x19

# NCASM values
NcAsmTotalEffect = {"off": 0, "on": 1}
NcAsmMode = {"nc": 0, "asm": 1}
AmbientSoundMode = {"normal": 0, "voice": 1}

# AUDIO inquired types
AUDIO_CONNECTION_MODE = 0x00
AUDIO_UPSCALING = 0x01

PRIOR_MODE = {"sound_quality": 0x00, "connection_quality": 0x01}
PRIOR_MODE_NAMES = {v: k for k, v in PRIOR_MODE.items()}
UPSCALING_AUTO_OFF = {"off": 0x00, "auto": 0x01}

DETECT_SENSITIVITY = {"auto": 0x00, "high": 0x01, "low": 0x02}
MODE_OUT_TIME = {"fast": 0x00, "mid": 0x01, "slow": 0x02, "none": 0x03}
# EnableDisable is INVERTED relative to OnOff: ENABLE = 0, DISABLE = 1
ENABLE_DISABLE = {"on": 0x00, "off": 0x01}

PLAY_MUSIC_VOLUME = 0x20


class ProtocolError(Exception):
    pass


class DeviceError(Exception):
    pass


def _escape(data):
    out = bytearray()
    for b in data:
        if b in (0x3C, 0x3D, 0x3E):
            out.append(ESC)
            out.append(b & 0xEF)
        else:
            out.append(b)
    return bytes(out)


def _unescape(data):
    out = bytearray()
    i = 0
    while i < len(data):
        if data[i] == ESC:
            if i + 1 >= len(data):
                raise ProtocolError("trailing escape byte")
            out.append(data[i + 1] | 0x10)
            i += 2
        else:
            out.append(data[i])
            i += 1
    return bytes(out)


def build_frame(data_type, seq, payload):
    body = bytes([data_type, seq]) + len(payload).to_bytes(4, "big") + bytes(payload)
    body += bytes([sum(body) & 0xFF])
    return bytes([START]) + _escape(body) + bytes([END])


def split_frames(buf):
    frames = []
    i = 0
    while True:
        s = buf.find(START, i)
        if s < 0:
            return frames, b""
        e = buf.find(END, s + 1)
        if e < 0:
            return frames, buf[s:]
        body = _unescape(buf[s + 1 : e])
        if len(body) >= 7:
            size = int.from_bytes(body[2:6], "big")
            frames.append((body[0], body[1], body[6 : 6 + size]))
        i = e + 1


class Frame:
    __slots__ = ("data_type", "seq", "payload")

    def __init__(self, data_type, seq, payload):
        self.data_type = data_type
        self.seq = seq
        self.payload = payload

    @property
    def command(self):
        return self.payload[0] if self.payload else None

    def __repr__(self):
        return f"<Frame dt={self.data_type:#04x} seq={self.seq} {bytes(self.payload).hex()}>"


class Session:
    def __init__(self, address, channel=DEFAULT_CHANNEL, debug=False):
        self.address = address
        self.channel = channel
        self.debug = debug
        self.sock = None
        self.buf = b""
        self.seq = 0
        self.supports = set()
        self.supports_table1 = False
        self.supports_table2 = False
        self.model = None
        self.firmware = None
        self._lock = threading.RLock()

    # -- low level -------------------------------------------------------
    def _log(self, *a):
        if self.debug:
            print(*a, file=sys.stderr, flush=True)

    def connect(self, timeout=6.0):
        sock = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM)
        sock.setblocking(False)
        err = sock.connect_ex((self.address, self.channel))
        if err not in (0, errno.EINPROGRESS, errno.EAGAIN, errno.EALREADY):
            sock.close()
            raise DeviceError(f"could not open RFCOMM channel {self.channel}: {os.strerror(err)}")
        if err != 0:
            _, writable, _ = select.select([], [sock], [], timeout)
            if not writable:
                sock.close()
                raise DeviceError(
                    f"timed out opening RFCOMM channel {self.channel} to {self.address}"
                )
            so_error = sock.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
            if so_error != 0:
                sock.close()
                raise DeviceError(
                    f"could not open RFCOMM channel {self.channel}: {os.strerror(so_error)}"
                )
        sock.setblocking(True)
        sock.settimeout(0.3)
        self.sock = sock
        self.buf = b""
        self.seq = 0
        self._handshake()

    def close(self):
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None

    @property
    def alive(self):
        return self.sock is not None

    def _emit(self, data_type, seq, payload):
        frame = build_frame(data_type, seq, bytes(payload))
        self._log("  ->", frame.hex())
        self.sock.send(frame)

    def _send(self, payload, data_type=DATA_MDR):
        self._emit(data_type, self.seq, payload)

    def _recv_frames(self, timeout, match=None):
        """Collect frames for up to `timeout` seconds, ACKing as we go.

        Returns early as soon as a frame satisfies `match` (if given).
        """
        frames = []
        deadline = time.time() + timeout
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                break
            self.sock.settimeout(min(0.3, remaining))
            try:
                data = self.sock.recv(8192)
            except socket.timeout:
                continue
            except OSError as exc:
                raise DeviceError(f"connection lost: {exc}") from exc
            if not data:
                raise DeviceError("device closed the connection")
            self.buf += data
            parsed, self.buf = split_frames(self.buf)
            for data_type, seq, payload in parsed:
                self.seq = seq
                if data_type == ACK:
                    continue
                self._log("  <-", bytes([data_type, seq]).hex(), bytes(payload).hex())
                self._emit(ACK, 1 - seq, b"")
                frame = Frame(data_type, seq, payload)
                frames.append(frame)
                if match is not None and match(frame):
                    return frames
        return frames

    def request(self, payload, response_command, timeout=3.0):
        self._send(bytes(payload))
        frames = self._recv_frames(
            timeout,
            match=lambda f: f.data_type == DATA_MDR and f.command == response_command,
        )
        for frame in frames:
            if frame.data_type == DATA_MDR and frame.command == response_command:
                return frame
        raise DeviceError(
            f"no response for cmd {payload[0]:#04x} (expected {response_command:#04x})"
        )

    # -- handshake -------------------------------------------------------
    def _handshake(self):
        self.request([C_CONNECT_GET_PROTOCOL_INFO, 0x00], C_CONNECT_RET_PROTOCOL_INFO)
        self.supports_table1 = True
        try:
            self._send([C_CONNECT_GET_CAPABILITY_INFO, 0x00])
            self._recv_frames(0.6)
        except DeviceError:
            pass

        for info_type, attr in ((0x01, "model"), (0x02, "firmware")):
            try:
                frame = self.request(
                    [C_CONNECT_GET_DEVICE_INFO, info_type], C_CONNECT_RET_DEVICE_INFO, timeout=2.0
                )
                length = frame.payload[2]
                value = bytes(frame.payload[3 : 3 + length]).decode("utf-8", "replace")
                setattr(self, attr, value)
            except (DeviceError, IndexError):
                pass

        frame = self.request(
            [C_CONNECT_GET_SUPPORT_FUNCTION, 0x00], C_CONNECT_RET_SUPPORT_FUNCTION, timeout=3.0
        )
        count = frame.payload[2]
        funcs = frame.payload[3:]
        self.supports = set()
        for i in range(count):
            idx = i * 2
            if idx < len(funcs):
                self.supports.add(funcs[idx])
        if 0x00 in self.supports or any(0x20 <= f <= 0x2F for f in self.supports):
            self.supports_table1 = True

    def supports_function(self, *funcs):
        return any(f in self.supports for f in funcs)

    @property
    def ncasam_type(self):
        if 0x6D in self.supports:
            return NCASM_DUAL_NC_MODESWITCH_ASM_SEAMLESS_NA
        if 0x6B in self.supports:
            return NCASM_DUAL_NC_MODESWITCH_ASM_SEAMLESS
        if 0x6A in self.supports:
            return 0x16
        if 0x68 in self.supports:
            return 0x15
        if 0x64 in self.supports:
            return 0x13
        if 0x62 in self.supports:
            return NCASM_ONOFF_ASM_ONOFF
        if 0x61 in self.supports:
            return NCASM_NC_ON_OFF
        if 0x67 in self.supports:
            return 0x22
        if 0x66 in self.supports:
            return 0x21
        return None

    @property
    def stc_type(self):
        if F_SMART_TALKING2 in self.supports:
            return 0x0C
        if F_SMART_TALKING1 in self.supports:
            return 0x02
        return None

    # -- reads -----------------------------------------------------------
    def read(self):
        state = {
            "connected": True,
            "address": self.address,
            "model": self.model,
            "firmware": self.firmware,
            "capabilities": {
                "noise": self.ncasam_type is not None,
                "speak_to_chat": self.stc_type is not None,
                "dsee": self.supports_function(F_UPSCALING),
                "connection": self.supports_function(F_CONNECTION_MODE, F_CONNECTION_MODE_LDAC),
                "volume": self.supports_function(F_PLAYBACK_CTRL),
                "power_off": self.supports_function(F_POWER_OFF),
                "battery": self.supports_function(F_BATTERY),
            },
        }
        readers = [
            ("battery", self.read_battery),
            ("noise", self.read_noise),
            ("dsee", self.read_dsee),
            ("connection", self.read_connection),
            ("speak_to_chat", self.read_stc),
            ("volume", self.read_volume),
        ]
        for key, reader in readers:
            if not state["capabilities"].get(key):
                continue
            try:
                state.update(reader())
            except (DeviceError, IndexError, ProtocolError) as exc:
                self._log(f"read {key} failed: {exc}")
        return state

    def read_battery(self):
        frame = self.request([C_POWER_GET_STATUS, 0x00], C_POWER_RET_STATUS)
        charging = {0: "not_charging", 1: "charging", 2: "unknown", 3: "charged"}
        return {
            "battery": frame.payload[2],
            "charging": charging.get(frame.payload[3], "unknown"),
        }

    def read_noise(self):
        ntype = self.ncasam_type
        frame = self.request([C_NCASM_GET_PARAM, ntype], C_NCASM_RET_PARAM)
        p = frame.payload
        # [cmd][type][changeStatus][totalEffect][ncAsmMode][ambientSoundMode][level]...
        total = p[3]
        mode = p[4]
        asm_mode = p[5]
        level = p[6] if len(p) > 6 else 0
        if total == 0:
            noise = "off"
        elif mode == NcAsmMode["nc"]:
            noise = "anc"
        else:
            noise = "ambient"
        return {
            "noise": noise,
            "ambient_level": level,
            "focus_on_voice": asm_mode == AmbientSoundMode["voice"],
        }

    def read_dsee(self):
        frame = self.request([C_AUDIO_GET_PARAM, AUDIO_UPSCALING], C_AUDIO_RET_PARAM)
        return {"dsee": frame.payload[2] == UPSCALING_AUTO_OFF["auto"]}

    def read_connection(self):
        itype = 0x02 if F_CONNECTION_MODE_LDAC in self.supports else AUDIO_CONNECTION_MODE
        frame = self.request([C_AUDIO_GET_PARAM, itype], C_AUDIO_RET_PARAM)
        return {"connection": PRIOR_MODE_NAMES.get(frame.payload[2], "unknown")}

    def read_stc(self):
        stype = self.stc_type
        frame = self.request([C_SYSTEM_GET_PARAM, stype], C_SYSTEM_RET_PARAM)
        result = {"speak_to_chat": frame.payload[2] == ENABLE_DISABLE["on"]}
        try:
            ext = self.request([C_SYSTEM_GET_EXT_PARAM, stype], C_SYSTEM_RET_EXT_PARAM, timeout=2.0)
            names = {v: k for k, v in DETECT_SENSITIVITY.items()}
            times = {v: k for k, v in MODE_OUT_TIME.items()}
            result["stc_sensitivity"] = names.get(ext.payload[2], "auto")
            result["stc_mode_off"] = times.get(ext.payload[3], "mid")
        except (DeviceError, IndexError):
            pass
        return result

    def read_volume(self):
        frame = self.request([C_PLAY_GET_PARAM, PLAY_MUSIC_VOLUME], C_PLAY_RET_PARAM)
        return {"volume": frame.payload[2]}

    # -- writes ----------------------------------------------------------
    def set_noise(self, mode, level=None, focus=None):
        if mode not in ("off", "anc", "ambient"):
            raise ValueError("mode must be off|anc|ambient")
        ntype = self.ncasam_type
        if ntype is None:
            raise DeviceError("device does not support noise control")
        current = self.read_noise()
        if level is None:
            level = current["ambient_level"]
        if focus is None:
            focus = current["focus_on_voice"]
        level = max(0, min(20, int(level)))
        total = NcAsmTotalEffect["off"] if mode == "off" else NcAsmTotalEffect["on"]
        nc_mode = NcAsmMode["asm"] if mode == "ambient" else NcAsmMode["nc"]
        asm_mode = AmbientSoundMode["voice"] if focus else AmbientSoundMode["normal"]
        payload = [C_NCASM_SET_PARAM, ntype, 0x01, total, nc_mode, asm_mode, level]
        if ntype == NCASM_DUAL_NC_MODESWITCH_ASM_SEAMLESS_NA:
            payload += [0x00, 0x00]
        self._send(payload)
        self._recv_frames(0.8)

    def set_ambient_level(self, level):
        # Sony's own app switches to ambient sound when the level slider moves,
        # so the new level is audible immediately (and actually persisted).
        current = self.read_noise()
        self.set_noise("ambient", level=level, focus=current["focus_on_voice"])

    def set_focus_on_voice(self, enabled):
        # Focus on Voice only applies to ambient sound; write it in ambient
        # mode so the device actually stores it (Sony's app does the same).
        current = self.read_noise()
        mode = current["noise"] if current["noise"] == "ambient" else "ambient"
        self.set_noise(mode, focus=bool(enabled))

    def set_dsee(self, enabled):
        value = UPSCALING_AUTO_OFF["auto"] if enabled else UPSCALING_AUTO_OFF["off"]
        self._send([C_AUDIO_SET_PARAM, AUDIO_UPSCALING, value])
        self._recv_frames(0.8)

    def set_connection(self, mode):
        if mode not in PRIOR_MODE:
            raise ValueError("mode must be sound_quality|connection_quality")
        itype = 0x02 if F_CONNECTION_MODE_LDAC in self.supports else AUDIO_CONNECTION_MODE
        self._send([C_AUDIO_SET_PARAM, itype, PRIOR_MODE[mode]])
        self._recv_frames(0.8)

    def set_speak_to_chat(self, enabled):
        stype = self.stc_type
        if stype is None:
            raise DeviceError("device does not support speak-to-chat")
        value = ENABLE_DISABLE["on"] if enabled else ENABLE_DISABLE["off"]
        self._send([C_SYSTEM_SET_PARAM, stype, value, 0x01])
        self._recv_frames(0.8)

    def set_volume(self, volume):
        volume = max(0, min(100, int(volume)))
        self._send([C_PLAY_SET_PARAM, PLAY_MUSIC_VOLUME, volume])
        self._recv_frames(0.8)

    def power_off(self):
        self._send([C_POWER_SET_STATUS, 0x03, 0x01])
        self._recv_frames(0.5)


def open_session(address, channel, debug=False, retries=6, pause=0.7):
    """Connect, retrying while the single control channel is still in use."""
    last = None
    for attempt in range(retries):
        session = Session(address, channel, debug=debug)
        try:
            session.connect()
            return session
        except DeviceError as exc:
            session.close()
            last = exc
            if attempt + 1 < retries:
                time.sleep(pause)
    raise last


def with_session(args, action):
    """Run `action(session)` against a freshly connected device."""
    session = open_session(args.address, args.channel, debug=args.debug)
    try:
        return action(session)
    finally:
        session.close()


def print_status(state):
    print(json.dumps(state, indent=2, sort_keys=True))


# --------------------------------------------------------------------------
# daemon
# --------------------------------------------------------------------------
class Daemon:
    def __init__(self, address, channel, state_file, socket_file, poll, idle_timeout, debug):
        self.address = address
        self.channel = channel
        self.state_file = state_file
        self.socket_file = socket_file
        self.poll = poll
        self.idle_timeout = idle_timeout
        self.debug = debug
        self.session = None
        self.state = {"connected": False, "address": address}
        self.last_command = 0.0
        self.lock = threading.RLock()
        self.stop = threading.Event()

    def log(self, *a):
        if self.debug:
            print("[xm5d]", *a, file=sys.stderr, flush=True)

    def publish(self):
        os.makedirs(os.path.dirname(self.state_file), exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(self.state_file))
        with os.fdopen(fd, "w") as fh:
            json.dump(self.state, fh)
        os.replace(tmp, self.state_file)

    def ensure(self):
        with self.lock:
            if self.session and self.session.alive:
                return self.session
            try:
                self.session = open_session(self.address, self.channel, debug=self.debug)
                self.log("connected")
            except DeviceError as exc:
                self.session = None
                self.state = {"connected": False, "address": self.address, "error": str(exc)}
                self.publish()
                raise
            return self.session

    def refresh(self):
        # serialise all session I/O: the poller thread and client requests must
        # never read/write the one RFCOMM socket at the same time.
        with self.lock:
            try:
                session = self.ensure()
                state = session.read()
                state["idle_disconnect"] = self.idle_timeout
                self.state = state
            except (DeviceError, ProtocolError, OSError) as exc:
                self.log("refresh failed:", exc)
                if self.session is not None:
                    self.session.close()
                    self.session = None
                self.state = {"connected": False, "address": self.address, "error": str(exc)}
            self.publish()
            return self.state

    def disconnect(self):
        if self.session:
            self.session.close()
            self.session = None
            self.log("disconnected (idle)")
        if self.state.get("connected"):
            self.state = dict(self.state)
            self.state["connected"] = False
            self.publish()

    def handle(self, request):
        cmd = request.get("cmd")
        self.last_command = time.time()
        if cmd in ("refresh", "connect"):
            return self.refresh()
        with self.lock:
            return self._apply(cmd, request)

    def _apply(self, cmd, request):
        session = self.ensure()
        try:
            if cmd == "noise":
                session.set_noise(
                    request["mode"], level=request.get("level"), focus=request.get("focus")
                )
            elif cmd == "ambient-level":
                session.set_ambient_level(request["level"])
            elif cmd == "focus-on-voice":
                session.set_focus_on_voice(request["value"])
            elif cmd == "dsee":
                session.set_dsee(request["value"])
            elif cmd == "connection":
                session.set_connection(request["mode"])
            elif cmd == "speak-to-chat":
                session.set_speak_to_chat(request["value"])
            elif cmd == "volume":
                session.set_volume(request["level"])
            elif cmd == "power-off":
                session.power_off()
                self.state = {"connected": False, "address": self.address, "powered_off": True}
                self.publish()
                self.session.close()
                self.session = None
                return self.state
            else:
                return {"ok": False, "error": f"unknown command {cmd!r}"}
        except (DeviceError, ValueError) as exc:
            return {"ok": False, "error": str(exc)}
        # let the device settle and push its notification, then re-read
        time.sleep(0.4)
        return self.refresh()

    def serve(self):
        if os.path.exists(self.socket_file):
            os.unlink(self.socket_file)
        os.makedirs(os.path.dirname(self.socket_file), exist_ok=True)
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(self.socket_file)
        server.listen(16)
        server.settimeout(1.0)
        self.last_command = time.time()
        # publish a placeholder immediately so the widget has something to read
        self.state = {"connected": False, "address": self.address, "error": "connecting\u2026"}
        self.publish()
        threading.Thread(target=self.poller, daemon=True).start()
        self.refresh()
        try:
            while not self.stop.is_set():
                try:
                    conn, _ = server.accept()
                except socket.timeout:
                    continue
                with conn:
                    conn.settimeout(30.0)
                    data = b""
                    try:
                        while not data.endswith(b"\n"):
                            chunk = conn.recv(4096)
                            if not chunk:
                                break
                            data += chunk
                    except (socket.timeout, OSError):
                        pass
                    if not data.strip():
                        continue
                    try:
                        request = json.loads(data.decode())
                    except ValueError:
                        self._reply(conn, {"ok": False, "error": "bad json"})
                        continue
                    try:
                        result = self.handle(request)
                    except DeviceError as exc:
                        result = {"ok": False, "error": str(exc)}
                    except Exception as exc:  # never let one client kill the daemon
                        self.log("request failed:", repr(exc))
                        result = {"ok": False, "error": str(exc)}
                    self._reply(conn, result)
        finally:
            server.close()
            try:
                os.unlink(self.socket_file)
            except OSError:
                pass
            self.disconnect()

    @staticmethod
    def _reply(conn, result):
        try:
            conn.sendall(json.dumps(result).encode() + b"\n")
        except OSError:
            # client hung up before we answered; nothing to do
            pass

    def poller(self):
        last_poll = time.time()
        while not self.stop.is_set():
            time.sleep(1.0)
            idle = time.time() - self.last_command
            if self.idle_timeout > 0 and idle > self.idle_timeout:
                if self.session:
                    self.disconnect()
                continue
            # keep_alive (idle_timeout <= 0) polls unconditionally so a dropped
            # link reconnects; otherwise only refresh while a link is open.
            if self.idle_timeout > 0 and not self.alive_ok():
                continue
            if time.time() - last_poll >= self.poll:
                last_poll = time.time()
                try:
                    self.refresh()
                except DeviceError:
                    pass

    def alive_ok(self):
        return bool(self.session and self.session.alive)


def send_command(socket_file, request, timeout=15.0):
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(timeout)
        client.connect(socket_file)
    except OSError as exc:
        raise DeviceError(f"daemon not running ({exc})") from exc
    try:
        client.sendall(json.dumps(request).encode() + b"\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = client.recv(4096)
            if not chunk:
                break
            data += chunk
        return json.loads(data.decode()) if data.strip() else None
    finally:
        client.close()


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def default_args():
    return {
        "address": DEFAULT_ADDRESS,
        "channel": DEFAULT_CHANNEL,
        "debug": False,
        "state_file": os.path.join(STATE_HOME, "status.json"),
        "socket_file": os.path.join(STATE_HOME, "control.sock"),
        "poll": 30,
        "idle_timeout": 90,
    }


def build_parser():
    p = argparse.ArgumentParser(description="Sony WH-1000XM5 (MDR v2) control")
    p.add_argument("--address", default=DEFAULT_ADDRESS)
    p.add_argument("--channel", type=int, default=DEFAULT_CHANNEL)
    p.add_argument("--debug", action="store_true")
    p.add_argument("--state-file", default=os.path.join(STATE_HOME, "status.json"))
    p.add_argument("--socket-file", default=os.path.join(STATE_HOME, "control.sock"))
    sub = p.add_subparsers(dest="command", required=True)

    s = sub.add_parser("status")
    s.add_argument("--json", action="store_true")
    s.add_argument("--direct", action="store_true", help="ignore the daemon, talk directly")

    sub.add_parser("noise").add_argument("mode", choices=["off", "anc", "ambient"])
    sub.add_parser("ambient-level").add_argument("level", type=int)
    sub.add_parser("focus-on-voice").add_argument("value", choices=["on", "off"])
    sub.add_parser("speak-to-chat").add_argument("value", choices=["on", "off"])
    sub.add_parser("dsee").add_argument("value", choices=["on", "off"])
    sub.add_parser("connection").add_argument("mode", choices=["quality", "stable"])
    sub.add_parser("volume").add_argument("level", type=int)
    sub.add_parser("power-off")

    d = sub.add_parser("daemon")
    d.add_argument("--poll", type=int, default=30)
    d.add_argument("--idle-timeout", type=int, default=90)
    return p


def cli_requests(args):
    if args.command == "noise":
        return {"cmd": "noise", "mode": args.mode}
    if args.command == "ambient-level":
        return {"cmd": "ambient-level", "level": args.level}
    if args.command == "focus-on-voice":
        return {"cmd": "focus-on-voice", "value": args.value == "on"}
    if args.command == "speak-to-chat":
        return {"cmd": "speak-to-chat", "value": args.value == "on"}
    if args.command == "dsee":
        return {"cmd": "dsee", "value": args.value == "on"}
    if args.command == "connection":
        return {"cmd": "connection", "mode": "sound_quality" if args.mode == "stable" else "connection_quality"}
    if args.command == "volume":
        return {"cmd": "volume", "level": args.level}
    if args.command == "power-off":
        return {"cmd": "power-off"}
    return None


def main(argv=None):
    args = build_parser().parse_args(argv)

    if args.command == "daemon":
        handle = {
            "address": args.address,
            "channel": args.channel,
            "state_file": args.state_file,
            "socket_file": args.socket_file,
            "poll": args.poll,
            "idle_timeout": args.idle_timeout,
            "debug": args.debug,
        }
        daemon = Daemon(**handle)
        try:
            daemon.serve()
        except KeyboardInterrupt:
            daemon.stop.set()
        return 0

    if args.command == "status":
        if not args.direct and os.path.exists(args.socket_file):
            try:
                result = send_command(args.socket_file, {"cmd": "refresh"})
                if result is not None:
                    print_status(result)
                    return 0
            except DeviceError:
                pass
        state = with_session(args, lambda s: s.read())
        print_status(state)
        return 0

    request = cli_requests(args)
    if request is not None and os.path.exists(args.socket_file):
        try:
            result = send_command(args.socket_file, request)
            if result is not None and not result.get("error"):
                print(json.dumps(result))
                return 0
        except DeviceError:
            pass

    # fallback: direct connection
    def action(session):
        cmd = args.command
        if cmd == "noise":
            session.set_noise(args.mode)
        elif cmd == "ambient-level":
            session.set_ambient_level(args.level)
        elif cmd == "focus-on-voice":
            session.set_focus_on_voice(args.value == "on")
        elif cmd == "speak-to-chat":
            session.set_speak_to_chat(args.value == "on")
        elif cmd == "dsee":
            session.set_dsee(args.value == "on")
        elif cmd == "connection":
            session.set_connection(
                "sound_quality" if args.mode == "stable" else "connection_quality"
            )
        elif cmd == "volume":
            session.set_volume(args.level)
        elif cmd == "power-off":
            session.power_off()
            return {"connected": False, "powered_off": True}
        time.sleep(0.4)
        return session.read()

    print(json.dumps(with_session(args, action)))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except DeviceError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
