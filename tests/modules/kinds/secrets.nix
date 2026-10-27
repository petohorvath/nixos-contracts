{
  contracts,
  contractsLib,
  lib,
}:
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
    (configWithSecret modules identity secret).contracts.claimSets.secrets.svc.key;
  ownerOf =
    identity: secret:
    let
      claim = (configWithSecret [ ] identity secret).contracts.services.svc.secrets.key;
    in
    {
      inherit (claim) group owner;
    };
  # A backend and a delivery naming a secret `<service>_<id>`, as the
  # shipped adapters do. Their paths take no other arguments, so a slot
  # passed anything else fails.
  backendPath = { service, id }: "/run/agenix/${service}_${id}";
  backendSlot.contracts.kinds.secrets.backend = {
    path = backendPath;
    generators = [ ];
  };
  slots = {
    imports = [ backendSlot ];
    contracts.kinds.secrets.delivery.path =
      {
        unit,
        service,
        id,
      }:
      "/run/credentials/${unit}/${service}_${id}";
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

  # Influxdb receiving `references` as a receiver writes its claims from
  # shared data: one copy of each, keyed by its claim name, and an
  # htpasswd derived from all.
  receiving =
    references:
    store (
      contractsLib.copiesOf references
      // {
        htpasswd.value.derived = {
          generator = "basic-auth";
          from = references;
        };
      }
    );
  # Nodes by identity, telegraf on each of `senders` and influxdb on each
  # of `receivers`, every receiver given the same `let`-bound list of
  # references: each sender's telegraf token `ref`, and then `extra`.
  handingTokens =
    {
      senders,
      receivers,
      extra ? [ ],
    }:
    let
      tokens =
        map (node: nodes.${node}.config.contracts.services.telegraf.secrets.token.ref) senders ++ extra;
      nodes = nodesOf (
        lib.genAttrs (lib.unique (senders ++ receivers)) (
          node:
          lib.optional (builtins.elem node senders) telegraf
          ++ lib.optional (builtins.elem node receivers) (receiving tokens)
        )
      );
    in
    nodes;
  sourceNamesOf = secret: map (source: source.claim.name) secret.sources;
  # What a receiving node holds: the sources of each copy, by id, and of
  # its derived htpasswd.
  receivedBy =
    node:
    let
      secrets = node.config.contracts.claimSets.secrets.influxdb;
    in
    {
      copies = lib.mapAttrs (_: sourceNamesOf) (removeAttrs secrets [ "htpasswd" ]);
      derived = sourceNamesOf secrets.htpasswd;
    };
