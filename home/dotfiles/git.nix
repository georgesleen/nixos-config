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
      core.pager = "delta";
      init.defaultBranch = "main";
      pull.rebase = false;
      interactive.diffFilter = "delta --color-only";
      delta = {
        navigate = true;
        dark = true;
        line-numbers = true;
        hyperlinks = true;
        syntax-theme = "OneHalfDark";
        hunk-header-style = "file line-number syntax";
        hunk-header-file-style = "bold yellow";
        file-style = "bold yellow";
        blame-format = "{author:<15} {timestamp:<15} {commit:<8} {filename}\n";
      };
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper = {
      enable = true;
    };
  };
}
