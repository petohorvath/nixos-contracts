{ contracts, lib }:
let
  inherit (contracts) evaluate failures nodesOf;

  service = name: claims: {
    contracts.services.${name} = {
      enable = true;
      identity.static.user = name;
    }
    // claims;
  };

  # Inboxes of nginx on the `proxy` node: `upstreams` takes binds and
  # `clients` takes secrets.
  upstreams = {
    node = "proxy";
    service = "nginx";
    id = "upstreams";
  };
  clients = upstreams // {
    id = "clients";
  };
  nginx = service "nginx" {
    inboxes = {
      upstreams.kind = "binds";
      clients = { };
    };
  };

  # A loki bind sent to nginx's upstreams.
  loki =
    sendTo:
    service "loki" {
      binds.http = {
        port = 3100;
        addresses = "10.0.0.2";
        inherit sendTo;
      };
    };

  # An upstream per received bind, as a service module builds it.
  nginxUpstreams =
    { config, lib, ... }:
    {
      options.upstreams = lib.mkOption { type = lib.types.attrsOf (lib.types.listOf lib.types.str); };
      config.upstreams = lib.concatMapAttrs (
        node:
        lib.concatMapAttrs (
          sender:
          lib.mapAttrs' (id: entry: lib.nameValuePair "${node}_${sender}_${id}" entry.claim.bindpoints)
        )
      ) config.contracts.services.nginx.inboxes.upstreams.received;
    };

  receivedBy = config: inbox: config.contracts.services.nginx.inboxes.${inbox}.received;
  refsOf = config: inbox: config.contracts.services.nginx.inboxes.${inbox}.refs;
  failuresOf = node: node.config.contracts.failures;

  # A telegraf token sent to nginx's clients.
  telegraf =
    sendTo:
    service "telegraf" {
      secrets.token = {
        value.generated = "alnum";
        inherit sendTo;
      };
    };
  tokenOf = node: {
    inherit node;
    kind = "secrets";
    service = "telegraf";
    id = "token";
  };
  # What a test reads of a received entry.
  entryOf = entry: {
    inherit (entry) ref copy;
    inherit (entry.claim) name value;
  };

  # Influxdb's `writers` inbox on the `store` node, holding a copy of each
  # token it receives with the settings `copy`.
  writers = {
    node = "store";
    service = "influxdb";
    id = "writers";
  };
  influxdb = identity: copy: {
    contracts.services.influxdb = {
      enable = true;
      inherit identity;
      inboxes.writers = { inherit copy; };
    };
  };
  # A backend naming a secret by its location joined with `_`, with one
  # generator.
  backend.contracts.kinds.secrets.backend = {
    path = location: "/run/agenix/${lib.concatStringsSep "_" location}";
    generators = [ "alnum" ];
  };
  writersOf = config: config.contracts.services.influxdb.inboxes.writers.received;
  # What a test reads of a copy.
  copyOf = copy: {
    inherit (copy)
      owner
      group
      mode
      value
      location
      ;
    hasRefOrName = copy ? ref || copy ? name;
  };
