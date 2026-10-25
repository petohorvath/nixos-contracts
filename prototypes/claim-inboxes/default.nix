# PROTOTYPE, throwaway. Question: does the revised inbox design hold
# together on real NixOS nodes, agenix-rekey across nodes included,
# without evaluation cycles? The design: `to` on every claim and an
# `inboxes` claim kind; received copies kept outside the claim sets; claim
# sets keyed `<kind>.<service>.<id>` with backend names an adapter makes;
# a secret's value as one tag (provided, generate, copy, derive); inbox
# copies built from the secrets claim type; and an opt-in routing check.
#
#   nix eval --json -f prototypes/claim-inboxes summary          # every scenario, errors caught
#   nix eval --json -f prototypes/claim-inboxes state.main
#   nix eval --json -f prototypes/claim-inboxes toplevel.main    # every node's drvPath
#   nix eval        -f prototypes/claim-inboxes errors.<scenario>
#   bash prototypes/claim-inboxes/fake.sh                        # recreate the empty .age files
{ }:
let
  locked = lockFile: name: (builtins.fromJSON (builtins.readFile lockFile)).nodes.${name}.locked;
  fetch = lockFile: name: builtins.fetchTree (locked lockFile name);
  contractsLock = ../../flake.lock;
  configLock = ../../../nixos-config/flake.lock;

  nixpkgs = fetch contractsLock "nixpkgs";
  agenix = fetch contractsLock "agenix";
  agenix-rekey = fetch contractsLock "agenix-rekey";
  libnet = import (fetch contractsLock "nix-libnet");
  cross-config = fetch configLock "nixos-cross-config";

  lib = import "${nixpkgs}/lib";
  contracts = import ../../nixos { inherit libnet; };
  contractsLib = import ../../lib { inherit lib; };
  fake = ./fake;

  inbox = node: service: id: {
    inherit node service id;
  };

  fleet = {
    influxdb = "beta-influxdb";
    proxy = "beta-nginx";
    roles = {
      beta = [ "microvm-host" ];
      beta-vm = [ "guest" ];
      beta-influxdb = [ "influxdb" ];
      beta-grafana = [
        "grafana"
        "alloy"
      ];
      beta-loki = [
        "loki"
        "alloy"
      ];
      beta-nginx = [
        "nginx"
        "alloy"
      ];
    };
    hostOf.beta-vm = "beta";
    # The registry carries the inboxes senders write to.
    inboxes = {
      influxdbWriters = inbox "beta-influxdb" "influxdb" "writers";
      lokiClients = inbox "beta-nginx" "nginx" "loki-clients-main";
      upstreams = inbox "beta-nginx" "nginx" "upstreams";
    };
    inherit inbox;
  };

  nodeModule =
    { hostName, nodes, ... }:
    {
      imports = [
        "${agenix}/modules/age.nix"
        (import "${agenix-rekey}/modules/agenix-rekey.nix" nixpkgs)
        "${cross-config}/nixos/module.nix"
        contracts.agenix-rekey
        contracts.systemd-credentials
        contracts.cross-config
        ./services.nix
      ];
      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "26.05";
      boot.isContainer = true;
      networking.hostName = hostName;

      age.rekey = {
        hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPrototypeOnlyPrototypeOnlyPrototypeOnly";
        masterIdentities = [ (fake + "/master-identity.pub") ];
        storageMode = "local";
        localStorageDir = fake + "/rekeyed/${hostName}";
        secretsDir = fake + "/static/${hostName}";
        generatedSecretsDir = fake + "/generated/${hostName}";
      };
      age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      age.generators.basic-auth = { ... }: "echo prototype";

      # Identity and collection only: no option paths, no contributions.
      crossConfig = {
        name = hostName;
        nodeConfigurations = nodes;
        optionPaths = [ ];
      };
    };

  evalNode =
    nodes: extra: hostName: modules:
    import "${nixpkgs}/nixos/lib/eval-config.nix" {
      system = null;
      specialArgs = {
        inherit
          hostName
          fleet
          contractsLib
          nodes
          ;
      };
      modules = [ nodeModule ] ++ modules ++ (extra.${hostName} or [ ]);
    };

  # One node collection per scenario; `extra` adds modules by node. The
  # guest is evaluated inside its host's configuration, as microvm.nix does.
  mkNodes =
    extra:
    let
      top = lib.genAttrs (lib.filter (n: n != "beta-vm") (lib.attrNames fleet.roles)) (
        hostName:
        evalNode nodes extra hostName (
          lib.optional (hostName == "beta") (
            { lib, ... }:
            {
              options.prototype.guests = lib.mkOption {
                type = lib.types.raw;
                default = { };
              };
              config.prototype.guests.beta-vm = evalNode nodes extra "beta-vm" [ ];
            }
          )
        )
      );
      nodes = top // {
        beta-vm = top.beta.config.prototype.guests.beta-vm;
      };
    in
    nodes;

  everywhere = modules: lib.genAttrs (lib.attrNames fleet.roles) (_: modules);

  scenarios = {
    main = mkNodes { };

    # The same fleet with every node's sends read from a second evaluation.
    routing = mkNodes (everywhere [ { contracts.checks.routing = true; } ]);

    # A sender misspells the inbox.
    typo = mkNodes {
      beta-grafana = [
        {
          contracts.services.grafana.secrets.loki-password.to = lib.mkForce [
            (inbox "beta-nginx" "nginx" "loki-client-main")
          ];
        }
      ];
    };

    # A bind sent to a secrets inbox.
    wrongKind = mkNodes {
      beta-loki = [
        { contracts.services.loki.binds.http.to = lib.mkForce [ fleet.inboxes.lokiClients ]; }
      ];
    };

    # A misspelt field of the inbox's copy.
    copyField = mkNodes {
      beta-influxdb = [ { contracts.services.influxdb.inboxes.writers.copy.gruop = "x"; } ];
    };

    # The receiver is disabled while writers still send to it.
    disabledReceiver = mkNodes {
      beta-influxdb = [ { contracts.services.influxdb.enable = lib.mkForce false; } ];
    };

    # A node overrides telegraf's default-priority `generate` with a copy:
    # does the value tag still need `lib.mkForce`?
    tagOverride = mkNodes {
      beta-loki = [
        {
          contracts.services.telegraf.secrets.metrics-token.value.copy = {
            node = "beta-grafana";
            service = "telegraf";
            id = "metrics-token";
          };
        }
      ];
    };
    # Two tags at the same priority still fail.
    tagConflict = mkNodes {
      beta-loki = [
        {
          contracts.services.loki.secrets.both.value = lib.mkMerge [
            { generate = "alnum"; }
            {
              copy = {
                node = "beta-grafana";
                service = "telegraf";
                id = "metrics-token";
              };
            }
          ];
        }
      ];
    };

    # A node switches telegraf's default-priority static identity to a
    # dynamic one at normal priority.
    identitySwitch = mkNodes {
      beta-loki = [ { contracts.services.telegraf.identity.dynamic.unit = "telegraf.service"; } ];
    };

    tagOverrideWhole = mkNodes {
      beta-loki = [
        {
          contracts.services.telegraf.secrets.metrics-token.value = lib.mkOverride 90 {
            copy = {
              node = "beta-grafana";
              service = "telegraf";
              id = "metrics-token";
            };
          };
        }
      ];
    };

    # A send built from what the node received, with and without routing.
    drift = mkNodes { beta-grafana = [ driftModule ]; };
    driftRouting = mkNodes (
      everywhere [ { contracts.checks.routing = true; } ]
      // {
        beta-grafana = [
          driftModule
          { contracts.checks.routing = true; }
        ];
      }
    );
  };

  # A claim per bind received by telegraf, each sent on to influxdb.
  driftModule =
    { config, lib, ... }:
    {
      contracts.services.telegraf.secrets = lib.concatMapAttrs (node: _: {
        "echo-${node}" = {
          value.generate = "alnum";
          to = [ fleet.inboxes.influxdbWriters ];
        };
      }) config.contracts.services.telegraf.inboxes.stores.received;
    };

  relative =
    path: if path == null then null else lib.removePrefix "${toString fake}/" (toString path);

  stateOf =
    _: node:
    let
      inherit (node) config;
    in
    {
      inherit (config.contracts) node failures;
      secrets = lib.mapAttrs (_: secret: {
        inherit (secret) group mode path;
        rekeyFile = relative secret.rekeyFile;
        generator = secret.generator.script or null;
        dependencies = map (dep: dep.id) (
          if secret.generator == null then [ ] else secret.generator.dependencies
        );
      }) config.age.secrets;
      loadCredential = config.systemd.services.alloy.serviceConfig.LoadCredential or [ ];
      influxdbAuths = lib.mapAttrs (_: auth: auth.tokenFile) (
        config.services.influxdb2.provision.organizations.main.auths or { }
      );
      telegrafOutputs = config.services.telegraf.extraConfig.outputs.influxdb_v2 or [ ];
      nginxUpstreams = lib.mapAttrs (
        _: upstream: lib.attrNames upstream.servers
      ) config.services.nginx.upstreams;
    };

  state = lib.mapAttrs (_: lib.mapAttrs stateOf) scenarios;

  # agenix-rekey's `findHost` (apps/generate.nix): the hosts `agenix
  # generate` finds each generator dependency of a node's secrets on.
  dependencyHosts = lib.mapAttrs (
    _: node:
    lib.mapAttrs
      (
        _: secret:
        map (
          dep:
          lib.filter (
            host:
            lib.any (s: s.id == dep.id && s.rekeyFile == dep.rekeyFile) (
              lib.attrValues scenarios.main.${host}.config.age.secrets
            )
          ) (lib.attrNames scenarios.main)
        ) secret.generator.dependencies
      )
      (
        lib.filterAttrs (
          _: secret: secret.generator != null && secret.generator.dependencies != [ ]
        ) node.config.age.secrets
      )
  ) scenarios.main;

  tryState =
    value:
    let
      result = builtins.tryEval (builtins.deepSeq value value);
    in
    if result.success then result.value else "error";
