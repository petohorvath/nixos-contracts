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
  agenixRekeyBackends = [
    backends.agenix
    backends.agenix-rekey
  ];
in
{
  flake = import ./flake.nix {
    inherit lib;
    flake = self;
  };
  lib.mkDefaultContract = import ./lib/mk-default-contract.nix {
    inherit contracts contractsLib lib;
  };
  modules = {
    default = import ./modules/default.nix {
      inherit lib;
      module = self.modules.generic.default;
    };
    core = import ./modules/core.nix { inherit contracts lib; };
    mkClaimKind = import ./modules/mk-claim-kind.nix { inherit contracts contractsLib lib; };
    types = import ./modules/types.nix { inherit contractsLib lib; };
    kinds = {
      binds = import ./modules/kinds/binds.nix { inherit contracts; };
      mounts = import ./modules/kinds/mounts.nix { inherit contracts; };
      secrets = import ./modules/kinds/secrets.nix { inherit contracts contractsLib lib; };
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
      sharedToken = import ../examples/shared-token {
        inherit
          backends
          exports
          nixpkgs
          system
          ;
      };
      exporter = import ../examples/exporter { inherit exports nixpkgs system; };
      customKind = import ../examples/custom-kind { inherit exports lib; };
    };
  };
  nixos = {
    default = import ./nixos/default.nix {
      inherit nixos;
      module = self.nixosModules.default;
    };
    adapters = {
      preservation = import ./nixos/adapters/preservation.nix {
        inherit lib nixos;
        adapter = self.nixosModules.preservation;
        backend = backends.preservation;
      };
      agenixRekey = import ./nixos/adapters/agenix-rekey.nix {
        inherit contractsLib lib nixos;
        contracts = self.nixosModules.default;
        adapter = self.nixosModules.agenix-rekey;
        backends = agenixRekeyBackends;
      };
      systemdCredentials = import ./nixos/adapters/systemd-credentials.nix {
        inherit lib nixos;
        adapter = self.nixosModules.systemd-credentials;
        backends = agenixRekeyBackends;
        backendAdapter = self.nixosModules.agenix-rekey;
      };
    };
  };
}
