# Every test under the given roots, found by filename: See NOTES.md.
{ pkgs, roots }:
let
  inherit (pkgs) lib;
  files = lib.concatMap lib.filesystem.listFilesRecursive roots;
  # Roots from flake inputs are store-path strings; names must not carry that.
  nameOf = suffix: f: builtins.unsafeDiscardStringContext (lib.removeSuffix suffix (baseNameOf f));
  pairs =
    suffix: ext:
    map
      (f: rec {
        name = nameOf suffix f;
        test = f;
        script = dirOf f + "/${name}${ext}";
      })
      (
        builtins.filter (
          f:
          lib.hasSuffix suffix (baseNameOf f)
          && builtins.pathExists (dirOf f + "/${lib.removeSuffix suffix (baseNameOf f)}${ext}")
        ) files
      );

  shellTest =
    t:
    pkgs.runCommand "test-${t.name}"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.gawk
          pkgs.git
          pkgs.gnugrep
          pkgs.findutils
          pkgs.jq
          pkgs.util-linux
        ];
      }
      ''
        bash ${t.test} ${t.script} ${../tests/lib.sh} 2>&1 | tee "$out"
      '';
  pyTest =
    t:
    pkgs.runCommand "test-${t.name}"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        set -o pipefail
        python ${t.test} ${t.script} 2>&1 | tee "$out"
      '';
  custom = map (f: {
    name = nameOf ".check.nix" f;
    value = import f { inherit pkgs; };
  }) (builtins.filter (f: lib.hasSuffix ".check.nix" (baseNameOf f)) files);

  all =
    map (t: lib.nameValuePair t.name (shellTest t)) (pairs ".test.sh" ".sh")
    ++ map (t: lib.nameValuePair t.name (pyTest t)) (pairs ".test.py" ".py")
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 custom;
  dupes = lib.filter (n: lib.count (x: x.name == n) all > 1) (lib.unique (map (x: x.name) all));
in
if dupes != [ ] then
  throw "lib/checks.nix: duplicate test names ${toString dupes}"
else
  lib.listToAttrs all
