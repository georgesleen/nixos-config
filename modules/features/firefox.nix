# Firefox: hardware video decode, extensions, and telemetry/new-tab policy.
#
# Extensions are force_installed from AMO's "latest" URL, so they track upstream
# and cannot be removed in about:addons. Add or drop one here, then rebuild.

{ ... }:

let
  # AMO GUID -> slug. Slug comes from
  # https://addons.mozilla.org/api/v5/addons/addon/<guid>/
  extensions = {
    "@contain-facebook" = "facebook-container";
    "ATBC@EasonWong" = "adaptive-tab-bar-colour";
    "jid1-MnnxcxisBPnSXQ@jetpack" = "privacy-badger17";
    "uBlock0@raymondhill.net" = "ublock-origin";
    "{34daeb50-c2d2-4f14-886a-7160b24d66a4}" = "youtube-shorts-block";
    "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
    "{74145f27-f039-47ce-a470-a662b129930a}" = "clearurls";
    "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = "vimium-ff";
  };
in
{
  programs.firefox = {
    enable = true;
    policies = {
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisableTelemetry = true;
      DontCheckDefaultBrowser = true;
      ExtensionSettings = builtins.mapAttrs (_: slug: {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
        installation_mode = "force_installed";
      }) extensions;
      FirefoxHome = {
        Pocket = false;
        SponsoredPocket = false;
        SponsoredTopSites = false;
        TopSites = false;
      };
    };
    preferences = {
      # VA-API hardware video decode — opt-in upstream due to historical driver bugs
      "media.ffmpeg.vaapi.enabled" = true;
      # Force it on even when Firefox detects a potentially problematic GPU
      "media.hardware-video-decoding.force-enabled" = true;
    };
  };
}
