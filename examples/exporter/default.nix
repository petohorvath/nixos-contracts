# A helper daemon as a service of its own: chrony and its exporter each hold
# a contract, so the exporter's bind is a claim of the exporter, under the
# account the exporter runs as.
{
  nixpkgs,
  exports,
  system ? "x86_64-linux",
}:
let
  inherit (nixpkgs) lib;

  node = lib.nixosSystem {
    specialArgs.contractsLib = exports.lib;
    modules = [
      exports.nixosModules.default
      ./chrony.nix
      ./exporter.nix
      {
        services.chrony.enable = true;
        services.prometheus.exporters.chrony.enable = true;
        nixpkgs.hostPlatform = system;
        system.stateVersion = "26.05";
      }
    ];
  };
  inherit (node) config;
  exporter = config.services.prometheus.exporters.chrony;
in
{
  inherit node;

  result = {
    binds = lib.mapAttrs (_: lib.mapAttrs (_: bind: bind.bindpoints)) config.contracts.claimSets.binds;
    identities = lib.mapAttrs (_: contract: contract.identity) config.contracts.services;
    exporterListen = "${exporter.listenAddress}:${toString exporter.port}";
    inherit (config.contracts) failures;
  };
}
