{ config, pkgs, ... }:

let
  swayBg = builtins.path {
    path = ../../assets/wallpapers/background.png;
    name = "background.png";
  };
  swaylockBg = pkgs.runCommand "swaylock-background" { } ''
    mkdir -p "$out"
    ${pkgs.ffmpeg}/bin/ffmpeg -loglevel error -y -i ${swayBg} \
      -vf "gblur=sigma=28,eq=brightness=-0.10:saturation=0.85" \
      -frames:v 1 "$out/background.png"
  '';
  swaylockPackage = pkgs.swaylock-effects;
  swaylockConfig = "${config.xdg.configHome}/swaylock/config";
  swaylockCmd = "${swaylockPackage}/bin/swaylock -f -C ${swaylockConfig}";
  dpmsOffCmd = "${pkgs.sway}/bin/swaymsg \"output * dpms off\"";
  dpmsOnCmd = "${pkgs.sway}/bin/swaymsg \"output * dpms on\"";
in
{
  services.swayidle = {
    enable = true;
    events = {
      before-sleep = swaylockCmd;
      lock = swaylockCmd;
      after-resume = dpmsOnCmd;
    };
    timeouts = [
      {
        timeout = 1800;
        command = swaylockCmd;
      }
      {
        timeout = 1801;
        command = dpmsOffCmd;
        resumeCommand = dpmsOnCmd;
      }
    ];
  };

  xdg.configFile."swaylock/config".text = ''
    image=${swaylockBg}/background.png
    scaling=fill
    indicator
    indicator-idle-visible
    clock
    timestr=%H:%M
    datestr=%a, %b %d
    show-failed-attempts
    font=JetBrains Mono
    font-size=24
    indicator-radius=130
    indicator-thickness=10
    effect-vignette=0.35:0.35
    inside-color=00000066
    inside-clear-color=1f7a8c88
    inside-caps-lock-color=b0896888
    inside-ver-color=58815788
    inside-wrong-color=bc474988
    ring-color=f2efe9aa
    ring-clear-color=1f7a8cff
    ring-caps-lock-color=b08968ff
    ring-ver-color=588157ff
    ring-wrong-color=bc4749ff
    key-hl-color=4ea8deff
    bs-hl-color=bc4749ff
    caps-lock-key-hl-color=4ea8deff
    caps-lock-bs-hl-color=4ea8deff
    line-uses-ring
    separator-color=0b132bff
    layout-bg-color=00000066
    layout-border-color=00000000
    layout-text-color=f8f5f0ff
    text-color=f8f5f0ff
    text-clear-color=f8f5f0ff
    text-caps-lock-color=f8f5f0ff
    text-ver-color=f8f5f0ff
    text-wrong-color=f8f5f0ff
  '';
}
