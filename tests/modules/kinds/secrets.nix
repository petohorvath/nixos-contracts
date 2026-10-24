{ contracts }:
let
  inherit (contracts) evaluate failures nodesOf;

  service = name: identity: secrets: {
    contracts.services.${name} = {
      enable = true;
      inherit identity secrets;
    };
  };
  oneSecret = {
    key = { };
  };
  configWithSecret =
    modules: identity: secret:
    evaluate (
      modules
      ++ [
        (service "svc" identity {
          key = secret;
        })
      ]
    );
  secretOf =
    modules: identity: secret:
    (configWithSecret modules identity secret).contracts.claimSets.secrets.svc-key;
  ownerOf =
    identity: secret:
    let
      claim = (configWithSecret [ ] identity secret).contracts.services.svc.secrets.key;
    in
    {
      inherit (claim) owner group;
    };
  backend.contracts.kinds.secrets.backend = {
    location = name: "/run/agenix/${name}";
    generators = [ ];
  };
  rules = {
    imports = [ backend ];
    contracts.kinds.secrets.delivery.path = { unit, name }: "/run/credentials/${unit}/${name}";
  };

  # A telegraf service generating its token, and a store service copying
  # the secrets its references name.
  telegraf = service "telegraf" { static.user = "telegraf"; } { token.generate = "alnum"; };
  store = service "influxdb" { static.user = "influxdb2"; };
  remoteToken = {
    node = "metrics";
    name = "telegraf-token";
  };
