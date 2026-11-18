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

      # Critical notifications never expire; the spec says a critical
      # notification must stay until dismissed, but mako applies
      # default-timeout to every urgency. The battery warning is the case that
      # matters: it announces a hibernate 60s out, and at 5000 ms it was gone
      # from the screen before the machine went down.
      "urgency=critical" = {
        default-timeout = 0;
      };

      # Low battery is urgency normal and fires exactly once per discharge, so
      # 5 s was one easily missed toast.
      "urgency=normal" = {
        default-timeout = 20000;
      };
    };
  };
}
