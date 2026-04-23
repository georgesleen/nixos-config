{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    asusctl
  ];
  # asusd bind-mounts /etc/asusd into its private namespace — create it if absent
  systemd.tmpfiles.rules = [
    "d /etc/asusd 0755 root root -"
  ];

  # ASUS system daemon: fan curves, battery charge limits, keyboard RGB, power profiles
  services.asusd.enable = true;

  # GPU switching (integrated / hybrid / dedicated) — enabled automatically by asusd,
  # listed here explicitly so the intent is clear.
  services.supergfxd.enable = true;

  # GUI control panel for all of the above
  programs.rog-control-center.enable = true;
}
