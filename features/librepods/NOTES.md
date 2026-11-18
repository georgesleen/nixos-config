# librepods

## Workarounds

- `features/librepods/home.nix` / `librepods-watch.py`: the login-started unit is now a passive BlueZ listener, not the LibrePods GUI. It starts the GUI only for paired and connected devices advertising LibrePods' AirPods UUID (`74ec2172-0bad-4d01-8f77-997b2be0722a`) and stops it after the last disconnect or BlueZ shutdown. Pairing alone is not enough; device names are not used. LibrePods 0.2.5 hardcodes continuous BLE discovery, which caused system-wide D-Bus wakeups even without AirPods nearby. The watcher requests no discovery and ignores RSSI-only changes. Ordinary Bluetooth audio remains independent; LibrePods controls remain automatic when connected. `librepods-watch` check covers matching, late UUIDs and multiple devices; private-D-Bus runtime smoke also exercised the real user service through connection/removal and BlueZ restart events.