in
{
  testBindSentToAnotherNodeBuildsAnUpstreamThere = {
    expr =
      (nodesOf {
        logs = [ (loki [ upstreams ]) ];
        proxy = [
          nginx
          nginxUpstreams
        ];
      }).proxy.config.upstreams;
    expected.logs_loki_http = [ "10.0.0.2:3100" ];
  };

  testSecretSentToAnotherNodeIsReceivedWithItsRefAndClaim = {
    expr = builtins.mapAttrs (_: builtins.mapAttrs (_: builtins.mapAttrs (_: entryOf))) (
      receivedBy
        (nodesOf {
          metrics = [ (telegraf [ clients ]) ];
          proxy = [ nginx ];
        }).proxy.config
        "clients"
    );
    expected.metrics.telegraf.token = {
      ref = tokenOf "metrics";
      copy = null;
      name = "metrics_telegraf_token";
      value.generated = "alnum";
    };
  };

  testClaimSentToItsOwnNodeIsReceivedThere = {
    expr =
      builtins.attrNames
        (receivedBy (evaluate [
          { contracts.node = "proxy"; }
          nginx
          (loki [ upstreams ])
        ]) "upstreams").proxy.loki;
    expected = [ "http" ];
  };

  testClaimSentToSeveralInboxesIsReceivedByEach =
    let
      nodes = nodesOf {
        logs = [
          (loki [
            upstreams
            (upstreams // { node = "edge"; })
          ])
        ];
        proxy = [ nginx ];
        edge = [ nginx ];
      };
    in
    {
      expr = map (node: (receivedBy nodes.${node}.config "upstreams").logs.loki.http.claim.bindpoints) [
        "proxy"
        "edge"
      ];
      expected = [
        [ "10.0.0.2:3100" ]
        [ "10.0.0.2:3100" ]
      ];
    };

  # `-` sorts before `:`, so `beta-vm:…` comes before `beta:…`.
  testRefsListTheReceivedReferencesSortedByLabel = {
    expr =
      refsOf
        (nodesOf {
          beta = [ (telegraf [ clients ]) ];
          beta-vm = [ (telegraf [ clients ]) ];
          alpha = [
            (telegraf [ clients ])
            (service "alloy" { secrets.password.sendTo = [ clients ]; })
          ];
          proxy = [ nginx ];
        }).proxy.config
        "clients";
    expected = [
      {
        node = "alpha";
        kind = "secrets";
        service = "alloy";
        id = "password";
      }
      (tokenOf "alpha")
      (tokenOf "beta-vm")
      (tokenOf "beta")
    ];
  };

  testInboxReceivesNothingWithoutANodeIdentity = {
    expr =
      let
        config = evaluate [
          nginx
          (loki [ upstreams ])
        ];
      in
      {
        received = receivedBy config "upstreams";
        refs = refsOf config "upstreams";
      };
    expected = {
      received = { };
      refs = [ ];
    };
  };

  testDisabledSendingContractSendsNothing =
    let
      nodes = nodesOf {
        metrics = [
          (telegraf [ clients ])
          { contracts.services.telegraf.enable = lib.mkForce false; }
        ];
        proxy = [ nginx ];
      };
    in
    {
      expr = {
        received = receivedBy nodes.proxy.config "clients";
        failures = failuresOf nodes.metrics;
      };
      expected = {
        received = { };
        failures = [ ];
      };
    };

  testDisabledReceivingContractShowsNothingReceived =
    let
      nodes = nodesOf {
        metrics = [ (telegraf [ clients ]) ];
        proxy = [
          nginx
          { contracts.services.nginx.enable = lib.mkForce false; }
        ];
      };
    in
    {
      expr = {
        received = receivedBy nodes.proxy.config "clients";
        refs = refsOf nodes.proxy.config "clients";
        failures = failuresOf nodes.metrics;
      };
      expected = {
        received = { };
        refs = [ ];
        failures = [
          "nixos-contracts: secrets claim `telegraf.token` sends to `proxy:inboxes.nginx.clients`: no enabled contract on `proxy` holds it."
        ];
      };
    };

  # Telegraf sends its token to the store's influxdb, which sends its bind
  # to telegraf's outputs.
  testNodesSendingToEachOtherEvaluateWithoutACycle =
    let
      nodes = nodesOf {
        metrics = [
          (service "telegraf" {
            secrets.token.sendTo = [
              {
                node = "store";
                service = "influxdb";
                id = "writers";
              }
            ];
            inboxes.outputs.kind = "binds";
          })
        ];
        store = [
          (service "influxdb" {
            binds.http = {
              port = 8086;
              sendTo = [
                {
                  node = "metrics";
                  service = "telegraf";
                  id = "outputs";
                }
              ];
            };
            inboxes.writers = { };
          })
        ];
      };
      inboxesOf = node: nodes.${node}.config.contracts.claimSets.inboxes;
    in
    {
      expr = {
        outputs = (inboxesOf "metrics").telegraf.outputs.received.store.influxdb.http.claim.bindpoints;
        writers = (inboxesOf "store").influxdb.writers.refs;
        failures = map failuresOf [
          nodes.metrics
          nodes.store
        ];
      };
      expected = {
        outputs = [ "0.0.0.0:8086" ];
        writers = [ (tokenOf "metrics") ];
        failures = [
          [ ]
          [ ]
        ];
      };
    };

  # Telegraf sends its token to influxdb's writers, and influxdb its own
  # token to telegraf's outputs, each holding a copy of what it receives.
  testNodesCopyingEachOthersSecretsEvaluateWithoutACycle =
    let
      nodes = nodesOf {
        metrics = [
          backend
          (service "telegraf" {
            secrets.token = {
              value.generated = "alnum";
              sendTo = [ writers ];
            };
            inboxes.outputs.copy = { };
          })
        ];
        store = [
          backend
          (influxdb { static.user = "influxdb2"; } { })
          {
            contracts.services.influxdb.secrets.token = {
              value.generated = "alnum";
              sendTo = [
                {
                  node = "metrics";
                  service = "telegraf";
                  id = "outputs";
                }
              ];
            };
          }
        ];
      };
      inboxesOf = node: nodes.${node}.config.contracts.claimSets.inboxes;
    in
    {
      expr = {
        outputs = (inboxesOf "metrics").telegraf.outputs.received.store.influxdb.token.copy.path;
        writers = (inboxesOf "store").influxdb.writers.received.metrics.telegraf.token.copy.path;
        failures = map failuresOf [
          nodes.metrics
          nodes.store
        ];
      };
      expected = {
        outputs = "/run/agenix/telegraf_outputs_store_influxdb_token";
        writers = "/run/agenix/influxdb_writers_metrics_telegraf_token";
        failures = [
          [ ]
          [ ]
        ];
      };
    };

  testSendThatDoesNotResolveFailsACheckOnTheSendingNode = {
    expr =
      map
        (
          case:
          failuresOf
            (nodesOf {
              metrics = [ (telegraf [ case.to ]) ] ++ case.modules;
              proxy = [ nginx ];
            }).metrics
        )
        [
          {
            to = clients // {
              node = "nowhere";
            };
            modules = [ ];
          }
          {
            to = clients;
            modules = [ { contracts.nodes.proxy = lib.mkForce { config = { }; }; } ];
          }
          {
            to = clients // {
              id = "client";
            };
            modules = [ ];
          }
        ];
    expected = [
      [
        "nixos-contracts: secrets claim `telegraf.token` sends to `nowhere:inboxes.nginx.clients`: node `nowhere` is not in `contracts.nodes`."
      ]
      [
        "nixos-contracts: secrets claim `telegraf.token` sends to `proxy:inboxes.nginx.clients`: node `proxy` imports no nixos-contracts module."
      ]
      [
        "nixos-contracts: secrets claim `telegraf.token` sends to `proxy:inboxes.nginx.client`: no enabled contract on `proxy` holds it."
      ]
    ];
  };

  testClaimSentToAnInboxOfAnotherKindFailsACheckNamingBoth =
    let
      nodes = nodesOf {
        logs = [ (loki [ clients ]) ];
        proxy = [ nginx ];
      };
    in
    {
      expr = {
        failures = failuresOf nodes.logs;
        received = receivedBy nodes.proxy.config "clients";
      };
      expected = {
        failures = [
          "nixos-contracts: binds claim `loki.http` sends to `proxy:inboxes.nginx.clients`, which takes `secrets`, not `binds`."
        ];
        received = { };
      };
    };

  testInboxTakingNoKindOfItsNodeFailsACheck = {
    expr = map (kind: failures [ (service "nginx" { inboxes.upstreams.kind = kind; }) ]) [
      "bindz"
      "inboxes"
    ];
    expected = [
      [
        "nixos-contracts: inboxes claim `nginx.upstreams`: it takes `bindz`, which is no claim kind of this node."
      ]
      [
        "nixos-contracts: inboxes claim `nginx.upstreams`: it takes `inboxes`, which no claim can be sent as."
      ]
    ];
  };

  testCopyOfAReceivedSecretIsOwnedByTheReceivingService = {
    expr =
      copyOf
        (writersOf
          (nodesOf {
            metrics = [ (telegraf [ writers ]) ];
            store = [ (influxdb { static.user = "influxdb2"; } { mode = "0400"; }) ];
          }).store.config
        ).metrics.telegraf.token.copy;
    expected = {
      owner = "root";
      group = "influxdb2";
      mode = "0400";
      value.copied = tokenOf "metrics";
      location = [
        "influxdb"
        "writers"
        "metrics"
        "telegraf"
        "token"
      ];
      hasRefOrName = false;
    };
  };

  testCopyPathIsWhereTheReceivingDaemonReadsIt =
    let
      pathOf =
        identity: modules:
        (writersOf
          (nodesOf {
            metrics = [ (telegraf [ writers ]) ];
            store = [ (influxdb identity { }) ] ++ modules;
          }).store.config
        ).metrics.telegraf.token.copy.path;
    in
    {
      expr = {
        static = pathOf { static.user = "influxdb2"; } [ backend ];
        delivered = pathOf { dynamic.unit = "influxdb.service"; } [
          backend
          {
            contracts.kinds.secrets.delivery.path =
              { unit, location }: "/run/credentials/${unit}/${lib.concatStringsSep "_" location}";
          }
        ];
      };
      expected = {
        static = "/run/agenix/influxdb_writers_metrics_telegraf_token";
        delivered = "/run/credentials/influxdb.service/influxdb_writers_metrics_telegraf_token";
      };
    };

  testMisspeltCopyFieldFailsAtItsDefinition = {
    expr =
      (writersOf
        (nodesOf {
          metrics = [ (telegraf [ writers ]) ];
          store = [ (influxdb { static.user = "influxdb2"; } { gruop = "writers"; }) ];
        }).store.config
      ).metrics.telegraf.token.copy.group;
    expectedError.msg = "telegraf\\.token\\.gruop' does not exist";
  };

  testMisspeltCopyFieldOffersTheClosestOption = {
    expr =
      (writersOf
        (nodesOf {
          metrics = [ (telegraf [ writers ]) ];
          store = [ (influxdb { static.user = "influxdb2"; } { gruop = "writers"; }) ];
        }).store.config
      ).metrics.telegraf.token.copy.group;
    expectedError.msg = "Did you mean `[^`]*\\.group'";
  };

  testCopyOfACopiedOrDerivedSecretFailsTheCopysCheck = {
    expr =
      map
        (
          value:
          failuresOf
            (nodesOf {
              metrics = [
                (service "telegraf" {
                  secrets = {
                    origin.value.generated = "alnum";
                    token = {
                      inherit value;
                      sendTo = [ writers ];
                    };
                  };
                })
              ];
              store = [ (influxdb { static.user = "influxdb2"; } { }) ];
            }).store
        )
        [
          {
            copied = (tokenOf "metrics") // {
              id = "origin";
            };
          }
          { derived.generator = "basic-auth"; }
        ];
    expected = lib.replicate 2 [
      "nixos-contracts: secrets claim `influxdb.writers.metrics.telegraf.token`: it references `metrics:secrets.telegraf.token`, which is copied or derived itself; reference a provided or generated secret."
    ];
  };

  testCopyItsDynamicIdentityCannotReadFailsTheReadabilityCheck = {
    expr =
      failuresOf
        (nodesOf {
          metrics = [ (telegraf [ writers ]) ];
          store = [ (influxdb { dynamic.unit = "influxdb.service"; } { }) ];
        }).store;
    expected = [
      "nixos-contracts: secrets claim `influxdb.writers.metrics.telegraf.token`: its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup` and the secret that group."
    ];
  };

  testCopyOnAnInboxOfAKindOtherThanSecretsFailsACheck = {
    expr = map (inbox: failures [ (service "nginx" { inboxes.received = inbox; }) ]) [
      {
        kind = "binds";
        copy = { };
      }
      { copy.mode = "0400"; }
    ];
    expected = [
      [
        "nixos-contracts: inboxes claim `nginx.received`: it sets `copy`, but `binds` claims have no copies; set `copy = null` and read `received`."
      ]
      [ ]
    ];
  };

  testInboxIsSentNowhere = {
    expr =
      (evaluate [
        (service "nginx" {
          inboxes.upstreams.sendTo = [ clients ];
        })
      ]).contracts.services.nginx.inboxes.upstreams.kind;
    expectedError.msg = "inboxes\\.upstreams\\.sendTo' does not exist";
  };
}
