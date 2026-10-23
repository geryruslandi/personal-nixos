import argparse
import datetime
import fcntl
import glob
import json
import os
import sys
import time

_IOC_NRSHIFT = 0
_IOC_TYPESHIFT = 8
_IOC_SIZESHIFT = 16
_IOC_DIRSHIFT = 30
_IOC_WRITE = 1
_IOC_READ = 2


def _IOC(direction, t, nr, size):
    return (
        (direction << _IOC_DIRSHIFT)
        | (size << _IOC_SIZESHIFT)
        | (t << _IOC_TYPESHIFT)
        | (nr << _IOC_NRSHIFT)
    )


HIDIOCSFEATURE = _IOC(_IOC_WRITE | _IOC_READ, 0x48, 0x06, 65)
HIDIOCGFEATURE = _IOC(_IOC_WRITE | _IOC_READ, 0x48, 0x07, 65)

VENDOR = b"v00003151"
SCREEN_CHANNEL = bytes.fromhex("06ffff0902a101")
FEATURE_64 = bytes.fromhex("95407508b102")

CMD_SET_LEDPARAM = 0x07
CMD_GET_LEDPARAM = 0x87
CMD_SET_SLEEPTIME = 0x11
CMD_SET_OLEDCLOCK = 0x28
CMD_SET_OLEDOPTION = 0x22
CMD_SET_OLEDLANGUAGE = 0x27
CMD_SET_OLEDEFFECT = 0x2B
CMD_GET_OLEDEFFECT = 0xAB
CMD_GETOLED_VERSION = 0xAD

CHECKSUM_BIT7 = "bit7"
CHECKSUM_BIT8 = "bit8"
CHECKSUM_NONE = "none"

EFFECTS = {
    "off": 0,
    "static": 1,
    "breath": 2,
    "wave": 4,
    "rainbow": 16,
}

SCREEN_MODES = {
    "off": 0,
    "clock": 64,
    "cpu": 65,
}

MAX_SPEED = 4
MAX_BRIGHTNESS = 4
NORMAL = 7
DAZZLE = 8


def _clamp(value, low, high):
    return max(low, min(high, int(value)))


def _read_file(path, mode="r"):
    with open(path, mode) as handle:
        return handle.read()


def _parse_uevent(path):
    values = {}
    try:
        for line in _read_file(path).splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value
    except OSError:
        pass
    return values


def _hid_identity(uevent):
    hid_id = uevent.get("HID_ID", "")
    parts = hid_id.split(":")
    if len(parts) == 3:
        try:
            vid = "%04x" % int(parts[1], 16)
            pid = "%04x" % int(parts[2], 16)
            return vid, pid
        except ValueError:
            pass
    return "", ""


class DeviceInfo:
    def __init__(self, path, vid, pid, name):
        self.path = path
        self.vid = vid
        self.pid = pid
        self.name = name

    def as_dict(self):
        return {
            "path": self.path,
            "vid": self.vid,
            "pid": self.pid,
            "name": self.name,
        }


def find_devices():
    devices = []
    for entry in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        device_dir = os.path.join(entry, "device")
        try:
            modalias = _read_file(os.path.join(device_dir, "modalias"), "rb")
            descriptor = _read_file(
                os.path.join(device_dir, "report_descriptor"), "rb"
            )
        except OSError:
            continue
        if VENDOR not in modalias:
            continue
        if SCREEN_CHANNEL not in descriptor or FEATURE_64 not in descriptor:
            continue
        uevent = _parse_uevent(os.path.join(device_dir, "uevent"))
        vid, pid = _hid_identity(uevent)
        devices.append(
            DeviceInfo(
                "/dev/" + os.path.basename(entry),
                vid,
                pid,
                uevent.get("HID_NAME", ""),
            )
        )
    return devices


def _checksum(frame, kind):
    if kind == CHECKSUM_BIT7:
        frame[7] = (0xFF - (sum(frame[0:7]) & 0xFF)) & 0xFF
    elif kind == CHECKSUM_BIT8:
        frame[8] = (0xFF - (sum(frame[0:8]) & 0xFF)) & 0xFF


def _frame(values):
    frame = bytearray(64)
    for index, value in enumerate(values):
        if index >= len(frame):
            break
        frame[index] = int(value) & 0xFF
    return frame


