{ contracts }:
let
  inherit (contracts) evaluate failures;

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
  backendLocation.contracts.kinds.secrets.location = name: "/run/agenix/${name}";
  rules = {
    imports = [ backendLocation ];
    contracts.kinds.secrets.delivery = { unit, name }: "/run/credentials/${unit}/${name}";
  };
in
{
  testSecretDefaultsToAGroupReadableRootFile = {
    expr =
      (evaluate [
        backendLocation
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

  testSecretNamingAGeneratorNoAdapterProvidesFailsItsCheck =
    let
      generators.contracts.kinds.secrets.generators = [
        "alnum"
        "hex"
      ];
      generating = generate: service "svc" { static.user = "svc"; } { key.generate = generate; };
    in
    {
      expr = {
        unknown = failures [
          generators
          (generating "alnm")
        ];
        provided = failures [
          generators
          (generating "hex")
        ];
        withoutAVocabulary = failures [ (generating "alnm") ];
      };
      expected = {
        unknown = [
          "nixos-contracts: secrets claim `svc-key`: no adapter provides its generator `alnm`; name one of `contracts.kinds.secrets.generators`."
        ];
        provided = [ ];
        withoutAVocabulary = [ ];
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
    expectedError.msg = "nixos-contracts: secret `svc-key` has no location: import a secret backend adapter such as `nixosModules\\.agenix-rekey`, which sets `contracts\\.kinds\\.secrets\\.location`";
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
    expr = (secretOf [ backendLocation ] { dynamic.unit = "svc.service"; } { }).path;
    expected = "/run/agenix/svc-key";
  };

  testOnlyADynamicIdentityWithADeliveryAdapterIsDelivered = {
    expr = {
      dynamicWithDelivery = (secretOf [ rules ] { dynamic.unit = "svc.service"; } { }).delivered;
      dynamicWithoutDelivery =
        (secretOf [ backendLocation ] { dynamic.unit = "svc.service"; } { }).delivered;
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
          backendLocation
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
        backendLocation
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
        backendLocation
        (service "svc" { static.user = "svc"; } oneSecret)
      ];
    };
    expected = {
      sharedGroup = [ ];
      delivered = [ ];
      static = [ ];
    };
  };

  testSecondBackendLocationFails = {
    expr =
      (secretOf [
        backendLocation
        { contracts.kinds.secrets.location = name: "/run/secrets/${name}"; }
      ] { static.user = "svc"; } { }).path;
    expectedError.msg = "contracts\\.kinds\\.secrets\\.location' is defined multiple times while it's expected to be unique\\.\nA configuration imports one secret backend adapter";
  };

  testSecondBackendGeneratorsFail = {
    expr = failures [
      backendLocation
      { contracts.kinds.secrets.generators = [ "alnum" ]; }
      { contracts.kinds.secrets.generators = [ "hex" ]; }
      (service "svc" { static.user = "svc"; } { key.generate = "hex"; })
    ];
    expectedError.msg = "contracts\\.kinds\\.secrets\\.generators' is defined multiple times while it's expected to be unique\\.\nA configuration imports one secret backend adapter";
  };

  testSecondDeliveryFails = {
    expr =
      (secretOf [
        rules
        { contracts.kinds.secrets.delivery = { unit, name }: "/run/keys/${unit}/${name}"; }
      ] { dynamic.unit = "svc.service"; } { }).path;
    expectedError.msg = "contracts\\.kinds\\.secrets\\.delivery' is defined multiple times while it's expected to be unique\\.\nA configuration imports one delivery adapter";
  };

  testNodeForcesTheBackendLocation = {
    expr =
      (secretOf [
        backendLocation
        (
          { lib, ... }:
          {
            contracts.kinds.secrets.location = lib.mkForce (name: "/run/secrets/${name}");
          }
        )
      ] { static.user = "svc"; } { }).path;
    expected = "/run/secrets/svc-key";
  };

  testSecretPathIsReadOnly = {
    expr =
      (evaluate [
        (service "svc" { static.user = "svc"; } oneSecret)
        { contracts.services.svc.secrets.key.path = "/elsewhere"; }
      ]).contracts.services.svc.secrets.key.path;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.path' is read-only";
  };
}
