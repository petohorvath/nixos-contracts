{ contracts, lib }:
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
  identityOf = modules: (evaluate modules).contracts.services.chrony.identity;
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

  testNodeSwitchesADefaultStaticIdentityToADynamicOne = {
    expr = identityOf [
      { contracts.services.chrony.identity.static.user = lib.mkDefault "chrony"; }
      { contracts.services.chrony.identity.dynamic.unit = "chronyd.service"; }
    ];
    expected.dynamic = {
      unit = "chronyd.service";
      sharedGroup = null;
    };
  };

  testNodeSwitchesADefaultDynamicIdentityToAStaticOne = {
    expr = identityOf [
      { contracts.services.chrony.identity.dynamic.unit = lib.mkDefault "chronyd.service"; }
      { contracts.services.chrony.identity.static.user = "chrony"; }
    ];
    expected.static = {
      user = "chrony";
      group = null;
    };
  };

  testTwoTagsOfOnePriorityFail = {
    expr = identityOf [
      { contracts.services.chrony.identity.static.user = "chrony"; }
      { contracts.services.chrony.identity.dynamic.unit = "chronyd.service"; }
    ];
    expectedError.msg = "contracts\\.services\\.chrony\\.identity` is defined both as `dynamic` and `static`";
  };

  testOverrideOnAWholeTagWins = {
    expr = identityOf [
      { contracts.services.chrony.identity.static.user = "chrony"; }
      {
        contracts.services.chrony.identity = lib.mkOverride 90 { dynamic.unit = "chronyd.service"; };
      }
    ];
    expected.dynamic = {
      unit = "chronyd.service";
      sharedGroup = null;
    };
  };

  testLeafInsideADefaultCountsAtDefaultPriority = {
    expr = identityOf [
      { contracts.services.chrony.identity.static = lib.mkDefault { user = "chrony"; }; }
      { contracts.services.chrony.identity.dynamic.unit = "chronyd.service"; }
    ];
    expected.dynamic = {
      unit = "chronyd.service";
      sharedGroup = null;
    };
  };

  testLeafCountsAtItsInnermostOverride = {
    expr = identityOf [
      { contracts.services.chrony.identity.static = lib.mkDefault { user = lib.mkForce "chrony"; }; }
      { contracts.services.chrony.identity.dynamic.unit = "chronyd.service"; }
    ];
    expected.static = {
      user = "chrony";
      group = null;
    };
  };

  testConditionalTagCountsAtItsContents = {
    expr = identityOf [
      { contracts.services.chrony.identity.static = lib.mkIf true { user = lib.mkDefault "chrony"; }; }
      { contracts.services.chrony.identity.dynamic.unit = "chronyd.service"; }
    ];
    expected.dynamic = {
      unit = "chronyd.service";
      sharedGroup = null;
    };
  };

  testMergeOfDefaultContentsGivesWayToANormalTag = {
    expr = identityOf [
      {
        contracts.services.chrony.identity.static = lib.mkMerge [
          { user = lib.mkDefault "chrony"; }
          (lib.mkDefault { group = "time"; })
        ];
      }
      { contracts.services.chrony.identity.dynamic.unit = "chronyd.service"; }
    ];
    expected.dynamic = {
      unit = "chronyd.service";
      sharedGroup = null;
    };
  };

  testMergeInsideADefaultCountsAtDefaultPriority = {
    expr = identityOf [
      {
        contracts.services.chrony.identity.static = lib.mkDefault (
          lib.mkMerge [
            { user = "chrony"; }
            { group = "time"; }
          ]
        );
      }
      { contracts.services.chrony.identity.dynamic.unit = "chronyd.service"; }
    ];
    expected.dynamic = {
      unit = "chronyd.service";
      sharedGroup = null;
    };
  };

  testTagUnderAFalseConditionKeepsTheOtherTag = {
    expr = identityOf [
      { contracts.services.chrony.identity.static.user = lib.mkDefault "chrony"; }
      { contracts.services.chrony.identity.dynamic = lib.mkIf false { unit = "chronyd.service"; }; }
    ];
    expected.static = {
      user = "chrony";
      group = null;
    };
  };

  testLeafUnderAFalseConditionDoesNotSwitchTheTag = {
    expr = identityOf [
      { contracts.services.chrony.identity.static.user = lib.mkDefault "chrony"; }
      { contracts.services.chrony.identity.dynamic.unit = lib.mkIf false "chronyd.service"; }
    ];
    expected.static = {
      user = "chrony";
      group = null;
    };
  };

  testFalseConditionInAMergeCountsAtTheTrueOnesPriority = {
    expr = identityOf [
      { contracts.services.chrony.identity.static.user = "chrony"; }
      {
        contracts.services.chrony.identity.dynamic = lib.mkMerge [
          (lib.mkIf false { unit = lib.mkForce "chronyd.service"; })
          (lib.mkIf true { unit = lib.mkDefault "chronyd.service"; })
        ];
      }
    ];
    expected.static = {
      user = "chrony";
      group = null;
    };
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

  testNodeIdentityMayUseOnlyLowercaseLettersDigitsAndHyphens = {
    expr = (evaluate [ { contracts.node = "beta-2"; } ]).contracts.node;
    expected = "beta-2";
  };

  testNodeIdentityWithAnUnderscoreFails = {
    expr = (evaluate [ { contracts.node = "beta_influxdb"; } ]).contracts.node;
    expectedError.msg = "node identity `beta_influxdb` may contain only lowercase letters, digits and hyphens";
  };

  testNodeIdentityWithAnUppercaseLetterFails = {
    expr = failures [
      web
      { contracts.node = "Beta"; }
    ];
    expectedError.msg = "node identity `Beta` may contain only lowercase letters, digits and hyphens";
  };

  testServiceNameWithAnUnderscoreFails = {
    expr =
      (evaluate [
        {
          contracts.services.web_proxy = {
            enable = true;
            identity.static.user = "web";
            binds.http.port = 8080;
          };
        }
      ]).contracts.claimSets.binds;
    expectedError.msg = "service name `web_proxy` may contain only lowercase letters, digits and hyphens";
  };

  testServiceNameWithAnUppercaseLetterFails = {
    expr = failures [
      {
        contracts.services.Web = {
          enable = true;
          identity.static.user = "web";
        };
      }
    ];
    expectedError.msg = "service name `Web` may contain only lowercase letters, digits and hyphens";
  };

  testEmptyServiceNameFails = {
    expr =
      (evaluate [
        {
          contracts.services."" = {
            identity.static.user = "web";
            binds.http.port = 8080;
          };
        }
      ]).contracts.services."".binds.http.location;
    expectedError.msg = "service name `` may contain only lowercase letters, digits and hyphens";
  };

  testResolveIndexesTheNestedClaimSet = {
    expr =
      let
        config = evaluate [
          web
          {
            contracts.node = "here";
            contracts.services.web.binds.http-alt.port = 8081;
          }
        ];
      in
      config.contracts.resolve config.contracts.services.web.binds.http-alt.ref
      == config.contracts.claimSets.binds.web.http-alt;
    expected = true;
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
        inherit (result.claim) location name;
        inherit (result) reason;
      };
    expected = {
      location = [
        "web"
        "http"
      ];
      name = "backend_web_http";
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
              # `exporter-metrics` join into one name with `-`; the
              # lookup tells them apart.
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
        noNode = "it names no node; a claim's `ref` names one only when its configuration sets `contracts.node`";
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
    expected = "it names no node; a claim's `ref` names one only when its configuration sets `contracts.node`";
  };

  testLookupIsReadOnly = {
    expr = (evaluate [ { contracts.lookup = _: { }; } ]).contracts.lookup;
    expectedError.msg = "contracts\\.lookup' is read-only";
  };

  testResolveIsReadOnly = {
    expr = (evaluate [ { contracts.resolve = _: { }; } ]).contracts.resolve;
    expectedError.msg = "contracts\\.resolve' is read-only";
  };
}
