#!/bin/sh
# Reports whether the Thunderbolt controller is wedged. Prints `wedged` or `ok`.
#
# A hung ICM leaves the bridge functions (8086:15c0) on the PCI bus with the
# NHI (8086:15bf) gone, or the NHI present with an empty thunderbolt domain.
# Either way hotplug is invisible and replugging the dock does nothing.
#
# With the argument `domain-up`, instead exits 0 if the thunderbolt domain has
# any device and 1 if it is empty. That is the check tb-recover uses to decide
# whether a power cycle worked.
#
# Split out of tb-recover so the detection is testable. Overrides for tests:
#   PCI_DEVICES  (default /sys/bus/pci/devices)
#   TB_DEVICES   (default /sys/bus/thunderbolt/devices)

pci_devices="${PCI_DEVICES:-/sys/bus/pci/devices}"
tb_devices="${TB_DEVICES:-/sys/bus/thunderbolt/devices}"

# present <device-id>: an Intel (0x8086) PCI function with this device id.
present() {
  for d in "$pci_devices"/*; do
    [ -r "$d/vendor" ] && [ -r "$d/device" ] || continue
    read -r vendor < "$d/vendor" || continue
    read -r device < "$d/device" || continue
    [ "$vendor" = "0x8086" ] && [ "$device" = "$1" ] && return 0
  done
  return 1
}

domain_up() {
  for d in "$tb_devices"/*; do
    [ -e "$d" ] && return 0
  done
  return 1
}

if [ "${1-}" = "domain-up" ]; then
  domain_up
  exit $?
fi

if present 0x15c0 && ! present 0x15bf; then
  echo wedged        # bridges alive, NHI gone
elif present 0x15bf && ! domain_up; then
  echo wedged        # NHI alive, ICM dead
else
  echo ok
fi
