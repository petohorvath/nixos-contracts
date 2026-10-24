{ contracts }:
let
  inherit (contracts) evaluate failures nodesOf;

  # A web service listening on port 8080, and a reference to that bind.
  web = {
    contracts.services.web = {
      enable = true;
      identity.static.user = "web";
      binds.http.port = 8080;
    };
  };
  webHttp = node: {
    inherit node;
    kind = "binds";
    service = "web";
    id = "http";
  };
  reasonOf = config: reference: (config.contracts.lookup reference).reason;
in
{
  testContractsAreDisabledByDefault = {
    expr =
      (evaluate [ { contracts.services.chrony.identity.static.user = "chrony"; } ])
      .contracts.services.chrony.enable;
    expected = false;
  };

  testStaticIdentityGroupDefaultsToNull = {
    expr =
      (evaluate [ { contracts.services.chrony.identity.static.user = "chrony"; } ])
      .contracts.services.chrony.identity;
    expected.static = {
      user = "chrony";
      group = null;
    };
  };

  testDynamicIdentityNamesItsUnit = {
    expr =
      (evaluate [ { contracts.services.alloy.identity.dynamic.unit = "alloy.service"; } ])
      .contracts.services.alloy.identity;
    expected.dynamic = {
      unit = "alloy.service";
      sharedGroup = null;
    };
  };

  testIdentityIsRequired = {
    expr =
      (evaluate [ { contracts.services.chrony.enable = true; } ]).contracts.services.chrony.identity;
    expectedError.msg = "contracts\\.services\\.chrony\\.identity' was accessed but has no value defined";
  };

  testIdentityTakesExactlyOneTag = {
    expr =
      (evaluate [
        {
          contracts.services.chrony.identity = {
            static.user = "chrony";
            dynamic.unit = "chronyd.service";
          };
        }
      ]).contracts.services.chrony.identity;
    expectedError.msg = "contracts\\.services\\.chrony\\.identity";
  };

  testNoContractsMeanNoAssertions = {
    expr = (evaluate [ ]).contracts.assertions;
    expected = [ ];
  };

  testFailuresArePrefixedMessagesOfFailedChecks = {
    expr =
      (evaluate [
        {
          contracts.assertions = [
            {
              assertion = false;
              message = "the first check fails.";
            }
            {
              assertion = true;
              message = "the second check holds.";
            }
          ];
        }
      ]).contracts.failures;
    expected = [ "nixos-contracts: the first check fails." ];
  };

  testFailuresAreReadOnly = {
    expr = (evaluate [ { contracts.failures = [ "set by hand" ]; } ]).contracts.failures;
    expectedError.msg = "contracts\\.failures' is read-only";
  };

  testNodeIdentityDefaultsToNull = {
    expr = (evaluate [ ]).contracts.node;
    expected = null;
  };

  testNodeIdentityMustBeInTheNodeCollection = {
    expr = failures [
      {
        contracts = {
          node = "here";
          nodes.elsewhere.config = { };
        };
      }
    ];
    expected = [
      "nixos-contracts: `contracts.node` is `here`, which is not in `contracts.nodes`."
    ];
  };

  testNodeIdentityNeedsNoNodeCollection = {
    expr = failures [ { contracts.node = "here"; } ];
    expected = [ ];
  };

  testResolveFindsAClaimOfThisConfiguration = {
    expr =
      let
        config = evaluate [
          web
          { contracts.node = "here"; }
        ];
      in
      (config.contracts.resolve config.contracts.services.web.binds.http.ref).port;
    expected = 8080;
  };

  testResolveFindsAClaimOnAnotherNode = {
    expr =
      (
        (nodesOf {
          backend = [ web ];
          proxy = [ ];
        }).proxy.config.contracts.resolve
          (webHttp "backend")
      ).port;
    expected = 8080;
  };

  testResolveFailsWithTheReason = {
    expr = ((evaluate [ web ]).contracts.resolve (webHttp "backend")).port;
    expectedError.msg = "nixos-contracts: cannot resolve `backend:binds\\.web\\.http`: node `backend` is not in `contracts\\.nodes`";
  };

  testLookupReturnsTheClaimAndNoReason = {
    expr =
      let
        result = (nodesOf { backend = [ web ]; }).backend.config.contracts.lookup (webHttp "backend");
      in
      {
        inherit (result.claim) name;
        inherit (result) reason;
      };
    expected = {
      name = "web-http";
      reason = null;
    };
  };

  testLookupReasons =
    let
      nodes = nodesOf {
        backend = [
          web
          {
            contracts.services = {
              # A disabled contract holds no claim a reference may name.
              off = {
                identity.static.user = "off";
                binds.http.port = 9090;
              };
              # `chrony-exporter` + `metrics` and `chrony` +
              # `exporter-metrics` share the claim name
              # `chrony-exporter-metrics`.
              chrony-exporter = {
                enable = true;
                identity.static.user = "chrony";
                binds.metrics.port = 9123;
              };
            };
          }
        ];
        proxy = [ ];
        bare = [ ];
      };
      inherit (nodes.proxy) config;
      backend = webHttp "backend";
    in
    {
      expr = {
        noNode = reasonOf config (backend // { node = null; });
        unknownNode = reasonOf config (webHttp "nope");
        unknownKind = reasonOf config (backend // { kind = "databases"; });
        disabled = reasonOf config (backend // { service = "off"; });
        otherSplit = reasonOf config (
          backend
          // {
            service = "chrony";
            id = "exporter-metrics";
          }
        );
      };
      expected = {
        noNode = "it names no node, since the configuration holding the claim sets no `contracts.node`";
        unknownNode = "node `nope` is not in `contracts.nodes`";
        unknownKind = "node `backend` has no claim kind `databases`";
        disabled = "no enabled contract on `backend` holds it";
        otherSplit = "no enabled contract on `backend` holds it";
      };
    };

  testLookupOfANodeWithoutContracts = {
    expr = reasonOf (evaluate [ { contracts.nodes.bare.config = { }; } ]) (webHttp "bare");
    expected = "node `bare` imports no nixos-contracts module";
  };

  testANullNodeNeverResolvesInThisConfiguration = {
    expr =
      let
        # Neither configuration has a node identity, so the reference's null
        # node equals this configuration's.
        config = evaluate [ web ];
      in
      reasonOf config config.contracts.services.web.binds.http.ref;
    expected = "it names no node, since the configuration holding the claim sets no `contracts.node`";
  };

  testResolveIsReadOnly = {
    expr = (evaluate [ { contracts.resolve = _: { }; } ]).contracts.resolve;
    expectedError.msg = "contracts\\.resolve' is read-only";
  };
}