in
{
  testSecretDefaultsToAGroupReadableRootFile = {
    expr =
      (evaluate [
        backend
        (service "chrony" { static.user = "chrony"; } oneSecret)
      ]).contracts.claimSets.secrets.chrony-key;
    expected = {
      service = "chrony";
      id = "key";
      name = "chrony-key";
      mode = "0440";
      owner = "root";
      group = "chrony";
      generate = null;
      from = [ ];
      referenced = [ ];
      unit = null;
      delivered = false;
      path = "/run/agenix/chrony-key";
    };
  };

  testStaticIdentityGroupReadsTheSecret = {
    expr = ownerOf {
      static = {
        user = "kea";
        group = "dhcp";
      };
    } { };
    expected = {
      owner = "root";
      group = "dhcp";
    };
  };

  testDynamicIdentityLeavesTheSecretToRoot = {
    expr = ownerOf { dynamic.unit = "alloy.service"; } { };
    expected = {
      owner = "root";
      group = "root";
    };
  };

  testDynamicIdentitySharedGroupReadsTheSecret = {
    expr = ownerOf {
      dynamic = {
        unit = "alloy.service";
        sharedGroup = "logs";
      };
    } { };
    expected = {
      owner = "root";
      group = "logs";
    };
  };

  testExplicitSecretOwnerAndGroupAreKept = {
    expr = ownerOf { static.user = "chrony"; } {
      owner = "chrony";
      group = "time";
    };
    expected = {
      owner = "chrony";
      group = "time";
    };
  };

  testSecretNamesTheGeneratorOfItsValue = {
    expr = (secretOf [ ] { static.user = "svc"; } { generate = "alnum"; }).generate;
    expected = "alnum";
  };

  testSecretNamingAGeneratorTheBackendLacksFailsItsCheck =
    let
      alnumAndHex.contracts.kinds.secrets.backend = {
        location = name: "/run/agenix/${name}";
        generators = [
          "alnum"
          "hex"
        ];
      };
      generating = generate: service "svc" { static.user = "svc"; } { key.generate = generate; };
    in
    {
      expr = {
        unknown = failures [
          alnumAndHex
          (generating "alnm")
        ];
        provided = failures [
          alnumAndHex
          (generating "hex")
        ];
        noneProvided = failures [
          backend
          (generating "alnum")
        ];
        withoutABackend = failures [ (generating "alnm") ];
      };
      expected = {
        unknown = [
          "nixos-contracts: secrets claim `svc-key`: the secret backend provides no generator `alnm`; name one of `alnum`, `hex`."
        ];
        provided = [ ];
        noneProvided = [
          "nixos-contracts: secrets claim `svc-key`: the secret backend provides no generator `alnum`."
        ];
        withoutABackend = [ ];
      };
    };

  testSecretReferenceByClaimNameNamesThisConfiguration = {
    expr =
      (secretOf [ ] { static.user = "svc"; } {
        from = [
          "svc-other"
          {
            node = "metrics";
            name = "telegraf-token";
          }
        ];
      }).from;
    expected = [
      {
        node = null;
        name = "svc-other";
      }
      {
        node = "metrics";
        name = "telegraf-token";
      }
    ];
  };

  testSecretReferencingSeveralSecretsNeedsAGenerator =
    let
      referencing =
        secret:
        service "svc" { static.user = "svc"; } {
          a = { };
          b = { };
          key = {
            from = [
              "svc-a"
              "svc-b"
            ];
          }
          // secret;
        };
    in
    {
      expr = {
        copy = failures [ (referencing { }) ];
        generated = failures [ (referencing { generate = "basic-auth"; }) ];
      };
      expected = {
        copy = [
          "nixos-contracts: secrets claim `svc-key`: it references several secrets but has no `generate`; a copy references one."
        ];
        generated = [ ];
      };
    };

  testSecretRejectsAGenerator = {
    expr = (secretOf [ ] { static.user = "svc"; } { generator = "alnum"; }).mode;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.generator' does not exist";
  };

  testSecretPathWithoutABackendFails = {
    expr = (secretOf [ ] { static.user = "svc"; } { }).path;
    expectedError.msg = "nixos-contracts: secret `svc-key` has no location: import a secret backend adapter such as `nixosModules\\.agenix-rekey`, which sets `contracts\\.kinds\\.secrets\\.backend`";
  };

  testStaticIdentityReadsTheBackendLocation = {
    expr = (secretOf [ rules ] { static.user = "svc"; } { }).path;
    expected = "/run/agenix/svc-key";
  };

  testDynamicIdentitySecretNamesItsUnit = {
    expr = (secretOf [ ] { dynamic.unit = "svc.service"; } { }).unit;
    expected = "svc.service";
  };

  testDynamicIdentityReadsTheDeliveredCredential = {
    expr = (secretOf [ rules ] { dynamic.unit = "svc.service"; } { }).path;
    expected = "/run/credentials/svc.service/svc-key";
  };

  testDynamicIdentityWithoutDeliveryReadsTheBackendLocation = {
    expr = (secretOf [ backend ] { dynamic.unit = "svc.service"; } { }).path;
    expected = "/run/agenix/svc-key";
  };

  testOnlyADynamicIdentityWithADeliveryAdapterIsDelivered = {
    expr = {
      dynamicWithDelivery = (secretOf [ rules ] { dynamic.unit = "svc.service"; } { }).delivered;
      dynamicWithoutDelivery = (secretOf [ backend ] { dynamic.unit = "svc.service"; } { }).delivered;
      static = (secretOf [ rules ] { static.user = "svc"; } { }).delivered;
    };
    expected = {
      dynamicWithDelivery = true;
      dynamicWithoutDelivery = false;
      static = false;
    };
  };

  testDynamicIdentityCannotReadAnUndeliveredSecretOutsideItsGroup =
    let
      message = "nixos-contracts: secrets claim `svc-key`: its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup` and the secret that group.";
      undelivered = service "svc" { dynamic.unit = "svc.service"; } oneSecret;
    in
    {
      expr = {
        installed = failures [
          backend
          undelivered
        ];
        withoutABackend = failures [ undelivered ];
      };
      expected = {
        installed = [ message ];
        withoutABackend = [ message ];
      };
    };

  testReadableSecretsPassTheCheck = {
    expr = {
      sharedGroup = failures [
        backend
        (service "svc" {
          dynamic = {
            unit = "svc.service";
            sharedGroup = "logs";
          };
        } oneSecret)
      ];
      delivered = failures [
        rules
        (service "svc" { dynamic.unit = "svc.service"; } oneSecret)
      ];
      static = failures [
        backend
        (service "svc" { static.user = "svc"; } oneSecret)
      ];
    };
    expected = {
      sharedGroup = [ ];
      delivered = [ ];
      static = [ ];
    };
  };

  testSecondBackendFails = {
    expr =
      (secretOf [
        backend
        {
          contracts.kinds.secrets.backend = {
            location = name: "/run/secrets/${name}";
            generators = [ "hex" ];
          };
        }
      ] { static.user = "svc"; } { }).path;
    expectedError.msg = "contracts\\.kinds\\.secrets\\.backend'[^\n]*\nA configuration imports one secret backend adapter[^\n]*\nDefinition values:\n- In [\\s\\S]*\n- In ";
  };

  testSecondDeliveryFails = {
    expr =
      (secretOf [
        rules
        { contracts.kinds.secrets.delivery.path = { unit, name }: "/run/keys/${unit}/${name}"; }
      ] { dynamic.unit = "svc.service"; } { }).path;
    expectedError.msg = "contracts\\.kinds\\.secrets\\.delivery'[^\n]*\nA configuration imports one delivery adapter[^\n]*\nDefinition values:\n- In [\\s\\S]*\n- In ";
  };

  testNodeForcesTheWholeBackend = {
    expr =
      (secretOf [
        backend
        (
          { lib, ... }:
          {
            contracts.kinds.secrets.backend = lib.mkForce {
              location = name: "/run/secrets/${name}";
              generators = [ ];
            };
          }
        )
      ] { static.user = "svc"; } { }).path;
    expected = "/run/secrets/svc-key";
  };

  testNodeCannotForceOnlyTheBackendLocation = {
    expr =
      (secretOf [
        backend
        (
          { lib, ... }:
          {
            contracts.kinds.secrets.backend.location = lib.mkForce (name: "/run/secrets/${name}");
          }
        )
      ] { static.user = "svc"; } { }).path;
    expectedError.msg = "contracts\\.kinds\\.secrets\\.backend'[^\n]*\nA configuration imports one secret backend adapter";
  };

  testSecretPathIsReadOnly = {
    expr =
      (evaluate [
        (service "svc" { static.user = "svc"; } oneSecret)
        { contracts.services.svc.secrets.key.path = "/elsewhere"; }
      ]).contracts.services.svc.secrets.key.path;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.path' is read-only";
  };

  testReferenceResolvesToTheClaimItNames =
    let
      nodes = nodesOf {
        metrics = [ telegraf ];
        store = [
          (store {
            origin.generate = "alnum";
            remote.from = [ remoteToken ];
            local.from = [ "influxdb-origin" ];
          })
        ];
      };
      inherit (nodes.store.config.contracts.claimSets) secrets;
      namesOf = secret: map (reference: reference.claim.name) secret.referenced;
    in
    {
      expr = {
        remote = namesOf secrets.influxdb-remote;
        local = namesOf secrets.influxdb-local;
        inherit (nodes.store.config.contracts) failures;
      };
      expected = {
        remote = [ "telegraf-token" ];
        local = [ "influxdb-origin" ];
        failures = [ ];
      };
    };

  testReferenceToItsOwnNodeByNameReadsThisConfiguration =
    let
      nodes = nodesOf {
        store = [
          (store {
            origin.generate = "alnum";
            copy.from = [
              {
                node = "store";
                name = "influxdb-origin";
              }
            ];
          })
        ];
      };
    in
    {
      expr = map (
        reference: reference.claim.name
      ) nodes.store.config.contracts.claimSets.secrets.influxdb-copy.referenced;
      expected = [ "influxdb-origin" ];
    };

  testReferenceToAnUnknownNodeFailsItsCheck = {
    expr =
      (nodesOf { store = [ (store { token.from = [ remoteToken ]; }) ]; })
      .store.config.contracts.failures;
    expected = [
      "nixos-contracts: secrets claim `influxdb-token`: it references node `metrics`, which is not in `contracts.nodes`."
    ];
  };

  testReferenceToANodeWithoutContractsFailsItsCheck = {
    expr = failures [
      (store { token.from = [ remoteToken ]; })
      # The metrics node imports no nixos-contracts module.
      { contracts.nodes.metrics.config = { }; }
    ];
    expected = [
      "nixos-contracts: secrets claim `influxdb-token`: it references `metrics:telegraf-token`, whose node imports no nixos-contracts module."
    ];
  };

  testReferenceToNoSecretOfAnEnabledContractFailsItsCheck = {
    expr =
      (nodesOf {
        metrics = [
          telegraf
          ({ lib, ... }: { contracts.services.telegraf.enable = lib.mkForce false; })
        ];
        store = [
          (store {
            remote.from = [ remoteToken ];
            local.from = [ "influxdb-missing" ];
          })
        ];
      }).store.config.contracts.failures;
    expected = [
      "nixos-contracts: secrets claim `influxdb-local`: it references `influxdb-missing`, which is no secret claim of an enabled contract."
      "nixos-contracts: secrets claim `influxdb-remote`: it references `metrics:telegraf-token`, which is no secret claim of an enabled contract."
    ];
  };

  testRejectedReferenceResolvesToANullClaim = {
    expr =
      (nodesOf { store = [ (store { token.from = [ remoteToken ]; }) ]; })
      .store.config.contracts.claimSets.secrets.influxdb-token.referenced;
    expected = [
      {
        node = "metrics";
        name = "telegraf-token";
        claim = null;
      }
    ];
  };

  testEachRejectedReferenceFailsItsOwnCheck = {
    expr = failures [
      (store {
        hashes = {
          generate = "basic-auth";
          from = [
            "influxdb-a"
            "influxdb-b"
          ];
        };
      })
    ];
    expected = [
      "nixos-contracts: secrets claim `influxdb-hashes`: it references `influxdb-a`, which is no secret claim of an enabled contract."
      "nixos-contracts: secrets claim `influxdb-hashes`: it references `influxdb-b`, which is no secret claim of an enabled contract."
    ];
  };

  testReferenceToASecretWithReferencesFailsItsCheck = {
    expr = failures [
      (store {
        origin.generate = "alnum";
        copy.from = [ "influxdb-origin" ];
        chained.from = [ "influxdb-copy" ];
      })
    ];
    expected = [
      "nixos-contracts: secrets claim `influxdb-chained`: it references `influxdb-copy`, which references secrets itself; reference a secret without `from`."
    ];
  };

  testCopiesReferencingEachOtherFailTheirChecks =
    let
      nodes = nodesOf {
        metrics = [
          (service "telegraf" { static.user = "telegraf"; } {
            token.from = [
              {
                node = "store";
                name = "influxdb-token";
              }
            ];
          })
        ];
        store = [ (store { token.from = [ remoteToken ]; }) ];
      };
    in
    {
      expr = builtins.mapAttrs (_: node: node.config.contracts.failures) nodes;
      expected = {
        metrics = [
          "nixos-contracts: secrets claim `telegraf-token`: it references `store:influxdb-token`, which references secrets itself; reference a secret without `from`."
        ];
        store = [
          "nixos-contracts: secrets claim `influxdb-token`: it references `metrics:telegraf-token`, which references secrets itself; reference a secret without `from`."
        ];
      };
    };

  testSecretReferencedIsReadOnly = {
    expr =
      (evaluate [
        (service "svc" { static.user = "svc"; } oneSecret)
        { contracts.services.svc.secrets.key.referenced = [ ]; }
      ]).contracts.services.svc.secrets.key.referenced;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.referenced' is read-only";
  };
}
