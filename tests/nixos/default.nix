{ nixos, module }:
let
  inherit (nixos) evaluate;

  web = name: {
    contracts.services.${name} = {
      enable = true;
      identity.static.user = name;
      binds.http.port = 80;
    };
  };

  # NixOS configurations by node, sharing one node collection.
  nodesOf = import ../fixtures/nodes.nix {
    inherit evaluate;
    modulesOf = _: [ module ];
  };

  # Influxdb on `store` sends its bind to telegraf's outputs on `metrics`,
  # where telegraf sends its token to influxdb's writers, to every node its
  # outputs received from when `drifts`, under the send check when
  # `checkSends` on both. Influxdb holds a copy of each token it receives.
  telegrafAndInfluxdb =
    { checkSends, drifts }:
    nodesOf {
      store = [
        {
          contracts.checkSends = checkSends;
          contracts.services.influxdb = {
            enable = true;
            identity.static.user = "influxdb";
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
            inboxes.writers.copy.mode = "0400";
          };
        }
      ];
      metrics = [
        (
          { config, ... }:
          {
            contracts = {
              inherit checkSends;
              services.telegraf = {
                enable = true;
                identity.static.user = "telegraf";
                inboxes.outputs.kind = "binds";
                secrets.token.sendTo =
                  map
                    (node: {
                      inherit node;
                      service = "influxdb";
                      id = "writers";
                    })
                    (
                      if drifts then
                        builtins.attrNames config.contracts.services.telegraf.inboxes.outputs.received
                      else
                        [ "store" ]
                    );
              };
            };
          }
        )
      ];
    };
in
{
  # NixOS's own assertions fail too without a bootloader, so look for the
  # failure among them.
  testNixosModuleForwardsFailuresToAssertions = {
    expr =
      let
        failedAssertions =
          builtins.filter (check: !check.assertion)
            (evaluate [
              module
              (web "first")
              (web "second")
            ]).assertions;
      in
      builtins.elem
        "nixos-contracts: binds claims `first.http` and `second.http` clash: both listen on tcp port 80, at `0.0.0.0` and `0.0.0.0`."
        (map (check: check.message) failedAssertions);
    expected = true;
  };

  testNixosModuleWiresADaemonFromItsContract = {
    expr =
      (evaluate [
        module
        (web "first")
        (
          { config, ... }:
          {
            services.nginx = {
              enable = true;
              defaultHTTPListenPort = config.contracts.services.first.binds.http.port;
            };
          }
        )
      ]).services.nginx.defaultHTTPListenPort;
    expected = 80;
  };

  testNixosModuleImportedTwiceDeclaresItsOptionsOnce = {
    expr =
      (evaluate [
        module
        module
        (web "first")
      ]).contracts.claimSets.binds.first.http.port;
    expected = 80;
  };

  testSendCheckNamesASendThatDependsOnWhatItsNodeReceived = {
    expr =
      (telegrafAndInfluxdb {
        checkSends = true;
        drifts = true;
      }).metrics.config.contracts.failures;
    expected = [
      "nixos-contracts: secrets claim `telegraf.token` sends to `store:inboxes.influxdb.writers` once its node has received claims, but to nothing before: whether a claim exists and where it is sent must not depend on an inbox's `received` or `refs`."
    ];
  };

  # The copy's location shows that the comparison covers copies, whose
  # `path` needs a backend, which neither node has.
  testSendCheckChangesNoSendAndNothingReceivedWithoutADependence =
    let
      observe =
        checkSends:
        builtins.mapAttrs
          (_: node: {
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
            inherit (node.config.contracts) failures;
          })
          (telegrafAndInfluxdb {
            inherit checkSends;
            drifts = false;
          });
      observed = observe true;
    in
    {
      expr = {
        inherit observed;
        copy = observed.store.inboxes.influxdb.writers.received.metrics.telegraf.token.copy.location;
      };
      expected = {
        observed = observe false;
        copy = [
          "influxdb"
          "writers"
          "metrics"
          "telegraf"
          "token"
        ];
      };
    };
}
