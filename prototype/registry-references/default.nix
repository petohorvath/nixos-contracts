# PROTOTYPE, throwaway. Four NixOS nodes share one nixos-registry; each
# contributes its claims' references there, and receivers build copies,
# a derived htpasswd, InfluxDB auths and nginx vhosts from the combined
# data. Evaluated, not built.
#
#   nix eval --impure --json --expr 'import ./prototype/registry-references { }'
#   nix eval --impure --json --expr 'import ./prototype/registry-references { scenario = "typo-node"; }'
{
  flake ? builtins.getFlake (toString ../..),
  # default | typo-node | wrong-kind | disabled-receiver
  scenario ? "default",
}:
let
  inherit (flake.inputs.nixpkgs) lib;
  contractsLib = flake.lib;
  services = import ./modules.nix;

  # The revision nixos-config locks.
  registrySource = builtins.fetchTree {
    type = "github";
    owner = "petohorvath";
    repo = "nixos-registry";
    rev = "28965e3f0ee243912659cc47cf1a6a717e9f9a50";
    narHash = "sha256-cQNH2BMKP21Hryc5kirjcLQIucHutzgJV2quVl5UPvM=";
  };
  inherit (import "${registrySource}/lib") mkRegistry;

  registry = mkRegistry {
    inherit lib nodes;
    schemaModules = [ (import ./schema.nix { inherit contractsLib; }) ];
    centralModules = [
      {
        nodes = {
          logs.address = "10.0.0.2";
          metrics.address = "10.0.0.3";
          store.address = "10.0.0.4";
          proxy.address = "10.0.0.5";
        };
      }
    ];
  };

  mkNode =
    name: modules:
    lib.nixosSystem {
      specialArgs = { inherit contractsLib registry; };
      modules = [
        registry.module
        flake.inputs.agenix.nixosModules.default
        flake.inputs.agenix-rekey.nixosModules.default
        flake.nixosModules.agenix-rekey
        flake.nixosModules.systemd-credentials
        services.alloy
        services.grafana
        services.influxdb
        services.loki
        services.nginx
        services.telegraf
        {
          contracts = {
            node = name;
            inherit nodes;
          };
          age.rekey.generatedSecretsDir = ./secrets + "/${name}";
          # Placeholder keys: only the rekey setup assertions read them.
          age.rekey.extraEncryptionPubkeys = [ "age1placeholder" ];
          age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
          boot.isContainer = true;
          nixpkgs.hostPlatform = "x86_64-linux";
          system.stateVersion = "26.05";
        }
      ]
      ++ modules;
    };

  nodes = {
    logs = mkNode "logs" [
      (
        { config, ... }:
        {
          services.loki.enable = true;
          registry.services.loki.main = {
            node = "logs";
            exports.http = {
              bind = config.contracts.services.loki.binds.http.ref;
              vhost = {
                proxy = "main";
                domain = "logs.example.test";
                maxBodySize = "100M";
                websockets = true;
                readTimeout = "1800s";
                basicAuth = true;
              };
            };
          };
          services.alloy.enable = true;
          proto.alloy.lokiInstances = [ "main" ];
          services.telegraf.enable = true;
          proto.telegraf.stores = [ "system-metrics" ];
        }
      )
    ];

    metrics = mkNode "metrics" [
      (
        { config, ... }:
        {
          services.alloy.enable = true;
          proto.alloy.lokiInstances = [ "main" ];
          services.grafana.enable = true;
          proto.grafana = {
            lokiInstances = [ "main" ];
            stores = [ "system-metrics" ];
          };
          services.telegraf.enable = true;
          proto.telegraf.stores = [ "system-metrics" ];
        }
        // lib.optionalAttrs (scenario == "typo-node") {
          registry.stores.system-metrics.writers.typo = {
            node = "metrix";
            service = "telegraf";
            id = "system-metrics-token";
          };
        }
        // lib.optionalAttrs (scenario == "wrong-kind") {
          registry.services.loki.main.clients.wrong =
            config.contracts.services.grafana.secrets.secret-key.ref
            // {
              kind = "binds";
            };
        }
      )
    ];

    store = mkNode "store" [
      (
        { config, ... }:
        {
          services.influxdb2.enable = scenario != "disabled-receiver";
          registry.stores.system-metrics = {
            node = "store";
            organization = "nodes";
            bucket = "telegraf";
          };
          registry.services.influxdb.main = {
            node = "store";
            exports.http = {
              bind = config.contracts.services.influxdb.binds.http.ref;
              vhost = {
                proxy = "main";
                domain = "metrics.example.test";
                maxBodySize = "50M";
              };
            };
          };
          # The store writes its own metrics to itself.
          services.telegraf.enable = true;
          proto.telegraf.stores = [ "system-metrics" ];
        }
      )
    ];

    proxy = mkNode "proxy" [
      {
        services.nginx.enable = true;
        proto.nginx.proxyName = "main";
        # The proxy ships its own logs through itself.
        services.alloy.enable = true;
        proto.alloy.lokiInstances = [ "main" ];
      }
    ];
  };

  # ---- what the evaluation shows ----

  relative = path: lib.removePrefix "${toString ./secrets}/" (toString path);

  # As agenix-rekey's `apps/generate.nix` builds a generator's `deps`.
  findHost =
    secret:
    lib.head (
      lib.filter (
        host:
        lib.any (entry: entry.id == secret.id && entry.rekeyFile == secret.rekeyFile) (
          lib.attrValues nodes.${host}.config.age.secrets
        )
      ) (lib.attrNames nodes)
    );
  generatorScript =
    node: name:
    let
      secret = nodes.${node}.config.age.secrets.${name};
    in
    secret.generator._script {
      inherit secret name;
      inherit (nodes.${node}) pkgs;
      inherit lib;
      file = relative secret.rekeyFile;
      decrypt = "decrypt";
      deps = map (dep: {
        host = findHost dep;
        name = dep.id;
        file = relative dep.rekeyFile;
      }) secret.generator.dependencies;
    };

  htpasswdUsers = lib.sort lib.lessThan (
    map (line: lib.head (lib.splitString ":" (lib.removePrefix "echo \"" line))) (
      lib.filter (line: line != "") (
        lib.splitString "\n" (generatorScript "proxy" "nginx_htpasswd-loki-main")
      )
    )
  );

  # The user names the clients authenticate with, read from their configs.
  clientUsers = lib.sort lib.lessThan (
    lib.concatMap (
      node:
      let
        inherit (nodes.${node}) config;
        alloy = lib.optional config.services.alloy.enable config.contracts.services.alloy.secrets.loki-main-password.name;
        grafana = map (source: source.basicAuthUser) (
          lib.filter (source: source.type == "loki") (
            lib.optionals config.services.grafana.enable config.services.grafana.provision.datasources.settings.datasources
          )
        );
      in
      alloy ++ grafana
    ) (lib.attrNames nodes)
  );

  entry = node: name: {
    inherit (nodes.${node}.config.age.secrets.${name}) owner group mode;
    rekeyFile = relative nodes.${node}.config.age.secrets.${name}.rekeyFile;
  };

  storeConfig = nodes.store.config;
  proxyConfig = nodes.proxy.config;