in
{
  testSecretDefaultsToAGroupReadableRootFile = {
    expr =
      (evaluate [
        backendSlot
        (service "chrony" { static.user = "chrony"; } oneSecret)
      ]).contracts.claimSets.secrets.chrony.key;
    expected = {
      service = "chrony";
      id = "key";
      name = "local_secrets_chrony_key";
      mode = "0440";
      owner = "root";
      group = "chrony";
      value.provided = { };
      ref = {
        node = "local";
        kind = "secrets";
        service = "chrony";
        id = "key";
      };
      sources = [ ];
      unit = null;
      delivered = false;
      backendPath = "/run/agenix/chrony_key";
      path = "/run/agenix/chrony_key";
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
    } { unit = null; };
    expected = {
      owner = "root";
      group = "logs";
    };
  };

  testDeliveredSecretLeavesItsFileToRoot = {
    expr = {
      static = ownerOf { static.user = "mastodon"; } { unit = "mastodon-init-dirs.service"; };
      sharedGroup = ownerOf {
        dynamic = {
          unit = "alloy.service";
          sharedGroup = "logs";
        };
      } { };
    };
    expected = {
      static = {
        owner = "root";
        group = "root";
      };
      sharedGroup = {
        owner = "root";
        group = "root";
      };
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

  testDerivedValueReferencesNoSecretsByDefault = {
    expr = (secretOf [ ] { static.user = "svc"; } { value.derived.generator = "basic-auth"; }).value;
    expected.derived = {
      generator = "basic-auth";
      from = [ ];
    };
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
      ]).contracts.claimSets.secrets.svc.key.value;
    expected.provided = { };
  };

  testNodeWritesCopiedOverADefaultGenerated = {
    expr =
      (evaluate [
        {
          contracts.services.svc = contractsLib.mkDefaultContract {
            enable = true;
            identity.static.user = "svc";
            secrets.key.value.generated = "alnum";
          };
        }
        { contracts.services.svc.secrets.key.value.copied = remoteToken; }
      ]).contracts.claimSets.secrets.svc.key.value;
    expected.copied = remoteToken // {
      kind = "secrets";
    };
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
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.value' is not of type `attribute-tagged union with choices: copied, derived, generated, provided'";
  };

  testSecretNamingAGeneratorTheBackendLacksFailsItsCheck =
    let
      alnumAndHex.contracts.kinds.secrets.backend = {
        path = backendPath;
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
          backendSlot
          (generating "alnum")
        ];
        withoutABackend = failures [ (generating "alnm") ];
        derived = failures [
          alnumAndHex
          (service "svc" { static.user = "svc"; } { key.value.derived.generator = "basic-auth"; })
        ];
      };
      expected = {
        unknown = [
          "nixos-contracts: secrets claim `svc.key`: the secret backend provides no generator `alnm`; name one of `alnum`, `hex`."
        ];
        provided = [ ];
        noneProvided = [
          "nixos-contracts: secrets claim `svc.key`: the secret backend provides no generator `alnum`."
        ];
        withoutABackend = [ ];
        derived = [
          "nixos-contracts: secrets claim `svc.key`: the secret backend provides no generator `basic-auth`; name one of `alnum`, `hex`."
        ];
      };
    };

  testSecretReferenceDefaultsItsKind = {
    expr = (secretOf [ ] { static.user = "svc"; } { value.copied = remoteToken; }).value;
    expected.copied = {
      node = "metrics";
      kind = "secrets";
      service = "telegraf";
      id = "token";
    };
  };

  testSecretReferenceOfAnotherKindIsATypeError = {
    expr =
      (secretOf [ ] { static.user = "svc"; } {
        value.copied = remoteToken // {
          kind = "binds";
        };
      }).value;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.value\\.copied\\.kind' is not of type";
  };

  testSecretReferenceWithAnInvalidNameIsATypeError = {
    expr =
      (secretOf [ ] { static.user = "svc"; } {
        value.copied = remoteToken // {
          service = "web_proxy";
        };
      }).value;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.value\\.copied\\.service' is not of type `string of lowercase letters, digits and hyphens'";
  };

  testDerivedReferenceOfAnotherKindIsATypeError = {
    expr =
      (secretOf [ ] { static.user = "svc"; } {
        value.derived = {
          generator = "basic-auth";
          from = [ (remoteToken // { kind = "binds"; }) ];
        };
      }).value;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.value\\.derived\\.from[^\n]*\\.kind' is not of type";
  };

  testSecretReferenceByClaimNameIsATypeError = {
    expr = (secretOf [ ] { static.user = "svc"; } { value.copied = "telegraf-token"; }).value;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.value\\.copied' is not of type `submodule'";
  };

  testSecretReferenceNeedsANode = {
    expr =
      (secretOf [ ] { static.user = "svc"; } {
        value.copied = removeAttrs remoteToken [ "node" ];
      }).value;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.value\\.copied\\.node' was accessed but has no value defined";
  };

  testDerivedValueWithoutReferencesPassesTheCheck = {
    expr = failures [
      {
        contracts.kinds.secrets.backend = {
          path = backendPath;
          generators = [ "basic-auth" ];
        };
      }
      (service "svc" { static.user = "svc"; } { key.value.derived.generator = "basic-auth"; })
    ];
    expected = [ ];
  };

  testSecretRejectsAGenerator = {
    expr = (secretOf [ ] { static.user = "svc"; } { generator = "alnum"; }).mode;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.generator' does not exist";
  };

  testSecretPathWithoutABackendFails = {
    expr = (secretOf [ ] { static.user = "svc"; } { }).path;
    expectedError.msg = "nixos-contracts: secret `svc\\.key` has no path: import a secret backend adapter such as `nixosModules\\.agenix-rekey`, which sets `contracts\\.kinds\\.secrets\\.backend`";
  };

  testSecretBackendPathIsWhereTheBackendInstallsIt = {
    expr =
      let
        undelivered = secretOf [ slots ] { static.user = "svc"; } { };
        delivered = secretOf [ slots ] { static.user = "svc"; } { unit = "svc.service"; };
      in
      {
        undelivered = { inherit (undelivered) backendPath path; };
        delivered = { inherit (delivered) backendPath path; };
      };
    expected = {
      undelivered = {
        path = "/run/agenix/svc_key";
        backendPath = "/run/agenix/svc_key";
      };
      delivered = {
        path = "/run/credentials/svc.service/svc_key";
        backendPath = "/run/agenix/svc_key";
      };
    };
  };

  testSecretBackendPathWithoutABackendFails = {
    expr = (secretOf [ ] { static.user = "svc"; } { }).backendPath;
    expectedError.msg = "nixos-contracts: secret `svc\\.key` has no path: import a secret backend adapter such as `nixosModules\\.agenix-rekey`, which sets `contracts\\.kinds\\.secrets\\.backend`";
  };

  testStaticIdentityReadsTheBackendPath = {
    expr = (secretOf [ slots ] { static.user = "svc"; } { }).path;
    expected = "/run/agenix/svc_key";
  };

  testStaticIdentitySecretNamingAUnitReadsTheDeliveredCredential = {
    expr =
      let
        secret = secretOf [ slots ] { static.user = "mastodon"; } { unit = "mastodon-init-dirs.service"; };
      in
      {
        inherit (secret) delivered path unit;
      };
    expected = {
      unit = "mastodon-init-dirs.service";
      delivered = true;
      path = "/run/credentials/mastodon-init-dirs.service/svc_key";
    };
  };

  testDynamicIdentitySecretNamesItsUnit = {
    expr = (secretOf [ ] { dynamic.unit = "svc.service"; } { }).unit;
    expected = "svc.service";
  };

  testDynamicIdentityReadsTheDeliveredCredential = {
    expr = (secretOf [ slots ] { dynamic.unit = "svc.service"; } { }).path;
    expected = "/run/credentials/svc.service/svc_key";
  };

  testUndeliveredDynamicIdentitySecretReadsTheBackendPath = {
    expr = (secretOf [ slots ] { dynamic.unit = "svc.service"; } { unit = null; }).path;
    expected = "/run/agenix/svc_key";
  };

  testDeliveredSecretWithoutADeliveryAdapterHasNoPath = {
    expr = (secretOf [ backendSlot ] { dynamic.unit = "svc.service"; } { }).path;
    expectedError.msg = "nixos-contracts: secret `svc\\.key` is delivered to `svc\\.service` but has no path: import a delivery adapter such as `nixosModules\\.systemd-credentials`";
  };

  testDeliveredSecretWithoutADeliveryAdapterFailsItsCheck = {
    expr = {
      dynamic = failures [
        backendSlot
        (service "svc" { dynamic.unit = "svc.service"; } oneSecret)
      ];
      static = failures [
        backendSlot
        (service "svc" { static.user = "svc"; } { key.unit = "svc.service"; })
      ];
    };
    expected = {
      dynamic = [
        "nixos-contracts: secrets claim `svc.key`: it is delivered to `svc.service`, but no delivery adapter is imported; import one such as `nixosModules.systemd-credentials`, or set its `unit` to null."
      ];
      static = [
        "nixos-contracts: secrets claim `svc.key`: it is delivered to `svc.service`, but no delivery adapter is imported; import one such as `nixosModules.systemd-credentials`, or set its `unit` to null."
      ];
    };
  };

  testDynamicIdentitySecretDeliveredToAnotherUnitFailsItsCheck = {
    expr = failures [
      slots
      (service "svc" { dynamic.unit = "svc.service"; } { key.unit = "other.service"; })
    ];
    expected = [
      "nixos-contracts: secrets claim `svc.key`: it is delivered to `other.service`, but its dynamic identity exists only in `svc.service`; deliver it to `svc.service`, or set its `unit` to null."
    ];
  };

  testSecretIsDeliveredWhenItNamesAUnit = {
    expr = {
      dynamic = (secretOf [ slots ] { dynamic.unit = "svc.service"; } { }).delivered;
      dynamicWithoutADeliveryAdapter =
        (secretOf [ backendSlot ] { dynamic.unit = "svc.service"; } { }).delivered;
      dynamicUndelivered =
        (secretOf [ slots ] { dynamic.unit = "svc.service"; } { unit = null; }).delivered;
      static = (secretOf [ slots ] { static.user = "svc"; } { }).delivered;
    };
    expected = {
      dynamic = true;
      dynamicWithoutADeliveryAdapter = true;
      dynamicUndelivered = false;
      static = false;
    };
  };

  testDynamicIdentityCannotReadAnUndeliveredSecretOutsideItsGroup =
    let
      message = "nixos-contracts: secrets claim `svc.key`: its dynamic identity cannot read it; deliver it to `svc.service`, or give the identity a `sharedGroup` and the secret that group.";
      undelivered = service "svc" { dynamic.unit = "svc.service"; } { key.unit = null; };
    in
    {
      expr = {
        installed = failures [
          backendSlot
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
        backendSlot
        (service "svc" {
          dynamic = {
            unit = "svc.service";
            sharedGroup = "logs";
          };
        } { key.unit = null; })
      ];
      delivered = failures [
        slots
        (service "svc" { dynamic.unit = "svc.service"; } oneSecret)
      ];
      static = failures [
        backendSlot
        (service "svc" { static.user = "svc"; } oneSecret)
      ];
      staticDelivered = failures [
        slots
        (service "svc" { static.user = "svc"; } { key.unit = "svc.service"; })
      ];
    };
    expected = {
      sharedGroup = [ ];
      delivered = [ ];
      static = [ ];
      staticDelivered = [ ];
    };
  };

  testSecondBackendFails = {
    expr =
      (secretOf [
        backendSlot
        {
          contracts.kinds.secrets.backend = {
            path = { service, id }: "/run/secrets/${service}_${id}";
            generators = [ "hex" ];
          };
        }
      ] { static.user = "svc"; } { }).path;
    expectedError.msg = "contracts\\.kinds\\.secrets\\.backend'[^\n]*\nA configuration imports one secret backend adapter[^\n]*\nDefinition values:\n- In [\\s\\S]*\n- In ";
  };

  testSecondDeliveryFails = {
    expr =
      (secretOf [
        slots
        {
          contracts.kinds.secrets.delivery.path =
            {
              unit,
              service,
              id,
            }:
            "/run/keys/${unit}/${service}_${id}";
        }
      ] { dynamic.unit = "svc.service"; } { }).path;
    expectedError.msg = "contracts\\.kinds\\.secrets\\.delivery'[^\n]*\nA configuration imports one delivery adapter[^\n]*\nDefinition values:\n- In [\\s\\S]*\n- In ";
  };

  testNodeForcesTheWholeBackend = {
    expr =
      (secretOf [
        backendSlot
        (
          { lib, ... }:
          {
            contracts.kinds.secrets.backend = lib.mkForce {
              path = { service, id }: "/run/secrets/${service}_${id}";
              generators = [ ];
            };
          }
        )
      ] { static.user = "svc"; } { }).path;
    expected = "/run/secrets/svc_key";
  };

  testNodeCannotForceOnlyTheBackendPath = {
    expr =
      (secretOf [
        backendSlot
        (
          { lib, ... }:
          {
            contracts.kinds.secrets.backend.path = lib.mkForce (
              { service, id }: "/run/secrets/${service}_${id}"
            );
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
            remote.value.copied = remoteToken;
            local.value.copied = storeSecret "origin";
            derived.value.derived = {
              generator = "basic-auth";
              from = [
                (storeSecret "origin")
                remoteToken
              ];
            };
          })
        ];
      };
      inherit (nodes.store.config.contracts.claimSets) secrets;
      namesOf = secret: map (source: source.claim.name) secret.sources;
    in
    {
      expr = {
        remote = namesOf secrets.influxdb.remote;
        local = namesOf secrets.influxdb.local;
        derived = namesOf secrets.influxdb.derived;
        inherit (nodes.store.config.contracts) failures;
      };
      expected = {
        remote = [ "metrics_secrets_telegraf_token" ];
        local = [ "store_secrets_influxdb_origin" ];
        derived = [
          "store_secrets_influxdb_origin"
          "metrics_secrets_telegraf_token"
        ];
        failures = [ ];
      };
    };

  testProvidedOrGeneratedSecretHasNoSources = {
    expr = map (value: (secretOf [ ] { static.user = "svc"; } { inherit value; }).sources) [
      { provided = { }; }
      { generated = "alnum"; }
    ];
    expected = [
      [ ]
      [ ]
    ];
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
              contracts.services.influxdb.secrets.copy.value.copied =
                config.contracts.services.influxdb.secrets.origin.ref;
            }
          )
        ]).contracts.claimSets.secrets.influxdb.copy.sources;
    expected = [ "store_secrets_influxdb_origin" ];
  };

  testReferenceToAnUnknownNodeFailsItsCheck = {
    expr =
      (nodesOf { store = [ (store { token.value.copied = remoteToken; }) ]; })
      .store.config.contracts.failures;
    expected = [
      "nixos-contracts: secrets claim `influxdb.token`: it references `metrics:secrets.telegraf.token`: node `metrics` is not in `contracts.nodes`."
    ];
  };

  testReferenceToANodeWithoutContractsFailsItsCheck = {
    expr = failures [
      (store { token.value.copied = remoteToken; })
      # The metrics node imports no nixos-contracts module. `local` names
      # this configuration, whose entry is never read.
      {
        contracts.nodes = {
          metrics.config = { };
          local.config = { };
        };
      }
    ];
    expected = [
      "nixos-contracts: secrets claim `influxdb.token`: it references `metrics:secrets.telegraf.token`: node `metrics` imports no nixos-contracts module."
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
            remote.value.copied = remoteToken;
            local.value.copied = storeSecret "missing";
          })
        ];
      }).store.config.contracts.failures;
    expected = [
      "nixos-contracts: secrets claim `influxdb.local`: it references `store:secrets.influxdb.missing`: no enabled contract on `store` holds it."
      "nixos-contracts: secrets claim `influxdb.remote`: it references `metrics:secrets.telegraf.token`: no enabled contract on `metrics` holds it."
    ];
  };

  testRejectedReferenceResolvesToANullClaim = {
    expr =
      (nodesOf { store = [ (store { token.value.copied = remoteToken; }) ]; })
      .store.config.contracts.claimSets.secrets.influxdb.token.sources;
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
        hashes.value.derived = {
          generator = "basic-auth";
          from = [
            (storeSecret "a")
            (storeSecret "b")
          ];
        };
      })
    ];
    expected = [
      "nixos-contracts: secrets claim `influxdb.hashes`: it references `store:secrets.influxdb.a`: no enabled contract on `store` holds it."
      "nixos-contracts: secrets claim `influxdb.hashes`: it references `store:secrets.influxdb.b`: no enabled contract on `store` holds it."
    ];
  };

  testReferenceToACopiedOrDerivedSecretFailsItsCheck = {
    expr = failures [
      onStore
      (store {
        origin.value.generated = "alnum";
        copy.value.copied = storeSecret "origin";
        hashes.value.derived = {
          generator = "basic-auth";
          from = [ (storeSecret "origin") ];
        };
        chained.value.copied = storeSecret "copy";
        rehashed.value.derived = {
          generator = "basic-auth";
          from = [
            (storeSecret "origin")
            (storeSecret "hashes")
          ];
        };
      })
    ];
    expected = [
      "nixos-contracts: secrets claim `influxdb.chained`: it references `store:secrets.influxdb.copy`, which is copied or derived itself; reference a provided or generated secret."
      "nixos-contracts: secrets claim `influxdb.rehashed`: it references `store:secrets.influxdb.hashes`, which is copied or derived itself; reference a provided or generated secret."
    ];
  };

  testCopiesReferencingEachOtherFailTheirChecks =
    let
      nodes = nodesOf {
        metrics = [
          (service "telegraf" { static.user = "telegraf"; } {
            token.value.copied = storeSecret "token";
          })
        ];
        store = [ (store { token.value.copied = remoteToken; }) ];
      };
    in
    {
      expr = builtins.mapAttrs (_: node: node.config.contracts.failures) nodes;
      expected = {
        metrics = [
          "nixos-contracts: secrets claim `telegraf.token`: it references `store:secrets.influxdb.token`, which is copied or derived itself; reference a provided or generated secret."
        ];
        store = [
          "nixos-contracts: secrets claim `influxdb.token`: it references `metrics:secrets.telegraf.token`, which is copied or derived itself; reference a provided or generated secret."
        ];
      };
    };

  # Each receiver copies its own node's token too, so each node references
  # the other and itself.
  testNodesHandingEachOtherReferencesHoldACopyOfEachAndDeriveFromAll = {
    expr =
      lib.mapAttrs (_: node: receivedBy node // { inherit (node.config.contracts) failures; })
        (handingTokens {
          senders = [
            "alpha"
            "beta"
          ];
          receivers = [
            "alpha"
            "beta"
          ];
        });
    expected = lib.genAttrs [ "alpha" "beta" ] (_: {
      copies = {
        alpha_secrets_telegraf_token = [ "alpha_secrets_telegraf_token" ];
        beta_secrets_telegraf_token = [ "beta_secrets_telegraf_token" ];
      };
      derived = [
        "alpha_secrets_telegraf_token"
        "beta_secrets_telegraf_token"
      ];
      failures = [ ];
    });
  };

  testAddingASenderAddsACopyAndASourceWithoutChangingTheReceivingNode = {
    expr =
      map
        (
          senders:
          receivedBy
            (handingTokens {
              inherit senders;
              receivers = [ "store" ];
            }).store
        )
        [
          [ "alpha" ]
          [
            "alpha"
            "beta"
          ]
        ];
    expected = [
      {
        copies.alpha_secrets_telegraf_token = [ "alpha_secrets_telegraf_token" ];
        derived = [ "alpha_secrets_telegraf_token" ];
      }
      {
        copies = {
          alpha_secrets_telegraf_token = [ "alpha_secrets_telegraf_token" ];
          beta_secrets_telegraf_token = [ "beta_secrets_telegraf_token" ];
        };
        derived = [
          "alpha_secrets_telegraf_token"
          "beta_secrets_telegraf_token"
        ];
      }
    ];
  };

  testReferenceNamingAMistypedNodeFailsTheReceiversCheck = {
    expr =
      (handingTokens {
        senders = [ "alpha" ];
        receivers = [ "alpha" ];
        extra = [
          {
            node = "alhpa";
            kind = "secrets";
            service = "telegraf";
            id = "token";
          }
        ];
      }).alpha.config.contracts.failures;
    expected = [
      "nixos-contracts: secrets claim `influxdb.alhpa_secrets_telegraf_token`: it references `alhpa:secrets.telegraf.token`: node `alhpa` is not in `contracts.nodes`."
      "nixos-contracts: secrets claim `influxdb.htpasswd`: it references `alhpa:secrets.telegraf.token`: node `alhpa` is not in `contracts.nodes`."
    ];
  };

  testSecretSourcesIsReadOnly = {
    expr =
      (evaluate [
        (service "svc" { static.user = "svc"; } oneSecret)
        { contracts.services.svc.secrets.key.sources = [ ]; }
      ]).contracts.services.svc.secrets.key.sources;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.sources' is read-only";
  };

  testSecretRejectsATopLevelFrom = {
    expr = (secretOf [ ] { static.user = "svc"; } { from = [ remoteToken ]; }).mode;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.from' does not exist";
  };
}
