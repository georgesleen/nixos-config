# Personal packages shared across my interactive machines

{ pkgs, ... }:

let
  libreoffice = pkgs."libreoffice-fresh";
  # JMP renders a black screen (audio only) under Wayland-native Qt: EGL context
  # creation fails, mpv logs "No render context set". Force XWayland so mpv's VO
  # gets a working GL context. Scoped to this binary; a global QT_QPA_PLATFORM
  # would push every Qt app onto XWayland.
  jellyfin-media-player = pkgs.jellyfin-media-player.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/jellyfin-desktop --set-default QT_QPA_PLATFORM xcb
    '';
  });
in

{
  environment.systemPackages = with pkgs; [
    libreoffice # office suite
    discord # messaging service
    slack # messaging service (business)
    obsidian # markdown notes
    qbittorrent # torrenting client
    jellyfin # media server
    jellyfin-media-player # jellyfin desktop client (mpv-based; good subtitle rendering)
    python313Packages.grip # render GitHub flavoured markdown
    vlc # media player
    moonlight-qt # game stream client for Sunshine on the win11 VM
    kdePackages.okular # pdf viewer
    inkscape # vector graphics editor
    kicad # schematic capture and PCB design
    ngspice # circuit simulator used with kicad
    easyeda2kicad # rip symbols from jlc for kicad
    zed-editor # code editor
    zoom-us # video conferencing
    pandoc # Markdown Renderer
    texlive.combined.scheme-medium # LaTeX engine
  ];
}
