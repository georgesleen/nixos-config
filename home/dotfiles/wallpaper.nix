{ pkgs, lib, ... }:
let
  snowflakeSvg = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake-white.svg";

  # Badge rings (assets/nixos-emblem.svg) with the authoritative snowflake
  # dropped into the centre.
  emblem =
    pkgs.runCommand "nixos-emblem.png"
      {
        nativeBuildInputs = [
          pkgs.librsvg
          pkgs.imagemagick
        ];
      }
      ''
        rsvg-convert -w 200 -h 200 "${../../assets/nixos-emblem.svg}" -o badge.png
        rsvg-convert -w 110 -h 110 "${snowflakeSvg}" -o snowflake.png
        magick badge.png snowflake.png -gravity NorthWest -geometry +45+45 -composite "$out"
      '';

  # Render one variant: rasterize SVGs to 4K, then optionally inset the badge
  # at 7% of the image width, 3% from the bottom-right corner.
  mkImage =
    name: src: doWatermark:
    pkgs.runCommand "wallpaper-${name}.png"
      {
        nativeBuildInputs = [
          pkgs.librsvg
          pkgs.imagemagick
        ];
      }
      (
        ''
          case "${src}" in
            *.svg) rsvg-convert -w 3840 -h 2160 "${src}" -o base.png ;;
            *)     cp "${src}" base.png ;;
          esac
        ''
        + (
          if doWatermark then
            ''
              w=$(magick identify -format '%w' base.png)
              magick "${emblem}" -resize "$(( w * 7 / 100 ))x" emblem-scaled.png
              magick base.png emblem-scaled.png \
                -gravity SouthEast -geometry "+$(( w * 3 / 100 ))+$(( w * 3 / 100 ))" \
                -composite "$out"
            ''
          else
            ''
              mv base.png "$out"
            ''
        )
      );

  # Normalize a wallpapers.nix entry into resolved { light; dark; } store paths.
  # An entry with a single `src` reuses one render for both modes.
  mkEntry =
    i: e:
    let
      doWatermark = e.watermark or false;
      lightSrc = e.light or e.src;
      darkSrc = e.dark or e.src;
    in
    if lightSrc == darkSrc then
      let
        both = mkImage "${toString i}" lightSrc doWatermark;
      in
      {
        light = both;
        dark = both;
      }
    else
      {
        light = mkImage "${toString i}-light" lightSrc doWatermark;
        dark = mkImage "${toString i}-dark" darkSrc doWatermark;
      };

  wallpapers = lib.imap0 mkEntry (import ./wallpapers.nix);

  lightList = lib.concatMapStringsSep " " (w: "\"${w.light}\"") wallpapers;
  darkList = lib.concatMapStringsSep " " (w: "\"${w.dark}\"") wallpapers;

  # Apply the wallpaper for the current darkman mode. With --next, advance the
  # rotation index first; without it, re-render the current index in place
  # (used by the darkman light/dark hooks).
  wallpaperApply = pkgs.writeShellApplication {
    name = "wallpaper-apply";
    runtimeInputs = [
      pkgs.awww
      pkgs.darkman
    ];
    text = ''
      light=(${lightList})
      dark=(${darkList})
      count=${builtins.toString (builtins.length wallpapers)}
      state="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wallpaper-index"

      index=-1
      [ -f "$state" ] && index=$(< "$state")
      if [ "''${1:-}" = "--next" ]; then
        index=$(( (index + 1) % count ))
      else
        [ "$index" -lt 0 ] && index=0
        index=$(( index % count ))
      fi

      mode=$(darkman get 2>/dev/null || echo dark)
      if [ "$mode" = "light" ]; then
        img="''${light[$index]}"
      else
        img="''${dark[$index]}"
      fi

      awww img "$img" --transition-type fade --transition-duration 2
      printf '%d' "$index" > "$state"
    '';
  };
in
{
  home.packages = [ pkgs.awww ];

  systemd.user.services.awww-daemon = {
    Unit = {
      Description = "awww wallpaper daemon";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.awww}/bin/awww-daemon";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "sway-session.target" ];
  };

  systemd.user.services.wallpaper-rotate = {
    Unit = {
      Description = "Rotate to next wallpaper";
      After = [ "awww-daemon.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${wallpaperApply}/bin/wallpaper-apply --next";
    };
  };

  # Re-render the current wallpaper in the active light/dark mode; poked by the
  # darkman hooks on sunrise/sunset.
  systemd.user.services.wallpaper-refresh = {
    Unit = {
      Description = "Re-render current wallpaper for the active mode";
      After = [ "awww-daemon.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${wallpaperApply}/bin/wallpaper-apply";
    };
  };

  systemd.user.timers.wallpaper-rotate = {
    Unit.Description = "Rotate wallpaper every 30 minutes";
    Timer = {
      OnBootSec = "5s";
      OnUnitActiveSec = "30m";
    };
    Install.WantedBy = [ "sway-session.target" ];
  };
}