def _put_u16(frame, offset, value):
    value = _clamp(value, 0, 0xFFFF)
    frame[offset] = value & 0xFF
    frame[offset + 1] = (value >> 8) & 0xFF


class Device:
    def __init__(self, path):
        self.path = path

    def send(self, frame, checksum=CHECKSUM_BIT7, settle=0.02):
        frame = bytearray(frame)
        if len(frame) < 64:
            frame.extend(b"\x00" * (64 - len(frame)))
        frame = frame[:64]
        _checksum(frame, checksum)
        if settle > 0:
            time.sleep(settle)
        descriptor = os.open(self.path, os.O_RDWR)
        try:
            fcntl.ioctl(descriptor, HIDIOCSFEATURE, b"\x00" + bytes(frame))
        finally:
            os.close(descriptor)

    def read(self, settle=0.05):
        if settle > 0:
            time.sleep(settle)
        descriptor = os.open(self.path, os.O_RDWR)
        try:
            buffer = bytearray(65)
            fcntl.ioctl(descriptor, HIDIOCGFEATURE, buffer)
            return bytes(buffer[1:])
        finally:
            os.close(descriptor)

    def request(
        self, frame, checksum=CHECKSUM_BIT7, attempts=3, require_echo=True
    ):
        self.send(frame, checksum)
        for attempt in range(attempts):
            try:
                response = self.read(settle=0.08)
            except OSError:
                continue
            if response and (not require_echo or response[0] == frame[0]):
                return response
        return None

    def read_light(self):
        response = self.request(_frame([CMD_GET_LEDPARAM]), CHECKSUM_BIT7)
        if response is None or response[0] != CMD_GET_LEDPARAM:
            return None
        mode = response[1]
        speed = MAX_SPEED - response[2]
        brightness = response[3]
        flags = response[4]
        color = (response[5] << 16) | (response[6] << 8) | response[7]
        return {
            "mode": mode,
            "speed": speed,
            "brightness": brightness,
            "dazzle": (flags & 0x0F) == DAZZLE,
            "color": "#%06x" % color,
        }

    def read_screen(self):
        response = self.request(
            _frame([CMD_GET_OLEDEFFECT]), CHECKSUM_BIT7, require_echo=False
        )
        if response is None:
            return None
        return response[1]

    def read_oled_version(self):
        response = self.request(_frame([CMD_GETOLED_VERSION]), CHECKSUM_BIT7)
        if response is None or response[0] != CMD_GETOLED_VERSION:
            return None
        return {
            "oled": (response[2] << 8) | response[1],
            "flash": (response[4] << 8) | response[3],
        }


def open_device(path=None):
    if path:
        if os.path.exists(path):
            return Device(path)
        return None
    devices = find_devices()
    if not devices:
        return None
    return Device(devices[0].path)


def parse_color(value):
    if not isinstance(value, str):
        return (137, 180, 250)
    text = value.strip().lstrip("#")
    if len(text) == 3:
        text = "".join(ch * 2 for ch in text)
    if len(text) != 6:
        return (137, 180, 250)
    try:
        number = int(text, 16)
    except ValueError:
        return (137, 180, 250)
    return ((number >> 16) & 0xFF, (number >> 8) & 0xFF, number & 0xFF)


def format_color(red, green, blue):
    return "#%02x%02x%02x" % (red, green, blue)


def rgb_frame(effect, color, brightness, speed):
    red, green, blue = parse_color(color)
    mode = EFFECTS.get(effect, EFFECTS["static"])
    flags = NORMAL
    if effect == "rainbow":
        flags = DAZZLE
    return _frame(
        [
            CMD_SET_LEDPARAM,
            mode,
            MAX_SPEED - _clamp(speed, 0, MAX_SPEED),
            _clamp(brightness, 0, MAX_BRIGHTNESS),
            flags,
            red,
            green,
            blue,
        ]
    )


def sleep_frame():
    frame = _frame([CMD_SET_SLEEPTIME])
    _put_u16(frame, 8, 120)
    _put_u16(frame, 10, 120)
    _put_u16(frame, 12, 1680)
    _put_u16(frame, 14, 1680)
    return frame


def clock_frame(when=None):
    when = when or datetime.datetime.now()
    frame = _frame([CMD_SET_OLEDCLOCK])
    frame[8] = (when.year >> 8) & 0xFF
    frame[9] = when.year & 0xFF
    frame[10] = when.month
    frame[11] = when.day
    frame[12] = when.hour
    frame[13] = when.minute
    frame[14] = when.second
    return frame


