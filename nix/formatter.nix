{ pkgs, tools }:

pkgs.writeShellApplication {
  name = "direnv-nix-allow-format";
  runtimeInputs = [
    tools.fourmolu
    tools.cabal-fmt
    pkgs.nixpkgs-fmt
  ];
  text = ''
    set -euo pipefail

    if [ -f direnv-nix-allow.cabal ]; then
      cabal-fmt --inplace direnv-nix-allow.cabal
    fi

    find . \
      -path ./.git -prune -o \
      -path ./.direnv -prune -o \
      -path ./dist-newstyle -prune -o \
      -name '*.nix' -print0 \
      | xargs -0 -r nixpkgs-fmt

    find src tests \
      -name '*.hs' -print0 \
      | xargs -0 -r fourmolu --mode inplace
  '';
}
