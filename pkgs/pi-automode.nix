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
    homepage = "https://github.com/czottmann/pi-automode";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
  pname = "pi-automode";
  src = fetchFromGitHub {
    hash = "sha256-AZf+wH83JBjgwvkLFEewEdkCtT2sD8CTChwblMAY5aM=";
    owner = "czottmann";
    repo = "pi-automode";
    tag = "v${finalAttrs.version}";
  };
  # Sole runtime dependency. bun resolves node_modules by walking up from the
  # importing file, so one at the package root covers extensions/auto-mode.ts.
  unbash = fetchurl {
    hash = "sha256-T9c9xXUJLOGRKOT+eDbGcLeSSW+ywNIVXlkormCArL4=";
    url = "https://registry.npmjs.org/unbash/-/unbash-4.0.10.tgz";
  };
  version = "1.16.0";
})
