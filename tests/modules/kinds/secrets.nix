{ contracts }:
let
  inherit (contracts) evaluate failures;

  service = name: identity: secrets: {
    contracts.services.${name} = {
      enable = true;
      inherit identity secrets;
    };
  };
  generated = {
    key.provenance.generated = "alnum";
  };
  configWithSecret =
    modules: identity: secret:
    evaluate (
      modules
      ++ [
        (service "svc" identity {
          key = {
            provenance.provided = { };
          }
          // secret;
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
  location.contracts.secrets.location = name: "/run/agenix/${name}";
  rules = {
    imports = [ location ];
    contracts.secrets.delivery = { unit, name }: "/run/credentials/${unit}/${name}";
  };
in
{
  testSecretDefaultsToAGroupReadableRootFile = {
    expr =
      (evaluate [ (service "chrony" { static.user = "chrony"; } generated) ])
      .contracts.claimSets.secrets.chrony-key;
    expected = {
      service = "chrony";
      id = "key";
      name = "chrony-key";
      provenance.generated = "alnum";
      mode = "0440";
      owner = "root";
      group = "chrony";
      unit = null;
      delivered = false;
      path = null;
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

  testProvenanceTakesExactlyOneTag = {
    expr =
      (secretOf [ ] { static.user = "svc"; } {
        provenance = {
          provided = { };
          generated = "alnum";
        };
      }).provenance;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.provenance";
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
    expr = (secretOf [ location ] { dynamic.unit = "svc.service"; } { }).path;
    expected = "/run/agenix/svc-key";
  };

  testOnlyADynamicIdentityWithADeliveryAdapterIsDelivered = {
    expr = {
      dynamicWithDelivery = (secretOf [ rules ] { dynamic.unit = "svc.service"; } { }).delivered;
      dynamicWithoutDelivery = (secretOf [ location ] { dynamic.unit = "svc.service"; } { }).delivered;
      static = (secretOf [ rules ] { static.user = "svc"; } { }).delivered;
    };
    expected = {
      dynamicWithDelivery = true;
      dynamicWithoutDelivery = false;
      static = false;
    };
  };

  testDynamicIdentityCannotReadAnUndeliveredSecretOutsideItsGroup = {
    expr = failures [
      location
      (service "svc" { dynamic.unit = "svc.service"; } generated)
    ];
    expected = [
      "nixos-contracts: secrets claim `svc-key`: its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup`."
    ];
  };

  testReadableSecretsPassTheCheck = {
    expr = {
      sharedGroup = failures [
        location
        (service "svc" {
          dynamic = {
            unit = "svc.service";
            sharedGroup = "logs";
          };
        } generated)
      ];
      delivered = failures [
        rules
        (service "svc" { dynamic.unit = "svc.service"; } generated)
      ];
      static = failures [
        location
        (service "svc" { static.user = "svc"; } generated)
      ];
      notInstalled = failures [ (service "svc" { dynamic.unit = "svc.service"; } generated) ];
    };
    expected = {
      sharedGroup = [ ];
      delivered = [ ];
      static = [ ];
      notInstalled = [ ];
    };
  };

  testSecretPathIsReadOnly = {
    expr =
      (evaluate [
        (service "svc" { static.user = "svc"; } generated)
        { contracts.services.svc.secrets.key.path = "/elsewhere"; }
      ]).contracts.services.svc.secrets.key.path;
    expectedError.msg = "contracts\\.services\\.svc\\.secrets\\.key\\.path' is read-only";
  };
}