def screen_frame(mode):
    return _frame(
        [
            CMD_SET_OLEDEFFECT,
            SCREEN_MODES.get(mode, SCREEN_MODES["clock"]),
            MAX_SPEED,
            4,
        ]
    )


def language_frame(language):
    value = 1 if language == "en" else 0
    return _frame([CMD_SET_OLEDLANGUAGE, value])


def stats_frame(values):
    frame = _frame([CMD_SET_OLEDOPTION])
    _put_u16(frame, 8, values.get("disk_available_gb", 0))
    _put_u16(frame, 10, values.get("disk_total_gb", 0))
    _put_u16(frame, 12, values.get("mem_used_gb", 0))
    _put_u16(frame, 14, values.get("mem_total_gb", 0))
    frame[16] = _clamp(values.get("cpu_usage", 0), 0, 100)
    frame[17] = _clamp(values.get("cpu_temp", 0), 0, 255)
    _put_u16(frame, 18, values.get("net_up_kb", 0))
    _put_u16(frame, 20, values.get("net_down_kb", 0))
    return frame


def _meminfo():
    values = {}
    try:
        for line in _read_file("/proc/meminfo").splitlines():
            key, rest = line.split(":", 1)
            values[key] = int(rest.strip().split()[0])
    except (OSError, ValueError, IndexError):
        pass
    return values


def _cpu_times():
    try:
        fields = _read_file("/proc/stat").splitlines()[0].split()[1:]
    except (OSError, IndexError):
        return None
    values = [int(field) for field in fields]
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    total = sum(values)
    return total, idle


def _cpu_usage(previous, current):
    if previous is None or current is None:
        return 0
    total_delta = current[0] - previous[0]
    idle_delta = current[1] - previous[1]
    if total_delta <= 0:
        return 0
    return _clamp(
        round(100.0 * (total_delta - idle_delta) / total_delta), 0, 100
    )


def _cpu_temp():
    values = []
    for name_path in glob.glob("/sys/class/hwmon/hwmon*/name"):
        try:
            name = _read_file(name_path).strip().lower()
        except OSError:
            continue
        if not any(
            token in name
            for token in ("k10temp", "coretemp", "zenpower", "cpu")
        ):
            continue
        base = os.path.dirname(name_path)
        for temp_path in glob.glob(os.path.join(base, "temp*_input")):
            try:
                values.append(int(_read_file(temp_path).strip()) / 1000.0)
            except (OSError, ValueError):
                pass
    if not values:
        for temp_path in glob.glob("/sys/class/thermal/thermal_zone*/temp"):
            try:
                values.append(int(_read_file(temp_path).strip()) / 1000.0)
            except (OSError, ValueError):
                pass
    if not values:
        return 0
    return _clamp(round(max(values)), 0, 255)


def _disk(path):
    try:
        info = os.statvfs(path)
    except OSError:
        return 0, 0
    total = info.f_blocks * info.f_frsize
    available = info.f_bavail * info.f_frsize
    return (
        int(round(available / (1024**3))),
        int(round(total / (1024**3))),
    )


def _network_totals():
    try:
        lines = _read_file("/proc/net/dev").splitlines()[2:]
    except OSError:
        return 0, 0
    received = 0
    transmitted = 0
    for line in lines:
        if ":" not in line:
            continue
        name, rest = line.split(":", 1)
        if name.strip() == "lo":
            continue
        fields = rest.split()
        if len(fields) < 9:
            continue
        received += int(fields[0])
        transmitted += int(fields[8])
    return received, transmitted


