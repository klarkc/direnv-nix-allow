{ repoRoot, pkgs, lib, ... }:
let
  name = "direnv-nix-allow";
in
lib.iogx.mkHaskellProject {
  cabalProject = pkgs.haskell-nix.cabalProject' {
    inherit name;
    src = ../.;
    compiler-nix-name = lib.mkDefault "ghc96";
  };

  shellArgs = _: {
    name = "${name}-shell";
    packages = with pkgs; [
      cabal-install
      direnv
      hlint
    ];
  };
}
