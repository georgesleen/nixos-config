# usb-microscope

## Overview

ScopeTek DCM310 / AmScope MD800E microscope camera (0547:4d33).

Not a UVC device: the single interface is vendor class ff and no in-tree driver claims the ID, so no /dev/video node appears and uvcvideo never binds. The camera is driven from userspace over libusb instead (usb-microscope.py), which needs raw access to the USB node. TAG+="uaccess" does not fire under sway/Wayland, so grant plugdev directly, as keychron.nix and flipper-zero.nix do. The `microscope` command feeds the frames into a v4l2loopback node, which is what makes the camera visible to OBS and every other v4l2 app.

## boot.extraModprobeConfig

exclusive_caps makes the node advertise capture only, which is what apps that reject output-capable devices (Firefox, Chromium) require. max_buffers is above the module default of 2 because apps that request 4 mmap buffers fail outright when QUERYBUF returns EINVAL on the third.
