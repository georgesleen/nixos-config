# NixOS Configuration

Flake-based NixOS config.

## Commands

```bash
# Apply system + home-manager changes (use the host you're on)
sudo nixos-rebuild switch --flake .#<host>

# Direct build without switching (does not update the per-target retained root)
nixos-rebuild build --flake .#<host>

nix flake update          # update inputs
nix flake check           # validate outputs
nix develop               # default dev shell
```

### Package updates

A package update includes synchronizing the maintained forks with their upstreams,
then updating their flake inputs or source pins:

- `georgesleen/helix`, `steel-event-system-output`, from
  `mattwparas/helix`'s `steel-event-system` branch, not `master`.
- `georgesleen/kitty_grab_helix`, `main`, from `yurikhan/kitty_grab`'s `master`.
- `georgesleen/pi-automode`, the branch consumed by `pkgs/pi-automode.nix`,
  from `czottmann/pi-automode`'s `main`.

Also check manually pinned desktop tools and Open WebUI's official OCI image.
Advance the WebUI release tag and immutable digest together; its persistent state
must be backed up before starting a release that can migrate the database.

Preserve fork-specific behavior, check whether upstream has absorbed patches,
and preserve uncommitted local work. After updating the inputs, run `make test`,
build the local host with its retained-build target, activate it, and check
service health and the systemd ordering graph. Updating the shared lock file
does not deploy remote hosts or flash router images.

### Retained builds

Build without activating or flashing:

```bash
make build-gs-framework-13-pro
make build-gs-server
make build-gs-pi4
make gs-openwrt-one
make gs-pi1-parents
```

Each command registers its output with `nix build --out-link` at
`.gcroots/<host-or-target>` in this repository. Only a successful build advances
that target's link; a failed build leaves the previous success intact, and a
cached success also pins the output. `make gs-openwrt-one-flash` builds through
the same `gs-openwrt-one` root before flashing. See the OpenWrt runbooks in
`docs/` for secret requirements and flashing.

These roots retain runtime closures, not build dependencies or development
environments. They do not activate a NixOS configuration or replace the laptop's
current-system and known-good boot roots. Direct `nixos-rebuild build` and
`nixos-rebuild switch` commands do not advance these per-target links.
`make test` uses `--no-link`, so test outputs do not become permanent roots.

On `gs-framework-13-pro`, weekly GC removes non-current profile generations and
does not retain derivations or build outputs. The current system, the booted
system and the separate current known-good profile remain rooted. After pruning
generations, a system activation refreshes the boot menu.

Framework direnv flake shells use `nix print-dev-env` without persistent profiles
or input roots. Shells still load automatically, but entering a project after GC
can download or rebuild its environment. Other hosts retain their nix-direnv
configuration. The Framework cleanup command is:

```bash
sudo nix-clean
```

`nix-clean` defaults to `--delete-old` without arguments. Explicit arguments pass
through unchanged, so `sudo nix-clean --dry-run` does not prune profile
generations. Its distinct name avoids being shadowed by Nix development shells.

For non-interactive commands, `sudo-notify <command> [arguments...]` displays
`Authenticate with fingerprint reader`, or `Authenticate with password` with
the lid closed, only while authentication is pending. It dismisses its own
notification after authentication, before starting the command, and on failure
or cancellation. Sudo without a terminal uses a masked GTK password dialog
instead of fuzzel; terminal sudo keeps its normal prompt. On the Framework,
the password dialog cancels after five minutes without a submission; this
timeout does not limit the authenticated command's runtime. Polkit actions
use the separate GNOME authentication agent.

GC does not remove project build directories, personal files, VM disks or Btrfs
snapshots. Runtime references held by running processes remain live until those
processes exit.

## Native Steam

Steam is enabled by the laptop role, including 32-bit graphics support. On the
Framework, select `~/Media/Games` in Steam Settings > Storage and make it the
default library. It is a separate Btrfs subvolume, excluded from ordinary home
snapshots. Existing snapshots can still retain files deleted before migration.

Steam client settings and runtimes remain under `~/.local/share/Steam`, with
aliases under `~/.steam`. Game installations, Proton prefixes and shader caches
belong to the selected library. Some native games store saves elsewhere in home.

Keep exported Satisfactory saves under `~/Documents/Game Saves/Satisfactory`,
outside the library and covered by home snapshots. Back up selected saves before
uninstalling a game or removing its Proton prefix; Steam Cloud is not the only
backup. Uninstall games through Steam, or close Steam before manually removing
library contents. To remove Steam itself on the Framework,
override `programs.steam.enable = lib.mkForce false`, rebuild, and remove client
data only after preserving saves. The storage activation does not recreate the
library while Steam is disabled.

## Claude Code providers

Plain `claude` uses the normal Anthropic subscription login and defaults to
Opus 5.5. Alternative providers run in separate sessions:

```bash
claude-proxy-login          # one-time ChatGPT OAuth login for the local gateway
claude-codex                # GPT 6.1 Sol through the ChatGPT subscription
claude-ollama               # local Gemma 4 26B QAT
claude-ollama-abliterated   # local abliterated Gemma 4 26B
```

The launchers start `claude-proxy.service` on `127.0.0.1:8317`. Its `/model`
menu lists the gateway's Codex and Ollama models, not native Claude models.
These processes use a private local bearer token; upstream OAuth credentials
stay in `~/.local/state/claude-proxy/auth`, never in the Nix store.

