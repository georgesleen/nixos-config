# George's SSH public keys, one per device, authorized on every host here.
#
# Single source of truth: gs-pi4 and gs-server read this list directly, and
# both OpenWrt images render it into /etc/dropbear/authorized_keys at build
# time. Adding a device is one line here; the literal used to be copy-pasted
# into four files, where forgetting one is a silent lockout discovered only
# when that host is the one you need.
#
# The T480s key doubles as the `user_george` sops recipient in .sops.yaml
# (`ssh-to-age -i ~/.ssh/id_ed25519.pub` reproduces it), so removing a key
# here is not the same as revoking it: that needs `sops updatekeys` and, if
# the key is actually compromised, rotating the secret values themselves.
#
# A new key reaches the NixOS hosts on their next `nixos-rebuild switch`, but
# the OpenWrt pair only on a clean reflash. Append it live to
# /etc/dropbear/authorized_keys there as well, or the repo and the running
# router disagree until the next flash.
[
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDS8y5OdyR6OIy91fTAzt2GHg+aqm9H5F2l+G9/aWFJF george-sleen@GS-ThinkPad-T480s"
]
