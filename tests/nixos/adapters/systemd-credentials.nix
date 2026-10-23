{
  lib,
  nixos,
  adapter,
  backends,
  backendAdapter,
}:
let
  inherit (nixos) evaluate failures;

  alloy = {
    contracts.services.alloy = {
      enable = true;
      identity.dynamic.unit = "alloy.service";
      secrets.password = { };
    };
    systemd.services.alloy = {
      script = "true";
      serviceConfig.DynamicUser = true;
    };
  };
  chrony = {
    contracts.services.chrony = {
      enable = true;
      identity.static.user = "chrony";
      secrets.key = { };
    };
  };
  backend.contracts.kinds.secrets.backend = {
    location = name: "/run/agenix/${name}";
    generators = [ ];
  };
in
{
  testDynamicIdentitySecretIsLoadedIntoItsUnit = {
    expr =
      (evaluate [
        adapter
        alloy
        chrony
        backend
      ]).systemd.services.alloy.serviceConfig.LoadCredential;
    expected = [ "alloy-password:/run/agenix/alloy-password" ];
  };

  testDynamicIdentityClaimReadsTheCredential = {
    expr =
      (evaluate [
        adapter
        alloy
        backend
      ]).contracts.services.alloy.secrets.password.path;
    expected = "/run/credentials/alloy.service/alloy-password";
  };

  testStaticIdentityKeepsTheBackendLocation = {
    expr =
      let
        configuration = evaluate [
          adapter
          chrony
          backend
        ];
      in
      {
        path = configuration.contracts.services.chrony.secrets.key.path;
        loaded = configuration.systemd.services ? chrony;
      };
    expected = {
      path = "/run/agenix/chrony-key";
      loaded = false;
    };
  };

  testDeliveryNeedsABackendLocation = {
    expr =
      (evaluate [
        adapter
        alloy
      ]).systemd.services.alloy.serviceConfig.LoadCredential;
    expectedError.msg = "nixos-contracts: secret `alloy-password` has no location: import a secret backend adapter";
  };

  testMistypedUnitIsRejected = {
    expr = failures [
      adapter
      backend
      alloy
      { contracts.services.alloy.identity.dynamic.unit = lib.mkForce "alloy-typo.service"; }
    ];
    expected = [
      "nixos-contracts: dynamic identity unit `alloy-typo.service` is not a service defined in `systemd.services`."
    ];
  };

  testUnitWithoutDynamicUserIsRejected = {
    expr = failures [
      adapter
      backend
      alloy
      { systemd.services.alloy.serviceConfig.DynamicUser = lib.mkForce false; }
    ];
    expected = [
      "nixos-contracts: dynamic identity unit `alloy.service` does not set `DynamicUser`."
    ];
  };

  testDeliveryWorksWithTheAgenixRekeyAdapter = {
    expr =
      (evaluate (
        backends
        ++ [
          backendAdapter
          adapter
          alloy
          { age.rekey.secretsDir = ./.; }
        ]
      )).systemd.services.alloy.serviceConfig.LoadCredential;
    expected = [ "alloy-password:/run/agenix/alloy-password" ];
  };
}
