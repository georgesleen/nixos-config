# Declarative OCI containers via Podman + virtualisation.oci-containers. See
# NOTES.md.

{ ... }:

{
  virtualisation.podman = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [
        "--filter"
        "until=168h"
      ];
    };
    defaultNetwork.settings.dns_enabled = true;
  };

  virtualisation.oci-containers.backend = "podman";

  # Example container — copy this block into your host config and uncomment:
}
