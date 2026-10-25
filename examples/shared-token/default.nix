/*
  Two nodes sharing one value: each node's telegraf generates its token and
  sends it to the influxdb inbox on the store node, which holds a copy of
  each. Each node is given its node identity and all nodes as its node
  collection, as `nixosModules.cross-config` would set them. The encrypted
  files under `secrets/` are not part of the example; the configurations
  are evaluated, not built.
*/
{
  nixpkgs,
  exports,
  backends,
  system ? "x86_64-linux",
}:
let
  inherit (nixpkgs) lib;

  # The inboxes of the fleet, as a registry carries them, so no service
  # module spells them out.
  inboxes.influxdbWriters = {
    node = "store";
    service = "influxdb";
    id = "writers";
  };

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

  # Telegraf writes its metrics to the store, on every node that runs it.
  telegraf = {
    imports = [ ./telegraf.nix ];
    contracts.services.telegraf.secrets.token.sendTo = [ inboxes.influxdbWriters ];
  };

  nodes = {
    metrics = mkNode "metrics" [ telegraf ];
    # The store runs telegraf too, so it sends its own token to itself.
    store = mkNode "store" [
      telegraf
      ./influxdb.nix
      { services.influxdb2.enable = true; }
    ];
  };

  inherit (nodes.store) config;
  secret = config.age.secrets.influxdb_writers_metrics_telegraf_token;
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
    original = relative nodes.metrics.config.age.secrets.telegraf_token.rekeyFile;
    copiesOwn = relative config.age.secrets.influxdb_writers_store_telegraf_token.rekeyFile;
    auths = lib.mapAttrs (
      _: auth: auth.tokenFile
    ) config.services.influxdb2.provision.organizations.main.auths;
    failures = lib.mapAttrs (_: node: node.config.contracts.failures) nodes;
  };
}
