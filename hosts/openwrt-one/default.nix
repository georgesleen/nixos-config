# OpenWrt One (mediatek/filogic) firmware image, built declaratively via the
# upstream OpenWrt ImageBuilder (astro/nix-openwrt-imagebuilder). Not a NixOS
# host: this evaluates to a sysupgrade .bin package, built on the T480s only
# (ImageBuilder is x86_64-linux only). See docs/openwrt-one.md.
#
# WISP mode: Wi-Fi client uplink (wwan) -> NAT -> wired LAN + a local AP.
{
  openwrt-imagebuilder,
  pkgs,
}:
let
  inherit (pkgs) lib;

  # Pinned for stability. 25.12 switched to the apk package manager; no reason
  # to ride that on a router. Both 24.10.8 and 25.12.5 carry the openwrt_one
  # profile (mediatek/filogic).
  release = "24.10.8";

  profiles = openwrt-imagebuilder.lib.profiles { inherit pkgs release; };

  # Secret Wi-Fi values, decrypted at build time by `sops exec-env` (Makefile
  # `openwrt-one` target). builtins.getEnv needs `--impure`; when absent (plain
  # `nix flake check`) these fall back to obvious placeholders so eval still
  # succeeds and yields a harmless non-secret test image.
  envOr =
    name: default:
    let
      v = builtins.getEnv name;
    in
    if v == "" then default else v;
  wwanSsid = envOr "openwrt_one_wwan_ssid" "CHANGEME_wwan_ssid";
  wwanKey = envOr "openwrt_one_wwan_key" "CHANGEME_wwan_key";
  apSsid = envOr "openwrt_one_ap_ssid" "CHANGEME_ap_ssid";
  apKey = envOr "openwrt_one_ap_key" "CHANGEME_ap_key";

  # /etc/uci-defaults/* run once on first boot (of a fresh flash) and then
  # remove themselves: a reflash re-asserts this exact state. Non-secret
  # structure and the secret-bearing wireless script are kept separate.
  files = pkgs.runCommand "openwrt-one-files" { } ''
    mkdir -p $out/etc/uci-defaults
    cp ${./files/uci-defaults/10-wisp} $out/etc/uci-defaults/10-wisp
    substitute ${./files/uci-defaults/20-wisp-wireless.in} \
      $out/etc/uci-defaults/20-wisp-wireless \
      --subst-var-by WWAN_SSID ${lib.escapeShellArg wwanSsid} \
      --subst-var-by WWAN_KEY ${lib.escapeShellArg wwanKey} \
      --subst-var-by AP_SSID ${lib.escapeShellArg apSsid} \
      --subst-var-by AP_KEY ${lib.escapeShellArg apKey}
    cp ${./files/uci-defaults/30-ssh} $out/etc/uci-defaults/30-ssh
    cp ${./files/uci-defaults/40-adblock-dns} $out/etc/uci-defaults/40-adblock-dns
    chmod +x $out/etc/uci-defaults/10-wisp $out/etc/uci-defaults/20-wisp-wireless $out/etc/uci-defaults/30-ssh $out/etc/uci-defaults/40-adblock-dns
    # Root's authorized SSH public key; 30-ssh then disables password auth.
    mkdir -p $out/etc/dropbear
    cp ${./files/etc/dropbear/authorized_keys} $out/etc/dropbear/authorized_keys
    chmod 600 $out/etc/dropbear/authorized_keys
  '';
in
openwrt-imagebuilder.lib.build (
  profiles.identifyProfile "openwrt_one"
  // {
    inherit release files;
    packages = [
      # Full wpad: client + AP with WPA2/WPA3(SAE). Default image ships the
      # -basic build; swap it out.
      "-wpad-basic-mbedtls"
      "wpad-mbedtls"
      # Web UI for live debugging / iterating the WISP setup.
      "luci"
    ];
  }
)
