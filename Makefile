# Launch the throwaway gs-pi4-vm media VM (host: hosts/gs-pi4-vm). `make` builds
# and boots it detached, then prints the URLs; `make stop` shuts it down.
SHELL := bash
.ONESHELL:
.PHONY: vm build stop ssh log status

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
