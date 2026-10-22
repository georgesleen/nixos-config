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
    "sha256-+b3KDU6xCvUs9v12nbIyyRwR7TP2+wS1JkhIzRxIkhI=" =
      "sha256-5MIh9GFAf9n9CqkJHbma/sHpfix6a3yKuCq9cOWcC0k=";
    # routing/packages.adb
    "sha256-A/wuKSr4DGE3bLxoZ2JWaGMXJCt7ReZXU4+cVNjNGJA=" =
      "sha256-DGYlvFXDcNmFOydrD9XnJNrSuaSIqlKjd7FFGPb62Ws=";
    # packages/packages.adb
    "sha256-HpmU6Ky1GAFWr8EvPrfOUtrVkUWYpDdVV4bhm00TQzI=" =
      "sha256-knqtabU2udVHH5Q7oJ220h1MkfvJua1xb18hwJFsu/0=";
    # sha256sums
    "sha256-QaoOtxfG3hRQ/zjZa1OTOCzipKfkc4TeIo/UK6QdZYc=" =
      "sha256-4lJZAqw8v8NBTrsc5AOuaeUl+GtIOIntUpChyHcl9Mc=";
    # telephony/packages.adb
    "sha256-ecACA/OKmFWph4hAoQ7ixaa+OjR8pGMz6UjV2C2r34M=" =
      "sha256-sTgKWJVqlG+HvL0Ttt2uRXGCAr+vXkb/C77FX18eAS4=";
    # base/packages.adb
    "sha256-zjD8Xld5Yd06qLIPa3Zm7hDALDbHHr4gmMNxZz6Vs6c=" =
      "sha256-f85wV9lAT26L/15Svf4mpEZmfn4rIM9FJS3PQJJlOOY=";
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

  # Shared with every other host here, so a new device is added in one place.
  authorizedKeys = pkgs.writeText "authorized_keys" (
    lib.concatMapStrings (key: key + "\n") (import ../../keys/authorized.nix)
  );

  files = pkgs.runCommand "gs-pi1-parents-files" { } ''
    mkdir -p $out/etc/uci-defaults
    cp ${./files/uci-defaults/90-net} $out/etc/uci-defaults/90-net
    cp ${./files/uci-defaults/91-ssh} $out/etc/uci-defaults/91-ssh
    substitute ${./files/uci-defaults/95-tailscale.in} \
      $out/etc/uci-defaults/95-tailscale \
      --subst-var-by TS_AUTHKEY ${lib.escapeShellArg tsAuthkey}
    chmod +x $out/etc/uci-defaults/90-net $out/etc/uci-defaults/91-ssh $out/etc/uci-defaults/95-tailscale
    mkdir -p $out/etc/dropbear
    cp ${authorizedKeys} $out/etc/dropbear/authorized_keys
    chmod 600 $out/etc/dropbear/authorized_keys
    # Re-derives the advertised subnet on every lan ifup, so the board adapts
    # when it is moved to a different network instead of keeping a stale route.
    # chmod +x here is cosmetic: ImageBuilder does not carry the mode into the
    # image, so every caller invokes these as `sh <path>`.
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
