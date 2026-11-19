# virtualization

## Workarounds

- `default.nix` `virtualisation.spiceUSBRedirection.enable`: installing `spice-gtk` alone leaves `spice-client-glib-usb-acl-helper` as a plain store binary with no `cap_fowner`, so every SPICE USB redirect failed with "Error setting USB device node ACL: Operation not permitted", even on nodes George could already read and write. The module installs the polkit-checked `cap_fowner` wrapper in `/run/wrappers/bin`. Proven by toggling on `/dev/bus/usb/001/001` with no device captured: raw helper EPERM, wrapper grants then revokes the per-user ACL, raw EPERM again. The helper leaves a `mask::` entry equal to the group bits after revoking, so compare effective access, not byte-identical `getfacl` output.
- `default.nix`: `set_sched` removed from the libvirt qemu hook; those CFS sysctls don't exist post-EEVDF (Linux 6.6+).
