{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    linux-surface = {
      url = "github:linux-surface/kernel?ref=spx/v7.3";
      flake = false;
    };
    kernel-configs = {
      url = "github:qzed/aarch64-kernel-configs";
      flake = false;
    };
    spx-firmware = {
      url = "github:linux-surface/aarch64-firmware";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      spx = nixpkgs.lib.nixosSystem {
        modules = [ ./spx.nix ];
        specialArgs = { inherit inputs; };
      };
    in
    {
      nixosConfigurations.spx = spx;
      packages.aarch64-linux = {
        kernel = spx.config.boot.kernelPackages.kernel;
        image = spx.config.system.build.image;
        default = spx.config.system.build.image;
      };
    };
}
