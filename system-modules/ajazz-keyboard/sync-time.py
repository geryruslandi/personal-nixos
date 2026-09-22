import datetime
import errno
import fcntl
import glob
import os
import sys

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

VENDOR = b"v00003151"
SCREEN_CHANNEL = b"\x06\xff\xff\x09\x02\xa1\x01"
FEATURE_64 = b"\x95\x40\x75\x08\xb1\x02"


def find_screen_nodes():
    nodes = []
    for entry in sorted(glob.glob("/sys/class/hidraw/*")):
        hid = os.path.join(entry, "device")
        try:
            with open(os.path.join(hid, "modalias"), "rb") as f:
                if VENDOR not in f.read():
                    continue
            with open(os.path.join(hid, "report_descriptor"), "rb") as f:
                desc = f.read()
        except OSError:
            continue
        if SCREEN_CHANNEL in desc and FEATURE_64 in desc:
            nodes.append("/dev/" + os.path.basename(entry))
    return nodes


def build_clock_frame():
    now = datetime.datetime.now()
    frame = bytearray(64)
    frame[0] = 0x28
    frame[7] = (0xFF - (sum(frame[0:7]) & 0xFF)) & 0xFF
    frame[8] = (now.year >> 8) & 0xFF
    frame[9] = now.year & 0xFF
    frame[10] = now.month
    frame[11] = now.day
    frame[12] = now.hour
    frame[13] = now.minute
    frame[14] = now.second
    return bytes(frame)


def send_feature(node, frame):
    fd = os.open(node, os.O_RDWR)
    try:
        fcntl.ioctl(fd, HIDIOCSFEATURE, b"\x00" + frame)
    finally:
        os.close(fd)


def main():
    nodes = find_screen_nodes()
    if not nodes:
        sys.exit(0)
    frame = build_clock_frame()
    sent = 0
    failed = False
    for node in nodes:
        try:
            send_feature(node, frame)
        except OSError as err:
            if err.errno == errno.EACCES:
                continue
            failed = True
            print(f"ak820-sync-time: {node}: {err}", file=sys.stderr)
        else:
            sent += 1
            print(f"ak820-sync-time: synced {node}")
    if failed:
        sys.exit(1)
    if sent == 0:
        sys.exit(0)


if __name__ == "__main__":
    main()
