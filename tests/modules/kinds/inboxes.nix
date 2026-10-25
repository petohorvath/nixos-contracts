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

  # Influxdb on the `store` node takes secrets in its writers and sends its
  # bind to telegraf's outputs on the `metrics` node.
  writers = {
    node = "store";
    service = "influxdb";
    id = "writers";
  };
  outputs = {
    node = "metrics";
    service = "telegraf";
    id = "outputs";
  };
  influxdb = service "influxdb" {
    binds.http = {
      port = 8086;
      sendTo = [ outputs ];
    };
    inboxes.writers = { };
  };
  checkSendsIs = checkSends: { contracts = { inherit checkSends; }; };

  # The nodes above, with telegraf's secrets built by `secretsOf` from its
  # outputs inbox, under the send check on `metrics` when `checkSends`.
  driftingNodes =
    checkSends: secretsOf:
    nodesOf {
      store = [ influxdb ];
      metrics = [
        (checkSendsIs checkSends)
        (
          { config, ... }:
          service "telegraf" {
            inboxes.outputs.kind = "binds";
            secrets = secretsOf config.contracts.services.telegraf.inboxes.outputs;
          }
        )
      ];
    };
  driftThroughReceived = inbox: {
    token.sendTo = lib.mapAttrsToList (node: _: writers // { inherit node; }) inbox.received;
  };
  driftThroughRefs = inbox: {
    token.sendTo = map (ref: writers // { inherit (ref) node; }) inbox.refs;
  };

  # Nodes sending to others and to themselves, none depending on what it
  # received, every node under the send check when `checkSends`.
  fleetOf =
    checkSends:
    builtins.mapAttrs (_: modules: [ (checkSendsIs checkSends) ] ++ modules) {
      metrics = [
        (service "telegraf" {
          secrets.token.sendTo = [
            writers
            clients
          ];
          inboxes.outputs.kind = "binds";
        })
      ];
      store = [
        influxdb
        (telegraf [ writers ])
        (loki [
          upstreams
          outputs
        ])
      ];
      proxy = [
        nginx
        nginxUpstreams
      ];
    };

  # What each node of a fleet sends, receives and fails, by node.
  observedIn = builtins.mapAttrs (
    _: node: {
      sends = builtins.mapAttrs (_: builtins.mapAttrs (_: builtins.mapAttrs (_: claim: claim.sendTo))) (
        removeAttrs node.config.contracts.claimSets [ "inboxes" ]
      );
      inboxes = builtins.mapAttrs (
        _:
        builtins.mapAttrs (
          _: inbox: {
            received = builtins.mapAttrs (
              _:
              builtins.mapAttrs (
                _:
                builtins.mapAttrs (
                  _: entry: {
                    inherit (entry) ref copy;
                    inherit (entry.claim) name;
                  }
                )
              )
            ) inbox.received;
            inherit (inbox) refs;
          }
        )
      ) node.config.contracts.claimSets.inboxes;
      upstreams = node.config.upstreams or { };
      inherit (node.config.contracts) failures;
    }
  );
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

  testSendCheckNamesAClaimWhoseSendToDependsOnWhatItsNodeReceived = {
    expr = failuresOf (driftingNodes true driftThroughReceived).metrics;
    expected = [
      "nixos-contracts: secrets claim `telegraf.token` sends to `store:inboxes.influxdb.writers` once its node has received claims, but to nothing before: whether a claim exists and where it is sent must not depend on an inbox's `received` or `refs`."
    ];
  };

  # One claim exists only once the node has received, the other only before.
  testSendCheckNamesAClaimWhoseExistenceDependsOnWhatItsNodeReceived = {
    expr = map (secretsOf: failuresOf (driftingNodes true secretsOf).metrics) [
      (
        outputs:
        lib.mapAttrs' (node: _: lib.nameValuePair "echo-${node}" { sendTo = [ writers ]; }) outputs.received
      )
      (outputs: lib.optionalAttrs (outputs.received == { }) { standby.sendTo = [ writers ]; })
    ];
    expected = [
      [
        "nixos-contracts: secrets claim `telegraf.echo-store` sends to `store:inboxes.influxdb.writers` once its node has received claims, but to nothing before: whether a claim exists and where it is sent must not depend on an inbox's `received` or `refs`."
      ]
      [
        "nixos-contracts: secrets claim `telegraf.standby` sends to nothing once its node has received claims, but to `store:inboxes.influxdb.writers` before: whether a claim exists and where it is sent must not depend on an inbox's `received` or `refs`."
      ]
    ];
  };

  testSendCheckNamesAClaimWhoseSendToDependsOnTheRefsItsNodeReceived = {
    expr = failuresOf (driftingNodes true driftThroughRefs).metrics;
    expected = [
      "nixos-contracts: secrets claim `telegraf.token` sends to `store:inboxes.influxdb.writers` once its node has received claims, but to nothing before: whether a claim exists and where it is sent must not depend on an inbox's `received` or `refs`."
    ];
  };

  # Without the send check, a send that depends on what its node received
  # recurses, as documented for `contracts.checkSends`.
  testSendDependingOnWhatItsNodeReceivedRecursesWithoutTheSendCheck = {
    expr = failuresOf (driftingNodes false driftThroughReceived).metrics;
    expectedError.msg = "infinite recursion encountered";
  };

  testSendDependingOnTheRefsItsNodeReceivedRecursesWithoutTheSendCheck = {
    expr = failuresOf (driftingNodes false driftThroughRefs).metrics;
    expectedError.msg = "infinite recursion encountered";
  };

  testSendCheckChangesNoSendAndNothingReceivedWithoutADependence = {
    expr = observedIn (nodesOf (fleetOf true));
    expected = observedIn (nodesOf (fleetOf false));
  };
}
