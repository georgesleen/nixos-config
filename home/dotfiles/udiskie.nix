# Desktop notifications for removable media (USB drives, SD cards).

{
  services.udiskie = {
    enable = true;
    automount = false;
    notify = true;
    tray = "never";
  };
}
