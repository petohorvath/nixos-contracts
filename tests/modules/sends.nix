{ contracts, lib }:
let
  inherit (contracts) nodesOf;
  inherit (import ../fixtures/inboxes.nix)
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
  # received, every node under the send check when `checkSends`. Influxdb
  # holds a copy of each token its writers receive.
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
        { contracts.services.influxdb.inboxes.writers.copy.mode = "0400"; }
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
                    inherit (entry) ref;
                    inherit (entry.claim) name;
                    # A copy's `path` needs a backend, which the fleet has
                    # none of.
                    copy =
                      if entry.copy == null then
                        null
                      else
                        {
                          inherit (entry.copy)
                            owner
                            group
                            mode
                            value
                            location
                            ;
                        };
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

  # The copies' locations show that the comparison covers copies.
  testSendCheckChangesNoSendAndNothingReceivedWithoutADependence =
    let
      observed = observedIn (nodesOf (fleetOf true));
      writersReceived = observed.store.inboxes.influxdb.writers.received;
    in
    {
      expr = {
        inherit observed;
        copies = map (node: writersReceived.${node}.telegraf.token.copy.location) [
          "metrics"
          "store"
        ];
      };
      expected = {
        observed = observedIn (nodesOf (fleetOf false));
        copies = [
          [
            "influxdb"
            "writers"
            "metrics"
            "telegraf"
            "token"
          ]
          [
            "influxdb"
            "writers"
            "store"
            "telegraf"
            "token"
          ]
        ];
      };
    };
}
