{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    settings.user = {
      name = "George Sleen";
      email = "147893275+georgeSleen@users.noreply.github.com";
    };
    settings = {
      core.editor = "hx";
      init.defaultBranch = "main";
      pull.rebase = false;
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper = {
      enable = true;
    };
  };
}