in
{
  inherit state fleet dependencyHosts;

  summary = lib.mapAttrs (_: lib.mapAttrs (_: tryState)) state;

  failures = lib.mapAttrs (
    _: lib.mapAttrs (_: node: tryState node.config.contracts.failures)
  ) scenarios;

  errors = lib.mapAttrs (_: lib.mapAttrs stateOf) scenarios;

  # Every age.secrets entry's encrypted and then rekeyed paths, for
  # fake.sh; the rekeyed paths evaluate only once the encrypted files exist.
  fakePaths =
    let
      secrets = lib.concatMap (node: lib.attrValues node.config.age.secrets) (
        lib.attrValues scenarios.main
      );
    in
    {
      encrypted = lib.unique (
        lib.concatMap (secret: lib.optional (secret.rekeyFile != null) (relative secret.rekeyFile)) secrets
      );
      # agenix-rekey's prefix for this host key and an empty encrypted file.
      rekeyed = lib.concatLists (
        lib.mapAttrsToList (
          hostName: node:
          map (name: "rekeyed/${hostName}/b5662e2848284322db7fcea4a1dee33e-${name}.age") (
            lib.attrNames node.config.age.secrets
          )
        ) scenarios.main
      );
    };

  toplevel = lib.mapAttrs (_: lib.mapAttrs (_: node: node.config.system.build.toplevel.drvPath)) {
    inherit (scenarios) main routing;
  };
}
