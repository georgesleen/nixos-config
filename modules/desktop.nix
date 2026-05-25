# Desktop stack — only imported by hosts with a display

{ ... }:

{
  imports = [
    ./audio.nix
    ./fonts.nix
    ./sway.nix
    ./sway-extras.nix
  ];

  programs.firefox = {
    enable = true;
    preferences = {
      # VA-API hardware video decode — opt-in upstream due to historical driver bugs
      "media.ffmpeg.vaapi.enabled" = true;
      # Force it on even when Firefox detects a potentially problematic GPU
      "media.hardware-video-decoding.force-enabled" = true;
    };
  };
}
