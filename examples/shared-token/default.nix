/*
  Two nodes sharing one value: each node's telegraf generates its token,
  and the influxdb on the store node holds a copy of each. A `let`-bound
  list carries the tokens' references to the store, as a fleet's shared
  data, such as nixos-registry, would. Each node is given its node identity
  and all nodes as its node collection, as a fleet sets them. The
  encrypted files under `secrets/` are not part of the example; the
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

  # Every node runs telegraf and writes to the store, the store included.
  writers = map (node: node.config.contracts.services.telegraf.secrets.token.ref) (
    lib.attrValues nodes
  );

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
    # The store runs telegraf too, so it holds a copy of its own token.
    store = mkNode "store" [
      ./telegraf.nix
      ./influxdb.nix
      {
        services.influxdb2.enable = true;
        example.influxdb = { inherit writers; };
      }
    ];
  };

  inherit (nodes.store) config;
  relative = path: lib.removePrefix "${toString ./secrets}/" (toString path);
  # The store's copies, by the name of their `age.secrets` entry.
  copies = lib.mapAttrs' (
    id: _: lib.nameValuePair "influxdb_${id}" config.age.secrets."influxdb_${id}"
  ) (lib.filterAttrs (_: secret: secret.value ? copied) config.contracts.claimSets.secrets.influxdb);
in
{
  inherit nodes;

  result = {
    copies = lib.mapAttrs (_: secret: {
      inherit (secret) owner group mode;
      rekeyFile = relative secret.rekeyFile;
      generator = secret.generator.script or null;
    }) copies;
    original = relative nodes.metrics.config.age.secrets.telegraf_token.rekeyFile;
    auths = lib.mapAttrs (
      _: auth: auth.tokenFile
    ) config.services.influxdb2.provision.organizations.main.auths;
    failures = lib.mapAttrs (_: node: node.config.contracts.failures) nodes;
  };
}
