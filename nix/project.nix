{ pkgs, lib }:

pkgs.haskell-nix.cabalProject' ({ ... }: {
  name = "direnv-nix-allow";
  src = lib.cleanSource ../.;
  compiler-nix-name = lib.mkDefault "ghc967";

  flake.variants = {
    ghc967 = { };
  };

  modules = [
    {
      packages = { };
    }
  ];
})
