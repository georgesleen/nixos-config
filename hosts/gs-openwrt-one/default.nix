# OpenWrt One (mediatek/filogic) firmware image, built declaratively via the
# upstream OpenWrt ImageBuilder (astro/nix-openwrt-imagebuilder). Not a NixOS
# host: this evaluates to a sysupgrade .bin package, built on the T480s only
# (ImageBuilder is x86_64-linux only). See docs/gs-openwrt-one.md.
#
# WISP mode: Wi-Fi client uplink (wwan) -> NAT -> wired LAN + a local AP.
{
  openwrt-imagebuilder,
  pkgs,
}:
let
  inherit (pkgs) lib;

  # 25.12 replaces opkg with apk on the router (`apk add`, not `opkg install`).
  # uci-defaults run once on the first boot of a CLEAN flash, so a sysupgrade
  # that keeps settings will not re-run them. Flash without keeping settings.
  release = "25.12.5";

  # OpenWrt rebuilds package indexes in place, so every cached `packages.adb`
  # hash goes stale and fails its fixed-output derivation; updating the input
  # does not help. profiles takes cachePath for this. Refresh a value with
  # `nix store prefetch-file --json <url>` whenever a hash mismatch appears.
  freshHashes = {
    # luci/packages.adb
    "sha256-33oou+C7XNKX5bfzolAWc1swNtI157xA/HE281ZwBak=" =
      "sha256-xXbsxmyS99gw3NFD3sJNljM5PH+kgFjLsL1fkQGaL50=";
    # telephony/packages.adb
    "sha256-5rkxNdgfQ2IUESSe5EepqWrOPLAVYiX6S2MsmLfLZPM=" =
      "sha256-Q5uLMEqdvkzh6OwmBrUQotQ/oGaPHwDVluvnJH7J2HE=";
    "sha256-8kxQjOEnrcnRV8p4tZkDTZtCk6foNzWRP/pYwe/MFXE=" =
      "sha256-5sKSdLR7y5Mk2g9azsxWrF2o+HpFaZY1qKqvJpTlThQ=";
    # base/packages.adb
    "sha256-IHRKrNsMoJ+jqrd8kqq6KuotxdfdHPiAOsakV/nJH+Q=" =
      "sha256-AW83oJVu3ituBAlSEcGWMoqmcW0mgnKynf72wPPVaVk=";
    # packages/packages.adb
    "sha256-LxQKYJRKCAA8/mG6jedNUjuac8VvrJdwcOagCO7j76I=" =
      "sha256-YWpG0HCCzpnUy739B0uAaQK3nRbNxqmrK1ZtSKvJDLs=";
    "sha256-NBcmKXnHGqi3eX25i7w5CbmhsJ0h9PB642NRUnAsZTc=" =
      "sha256-+vZzLxbxcWpQii2yBIlFMp4q3APK6cLz0wyE/a0yN1U=";
    # routing/packages.adb
    "sha256-O/W9OMfGgyKRKincjsLtltYt3kCJuWMIyEd9ndZXJuQ=" =
      "sha256-blpIsyVqhE69QX6R/xm2WCqxenWPsKTGzhAKHYS0K9E=";
    "sha256-PjfEgiCUl/mj7vS9x2FJ2hezPNnX4fmFTxBsPkKwuEk=" =
      "sha256-qd/g9WK42Led3F+UgmPIxkJm1wz93CPWgnNyrxLn49o=";
    "sha256-Tp/TDCmvS6YXliemMF0KNVc66H6tAvPRH21PERh1cbI=" =
      "sha256-4+ipgpPjsT2LtDKcYLlWfhOldyMdHnGWyDAyspij6Bs=";
    # aarch64_cortex-a53/sha256sums
    "sha256-XQlZwVdJOEA32yygfBhJtLNiXvXYPW/uSLJf6KtouAs=" =
      "sha256-Jtf/cZmIYbn1aDlxzTXWfK7mqBGBD7t3zURGmHoIJL8=";
    "sha256-p0TOVWQtrU0pMD64vUTBWIuEgtZGlHNsiCGxXRN5NXs=" =
      "sha256-Y/FzOTQrvpl4PSRzD2XeyVa56BQ5IEiT7vuNzCM4jxw=";
    "sha256-q2FjxGwePvgs0oNIUITegAHcgp9bwEdjhlbRWC5Jg4A=" =
      "sha256-aeYGEHALVplGPrPaEZM4OzdFo469ZEWOWZxgcLTN1mk=";
  };

  cachePath = pkgs.runCommand "openwrt-${release}-cache-fresh" { } (
    ''
      cp -r ${openwrt-imagebuilder}/cache/${release} $out
      chmod -R u+w $out
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (stale: fresh: ''
        find $out -name '*.nix' -exec sed -i 's|${stale}|${fresh}|g' {} +
      '') freshHashes
    )
  );

  profiles = openwrt-imagebuilder.lib.profiles { inherit pkgs release cachePath; };

  # Secret Wi-Fi values, decrypted at build time by `sops exec-env` (Makefile
  # `gs-openwrt-one` target). builtins.getEnv needs `--impure`; when absent
  # (plain `nix flake check`) these fall back to obvious placeholders so eval
  # still succeeds and yields a harmless non-secret test image.
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
  # Reusable Tailscale auth key (from sops); used once at the first-boot join.
  tsAuthkey = envOr "openwrt_one_ts_authkey" "";
  # Static dropbear host key (from sops, base64-encoded: it's a binary
  # dropbearkey-format file, not an OpenSSH PEM one, which dropbear's OpenWrt
  # build rejects as invalid and silently replaces at boot). Baked into the
  # image so a reflash doesn't regenerate it, keeping the SSH fingerprint
  # (and known_hosts) stable across sysupgrades.
  sshHostKey = envOr "openwrt_one_ssh_host_key" "";

  # Shared with every other host here, so a new device is added in one place.
  # uci-defaults do not re-run on a settings-keeping sysupgrade, but this file
  # is copied by the ImageBuilder itself, so a reflash always re-asserts it.
  authorizedKeys = pkgs.writeText "authorized_keys" (
    lib.concatMapStrings (key: key + "\n") (import ../../keys/authorized.nix)
  );

  # /etc/uci-defaults/* run once on first boot (of a fresh flash) and then
  # remove themselves: a reflash re-asserts this exact state. Non-secret
  # structure and the secret-bearing wireless script are kept separate.
  files = pkgs.runCommand "gs-openwrt-one-files" { } ''
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
    substitute ${./files/uci-defaults/50-tailscale.in} \
      $out/etc/uci-defaults/50-tailscale \
      --subst-var-by TS_AUTHKEY ${lib.escapeShellArg tsAuthkey}
    chmod +x $out/etc/uci-defaults/10-wisp $out/etc/uci-defaults/20-wisp-wireless $out/etc/uci-defaults/30-ssh $out/etc/uci-defaults/40-adblock-dns $out/etc/uci-defaults/50-tailscale
    # Root's authorized SSH public keys; 30-ssh then disables password auth.
    mkdir -p $out/etc/dropbear
    cp ${authorizedKeys} $out/etc/dropbear/authorized_keys
    chmod 600 $out/etc/dropbear/authorized_keys
    # Static dropbear host key (see sshHostKey above), keeping the SSH
    # fingerprint stable across reflashes instead of dropbear generating a
    # fresh one on every first boot.
    printf '%s' ${lib.escapeShellArg sshHostKey} | base64 -d > $out/etc/dropbear/dropbear_ed25519_host_key
    chmod 600 $out/etc/dropbear/dropbear_ed25519_host_key
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
      # Tailscale (pulls kmod-tun); node joins on first boot via 50-tailscale.
      "tailscale"
    ];
  }
)
