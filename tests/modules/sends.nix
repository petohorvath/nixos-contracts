{ contracts, lib }:
let
  inherit (contracts) nodesOf;
  inherit (import ../fixtures/inboxes.nix)
    service
    clients
    nginx
    loki
    receivedBy
    failuresOf
    telegraf
    tokenOf
    writers
    outputs
    ;

  # Influxdb on the `store` node takes secrets in its writers and sends its
  # bind to telegraf's outputs on the `metrics` node.
  influxdb = service "influxdb" {
    binds.http = {
      port = 8086;
      sendTo = [ outputs ];
    };
    inboxes.writers = { };
  };

  # The nodes above, with telegraf's secrets built by `secretsOf` from its
  # outputs inbox.
  driftingNodes =
    secretsOf:
    nodesOf {
      store = [ influxdb ];
      metrics = [
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
in
{
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

  # Telegraf sends its token to the store's influxdb, which sends its bind
  # to telegraf's outputs.
  testNodesSendingToEachOtherEvaluateWithoutACycle =
    let
      nodes = nodesOf {
        metrics = [
          (service "telegraf" {
            secrets.token.sendTo = [ writers ];
            inboxes.outputs.kind = "binds";
          })
        ];
        store = [ influxdb ];
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

  # A node's sends are read from its claim sets, so a send that depends on
  # what its node received recurses.
  testSendDependingOnWhatItsNodeReceivedRecurses = {
    expr = failuresOf (driftingNodes driftThroughReceived).metrics;
    expectedError.msg = "infinite recursion encountered";
  };

  testSendDependingOnTheRefsItsNodeReceivedRecurses = {
    expr = failuresOf (driftingNodes driftThroughRefs).metrics;
    expectedError.msg = "infinite recursion encountered";
  };
}
