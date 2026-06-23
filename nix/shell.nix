{ inputs, pkgs, lib, project, ghc }:

let
  allTools = {
    ghc967.cabal = project.projectVariants.ghc967.tool "cabal" "latest";
    ghc967.cabal-fmt = project.projectVariants.ghc967.tool "cabal-fmt" "latest";
    ghc967.haskell-language-server = project.projectVariants.ghc967.tool "haskell-language-server" "latest";
    ghc967.fourmolu = project.projectVariants.ghc967.tool "fourmolu" "latest";
    ghc967.hlint = project.projectVariants.ghc967.tool "hlint" "latest";
  };

  tools = allTools.${ghc};

  preCommitCheck = inputs.pre-commit-hooks.lib.${pkgs.system}.run {
    src = lib.cleanSource ../.;
    hooks = {
      cabal-fmt = {
        enable = true;
        package = tools.cabal-fmt;
      };
      fourmolu = {
        enable = true;
        package = tools.fourmolu;
      };
      hlint = {
        enable = true;
        package = tools.hlint;
      };
      nixpkgs-fmt = {
        enable = true;
        package = pkgs.nixpkgs-fmt;
      };
    };
  };

  commonPkgs = [
    tools.haskell-language-server
    tools.haskell-language-server.package.components.exes.haskell-language-server-wrapper
    tools.fourmolu
    tools.cabal
    tools.hlint
    tools.cabal-fmt
    pkgs.nixpkgs-fmt
    pkgs.direnv
    pkgs.git
    pkgs.which
  ];
in
project.shellFor {
  name = "direnv-nix-allow-shell-${ghc}";
  buildInputs = commonPkgs;
  withHoogle = true;
  shellHook = ''
    ${preCommitCheck.shellHook}
  '';
}
