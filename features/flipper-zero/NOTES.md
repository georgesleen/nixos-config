# flipper-zero

## Overview

Flipper Zero desktop app (qFlipper) + USB access.

hardware.flipperzero brings qFlipper and its shipped 42-flipperzero.rules (ESP32 BlackMagic + U2F coverage we'd otherwise miss). Those rules grant via TAG+="uaccess", which doesn't fire under sway/Wayland, so the rules below re-grant the two devices that matter with GROUP="plugdev" + MODE="0660". extraRules land in 99-local.rules, applied after 42-*, so they win. Same pattern as keychron.nix; the user is already in plugdev.
