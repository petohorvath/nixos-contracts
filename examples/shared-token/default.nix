/*
  Two nodes sharing one value: a telegraf node generates its token, and an
  influxdb node copies it by the token's reference. Each node is given its
  node identity and all nodes as its node collection, as
  `nixosModules.cross-config` would set them. The encrypted files under `secrets/` are not part of the
  example; the configurations are evaluated, not built.
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
          contracts = {
            node = name;
            inherit nodes;
          };
          nixpkgs.hostPlatform = system;
          system.stateVersion = "26.05";
        }
      ]
      ++ modules;
    };

  nodes = {
    metrics = mkNode "metrics" [ ./telegraf.nix ];
    # The store runs telegraf too, so it holds a `telegraf-token` of its own.
    store = mkNode "store" [
      ./telegraf.nix
      ./influxdb.nix
      {
        services.influxdb2.enable = true;
        # A fleet's nixos-cross-config would carry the token's reference
        # from the metrics node.
        example.influxdb.writers.telegraf-metrics =
          nodes.metrics.config.contracts.services.telegraf.secrets.token.ref;
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
    storesOwn = relative config.age.secrets.telegraf-token.rekeyFile;
    auths = lib.mapAttrs (
      _: auth: auth.tokenFile
    ) config.services.influxdb2.provision.organizations.main.auths;
    failures = lib.mapAttrs (_: node: node.config.contracts.failures) nodes;
  };
}
