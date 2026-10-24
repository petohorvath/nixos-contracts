/*
  Two nodes sharing one value: a telegraf node generates its token, and an
  influxdb node copies it by reference to the node and claim name. Each node
  is given all nodes as its node collection, as nixos-cross-config would
  give them.
  The encrypted files under `secrets/` are not part of the example; the
  configurations are evaluated, not built.
*/
{
  nixpkgs,
  exports,
  backends,
  system ? "x86_64-linux",
}:
let
  inherit (nixpkgs) lib;

  mkNode =
    name: modules:
    lib.nixosSystem {
      specialArgs.contractsLib = exports.lib;
      modules = [
        backends.agenix
        backends.agenix-rekey
        exports.nixosModules.agenix-rekey
        {
          age.rekey.generatedSecretsDir = ./secrets + "/${name}";
          contracts = { inherit nodes; };
          nixpkgs.hostPlatform = system;
          system.stateVersion = "26.05";
        }
      ]
      ++ modules;
    };

  nodes = {
    metrics = mkNode "metrics" [ ./telegraf.nix ];
    store = mkNode "store" [
      ./influxdb.nix
      {
        services.influxdb2.enable = true;
        # A fleet's nixos-cross-config would carry this from the metrics node.
        example.influxdb.writers.telegraf-metrics = {
          node = "metrics";
          name = "telegraf-token";
        };
      }
    ];
  };

  inherit (nodes.store) config;
  secret = config.age.secrets.influxdb-writer-telegraf-metrics;
  relative = path: lib.removePrefix "${toString ./secrets}/" (toString path);
in
{
  inherit nodes;

  result = {
    copy = {
      inherit (secret) owner group mode;
      rekeyFile = relative secret.rekeyFile;
      generator = secret.generator.script or null;
    };
    original = relative nodes.metrics.config.age.secrets.telegraf-token.rekeyFile;
    auths = lib.mapAttrs (
      _: auth: auth.tokenFile
    ) config.services.influxdb2.provision.organizations.main.auths;
    failures = lib.mapAttrs (_: node: node.config.contracts.failures) nodes;
  };
}
