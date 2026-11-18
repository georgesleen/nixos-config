# dconf

## Workarounds

- `features/dconf/home.nix` virt-manager `console/auto-redirect = false`: virt-manager's schema default is true, so opening any console tried to grab every hot-plugged host USB device, the iPhone included. Redirection is manual only, from the console's Redirect USB device menu.
