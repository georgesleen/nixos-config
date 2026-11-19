# user-packages

## Workarounds

- `home.nix` `yazi` desktop entry: replaces yazi's packaged entry, whose `Terminal=true` xdg-open ignores: xdg-open runs `Exec` as is, so yazi got no terminal of its own.
- `default.nix` jellyfin-mpv-shim (replaced jellyfin-media-player): JMP 2.0.0 is abandoned upstream; pointed at the 10.11 server web client (`main.userWebClient`) its native-mpv hook fails to register and it falls back to the embedded QtWebEngine `htmlVideoPlayer`, whose limited Chromium codec set (`aac,opus,flac`, no ac3/eac3/dts) forces an HLS transcode. With gs-pi4 transcoding off that manifest comes back `manifestIncompatibleCodecsError` and playback hangs at the spinner (diagnosed 2026-07-27 from JMP's `jellyfin-desktop.log` `TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported`; the black-video-under-Wayland xcb wrap was a separate earlier issue, now moot). mpv-shim drives libmpv directly (no browser, no codec ceiling), Direct Plays what the Pi holds, and matches the no-transcode design.
