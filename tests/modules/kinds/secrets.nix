{ contracts, contractsLib }:
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
  telegraf = service "telegraf" { static.user = "telegraf"; } { token.value.generated = "alnum"; };
  store = service "influxdb" { static.user = "influxdb2"; };
  remoteToken = {
    node = "metrics";
    service = "telegraf";
    id = "token";
  };

  # A configuration whose node identity is `store`, without a node
  # collection, and a reference to an influxdb secret on the `store` node.
  onStore.contracts.node = "store";
  storeSecret = id: {
    node = "store";
    service = "influxdb";
    inherit id;
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
      value.provided = { };
      ref = {
        node = null;
        kind = "secrets";
        service = "chrony";
        id = "key";
      };
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
    expr = (secretOf [ ] { static.user = "svc"; } { value.generated = "alnum"; }).value;
    expected.generated = "alnum";
  };

  testNodeWritesProvidedOverADefaultGenerated = {
    expr =
      (evaluate [
        {
          contracts.services.svc = contractsLib.mkDefaultContract {
            enable = true;
            identity.static.user = "svc";
            secrets.key.value.generated = "alnum";
          };
        }
        { contracts.services.svc.secrets.key.value.provided = { }; }
      ]).contracts.claimSets.secrets.svc-key.value;
    expected.provided = { };
  };

  testProvidedValueTakesNoOptions = {
    expr = (secretOf [ ] { static.user = "svc"; } { value.provided.length = 32; }).value;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.value\\.provided\\.length' does not exist";
  };

  testGeneratedAndProvidedAtOnePriorityFail = {
    expr =
      (secretOf [
        { contracts.services.svc.secrets.key.value.provided = { }; }
      ] { static.user = "svc"; } { value.generated = "alnum"; }).value;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.value` is defined both as `generated` and `provided`";
  };

  testMisspeltValueTagIsATypeError = {
    expr = (secretOf [ ] { static.user = "svc"; } { value.generate = "alnum"; }).value;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.value' is not of type `attribute-tagged union with choices: generated, provided'";
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
      generating = generator: service "svc" { static.user = "svc"; } { key.value.generated = generator; };
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

  testSecretReferenceDefaultsItsKind = {
    expr = (secretOf [ ] { static.user = "svc"; } { from = [ remoteToken ]; }).from;
    expected = [
      {
        node = "metrics";
        kind = "secrets";
        service = "telegraf";
        id = "token";
      }
    ];
  };

  testSecretReferenceOfAnotherKindIsATypeError = {
    expr =
      (secretOf [ ] { static.user = "svc"; } {
        from = [ (remoteToken // { kind = "binds"; }) ];
      }).from;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.from[^\n]*\\.kind' is not of type";
  };

  testSecretReferenceByClaimNameIsATypeError = {
    expr = (secretOf [ ] { static.user = "svc"; } { from = [ "telegraf-token" ]; }).from;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.from[^\n]*' is not of type `submodule'";
  };

  testSecretReferenceNeedsANode = {
    expr =
      (secretOf [ ] { static.user = "svc"; } {
        from = [ (removeAttrs remoteToken [ "node" ]) ];
      }).from;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.from[^\n]*\\.node' was accessed but has no value defined";
  };

  testSecretReferencingSeveralSecretsNeedsAGenerator =
    let
      referencing =
        secret:
        service "svc" { static.user = "svc"; } {
          a = { };
          b = { };
          key = {
            from =
              map
                (id: {
                  node = "here";
                  service = "svc";
                  inherit id;
                })
                [
                  "a"
                  "b"
                ];
          }
          // secret;
        };
      here.contracts.node = "here";
    in
    {
      expr = {
        copy = failures [
          here
          (referencing { })
        ];
        generated = failures [
          here
          (referencing { value.generated = "basic-auth"; })
        ];
      };
      expected = {
        copy = [
          "nixos-contracts: secrets claim `svc-key`: it references several secrets but its value is not `generated`; a copy references one."
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
            origin.value.generated = "alnum";
            remote.from = [ remoteToken ];
            local.from = [ (storeSecret "origin") ];
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

  testReferenceToItsOwnNodeReadsThisConfiguration = {
    expr =
      map (reference: reference.claim.name)
        (evaluate [
          onStore
          (store { origin.value.generated = "alnum"; })
          (
            { config, ... }:
            {
              contracts.services.influxdb.secrets.copy.from = [
                config.contracts.services.influxdb.secrets.origin.ref
              ];
            }
          )
        ]).contracts.claimSets.secrets.influxdb-copy.referenced;
    expected = [ "influxdb-origin" ];
  };

  testReferenceWithoutANodeIdentityFailsItsCheck = {
    expr = failures [
      (store { origin.value.generated = "alnum"; })
      (
        { config, ... }:
        {
          contracts.services.influxdb.secrets.copy.from = [
            config.contracts.services.influxdb.secrets.origin.ref
          ];
        }
      )
    ];
    expected = [
      "nixos-contracts: secrets claim `influxdb-copy`: it references `<no node>:secrets.influxdb.origin`: it names no node; a claim's `ref` names one only when its configuration sets `contracts.node`."
    ];
  };

  testHandWrittenReferenceWithANullNodeFailsItsCheck = {
    expr = failures [
      onStore
      (store {
        origin.value.generated = "alnum";
        copy.from = [ (storeSecret "origin" // { node = null; }) ];
      })
    ];
    expected = [
      "nixos-contracts: secrets claim `influxdb-copy`: it references `<no node>:secrets.influxdb.origin`: it names no node; a claim's `ref` names one only when its configuration sets `contracts.node`."
    ];
  };

  testReferenceToAnUnknownNodeFailsItsCheck = {
    expr =
      (nodesOf { store = [ (store { token.from = [ remoteToken ]; }) ]; })
      .store.config.contracts.failures;
    expected = [
      "nixos-contracts: secrets claim `influxdb-token`: it references `metrics:secrets.telegraf.token`: node `metrics` is not in `contracts.nodes`."
    ];
  };

  testReferenceToANodeWithoutContractsFailsItsCheck = {
    expr = failures [
      (store { token.from = [ remoteToken ]; })
      # The metrics node imports no nixos-contracts module.
      { contracts.nodes.metrics.config = { }; }
    ];
    expected = [
      "nixos-contracts: secrets claim `influxdb-token`: it references `metrics:secrets.telegraf.token`: node `metrics` imports no nixos-contracts module."
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
            local.from = [ (storeSecret "missing") ];
          })
        ];
      }).store.config.contracts.failures;
    expected = [
      "nixos-contracts: secrets claim `influxdb-local`: it references `store:secrets.influxdb.missing`: no enabled contract on `store` holds it."
      "nixos-contracts: secrets claim `influxdb-remote`: it references `metrics:secrets.telegraf.token`: no enabled contract on `metrics` holds it."
    ];
  };

  testRejectedReferenceResolvesToANullClaim = {
    expr =
      (nodesOf { store = [ (store { token.from = [ remoteToken ]; }) ]; })
      .store.config.contracts.claimSets.secrets.influxdb-token.referenced;
    expected = [
      {
        node = "metrics";
        kind = "secrets";
        service = "telegraf";
        id = "token";
        claim = null;
      }
    ];
  };

  testEachRejectedReferenceFailsItsOwnCheck = {
    expr = failures [
      onStore
      (store {
        hashes = {
          value.generated = "basic-auth";
          from = [
            (storeSecret "a")
            (storeSecret "b")
          ];
        };
      })
    ];
    expected = [
      "nixos-contracts: secrets claim `influxdb-hashes`: it references `store:secrets.influxdb.a`: no enabled contract on `store` holds it."
      "nixos-contracts: secrets claim `influxdb-hashes`: it references `store:secrets.influxdb.b`: no enabled contract on `store` holds it."
    ];
  };

  testReferenceToASecretWithReferencesFailsItsCheck = {
    expr = failures [
      onStore
      (store {
        origin.value.generated = "alnum";
        copy.from = [ (storeSecret "origin") ];
        chained.from = [ (storeSecret "copy") ];
      })
    ];
    expected = [
      "nixos-contracts: secrets claim `influxdb-chained`: it references `store:secrets.influxdb.copy`, which references secrets itself; reference a secret without `from`."
    ];
  };

  testCopiesReferencingEachOtherFailTheirChecks =
    let
      nodes = nodesOf {
        metrics = [
          (service "telegraf" { static.user = "telegraf"; } {
            token.from = [ (storeSecret "token") ];
          })
        ];
        store = [ (store { token.from = [ remoteToken ]; }) ];
      };
    in
    {
      expr = builtins.mapAttrs (_: node: node.config.contracts.failures) nodes;
      expected = {
        metrics = [
          "nixos-contracts: secrets claim `telegraf-token`: it references `store:secrets.influxdb.token`, which references secrets itself; reference a secret without `from`."
        ];
        store = [
          "nixos-contracts: secrets claim `influxdb-token`: it references `metrics:secrets.telegraf.token`, which references secrets itself; reference a secret without `from`."
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
