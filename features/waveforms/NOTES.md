# waveforms

## Workarounds

- `features/waveforms/default.nix` adept2 overlay installs the vendor `usr/lib/udev/dftdrvdtch` into `$out/lib/udev`. waveforms-flake's Adept 2.30.1 installer copies only the separate Adept library directory, leaving its generated udev RUN target absent. Existing autoPatchelf supplies the helper's glibc interpreter and libusb RPATH.
