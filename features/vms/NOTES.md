# vms

## Workarounds

- `features/vms/default.nix` `virtualisation.libvirtd.onShutdown = "shutdown"`: the NixOS default `suspend` managed-saves guests at host shutdown, which libvirt refuses for virgl graphics and virtiofs shares, so host shutdown would stall on the Ubuntu guest.
- `features/vms/ubuntu-24-04/default.nix` guest screen lock disabled via a locked dconf system db: the guest account has a locked password (key-only SSH, `NOPASSWD` sudo, GDM autologin), and GNOME 46 only skips its lock for accounts with no password at all, so a locked session could never be unlocked. The host's swaylock protects the console instead. The first boot also installs `spice-vdagent` after its virtio port already exists, so the udev rule never starts the agent until the guest's next boot.