in
{
  inherit scenario;
  registryValidates = registry.validate;

  proxy = {
    upstreams = lib.mapAttrs (
      _: upstream: lib.attrNames upstream.servers
    ) proxyConfig.services.nginx.upstreams;
    vhosts = lib.mapAttrs (_: vhost: {
      inherit (vhost) extraConfig;
      location = {
        inherit (vhost.locations."/") proxyPass proxyWebsockets extraConfig;
      };
    }) proxyConfig.services.nginx.virtualHosts;
    htpasswd = {
      dependencies = map (
        dep: relative dep.rekeyFile
      ) proxyConfig.age.secrets.nginx_htpasswd-loki-main.generator.dependencies;
      users = htpasswdUsers;
    };
  };
  usersMatchClients = htpasswdUsers == clientUsers;

  store = {
    copies = lib.mapAttrs (name: _: entry "store" name) (
      lib.filterAttrs (
        name: _: lib.hasInfix "-writers-" name || lib.hasInfix "-readers-" name
      ) storeConfig.age.secrets
    );
    auths = lib.mapAttrs (_: auth: {
      inherit (auth) readBuckets writeBuckets tokenFile;
    }) (storeConfig.services.influxdb2.provision.organizations.nodes.auths or { });
  };

  failures = lib.mapAttrs (_: node: node.config.contracts.failures) nodes;
  failedAssertions = lib.mapAttrs (
    _: node:
    map (assertion: assertion.message) (
      lib.filter (assertion: !assertion.assertion) node.config.assertions
    )
  ) nodes;
}
