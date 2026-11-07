{
  config,
  inputs,
  lib,
  ...
}:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.fizzbot-3.nixosModules.default
  ];

  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = ../../secrets/gs-pi4-fizzbot.yaml;
    secrets.fizzbot_discord_token = { };
  };

  services.fizzbot = {
    enable = true;
    tokenFile = config.sops.secrets.fizzbot_discord_token.path;
    model = "fizzbot";
  };

  systemd.services.fizzbot.wantedBy = lib.mkForce [ ];
}