class StatsSampler:
    def __init__(self, disk_path="/", net_mode="rate", interval=1.0):
        self.disk_path = disk_path or "/"
        self.net_mode = net_mode if net_mode in ("rate", "total") else "rate"
        self.interval = max(0.2, float(interval))
        self.previous_cpu = _cpu_times()
        self.previous_net = _network_totals()
        self.previous_time = time.monotonic()

    def sample(self, interval=None):
        now = time.monotonic()
        elapsed = now - self.previous_time
        if elapsed < 0.2:
            time.sleep(0.2 - elapsed)
            now = time.monotonic()
            elapsed = now - self.previous_time
        current_cpu = _cpu_times()
        current_net = _network_totals()
        elapsed = max(0.001, elapsed)
        usage = _cpu_usage(self.previous_cpu, current_cpu)
        if self.net_mode == "rate":
            up = int((current_net[1] - self.previous_net[1]) / 1024 / elapsed)
            down = int(
                (current_net[0] - self.previous_net[0]) / 1024 / elapsed
            )
        else:
            up = int(current_net[1] / 1024)
            down = int(current_net[0] / 1024)
        self.previous_cpu = current_cpu
        self.previous_net = current_net
        self.previous_time = now

        mem = _meminfo()
        total_kb = mem.get("MemTotal", 0)
        available_kb = mem.get("MemAvailable", mem.get("MemFree", 0))
        disk_available, disk_total = _disk(self.disk_path)

        return {
            "cpu_usage": usage,
            "cpu_temp": _cpu_temp(),
            "mem_used_gb": int(round((total_kb - available_kb) / 1024 / 1024)),
            "mem_total_gb": int(round(total_kb / 1024 / 1024)),
            "disk_available_gb": disk_available,
            "disk_total_gb": disk_total,
            "net_up_kb": _clamp(up, 0, 0xFFFF),
            "net_down_kb": _clamp(down, 0, 0xFFFF),
        }


def _load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def _default_state():
    return {
        "rev": 0,
        "clock_seq": 0,
        "reconnect_seq": 0,
        "rgb": {
            "effect": "static",
            "color": "#89b4fa",
            "brightness": 4,
            "speed": 2,
        },
        "screen": {"mode": "clock", "language": "en"},
        "clock": {"enabled": True, "interval_s": 300},
        "stats": {"interval_s": 1, "disk_path": "/", "net_mode": "rate"},
    }


def _state_value(state, section, key, default):
    value = state.get(section, {})
    if isinstance(value, dict):
        return value.get(key, default)
    return default


def _print_json(data):
    print(json.dumps(data, separators=(",", ":")), flush=True)


def cmd_list(args):
    devices = [device.as_dict() for device in find_devices()]
    if args.json:
        _print_json(devices)
        return 0
    for device in devices:
        print(
            "%s  %s:%s  %s"
            % (device["path"], device["vid"], device["pid"], device["name"])
        )
    if not devices:
        print("no AK820 Max HE vendor interface found", file=sys.stderr)
        return 1
    return 0


def cmd_status(args):
    device = open_device(args.device)
    result = {"connected": False, "error": None}
    if device:
        info = None
        for candidate in find_devices():
            if candidate.path == device.path:
                info = candidate
                break
        result.update(
            {
                "connected": True,
                "path": device.path,
                "vid": info.vid if info else "",
                "pid": info.pid if info else "",
                "name": info.name if info else "",
            }
        )
        try:
            result["light"] = device.read_light()
            result["screen"] = device.read_screen()
            result["oled_version"] = device.read_oled_version()
        except OSError as error:
            result["error"] = str(error)
    if args.json:
        _print_json(result)
    else:
        print(json.dumps(result, indent=2))
    return 0 if result.get("connected") else 1


def cmd_rgb(args):
    device = open_device(args.device)
    if device is None:
        print("ak820ctl: keyboard not found", file=sys.stderr)
        return 1
    device.send(
        rgb_frame(args.effect, args.color, args.brightness, args.speed),
        CHECKSUM_BIT8,
        settle=0.05,
    )
    time.sleep(0.5)
    return 0


def cmd_screen(args):
    device = open_device(args.device)
    if device is None:
        print("ak820ctl: keyboard not found", file=sys.stderr)
        return 1
    device.send(screen_frame(args.mode), CHECKSUM_BIT8, settle=0.05)
    time.sleep(0.2)
    return 0


def cmd_language(args):
    device = open_device(args.device)
    if device is None:
        print("ak820ctl: keyboard not found", file=sys.stderr)
        return 1
    device.send(language_frame(args.language), CHECKSUM_BIT7)
    return 0


def cmd_clock(args):
    device = open_device(args.device)
    if device is None:
        print("ak820ctl: keyboard not found", file=sys.stderr)
        return 1
    device.send(clock_frame(), CHECKSUM_BIT7)
    return 0


