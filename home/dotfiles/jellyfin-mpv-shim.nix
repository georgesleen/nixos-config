{ ... }:

{
  # Jellyfin cast target with a large read-ahead buffer.
  services.jellyfin-mpv-shim = {
    enable = true;
    mpvConfig = {
      cache = "yes";
      cache-pause-initial = "yes";
      cache-pause-wait = 30;
      demuxer-max-back-bytes = "64MiB";
      demuxer-max-bytes = "1GiB";
      hwdec = "auto-safe";
    };
  };
}
