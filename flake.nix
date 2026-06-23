{
  description = "Nix-aware direnv approval reuse";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:ursi/flake-utils";
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, utils, ... }@inputs:
    utils.apply-systems { inherit inputs; } (
      { pkgs, system, ... }:
      let
        package = pkgs.haskellPackages.developPackage {
          root = ./.;
        };
        treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";

          programs.nixfmt.enable = true;
          programs.ormolu.enable = true;
          programs.prettier.enable = true;
          programs.shfmt.enable = true;

          settings.formatter.prettier.includes = [
            "*.md"
            "*.yml"
            "*.yaml"
          ];
        };
        pre-commit-check = inputs.git-hooks.lib.${system}.run {
          src = ./.;
          hooks.treefmt = {
            enable = true;
            package = treefmtEval.config.build.wrapper;
          };
        };
      in
      {
        packages.default = package;
        apps.default = {
          type = "app";
          program = "${package}/bin/direnv-nix-allow";
        };

        formatter = treefmtEval.config.build.wrapper;

        checks = {
          inherit package pre-commit-check;
          formatting = treefmtEval.config.build.check self;
        };

        devShells.default = pkgs.mkShell {
          inherit (pre-commit-check) shellHook;
          packages = with pkgs; [
            cabal-install
            direnv
            haskell-language-server
            hlint
            treefmtEval.config.build.wrapper
          ];
          inputsFrom = [
            package.env
          ];
        };
      }
    );
}
