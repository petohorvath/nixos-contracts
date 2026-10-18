# The nix-unit suite for one system, nested by source module.
{ inputs, system }:
let
  inherit (inputs) nixpkgs self;
  inherit (nixpkgs) lib;
  contracts = import ./fixtures/contracts.nix {
    inherit lib;
    module = self.modules.generic.default;
  };
  contractsLib = self.lib;
  nixos = import ./fixtures/nixos.nix { inherit nixpkgs system; };
  exports = { inherit (self) lib modules nixosModules; };
  backends = {
    preservation = inputs.preservation.nixosModules.default;
    agenix = inputs.agenix.nixosModules.default;
    agenix-rekey = inputs.agenix-rekey.nixosModules.default;
  };
  agenixRekey = [
    inputs.agenix.nixosModules.default
    inputs.agenix-rekey.nixosModules.default
  ];
in
{
  flake = import ./flake.nix {
    inherit lib;
    flake = self;
  };
  lib = {
    mkClaimKind = import ./lib/mk-claim-kind.nix { inherit contracts contractsLib lib; };
    mkDefaultContract = import ./lib/mk-default-contract.nix { inherit contracts contractsLib lib; };
  };
  modules = {
    core = import ./modules/core.nix { inherit contracts; };
    kinds = {
      binds = import ./modules/kinds/binds.nix { inherit contracts; };
      mounts = import ./modules/kinds/mounts.nix { inherit contracts; };
      secrets = import ./modules/kinds/secrets.nix { inherit contracts; };
    };
  };
  integration.examples = import ./integration/examples.nix {
    examples = {
      influxdb = import ../examples/influxdb {
        inherit
          backends
          exports
          nixpkgs
          system
          ;
      };
      alloy = import ../examples/alloy {
        inherit
          backends
          exports
          nixpkgs
          system
          ;
      };
      customKind = import ../examples/custom-kind { inherit exports lib; };
    };
  };
  nixos = {
    module = import ./nixos/module.nix {
      inherit nixos;
      module = self.nixosModules.default;
    };
    adapters = {
      preservation = import ./nixos/adapters/preservation.nix {
        inherit lib nixos;
        adapter = self.nixosModules.preservation;
        backend = inputs.preservation.nixosModules.default;
      };
      agenixRekey = import ./nixos/adapters/agenix-rekey.nix {
        inherit nixos;
        adapter = self.nixosModules.agenix-rekey;
        backends = agenixRekey;
      };
      systemdCredentials = import ./nixos/adapters/systemd-credentials.nix {
        inherit lib nixos;
        adapter = self.nixosModules.systemd-credentials;
        backend = agenixRekey ++ [ self.nixosModules.agenix-rekey ];
      };
    };
  };
}
