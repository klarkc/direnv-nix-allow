{
  description = "Nix-aware direnv approval reuse";

  inputs.iogx.url = "github:input-output-hk/iogx";
  inputs.nixpkgs.follows = "iogx/nixpkgs";

  outputs =
    { self, iogx, ... }@inputs:
    iogx.lib.mkFlake {
      inherit inputs;
      repoRoot = ./.;
      outputs = import ./nix/outputs.nix;
      systems = [ "x86_64-linux" ];
    };

  nixConfig = {
    accept-flake-config = true;
    extra-experimental-features = "nix-command flakes";
    allow-import-from-derivation = "true";
    extra-substituters = [
      "https://cache.iog.io"
    ];
    extra-trusted-public-keys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
    ];
  };
}
