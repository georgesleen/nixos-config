# Launch the throwaway gs-pi4-vm media VM (host: hosts/gs-pi4-vm). `make` builds
# and boots it detached, then prints the URLs; `make stop` shuts it down.
SHELL := bash
.ONESHELL:
.PHONY: vm build stop ssh log status gs-openwrt-one gs-openwrt-one-flash test

ROOT    := $(patsubst %/,%,$(dir $(realpath $(firstword $(MAKEFILE_LIST)))))
HOST    ?= gs-pi4-vm
PORT    ?= 2222
LOGIN   ?= george-sleen
CONSOLE := /var/tmp/$(HOST)-console.log
VMATTR  := $(ROOT)\#nixosConfigurations.$(HOST).config.system.build.vm
SSHOPT  := -p $(PORT) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

vm:
	@if ss -tln 2>/dev/null | grep -qE ':$(PORT)\b'; then
	  echo "gs-pi4-vm already up (port $(PORT) busy) — 'make ssh' or 'make stop'."
	  exit 0
	fi
	echo "Building $(HOST)..."
	run="$$(nix build --no-link --print-out-paths '$(VMATTR)')/bin/run-$(HOST)-vm"
	echo "Launching detached (console: $(CONSOLE))"
	setsid "$$run" >'$(CONSOLE)' 2>&1 </dev/null &
	for i in $$(seq 1 45); do
	  ssh $(SSHOPT) -o ConnectTimeout=3 -o BatchMode=yes $(LOGIN)@localhost true 2>/dev/null && break
	  sleep 4
	done
	echo
	echo "  Jellyseerr  http://localhost:5055   (request movies + shows)"
	echo "  Jellyfin    http://localhost:8096"
	echo "  Radarr :7878   Sonarr :8989   Prowlarr :9696"
	echo "  ssh: make ssh    stop: make stop    console: make log"

build:
	nix build --no-link --print-out-paths '$(VMATTR)'

# Run the shell unit tests (every flake `checks` output). Use this instead of
# `nix flake check`, which also builds gs-openwrt-one, whose ImageBuilder
# package index is a fixed-output derivation that drifts upstream and fails.
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

# Build the OpenWrt One WISP image. sops exec-env decrypts the Wi-Fi secrets
# into the environment; --impure lets the flake read them via builtins.getEnv.
# Long build: consider `inhibit-sleep` first. Output .bin path is printed.
gs-openwrt-one:
	@sops exec-env secrets/secrets.yaml \
	  'nix build --print-out-paths "$(ROOT)#packages.x86_64-linux.gs-openwrt-one" --impure'

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

stop:
	@ssh $(SSHOPT) $(LOGIN)@localhost 'sudo poweroff' 2>/dev/null || echo "(not running?)"
	@echo "poweroff sent"

status:
	@ssh $(SSHOPT) $(LOGIN)@localhost bash -s < '$(ROOT)/hosts/gs-pi4-vm/status.sh'
	@echo "disk (host) $$(du -h /var/tmp/$(HOST).qcow2 2>/dev/null | cut -f1) qcow2"

ssh:
	@ssh $(SSHOPT) $(LOGIN)@localhost

log:
	@tail -f '$(CONSOLE)'
