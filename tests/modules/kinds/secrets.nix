{ contracts }:
let
  inherit (contracts) evaluate;

  service = name: identity: secrets: {
    contracts.services.${name} = {
      enable = true;
      inherit identity secrets;
    };
  };
  generated = {
    key.provenance.generated = "alnum";
  };
  secretOf =
    modules: identity: secret:
    (evaluate (
      modules
      ++ [
        (service "svc" identity {
          key = {
            provenance.provided = { };
          }
          // secret;
        })
      ]
    )).contracts.claimSets.secrets.svc-key;
  ownerOf =
    identity: secret:
    let
      entry = secretOf [ ] identity secret;
    in
    {
      inherit (entry) owner group;
    };
  rules = {
    contracts.secrets = {
      location = name: "/run/agenix/${name}";
      delivery = { unit, name }: "/run/credentials/${unit}/${name}";
    };
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

  testDynamicIdentityReadsTheDeliveredCredential = {
    expr = (secretOf [ rules ] { dynamic.unit = "svc.service"; } { }).path;
    expected = "/run/credentials/svc.service/svc-key";
  };

  testDynamicIdentityWithoutDeliveryReadsTheBackendLocation = {
    expr =
      (secretOf [
        { contracts.secrets.location = name: "/run/agenix/${name}"; }
      ] { dynamic.unit = "svc.service"; } { }).path;
    expected = "/run/agenix/svc-key";
  };

  testClaimPathMatchesItsClaimSetEntry = {
    expr =
      let
        config = evaluate [
          rules
          (service "svc" { static.user = "svc"; } generated)
        ];
      in
      config.contracts.services.svc.secrets.key.path == config.contracts.claimSets.secrets.svc-key.path;
    expected = true;
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
