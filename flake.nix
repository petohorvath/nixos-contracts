# Typed service contracts for one NixOS configuration. The `dev` partition
# supplies development tools and checks.
{
  description = "Typed service contracts for one NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # Backends of the adapters. Only the adapter tests evaluate them.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix-rekey = {
      url = "github:oddlama/agenix-rekey";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };
    preservation.url = "github:nix-community/preservation";
    nix-libnet = {
      # A commit until nix-libnet tags a release past v0.1.0.
      url = "github:petohorvath/nix-libnet/280a8c4fbff9d5d16c4a2e156f34d302f2c3f36b";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        # Development-only inputs of libnet's own flake.
        treefmt-nix.follows = "";
        nix-unit.follows = "";
      };
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ inputs.flake-parts.flakeModules.partitions ];

      partitions.dev.module = ./dev;

      partitionedAttrs = {
        checks = "dev";
        devShells = "dev";
        formatter = "dev";
        tests = "dev";
      };

      flake =
        let
          libnet = inputs.nix-libnet.lib;
        in
        {
          lib = import ./lib { inherit (inputs.nixpkgs) lib; };
          modules.generic.default = import ./modules/contracts.nix { inherit libnet; };
          nixosModules = rec {
            default = import ./nixos/module.nix { inherit libnet; };
            agenix-rekey = {
              imports = [
                default
                ./nixos/adapters/agenix-rekey.nix
              ];
            };
            preservation = {
              imports = [
                default
                ./nixos/adapters/preservation.nix
              ];
            };
            systemd-credentials = {
              imports = [
                default
                ./nixos/adapters/systemd-credentials.nix
              ];
            };
          };
        };
    };
}
