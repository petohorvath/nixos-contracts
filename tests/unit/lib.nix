{
  contractsLib,
  helpers,
  lib,
  ...
}:
let
  inherit (helpers.contracts) evaluate nodesOf;
  inherit (contractsLib)
    backendNameOf
    claimNameOf
    claimsOf
    copiesOf
    labels
    mkReference
    ;

  telegraf.contracts.services.telegraf = {
    enable = true;
    identity.static.user = "telegraf";
    secrets.token.value.generated.generator = "alnum";
    mounts.state.path = "/var/lib/telegraf";
  };

  # Influxdb holding a copy of each of `references`, built with `copiesOf`,
  # and `extra` as further definitions of its secrets.
  receiving = references: extra: {
    contracts.services.influxdb = {
      enable = true;
      identity.static.user = "influxdb2";
      secrets = lib.mkMerge ([ (copiesOf references) ] ++ extra);
    };
  };

  # Nodes by identity, each running telegraf and holding a copy of every
  # node's telegraf token, read from a `let`-bound list of `ref`s as a
  # fleet's shared data carries them.
  handingEachOtherTokens =
    identities:
    let
      tokens = map (node: nodes.${node}.config.contracts.services.telegraf.secrets.token.ref) identities;
      nodes = nodesOf (
        lib.genAttrs identities (_: [
          telegraf
          (receiving tokens [ ])
        ])
      );
    in
    nodes;
