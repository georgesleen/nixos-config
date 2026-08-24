# Wi-Fi failover uplink. gs-server joins the gs-openwrt-one AP and holds the
# association, but only carries traffic when the wired link goes down.
# Router-side config: hosts/gs-openwrt-one, docs/gs-openwrt-one.md.
{
  config,
  lib,
  ...
}:

{
  # BCM4352 [14e4:43b1] is served only by the unfree Broadcom `wl` driver; the
  # in-tree drivers claim the PCI slot without driving the chip.
  boot.blacklistedKernelModules = [
    "b43"
    "bcma"
    "bcma_hcd"
    "brcmfmac"
    "brcmsmac"
    "ssb"
  ];
  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
  boot.kernelModules = [ "wl" ];
  hardware.enableRedistributableFirmware = true;
  networking.networkmanager.ensureProfiles = {
    # SSID and PSK are substituted from this env file at profile-write time, so
    # neither value reaches the nix store or git.
    environmentFiles = [ config.sops.templates."openwrt-one-wifi.env".path ];
    profiles.gs-openwrt-one = {
      connection = {
        autoconnect = true;
        id = "gs-openwrt-one";
        type = "wifi";
      };
      ipv4 = {
        # Worse than the wired default route (NetworkManager gives ethernet
        # metric 100), so this link only carries traffic when the wire drops.
        dns-priority = 200;
        method = "auto";
        route-metric = 700;
      };
      ipv6 = {
        addr-gen-mode = "stable-privacy";
        dns-priority = 200;
        method = "auto";
        route-metric = 700;
      };
      wifi = {
        mode = "infrastructure";
        ssid = "$OPENWRT_ONE_AP_SSID";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$OPENWRT_ONE_AP_PSK";
      };
    };
  };
  # broadcom_sta is unmaintained and carries unfixed CVE-2019-9501/9502 (remote
  # code execution from crafted Wi-Fi frames). Matched by name, not by the
  # versioned derivation name, so a kernel bump does not break eval. A
  # mainline-supported USB adapter would retire this whole driver stanza.
  nixpkgs.config.allowInsecurePredicate = pkg: lib.getName pkg == "broadcom-sta";
  sops.secrets.openwrt_one_ap_key = { };
  sops.secrets.openwrt_one_ap_ssid = { };
  sops.templates."openwrt-one-wifi.env".content = ''
    OPENWRT_ONE_AP_SSID=${config.sops.placeholder.openwrt_one_ap_ssid}
    OPENWRT_ONE_AP_PSK=${config.sops.placeholder.openwrt_one_ap_key}
  '';
}
