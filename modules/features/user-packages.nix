# Personal packages shared across my interactive machines

{ pkgs, ... }:

let
  libreoffice = pkgs."libreoffice-fresh";
  # Moonfin: not in nixpkgs; wrap the upstream x86_64 AppImage. libmpv-backed
  # Jellyfin client, Direct Plays HEVC/EAC3/mkv (matches the no-transcode server).
  moonfin =
    let
      version = "2.4.0";
      src = pkgs.fetchurl {
        url = "https://github.com/Moonfin-Client/Moonfin-Core/releases/download/${version}/Moonfin_Linux_v${version}.AppImage";
        hash = "sha256-HJUwK2hMmQ4TP7VWWcKRn9v5a3rLf6Ej1+YvIyT8weI=";
      };
      # wrapType2 only wraps the binary; pull the desktop entry + icon out of the
      # AppImage so the launcher (fuzzel) lists it. Exec=moonfin already matches.
      contents = pkgs.appimageTools.extractType2 { pname = "moonfin"; inherit version src; };
    in
    pkgs.appimageTools.wrapType2 {
      pname = "moonfin";
      inherit version src;
      # Not in the appimage FHS base: the first two are DT_NEEDED by the binary
      # (Flutter GTK/GL); libmpv is dlopen'd by media_kit at playback time.
      extraPkgs = p: [
        p.libepoxy
        p.xorg.libXv
        p.mpv-unwrapped
      ];
      extraInstallCommands = ''
        install -Dm444 ${contents}/org.moonfin.linux.desktop -t $out/share/applications
        install -Dm444 ${contents}/org.moonfin.linux.png -t $out/share/pixmaps
      '';
    };
in

{
  environment.systemPackages = with pkgs; [
    libreoffice # office suite
    discord # messaging service
    slack # messaging service (business)
    obsidian # markdown notes
    qbittorrent # torrenting client
    jellyfin # media server
    moonfin # libmpv jellyfin client (Direct Play HEVC/eac3, no browser codec limits); replaced delfin
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
