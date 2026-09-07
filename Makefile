# Build targets for this flake: the shell unit tests, the OpenWrt One router
# image, and the Raspberry Pi 1 Tailscale node image.
SHELL := bash
.ONESHELL:
.PHONY: check-boot-order gs-openwrt-one gs-openwrt-one-flash gs-pi1-parents test

ROOT    := $(patsubst %/,%,$(dir $(realpath $(firstword $(MAKEFILE_LIST)))))

test:
	@names=$$(nix eval --raw '$(ROOT)#checks.x86_64-linux' \
	    --apply 'cs: builtins.concatStringsSep " " (builtins.attrNames cs)')
	failed=0
	for n in $$names; do
	  echo "== $$n"
	  nix build --no-link -L "$(ROOT)#checks.x86_64-linux.$$n" || failed=1
	done
	if [ $$failed -ne 0 ]; then echo "SUITES FAILED"; exit 1; fi
	echo "all suites passed"

# Check a live host's systemd ordering graph for cycles. Run after a `switch`
# or `test` (which load the new units) and BEFORE rebooting: systemd breaks a
# cycle by deleting an arbitrary job, and on gs-pi4 it picked dbus-broker and
# local-fs.target, so the host booted with no network and no drive.
#   make check-boot-order HOST=george-sleen@192.168.10.219
check-boot-order:
	@test -n "$(HOST)" || { echo "usage: make check-boot-order HOST=<user@host>"; exit 2; }
	ssh -o BatchMode=yes "$(HOST)" 'systemd-analyze dot --order 2>/dev/null' \
	  | sh '$(ROOT)/modules/features/systemd-order-cycles.sh' \
	  && echo "no ordering cycles on $(HOST)"

# Build the OpenWrt One WISP image. sops exec-env decrypts the Wi-Fi secrets
# into the environment; --impure lets the flake read them via builtins.getEnv.
# Long build: consider `inhibit-sleep` first. Output .bin path is printed.
gs-openwrt-one:
	@sops exec-env secrets/secrets.yaml \
	  'nix build --print-out-paths "$(ROOT)#packages.x86_64-linux.gs-openwrt-one" --impure'

# Build the Raspberry Pi 1 B+ Tailscale node image. Writes an SD-card image, not
# a sysupgrade file: flash it once with dd, then manage the board over Tailscale
# SSH. Needs `pi_parents_ts_authkey` in secrets/secrets.yaml.
gs-pi1-parents:
	@sops exec-env secrets/secrets.yaml \
	  'nix build --print-out-paths "$(ROOT)#packages.x86_64-linux.gs-pi1-parents" --impure'

# Build then flash the router. Nix only builds the image; this is not a NixOS
# host, so there is no `nixos-rebuild switch` equivalent.
#
# -n does NOT keep config, which is required: everything the image configures
# lives in files/uci-defaults, and those run only on the first boot of a clean
# flash. Keeping settings would land on the new release with the old uci state.
#
# The transfer is `cat | ssh`, not scp: OpenSSH 9+ speaks SFTP by default and
# Dropbear ships no sftp-server, so plain scp fails with
# "/usr/libexec/sftp-server: not found". `scp -O` also works.
#
# Reachability is LAN-side (both ports are in br-lan), so a failed first boot
# leaves it on OpenWrt's default 192.168.1.1, recoverable over the wire.
gs-openwrt-one-flash: ROUTER ?= 192.168.10.1
gs-openwrt-one-flash:
	@out=$$(sops exec-env secrets/secrets.yaml \
	  'nix build --print-out-paths "$(ROOT)#packages.x86_64-linux.gs-openwrt-one" --impure')
	img=$$(echo "$$out"/*-squashfs-sysupgrade.itb)
	[ -f "$$img" ] || { echo "no sysupgrade image in $$out"; exit 1; }
	echo "image: $$img"
	cat "$$img" | ssh root@$(ROUTER) 'cat > /tmp/sysupgrade.itb'
	local=$$(sha256sum "$$img" | awk '{print $$1}')
	remote=$$(ssh root@$(ROUTER) 'sha256sum /tmp/sysupgrade.itb' | awk '{print $$1}')
	[ "$$local" = "$$remote" ] || { echo "checksum mismatch, refusing to flash"; exit 1; }
	ssh root@$(ROUTER) 'sysupgrade -T /tmp/sysupgrade.itb' || { echo "image rejected by device"; exit 1; }
	echo "flashing; the router drops for 2-3 min and returns on $(ROUTER)"
	ssh root@$(ROUTER) 'sysupgrade -n /tmp/sysupgrade.itb' || true
