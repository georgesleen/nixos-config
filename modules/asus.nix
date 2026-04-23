{ pkgs, ... }:

{
  # ASUS system daemon: fan curves, battery charge limits, keyboard RGB, power profiles
  services.asusd.enable = true;

  # GPU switching (integrated / hybrid / dedicated) — enabled automatically by asusd,
  # listed here explicitly so the intent is clear.
  services.supergfxd.enable = true;

  # GUI control panel for all of the above
  programs.rog-control-center.enable = true;
}