in
{
  # The claims are on `metrics`, read from the node collection `store`
  # shares.
  testClaimNameOfAReferenceToAClaimOnAnotherNodeIsThatClaimsName =
    let
      nodes = nodesOf {
        metrics = [ telegraf ];
        store = [ ];
      };
      contract = nodes.store.config.contracts.nodes.metrics.config.contracts.services.telegraf;
      claims = [
        contract.secrets.token
        contract.mounts.state
      ];
      names = [
        "metrics_secrets_telegraf_token"
        "metrics_mounts_telegraf_state"
      ];
    in
    {
      expr = {
        claimNames = map (claim: claimNameOf claim.ref) claims;
        names = map (claim: claim.name) claims;
      };
      expected = {
        claimNames = names;
        inherit names;
      };
    };

  testClaimNameOfJoinsTheReferencesNodeKindServiceAndId = {
    expr = claimNameOf {
      node = "metrics";
      kind = "secrets";
      service = "telegraf";
      id = "api_token";
    };
    expected = "metrics_secrets_telegraf_api_token";
  };

  testBackendNameOfJoinsTheClaimsServiceAndId = {
    expr = backendNameOf {
      service = "influxdb";
      id = "admin_token";
    };
    expected = "influxdb_admin_token";
  };

  testClaimsOfListsAClaimSetsClaimsByServiceAndThenId = {
    expr = map (claim: claim.name) (
      claimsOf
        (evaluate [
          {
            contracts.services = {
              telegraf = {
                enable = true;
                identity.static.user = "telegraf";
                secrets = {
                  token = { };
                  api-key = { };
                };
              };
              influxdb = {
                enable = true;
                identity.static.user = "influxdb2";
                secrets.admin-token = { };
              };
            };
          }
        ]).contracts.claimSets.secrets
    );
    expected = [
      "local_secrets_influxdb_admin-token"
      "local_secrets_telegraf_api-key"
      "local_secrets_telegraf_token"
    ];
  };

  # The copy references a node missing from the empty node collection, so
  # its check fails, naming the copy and the reference.
  testLabelsAreThoseAFailedChecksMessageNames =
    let
      reference = {
        node = "metrics";
        kind = "secrets";
        service = "telegraf";
        id = "token";
      };
      config = evaluate [
        {
          contracts.services.influxdb = {
            enable = true;
            identity.static.user = "influxdb2";
            secrets.token.value.copied = reference;
          };
        }
      ];
      claim = labels.claim config.contracts.services.influxdb.secrets.token;
      referenceLabel = labels.reference reference;
    in
    {
      expr = {
        inherit claim;
        reference = referenceLabel;
        named = map (
          message: lib.hasInfix "`${claim}`" message && lib.hasInfix "`${referenceLabel}`" message
        ) config.contracts.failures;
      };
      expected = {
        claim = "influxdb.token";
        reference = "metrics:secrets.telegraf.token";
        named = [ true ];
      };
    };

  testCopiesOfHoldsOneCopyPerReferenceKeyedByItsClaimName = {
    expr = copiesOf [
      {
        node = "alpha";
        kind = "secrets";
        service = "telegraf";
        id = "token";
      }
      {
        node = "beta";
        kind = "secrets";
        service = "telegraf";
        id = "token";
      }
    ];
    expected = {
      alpha_secrets_telegraf_token.value.copied = {
        node = "alpha";
        kind = "secrets";
        service = "telegraf";
        id = "token";
      };
      beta_secrets_telegraf_token.value.copied = {
        node = "beta";
        kind = "secrets";
        service = "telegraf";
        id = "token";
      };
    };
  };

  testPerCopyFieldsUnderTheSameKeysMergeIntoEachCopy =
    let
      tokens = map (node: nodes.${node}.config.contracts.services.telegraf.secrets.token.ref) [
        "alpha"
        "beta"
      ];
      nodes = nodesOf {
        alpha = [ telegraf ];
        beta = [ telegraf ];
        store = [
          (receiving tokens [
            (lib.genAttrs (map claimNameOf tokens) (_: {
              owner = "influxdb2";
              mode = "0400";
            }))
          ])
        ];
      };
    in
    {
      expr = lib.mapAttrs (_: secret: {
        inherit (secret) mode owner;
        source = map (source: source.claim.name) secret.sources;
      }) nodes.store.config.contracts.claimSets.secrets.influxdb;
      expected = {
        alpha_secrets_telegraf_token = {
          owner = "influxdb2";
          mode = "0400";
          source = [ "alpha_secrets_telegraf_token" ];
        };
        beta_secrets_telegraf_token = {
          owner = "influxdb2";
          mode = "0400";
          source = [ "beta_secrets_telegraf_token" ];
        };
      };
    };

  testReceiversCopyingEachOthersTokensEvaluateWithoutRecursion = {
    expr =
      lib.mapAttrs
        (_: node: {
          copies = lib.attrNames node.config.contracts.claimSets.secrets.influxdb;
          inherit (node.config.contracts) failures;
        })
        (handingEachOtherTokens [
          "alpha"
          "beta"
        ]);
    expected = lib.genAttrs [ "alpha" "beta" ] (_: {
      copies = [
        "alpha_secrets_telegraf_token"
        "beta_secrets_telegraf_token"
      ];
      failures = [ ];
    });
  };

  testMkReferenceEqualsTheRefOfTheClaimItNames =
    let
      nodes = nodesOf {
        metrics = [ telegraf ];
        store = [ ];
      };
      token = mkReference "secrets" {
        node = "metrics";
        service = "telegraf";
        id = "token";
      };
    in
    {
      expr = {
        equalsRef = token == nodes.metrics.config.contracts.services.telegraf.secrets.token.ref;
        resolved = (nodes.store.config.contracts.resolve token).claim.name;
      };
      expected = {
        equalsRef = true;
        resolved = "metrics_secrets_telegraf_token";
      };
    };

  mkReferenceFails =
    let
      token = {
        node = "metrics";
        service = "telegraf";
        id = "token";
      };
      lowercase = "may contain only lowercase letters, digits and hyphens\\.";
    in
    {
      testOnMissingField = {
        expr = mkReference "secrets" (removeAttrs token [ "service" ]);
        expectedError.msg = "nixos-contracts: reference `metrics:secrets\\.\\?\\.token` has no `service`";
      };
      testOnAValueThatIsNotAnAttributeSet = {
        expr = mkReference "secrets" "metrics_secrets_telegraf_token";
        expectedError.msg = "nixos-contracts: a reference is an attribute set `\\{ node; kind; service; id; }`, not a string";
      };

      testOnUnknownField = {
        expr = mkReference "secrets" (token // { path = "/run/token"; });
        expectedError.msg = "nixos-contracts: reference `metrics:secrets\\.telegraf\\.token` has an unknown field `path`";
      };
      testOnKindField = {
        expr = mkReference "secrets" (token // { kind = "secrets"; });
        expectedError.msg = "nixos-contracts: reference `metrics:secrets\\.telegraf\\.token` has an unknown field `kind`";
      };
      testOnInvalidNode = {
        expr = mkReference "secrets" (token // { node = "Metrics"; });
        expectedError.msg = "nixos-contracts: reference `Metrics:secrets\\.telegraf\\.token`: node identity `Metrics` ${lowercase}";
      };
      testOnInvalidKind = {
        expr = mkReference "api_tokens" token;
        expectedError.msg = "nixos-contracts: reference `metrics:api_tokens\\.telegraf\\.token`: claim kind name `api_tokens` ${lowercase}";
      };
      testOnInvalidService = {
        expr = mkReference "secrets" (token // { service = "web_proxy"; });
        expectedError.msg = "nixos-contracts: reference `metrics:secrets\\.web_proxy\\.token`: service name `web_proxy` ${lowercase}";
      };
      testOnInvalidId = {
        expr = mkReference "secrets" (token // { id = "admin.token"; });
        expectedError.msg = "nixos-contracts: reference `metrics:secrets\\.telegraf\\.admin\\.token`: secrets claim id `admin\\.token` of service `telegraf` may contain only lowercase letters, digits, hyphens and `_`\\.";
      };
    };
}
