# Claude Code style auto-mode guardrail for omp: an extension that judges every
# agent tool call with an LLM classifier instead of prompting.
#
# Packaged here because omp's marketplace rejects npm plugin sources ("npm
# plugin sources are not yet supported"), which is the extension's own install
# path. omp loads TypeScript directly under bun, so the source is staged in the
# store and loaded by absolute path; see home/dotfiles/omp.nix.
{
  fetchFromGitHub,
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  dontBuild = true;
  dontConfigure = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/node_modules/unbash"
    cp -r ./. "$out/"
    tar -xzf "$unbash" -C "$out/node_modules/unbash" --strip-components=1
    runHook postInstall
  '';
  meta = {
    description = "Claude Code style auto mode guardrail for pi and oh-my-pi";
    homepage = "https://github.com/georgesleen/pi-automode";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
  pname = "pi-automode";
  # Fork, not upstream v1.16.0, carrying three changes. `classifierModelByProvider`
  # (branch feature/classifier-model-routing): upstream's `classifierModel` is
  # one fixed spec, so a Codex session classified every tool call through the
  # Anthropic account and one provider's rate limit fail-closed the whole
  # session; proposed upstream as czottmann/pi-automode#44, PR #45. Branch
  # omp-hashline-edit-paths on top of it: upstream reads a file tool's target
  # from `input.path`, which omp's hashline `edit` does not have (its targets
  # are `[PATH#TAG]` headers), so `allowInsideWorkingDirectory` never fired and
  # every in-tree edit went to the classifier; the same branch stops the
  # classifier prompt hardcoding self-modification as hard_deny. And branch
  # fallback-on-classifier-failure on top: a configured classifier missing or
  # unauthenticated in the current context (claude-bridge inside a subagent:
  # "No classifier model/API key available") falls back to the session model,
  # and a fast provider failure (429) is retried once, then tried on the
  # session model, instead of failing closed. Drop the fork for the upstream
  # tag once all merge.
  src = fetchFromGitHub {
    hash = "sha256-vAd1ipKt7JRAmKQv6W6yFKxtZ+1FGnKeAmy8VFQpdls=";
    owner = "georgesleen";
    repo = "pi-automode";
    rev = "94b8c02adfc4e5e8601bf8015714ddf22e615826";
  };
  # Sole runtime dependency. bun resolves node_modules by walking up from the
  # importing file, so one at the package root covers extensions/auto-mode.ts.
  unbash = fetchurl {
    hash = "sha256-T9c9xXUJLOGRKOT+eDbGcLeSSW+ywNIVXlkormCArL4=";
    url = "https://registry.npmjs.org/unbash/-/unbash-4.0.10.tgz";
  };
  version = "1.16.0";
})
