{
  contracts,
  contractsLib,
  lib,
}:
let
  inherit (contracts) nodesOf;
  inherit (contractsLib) claimNameOf copiesOf;

  telegraf.contracts.services.telegraf = {
    enable = true;
    identity.static.user = "telegraf";
    secrets.token.value.generated = "alnum";
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
        inherit (secret) owner mode;
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
}
