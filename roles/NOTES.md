# roles

## Workarounds

- `roles/laptop.nix` udev rule: way-displays opens the lid switch through libinput as the user, and discovery only lists devices it can open. Grant `Lid Switch` alone to `plugdev` with mode `0660`, avoiding membership in `input`, which would expose every keyboard's raw events. Mode `0640` is insufficient: a runtime trace showed libinput requesting `O_RDWR|O_NONBLOCK|O_CLOEXEC` and receiving `EACCES` despite the device being readable. Input event numbers change across boots; identify the device by its name, not a saved `eventN`.