def cmd_stats(args):
    device = open_device(args.device)
    if device is None:
        print("ak820ctl: keyboard not found", file=sys.stderr)
        return 1
    sampler = StatsSampler(args.disk, args.net_mode, args.interval)
    count = 0
    while True:
        values = sampler.sample()
        device.send(stats_frame(values), CHECKSUM_BIT7, settle=0.02)
        count += 1
        if not args.loop:
            _print_json(values)
            return 0
        if args.count and count >= args.count:
            return 0
        time.sleep(max(0.2, args.interval))


def cmd_raw(args):
    device = open_device(args.device)
    if device is None:
        print("ak820ctl: keyboard not found", file=sys.stderr)
        return 1
    frame = bytearray(64)
    payload = bytes.fromhex(args.hex)
    frame[: len(payload[:64])] = payload[:64]
    device.send(frame, args.checksum, settle=0)
    if args.read:
        response = device.read(settle=0)
        print(response.hex())
    return 0


def _apply_changes(device, state, previous):
    previous = dict(previous or {})
    if not previous:
        time.sleep(0.3)
        device.send(sleep_frame(), CHECKSUM_BIT7, settle=0.05)
        time.sleep(0.7)
        previous["sleep"] = True
    rgb = state.get("rgb", {})
    effect = rgb.get("effect", "static")
    if effect not in EFFECTS:
        effect = "static"
    rgb_key = (
        effect,
        rgb.get("color", "#89b4fa"),
        _clamp(rgb.get("brightness", 4), 0, MAX_BRIGHTNESS),
        _clamp(rgb.get("speed", 2), 0, MAX_SPEED),
    )
    if previous.get("rgb") != rgb_key:
        time.sleep(0.3)
        device.send(rgb_frame(*rgb_key), CHECKSUM_BIT8, settle=0.05)
        time.sleep(0.7)
        previous["rgb"] = rgb_key
    screen = state.get("screen", {})
    mode = screen.get("mode", "clock")
    if mode not in SCREEN_MODES:
        mode = "clock"
    if previous.get("screen") != mode:
        time.sleep(0.3)
        device.send(screen_frame(mode), CHECKSUM_BIT8, settle=0.05)
        time.sleep(0.7)
        previous["screen"] = mode
    language = screen.get("language", "en")
    if language in ("en", "zh") and previous.get("language") != language:
        time.sleep(0.3)
        device.send(language_frame(language), CHECKSUM_BIT7)
        time.sleep(0.3)
        previous["language"] = language
    return previous


def cmd_daemon(args):
    state_path = args.state
    device = None
    device_path = args.device
    applied_rev = None
    last_clock_seq = None
    last_reconnect_seq = None
    last_clock = 0.0
    last_stats = 0.0
    next_scan = 0.0
    last_status = 0.0
    last_error = None
    sampler = None
    last_values = None
    last_state = _default_state()
    apply_cache = {}

    while True:
        loaded = _load_json(state_path)
        if (
            isinstance(loaded, dict)
            and isinstance(loaded.get("rev"), int)
            and isinstance(loaded.get("rgb"), dict)
        ):
            last_state = loaded
        state = last_state
        rev = int(state.get("rev", 0) or 0)
        clock_seq = int(state.get("clock_seq", 0) or 0)
        reconnect_seq = int(state.get("reconnect_seq", 0) or 0)
        clock_cfg = state.get("clock", {})
        stats_cfg = state.get("stats", {})
        screen_cfg = state.get("screen", {})
        screen_mode = screen_cfg.get("mode", "clock")
        stats_interval = max(0.5, float(stats_cfg.get("interval_s", 1) or 1))
        disk_path = stats_cfg.get("disk_path", "/") or "/"
        net_mode = stats_cfg.get("net_mode", "rate")
        clock_interval = max(
            30.0, float(clock_cfg.get("interval_s", 300) or 300)
        )

        if (
            sampler is None
            or getattr(sampler, "disk_path", None) != disk_path
            or getattr(sampler, "net_mode", None) != net_mode
        ):
            sampler = StatsSampler(disk_path, net_mode, stats_interval)

        now = time.monotonic()
        if device is None and now >= next_scan:
            device = open_device(device_path)
            next_scan = now + 2.0
            if device is not None:
                applied_rev = None
                apply_cache = {}
                last_clock = 0.0
                last_stats = 0.0
                last_values = None

        if device is not None and reconnect_seq != last_reconnect_seq:
            last_reconnect_seq = reconnect_seq
            device = open_device(device_path)
            applied_rev = None
            apply_cache = {}
            last_clock = 0.0
            last_stats = 0.0

        if device is not None:
            try:
                if applied_rev != rev:
                    apply_cache = _apply_changes(device, state, apply_cache)
                    applied_rev = rev
                    last_error = None
                    last_clock = 0.0
                    last_stats = 0.0

                if (
                    clock_cfg.get("enabled", True)
                    and now - last_clock >= clock_interval
                ):
                    device.send(clock_frame(), CHECKSUM_BIT7)
                    last_clock = now

                if clock_seq != last_clock_seq:
                    last_clock_seq = clock_seq
                    if clock_seq:
                        device.send(clock_frame(), CHECKSUM_BIT7)
                        last_clock = now

                if screen_mode == "cpu" and now - last_stats >= stats_interval:
                    values = sampler.sample()
                    device.send(
                        stats_frame(values), CHECKSUM_BIT7, settle=0.02
                    )
                    last_stats = now
                    last_values = values
            except OSError as error:
                last_error = str(error)
                device = None
                applied_rev = None
                apply_cache = {}
                last_values = None
                next_scan = now + 2.0

        if now - last_status >= 2.0:
            last_status = now
            info = None
            if device is not None:
                for candidate in find_devices():
                    if candidate.path == device.path:
                        info = candidate
                        break
            _print_json(
                {
                    "connected": device is not None,
                    "path": device.path if device else None,
                    "vid": info.vid if info else None,
                    "pid": info.pid if info else None,
                    "name": info.name if info else None,
                    "rev": rev,
                    "screen": screen_mode,
                    "stats": last_values,
                    "error": last_error,
                    "ts": int(time.time()),
                }
            )
        time.sleep(0.25)


