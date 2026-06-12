# Declarative OCI containers via Podman + virtualisation.oci-containers.
# Each container becomes a systemd service: podman-<name>.service
# Add containers under virtualisation.oci-containers.containers in any
# host/role module that imports this one.

{ pkgs, ... }:

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
  #
  # virtualisation.oci-containers.containers.whoami = {
  #   image = "traefik/whoami:latest";
  #   ports = [ "8080:80" ];
  #   autoStart = true;
  # };
  #
  # Available options per container:
  #   image          — image reference (tag or digest)
  #   imageFile      — pkgs.dockerTools image built in Nix (skips registry pull)
  #   ports          — [ "host:container" ]
  #   volumes        — [ "/host/path:/container/path" ]
  #   environment    — { KEY = "value"; }
  #   environmentFiles — [ /run/secrets/foo.env ] (for secrets)
  #   extraOptions   — [ "--network=host" ] etc.
  #   autoStart      — bool, default true
  #   user           — run as this uid:gid inside the container
}
