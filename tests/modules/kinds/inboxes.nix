{ contracts, lib }:
let
  inherit (contracts) evaluate failures nodesOf;
  inherit (import ../../fixtures/inboxes.nix)
    service
    upstreams
    clients
    nginx
    loki
    nginxUpstreams
    receivedBy
    failuresOf
    telegraf
    tokenOf
    writers
    outputs
    copyingInfluxdb
    ;

  refsOf = config: inbox: config.contracts.services.nginx.inboxes.${inbox}.refs;

  # What a test reads of a received entry.
  entryOf = entry: {
    inherit (entry) ref copy;
    inherit (entry.claim) name value;
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

  # An alloy password sent to nginx's clients.
  alloy = service "alloy" { secrets.password.sendTo = [ clients ]; };
  # Nginx deriving an htpasswd from the secrets its clients inbox received,
  # and the names of the htpasswd's sources.
  htpasswd =
    { config, ... }:
    {
      contracts.services.nginx.secrets.htpasswd.value.derived = {
        generator = "basic-auth";
        from = config.contracts.services.nginx.inboxes.clients.refs;
      };
    };
  sourceNamesOf =
    config: map (source: source.claim.name) config.contracts.services.nginx.secrets.htpasswd.sources;
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

  # `beta-vm:…` sorts before `beta:…`, and the second collection defines
  # alpha's services the other way round.
  testSecretDerivedFromAnInboxsRefsHasASourcePerSentSecretInTheirOrder =
    let
      nodesWith =
        alphaModules:
        nodesOf {
          alpha = alphaModules;
          beta = [ (telegraf [ clients ]) ];
          beta-vm = [ (telegraf [ clients ]) ];
          proxy = [
            nginx
            htpasswd
            (service "grafana" {
              secrets.password.sendTo = [ (clients // { node = "proxy"; }) ];
            })
          ];
        };
      nodes = nodesWith [
        (telegraf [ clients ])
        alloy
      ];
      reordered = nodesWith [
        alloy
        (telegraf [ clients ])
      ];
    in
    {
      expr = {
        sources = sourceNamesOf nodes.proxy.config;
        reordered = sourceNamesOf reordered.proxy.config;
        inherit (nodes.proxy.config.contracts) failures;
      };
      expected = {
        sources = [
          "alpha_alloy_password"
          "alpha_telegraf_token"
          "beta-vm_telegraf_token"
          "beta_telegraf_token"
          "proxy_grafana_password"
        ];
        reordered = [
          "alpha_alloy_password"
          "alpha_telegraf_token"
          "beta-vm_telegraf_token"
          "beta_telegraf_token"
          "proxy_grafana_password"
        ];
        failures = [ ];
      };
    };

  testAddingASenderAddsASourceWithoutChangingTheReceivingNode = {
    expr =
      map
        (
          senders:
          sourceNamesOf
            (nodesOf (
              senders
              // {
                proxy = [
                  nginx
                  htpasswd
                ];
              }
            )).proxy.config
        )
        [
          { metrics = [ (telegraf [ clients ]) ]; }
          {
            metrics = [ (telegraf [ clients ]) ];
            logs = [ alloy ];
          }
        ];
    expected = [
      [ "metrics_telegraf_token" ]
      [
        "logs_alloy_password"
        "metrics_telegraf_token"
      ]
    ];
  };

  # A generator building a user per source from its name, as an htpasswd
  # does, gets one user per node for one service and id sent from two.
  testSecretsOfOneServiceSentFromTwoNodesHaveDistinctNames = {
    expr =
      sourceNamesOf
        (nodesOf {
          alpha = [ (telegraf [ clients ]) ];
          beta = [ (telegraf [ clients ]) ];
          proxy = [
            nginx
            htpasswd
          ];
        }).proxy.config;
    expected = [
      "alpha_telegraf_token"
      "beta_telegraf_token"
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
          (copyingInfluxdb { static.user = "influxdb2"; } { })
          {
            contracts.services.influxdb.secrets.token = {
              value.generated = "alnum";
              sendTo = [ outputs ];
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
            store = [ (copyingInfluxdb { static.user = "influxdb2"; } { mode = "0400"; }) ];
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
            store = [ (copyingInfluxdb identity { }) ] ++ modules;
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
          store = [ (copyingInfluxdb { static.user = "influxdb2"; } { gruop = "writers"; }) ];
        }).store.config
      ).metrics.telegraf.token.copy.group;
    expectedError.msg = "inboxes\\.writers\\.copy\\.gruop' does not exist";
  };

  testMisspeltCopyFieldFailsAtItsDefinitionWithNothingReceived = {
    expr = failures [
      { contracts.node = "store"; }
      (copyingInfluxdb { static.user = "influxdb2"; } { gruop = "writers"; })
    ];
    expectedError.msg = "inboxes\\.writers\\.copy\\.gruop' does not exist";
  };

  testMisspeltCopyFieldOffersTheClosestOption = {
    expr =
      (writersOf
        (nodesOf {
          metrics = [ (telegraf [ writers ]) ];
          store = [ (copyingInfluxdb { static.user = "influxdb2"; } { gruop = "writers"; }) ];
        }).store.config
      ).metrics.telegraf.token.copy.group;
    expectedError.msg = "Did you mean `[^`]*\\.group'";
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
