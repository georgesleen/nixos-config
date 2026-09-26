# difit: GitHub-style "Files changed" view of a local git diff in the
# browser, with line/range comments an agent can read back
# (`difit comment get --port N`). Not in nixpkgs. Built from source because
# the npm tarball ships dist/ without its runtime node_modules.
{
  autoPatchelfHook,
  fetchFromGitHub,
  fetchPnpmDeps,
  git,
  lib,
  makeWrapper,
  nodejs,
  pnpmConfigHook,
  pnpm_11,
  stdenv,
  xdg-utils,
}:
let
  pnpm = pnpm_11; # upstream pins packageManager pnpm@11
in
stdenv.mkDerivation (finalAttrs: {
  # The prebuilt @parcel/watcher addon links libstdc++, which is not on any
  # default search path on NixOS.
  buildInputs = [ stdenv.cc.cc.lib ];
  buildPhase = ''
    runHook preBuild
    NODE_ENV=production pnpm --filter difit run build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    # pnpm cannot prune a workspace; reinstall prod deps only.
    find . -name node_modules -type d -prune -exec rm -rf {} +
    pnpm install --offline --prod --filter-prod difit --ignore-scripts
    mkdir -p $out/lib/difit $out/bin
    cp -r dist package.json node_modules $out/lib/difit/
    # git: simple-git shells out to it. xdg-utils: the `open` package
    # launches the browser through xdg-open.
    makeWrapper ${lib.getExe nodejs} $out/bin/difit \
      --add-flags $out/lib/difit/dist/cli/index.js \
      --set NODE_ENV production \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          xdg-utils
        ]
      }
    runHook postInstall
  '';
  meta = {
    description = "GitHub-style local git diff viewer with AI-ready review comments";
    homepage = "https://github.com/yoshiko-pg/difit";
    license = lib.licenses.mit;
    mainProgram = "difit";
    platforms = lib.platforms.linux;
  };
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    nodejs
    pnpm
    pnpmConfigHook
  ];
  pname = "difit";
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      pnpmWorkspaces
      ;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-lEJ0PyUISe71M3/qSu1WW6PhArtXmdwVGFoYJmkUKe8=";
  };
  # The workspace also holds packages/vscode (vsce, keytar); only the CLI.
  pnpmWorkspaces = [ "difit" ];
  src = fetchFromGitHub {
    hash = "sha256-1EoC5t+8KjNmwKg5lFLig26tzCnp2byhkeGjctVdRls=";
    owner = "yoshiko-pg";
    repo = "difit";
    tag = "v${finalAttrs.version}";
  };
  strictDeps = true;
  version = "5.0.12";
})
