{ ... }:

{
  services.mako = {
    enable = true;
    settings = {
      default-timeout = 5000;
      icon-path = "";
      # Render above fullscreen apps (default "top" layer sits under them).
      layer = "overlay";
      max-icon-size = 1;
    };
  };
}
