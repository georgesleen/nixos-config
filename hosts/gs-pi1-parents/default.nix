# Raspberry Pi 1 Model B+ (bcm27xx/bcm2708, ARMv6) as a Tailscale exit node and
# subnet router for a remote household. Built declaratively from the upstream
# OpenWrt ImageBuilder, exactly like gs-openwrt-one. Output is an SD-card image
# to write once with dd, not a sysupgrade file.
#
# Why OpenWrt and not NixOS: nixpkgs publishes no binary cache for armv6l, so a
# NixOS system would build glibc, gcc, systemd and the kernel from source under
# QEMU emulation. OpenWrt ships prebuilt ARMv6 packages, so ImageBuilder only
# assembles them and nothing is compiled at all.
{
  openwrt-imagebuilder,
  pkgs,
}:
let
  inherit (pkgs) lib;

  release = "25.12.5";

  # Same in-place package-index drift as gs-openwrt-one: OpenWrt rewrites the
  # indexes, so cached hashes go stale and fail their fixed-output derivation.
  # This architecture (arm_arm1176jzf-s_vfp) has its own set. Refresh a value
  # with `nix store prefetch-file --json <url>` when a mismatch appears.
  freshHashes = {
    # luci/packages.adb
    "sha256-NSdbTxGqSaLHpRPWt5+KmNcLIYTyIhozmVBf6jfHb5M=" =
      "sha256-fu0JV8GTFWa3dszOEipZgImfNKR/Wxk4C6TSUsUQM3A=";
    # routing/packages.adb
    "sha256-Nxenp25GBHrCsr9oTfdHToVoFxzX8aAg/YlsRmlUFAA=" =
      "sha256-QkrzbG0grCFdBkLesKAB+RgmPngypm3ygPxcUnsbsZ0=";
    # telephony/packages.adb
    "sha256-TKjFKuvuRhJ0e7gQvNnpPDr1IlLNz3ByuAm54yAp74I=" =
      "sha256-RbJxEYTr2rr7LGGICfLlOLVqYfkOcP/2JFdNcKwZP2A=";
    # base/packages.adb
    "sha256-pVrvLsJt1O9C30gUDmwtIaeJitRSq1AxhMEBp1wJBAw=" =
      "sha256-X+HpO7jZuj7EtU0vx2d+2ov1QbU9nfei15agzHEylmE=";
    # packages/packages.adb
    "sha256-rSzKBIeJ2oPSc35Bkg0sfZVRllo/v1gKKx+pSeH1em4=" =
      "sha256-aqhXXm901jshNfwUqsCrgTKNXXXKykzMyMIiJLmkWt4=";
    # sha256sums
    "sha256-wKhO7ObUHWh78udtXwgJsGFgnTV09j0z7kdcxdgq8Vc=" =
      "sha256-oC/SQHEXXYJBrxJvB8JSPaE+ZU1HNzwXJk62Y9wKRtc=";
  };

  cachePath = pkgs.runCommand "openwrt-${release}-cache-fresh-armv6" { } (
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

  # Reusable Tailscale auth key, decrypted at build time by `sops exec-env`
  # (Makefile `gs-pi1-parents`). Absent (plain eval) it falls back to an empty
  # string so `nix flake check` still evaluates and yields a keyless image.
  envOr =
    name: default:
    let
      v = builtins.getEnv name;
    in
    if v == "" then default else v;
  tsAuthkey = envOr "pi_parents_ts_authkey" "";

  files = pkgs.runCommand "gs-pi1-parents-files" { } ''
    mkdir -p $out/etc/uci-defaults
    cp ${./files/uci-defaults/10-net} $out/etc/uci-defaults/10-net
    cp ${./files/uci-defaults/30-ssh} $out/etc/uci-defaults/30-ssh
    substitute ${./files/uci-defaults/50-tailscale.in} \
      $out/etc/uci-defaults/50-tailscale \
      --subst-var-by TS_AUTHKEY ${lib.escapeShellArg tsAuthkey}
    chmod +x $out/etc/uci-defaults/10-net $out/etc/uci-defaults/30-ssh $out/etc/uci-defaults/50-tailscale
    mkdir -p $out/etc/dropbear
    cp ${./files/etc/dropbear/authorized_keys} $out/etc/dropbear/authorized_keys
    chmod 600 $out/etc/dropbear/authorized_keys
    # Re-derives the advertised subnet on every lan ifup, so the board adapts
    # when it is moved to a different network instead of keeping a stale route.
    mkdir -p $out/usr/bin $out/etc/hotplug.d/iface
    cp ${./files/usr/bin/ts-advertise-routes} $out/usr/bin/ts-advertise-routes
    cp ${./ts-route.sh} $out/usr/bin/ts-route.sh
    cp ${./files/etc/hotplug.d/iface/99-tailscale-routes} $out/etc/hotplug.d/iface/99-tailscale-routes
    chmod +x $out/usr/bin/ts-advertise-routes $out/usr/bin/ts-route.sh $out/etc/hotplug.d/iface/99-tailscale-routes
  '';
in
openwrt-imagebuilder.lib.build (
  profiles.identifyProfile "rpi"
  // {
    inherit release files;
    packages = [
      # Tailscale, and the TUN driver it needs. Without kmod-tun tailscaled
      # falls back to netstack mode, which cannot do subnet routing or act as
      # an exit node at all, so this is a hard requirement rather than a
      # performance tweak.
      "tailscale"
      "kmod-tun"
      # This board has no radio, so drop the wireless stack the stock image
      # carries. Nothing else is added: the whole point is a minimal system.
      "-wpad-basic-mbedtls"
    ];
  }
)
