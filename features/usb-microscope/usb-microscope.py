#!/usr/bin/env python3
"""Stream raw Bayer frames from a ScopeTek DCM310 (0547:4d33) to stdout.

The camera is not UVC. It is a Cypress FX2 bridge in front of a Micron
MT9T001 sensor, driven with three vendor requests: 0x01 control, 0x0a
sensor register read, 0x0b sensor register write. Register address goes in
wIndex, data in wValue. Frames arrive on bulk endpoint 0x82, each ended by
a short packet, so one large read returns one frame.

Protocol from https://github.com/FFY00/scopetek-re.
"""

import argparse
import sys
import time

import usb.core

VENDOR, PRODUCT = 0x0547, 0x4D33
EP_BULK = 0x82

# Register 0x22 (row) and 0x23 (column) address mode set skip factors. Output
# size is the 2048x1536 sensor divided by the skip.
MODES = {
    "2048x1536": (0x00, 2048, 1536),
    "1024x768": (0x11, 1024, 768),
    "512x384": (0x33, 512, 384),
}


def open_device():
    dev = usb.core.find(idVendor=VENDOR, idProduct=PRODUCT)
    if dev is None:
        sys.exit("microscope: camera 0547:4d33 not found")
    try:
        if dev.is_kernel_driver_active(0):
            dev.detach_kernel_driver(0)
    except usb.core.USBError:
        pass
    dev.set_configuration()
    return dev


class Camera:
    def __init__(self, dev):
        self.dev = dev

    def control(self, index, value):
        self.dev.ctrl_transfer(0x40, 0x01, value, index, None, 1000)
        time.sleep(0.002)

    def write(self, register, value):
        self.dev.ctrl_transfer(0xC0, 0x0B, value, register, 1, 1000)
        time.sleep(0.002)

    def read(self, register):
        r = bytes(self.dev.ctrl_transfer(0xC0, 0x0A, 0, register, 3, 1000))
        time.sleep(0.002)
        return int.from_bytes(r[:2], "big")

    def start(self, mode, shutter, gain):
        skip, _, _ = MODES[mode]
        self.control(0x000F, 0x0001)
        self.control(0x000F, 0x0000)
        self.control(0x000F, 0x0001)
        chip = self.read(0x0000)
        if chip != 0x1621:
            print(f"microscope: unexpected sensor id 0x{chip:04x}", file=sys.stderr)
        self.write(0x000A, 0x8000)
        self.write(0x000D, 0x0001)
        time.sleep(0.1)
        self.write(0x000D, 0x0000)
        time.sleep(0.1)
        self.write(0x0001, 0x0015)  # row start
        self.write(0x0002, 0x0021)  # column start
        time.sleep(0.2)
        self.write(0x0020, 0x0000)  # read mode 1
        self.write(0x001E, 0x8040)  # read mode 2
        self.write(0x004E, 0x0030)
        self.write(0x0004, 0x07FF)  # window width - 1
        self.write(0x0003, 0x05FF)  # window height - 1
        for channel in (0x2B, 0x2C, 0x2D, 0x2E):
            self.write(channel, 0x0060)  # per-quadrant gains
        self.write(0x000A, 0x8001)
        self.write(0x0022, skip)
        self.write(0x0023, skip)
        self.write(0x0005, 0x0150)  # horizontal blank
        self.write(0x000A, 0x8000)
        self.write(0x0005, 0x0300)
        self.write(0x0009, shutter)  # shutter width
        time.sleep(0.2)
        self.write(0x0035, gain)  # global gain
        self.control(0x000F, 0x0003)

    def stop(self):
        self.control(0x000F, 0x0000)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode", choices=MODES, default="1024x768")
    p.add_argument("--shutter", type=lambda s: int(s, 0), default=0x07FF,
                   help="sensor register 0x09, exposure in row times")
    p.add_argument("--gain", type=lambda s: int(s, 0), default=0x0056,
                   help="sensor register 0x35, global gain")
    p.add_argument("--frames", type=int, default=0, help="stop after N frames (0 = forever)")
    args = p.parse_args()

    _, width, height = MODES[args.mode]
    size = width * height

    dev = open_device()
    cam = Camera(dev)
    cam.start(args.mode, args.shutter, args.gain)
    print(f"microscope: {args.mode} shutter 0x{args.shutter:04x} gain 0x{args.gain:02x}",
          file=sys.stderr)

    sent = dropped = 0
    try:
        while args.frames == 0 or sent < args.frames:
            try:
                frame = bytes(dev.read(EP_BULK, size * 2, 5000))
            except usb.core.USBTimeoutError:
                print("microscope: read timed out", file=sys.stderr)
                break
            # A frame short of its full length lost packets while the host was
            # busy; passing it on would shear the picture, so drop it.
            if len(frame) != size:
                dropped += 1
                continue
            sys.stdout.buffer.write(frame)
            sys.stdout.buffer.flush()
            sent += 1
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    finally:
        cam.stop()
        print(f"microscope: {sent} frames sent, {dropped} dropped", file=sys.stderr)


if __name__ == "__main__":
    main()