def _add_device(parser):
    parser.add_argument(
        "--device", default=argparse.SUPPRESS, help="hidraw path override"
    )


def build_parser():
    parser = argparse.ArgumentParser(prog="ak820ctl")
    parser.add_argument("--device", default=None, help="hidraw path override")
    sub = parser.add_subparsers(dest="command", required=True)

    list_parser = sub.add_parser("list")
    list_parser.add_argument("--json", action="store_true")
    _add_device(list_parser)

    status_parser = sub.add_parser("status")
    status_parser.add_argument("--json", action="store_true")
    _add_device(status_parser)

    rgb_parser = sub.add_parser("rgb")
    rgb_parser.add_argument(
        "--effect", choices=sorted(EFFECTS), default="static"
    )
    rgb_parser.add_argument("--color", default="#89b4fa")
    rgb_parser.add_argument("--brightness", type=int, default=4)
    rgb_parser.add_argument("--speed", type=int, default=2)
    _add_device(rgb_parser)

    screen_parser = sub.add_parser("screen")
    screen_parser.add_argument("mode", choices=sorted(SCREEN_MODES))
    _add_device(screen_parser)

    language_parser = sub.add_parser("language")
    language_parser.add_argument("language", choices=("en", "zh"))
    _add_device(language_parser)

    clock_parser = sub.add_parser("clock")
    _add_device(clock_parser)

    stats_parser = sub.add_parser("stats")
    stats_parser.add_argument("--disk", default="/")
    stats_parser.add_argument(
        "--net-mode", choices=("rate", "total"), default="rate"
    )
    stats_parser.add_argument("--interval", type=float, default=1.0)
    stats_parser.add_argument("--loop", action="store_true")
    stats_parser.add_argument("--count", type=int, default=0)
    _add_device(stats_parser)

    daemon_parser = sub.add_parser("daemon")
    daemon_parser.add_argument("--state", required=True)
    _add_device(daemon_parser)

    raw_parser = sub.add_parser("raw")
    raw_parser.add_argument("--hex", required=True)
    raw_parser.add_argument(
        "--checksum",
        choices=(CHECKSUM_BIT7, CHECKSUM_BIT8, CHECKSUM_NONE),
        default=CHECKSUM_NONE,
    )
    raw_parser.add_argument("--read", action="store_true")
    _add_device(raw_parser)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    handlers = {
        "list": cmd_list,
        "status": cmd_status,
        "rgb": cmd_rgb,
        "screen": cmd_screen,
        "language": cmd_language,
        "clock": cmd_clock,
        "stats": cmd_stats,
        "daemon": cmd_daemon,
        "raw": cmd_raw,
    }
    try:
        return handlers[args.command](args)
    except OSError as error:
        print("ak820ctl: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
