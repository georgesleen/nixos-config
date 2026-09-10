{
  config,
  pkgs,
  ...
}:

{
  # omp's own gate must be wide open. pi-automode replaces the permission
  # prompt rather than answering it: it sees each `tool_call` event and either
  # lets the tool run or blocks it. Below `yolo`, omp prompts first and the
  # classifier never gets the chance. The extension is fail-closed once loaded
  # (a failed model call, an auth error or an unparseable reply all block), but
  # a session where it fails to LOAD has no gate at all, so check
  # `/automode status` before trusting one.
  #
  # Loaded by absolute store path because omp's marketplace rejects npm plugin
  # sources, which is the extension's own install path. See pkgs/pi-automode.nix.
  home.file.".omp/agent/config.yml".source = (pkgs.formats.yaml { }).generate "omp-config.yml" {
    extensions = [ "${pkgs.pi-automode}/extensions/auto-mode.ts" ];
    tools.approvalMode = "yolo";
  };

  # pi-automode reads `~/.pi`, never `~/.omp`, whichever host it runs under.
  # Its PI_AUTOMODE_SETTINGS_JSON source would avoid the stray directory, but
  # home-manager writes session variables as `export VAR="value"` with no
  # escaping, and this value is JSON.
  #
  # Tuned for long unattended runs. `allow` and `environment` are prose the
  # classifier reads; they are exceptions to `soft_deny` only and can never
  # override `hard_deny`, unlike a `permissions.allow` rule, which skips
  # classifier policy entirely. `$defaults` keeps the built-in entries for its
  # own section.
  home.file.".pi/agent/extensions/pi-automode/config.json".text = builtins.toJSON {
    autoMode = {
      allow = [
        "$defaults"
        "Deploying this NixOS config to the author's own hosts over ssh (gs-pi4, gs-server, gs-pi1-parents, gs-openwrt-one), including nixos-rebuild, systemctl, journalctl, and reading service state."
        "Running nixos-rebuild build, switch, test or dry-activate on the local machine, and nix build, nix flake update, nix store operations."
        "Starting local development servers, test harnesses and build watchers bound to localhost or the tailnet."
        "Restarting, stopping and starting systemd units on the author's own hosts."
      ];
      # The single biggest source of false blocks. Built-in soft_deny rejects
      # "overwriting local files that existed before session start" unless the
      # request named the task, the repo and the path scopes, which fires on
      # nearly every edit of an existing file. True routes non-protected
      # in-tree file access to the deterministic allow tier, so it never
      # reaches the classifier. Protected paths (.git, .envrc, shell rc files)
      # and everything that executes are still judged.
      allowInsideWorkingDirectory = true;
      # deniedPaths is checked before the classifier, so these never reach the
      # model. Entries accumulate across config sources instead of replacing.
      deniedPaths = [
        "${config.home.homeDirectory}/.ssh"
        "/etc/nixos/secrets"
        "/run/secrets"
      ];
      # Context, not permission. These entries stop the classifier reading a
      # personal host as production or shared infrastructure, which is what the
      # built-in soft_deny rules about deploys and remote shells are guarding.
      environment = [
        "$defaults"
        "Every machine here is a personal single-user host on one tailnet. There is no production estate, no shared infrastructure, no other users, and no customer data. Downtime affects nobody but the author."
        "Hosts: gs-thinkpad-t480s (laptop, the machine the agent usually runs on), gs-server, gs-pi4 (media server), gs-pi1-parents (remote OpenWrt gateway), gs-openwrt-one (router)."
        "The NixOS config is declarative and every switch is rollback-able from the boot menu, so a bad rebuild is recoverable rather than destructive."
      ];
      # Off by default. On, so a run that blocks too much can be tuned from the
      # real denial record (`/automode denials`) instead of guesswork.
      # classifierIo stays off: it would log full tool payloads.
      log = {
        classifierIo = false;
        enabled = true;
      };
    };
  };
}