Proxy sessions use Codex for the native auto-mode classifier, even when Ollama
is the coding model, so auto mode still needs ChatGPT quota. Native Anthropic
sessions keep their normal classifier. Named Claude background reviewers in a
proxy session route to Codex too. No Claude subscription token is given to the
proxy. The API-billing label and dollar estimates in Claude Code are not bills
from the local gateway; Codex uses its subscription and Ollama runs locally.

The Codex launcher selects the gateway's Claude-compatible discovery ID with
`[1m]`, giving Claude Code a 1M context budget. This is a client setting, not a
verified million-token upstream request; the gateway advertises 272k input.
Do not replace that ID with raw `gpt-6.1-sol`: Claude Code treats the latter as
a separate custom-model entry instead of the discovered GPT 6.1 Sol row.
Ollama launchers budget for the
server's 32k context window. Start a fresh local session rather than switching
a long Codex conversation to a local model.
Home Manager owns `~/.claude/settings.json`; press `s` in `/model` to switch
for this session without attempting to overwrite that read-only file.

## Block diagrams

Desktop hosts include D2 for text-based diagrams with automatic layout.
Run `d2 --watch diagram.d2 diagram.svg` for live preview; the generated SVG
can be embedded in Typst with `#image("diagram.svg")`.

## Laptop VMs

The Framework imports `virtualization/default.nix`. NixVirt manages the
`ubuntu-tools` and `windows-workstation` domain definitions on
`qemu:///system`; use virt-manager for their normal start, shutdown and console
controls. Neither guest starts automatically, and a rebuild does not restart a
running guest. Permanent domain changes belong in the Nix definitions, not the
GUI: NixVirt's domain list is authoritative. Existing networks and storage pools
are not adopted into its authoritative lists.

| Guest | Definition | Private state | Shared work |
| --- | --- | --- | --- |
| Ubuntu 24.04, 4 vCPU / 6 GiB / 64 GiB disk | `virtualization/ubuntu-24-04/default.nix` | `~/Virtualization/ubuntu-24-04` | `~/Documents/VMWork/ubuntu-24-04` |
| Windows 11, 8 vCPU / 12 GiB / 128 GiB disk | `virtualization/windows-11/default.nix` | `~/Virtualization/windows-11` | `~/Documents/VMWork/windows-11` |

Private state directories are Btrfs subvolumes excluded from home snapshots.
Their disks inherit NOCOW and grow on demand. Initialization never replaces an
existing disk; Ubuntu's base image is copied into a standalone QCOW2, not used as
a live backing file in the Nix store. Windows firmware variables and TPM state
stay in its private directory. Shared work is outside the guest's private state
and remains covered by home snapshots.

Ubuntu's pinned cloud image uses a NoCloud seed to install a minimal GNOME
desktop, SPICE/QEMU agents and SSH. Its desktop logs in automatically; SSH uses
the public keys in `keys/authorized.nix`, with password login disabled.
The work share appears at `~/Work`. Cloud-init provisions a fresh disk once;
editing the seed does not reinstall or continuously reconcile an existing OS.
Host shutdown requests a clean guest shutdown instead of saving guest RAM:
virgl graphics and virtiofs shares do not support libvirt managed save.

Windows uses the existing Windows and VirtIO ISOs in `~/Media/Disk Images`.
Complete its normal installer, account and licensing screens in virt-manager.
The additional `WORKSTATION` CD contains `INSTALL.txt` and
`Setup-Workstation.ps1` for signed guest tools, key-only SSH and the work share
at `W:`. Credentials never enter the Nix store. Its SPICE/QXL display is 2D;
heavy CAD and Windows gaming remain on the server.

```bash
virsh -c qemu:///system start ubuntu-tools
virsh -c qemu:///system start windows-workstation
virsh -c qemu:///system net-dhcp-leases default
```

SSH to the guest's listed NAT address using its account name. Both consoles use
local SPICE, not a network game stream. virt-manager resizes the guest display
to its window and shares the clipboard once the guest agents run; Windows
guest-tool installation is a post-install step described on its provisioning
CD. Ubuntu's address can change between its first and later boots, so read it
from the lease list rather than reusing an old one.

USB redirection is manual: use the console's **Redirect USB device** menu only
for the device you intend to hand to the guest. Opening a console never
automatically captures the phone or other host USB devices. The NixOS
`virtualisation.spiceUSBRedirection` module installs SPICE's polkit-checked
`cap_fowner` helper to grant and revoke a per-user ACL on the selected device;
installing `spice-gtk` or listing it as a udev package alone does not provide
that privilege. No blanket USB mode or group permission is required.

To retire a guest, export documents, shut it down, and remove its entry from
`workspaces` in `virtualization/default.nix`. Before applying that removal,
undefine the guest with its private disk, NVRAM and TPM cleanup through
libvirt; do not select shared work or installation media for deletion. Remove
only its `workspace-<domain-name>` storage pool and private state subvolume.
Then rebuild the host so initialization no longer recreates that workspace.
Keep the tracked definition and shared work folder for later reuse.

## Layout

- `hosts/<host>/`: host-specific config: hardware, networking, boot, services,
  power tuning.
- `modules/`: reusable system modules (see `modules/README.md`):
  - `core/`: imported by every host (universal CLI packages).
  - `roles/`: one per host kind (`laptop`, `server`); a host imports one role.
  - `features/`: opt-in modules a role pulls in.
  - `hardware/`: per-machine quirks.
- `home/`: home-manager entry points and `dotfiles/`.
- `assets/`: wallpapers.
- `docs/`: longer-form notes.
- `secrets/`: sops-nix encrypted secrets (`docs/secrets.md`).
- `hooks/`: tracked git hooks, wired via `.envrc` on `direnv allow`.
