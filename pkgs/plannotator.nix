# Plannotator: browser UI to annotate documents and review diffs, with the
# feedback returned to the calling agent. Not in nixpkgs. Upstream ships a Bun
# single binary; autoPatchelf leaves its embedded payload intact, but strip
# would remove it.
{
  autoPatchelfHook,
  fetchurl,
  lib,
  makeWrapper,
  stdenv,
}:
stdenv.mkDerivation (finalAttrs: {
  buildInputs = [ stdenv.cc.cc.lib ];
  dontStrip = true;
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/libexec/plannotator
    # The store copy is read-only; the self updater must not try.
    makeWrapper $out/libexec/plannotator $out/bin/plannotator \
      --set PLANNOTATOR_AUTO_UPDATE 0 \
      --set PLANNOTATOR_UPDATE_CHECK 0
    runHook postInstall
  '';
  meta = {
    description = "Annotate documents and review diffs in the browser for coding agents";
    homepage = "https://github.com/backnotprop/plannotator";
    license = with lib.licenses; [
      asl20
      mit
    ];
    mainProgram = "plannotator";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  pname = "plannotator";
  src = fetchurl {
    hash = "sha256-47L8Kdoa3VMLA07lriWeJ/QsFjx41ccXskXthQeETXs=";
    url = "https://github.com/backnotprop/plannotator/releases/download/v${finalAttrs.version}/plannotator-linux-x64";
  };
  version = "0.28.61";
})
