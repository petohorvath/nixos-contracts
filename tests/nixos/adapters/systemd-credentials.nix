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
      secrets.password.generator = "alnum";
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
      secrets.key.generator = "alnum";
    };
  };
  location.contracts.secrets.location = name: "/run/agenix/${name}";
in
{
  testDynamicIdentitySecretIsLoadedIntoItsUnit = {
    expr =
      (evaluate [
        adapter
        alloy
        chrony
        location
      ]).systemd.services.alloy.serviceConfig.LoadCredential;
    expected = [ "alloy-password:/run/agenix/alloy-password" ];
  };

  testDynamicIdentityClaimReadsTheCredential = {
    expr =
      (evaluate [
        adapter
        alloy
        location
      ]).contracts.services.alloy.secrets.password.path;
    expected = "/run/credentials/alloy.service/alloy-password";
  };

  testStaticIdentityKeepsTheBackendLocation = {
    expr =
      let
        configuration = evaluate [
          adapter
          chrony
          location
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
    expr = failures [
      adapter
      alloy
    ];
    expected = [
      "nixos-contracts: delivering secrets needs a secret backend adapter that sets `contracts.secrets.location`."
    ];
  };

  testMistypedUnitIsRejected = {
    expr = failures [
      adapter
      location
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
      location
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
          { contracts.adapters.agenixRekey.secretsDir = ./.; }
        ]
      )).systemd.services.alloy.serviceConfig.LoadCredential;
    expected = [ "alloy-password:/run/agenix/alloy-password" ];
  };
}
