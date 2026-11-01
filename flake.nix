# Typed service contracts for one NixOS configuration. The `dev` partition
# supplies development tools, checks, and the `tests` output.
{
  description = "Typed service contracts for one NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # The flake-parts module that runs the tests; nix-unit itself comes
    # from nixpkgs.
    nix-unit = {
      url = "github:nix-community/nix-unit";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        treefmt-nix.follows = "";
        nix-github-actions.follows = "";
      };
    };
    # Development only: the flake-parts module that formats and lints the
    # repository; the tools come from nixpkgs.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
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
        treefmt-nix.follows = "treefmt-nix";
      };
    };
    preservation.url = "github:nix-community/preservation";
    nix-libnet = {
      url = "github:petohorvath/nix-libnet/v0.2.0";
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
          modules.generic.default = import ./modules { inherit libnet; };
          nixosModules = import ./nixos { inherit libnet; };
        };
    };
}
