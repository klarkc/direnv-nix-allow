{ inputs, system }:

let
  pkgs = import ./pkgs.nix { inherit inputs system; };
  inherit (pkgs) lib;

  project = import ./project.nix { inherit inputs pkgs lib; };
  projectFlake = project.flake { };

  tools = {
    cabal = project.projectVariants.ghc967.tool "cabal" "latest";
    cabal-fmt = project.projectVariants.ghc967.tool "cabal-fmt" "latest";
    haskell-language-server = project.projectVariants.ghc967.tool "haskell-language-server" "latest";
    fourmolu = project.projectVariants.ghc967.tool "fourmolu" "latest";
    hlint = project.projectVariants.ghc967.tool "hlint" "latest";
  };

  formatter = import ./formatter.nix { inherit pkgs tools; };

  devShells = {
    default = import ./shell.nix {
      inherit inputs pkgs lib project;
      ghc = "ghc967";
    };
  };

  package = project.hsPkgs."direnv-nix-allow".components.exes."direnv-nix-allow";
  test = project.hsPkgs."direnv-nix-allow".components.tests."direnv-nix-allow-test";

  formatting = pkgs.runCommand "formatting-check" { nativeBuildInputs = [ formatter ]; } ''
    cp -r ${lib.cleanSource ../.} source
    chmod -R u+w source
    cd source
    direnv-nix-allow-format
    diff -ru ${lib.cleanSource ../.} .
    touch $out
  '';

  pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
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
in
{
  inherit formatter devShells;

  packages.default = package;

  apps.default = {
    type = "app";
    program = "${package}/bin/direnv-nix-allow";
  };

  checks = (projectFlake.checks or { }) // {
    inherit package test formatting pre-commit-check;
  };

  hydraJobs = {
    required = pkgs.releaseTools.aggregate {
      name = "required";
      constituents = lib.collect lib.isDerivation {
        inherit package test formatting pre-commit-check;
      };
    };
  };
}
