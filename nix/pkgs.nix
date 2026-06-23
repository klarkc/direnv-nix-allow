{ inputs, system }:

import inputs.nixpkgs {
  inherit system;
  config = inputs.haskell-nix.config;
  overlays = [
    inputs.iohk-nix.overlays.crypto
    inputs.haskell-nix.overlay
    inputs.iohk-nix.overlays.haskell-nix-crypto
    inputs.iohk-nix.overlays.haskell-nix-extra
    (final: prev: {
      haskell = prev.haskell // {
        compiler = prev.haskell.compiler // {
          ghc943 = prev.haskell.compiler.ghc948;
          ghc944 = prev.haskell.compiler.ghc948;
        };
      };
    })
  ];
}
