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
    path = { service, id }: "/run/agenix/${service}_${id}";
    generators = [ ];
  };

  # Configurations by node identity with the adapter and the backend,
  # sharing one node collection.
  nodesOf = import ../../fixtures/nodes.nix {
    evaluate =
      modules:
      evaluate (
        [
          adapter
          backend
        ]
        ++ modules
      );
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
    expected = [ "alloy_password:/run/agenix/alloy_password" ];
  };

  # Alloy on the `edge` node copies chrony's key on the `time` node, its
  # id joining the reference's node, kind, service and id with `_`.
  testDynamicIdentityCopyIsDeliveredIntoItsUnit =
    let
      key = nodes.time.config.contracts.services.chrony.secrets.key.ref;
      nodes = nodesOf {
        time = [ chrony ];
        edge = [
          alloy
          {
            contracts.services.alloy.secrets."${key.node}_${key.kind}_${key.service}_${key.id}".value.copied =
              key;
          }
        ];
      };
      inherit (nodes.edge) config;
    in
    {
      expr = {
        inherit (config.systemd.services.alloy.serviceConfig) LoadCredential;
        inherit (config.contracts.services.alloy.secrets.time_secrets_chrony_key) path;
        inherit (config.contracts) failures;
      };
      expected = {
        LoadCredential = [
          "alloy_time_secrets_chrony_key:/run/agenix/alloy_time_secrets_chrony_key"
          "alloy_password:/run/agenix/alloy_password"
        ];
        path = "/run/credentials/alloy.service/alloy_time_secrets_chrony_key";
        failures = [ ];
      };
    };

  testDynamicIdentityClaimReadsTheCredential = {
    expr =
      (evaluate [
        adapter
        alloy
        backend
      ]).contracts.services.alloy.secrets.password.path;
    expected = "/run/credentials/alloy.service/alloy_password";
  };

  # Chrony runs `chronyd.service` as its static account, which sets no
  # `DynamicUser`; the `script` gives the unit the command another module
  # would.
  testStaticIdentitySecretIsLoadedIntoTheUnitItNames =
    let
      configuration = evaluate [
        adapter
        backend
        chrony
        {
          contracts.services.chrony.secrets.key.unit = "chronyd.service";
          systemd.services.chronyd.script = "true";
        }
      ];
    in
    {
      expr = {
        inherit (configuration.systemd.services.chronyd.serviceConfig) LoadCredential;
        inherit (configuration.contracts.services.chrony.secrets.key) path;
        inherit (configuration.contracts) failures;
      };
      expected = {
        LoadCredential = [ "chrony_key:/run/agenix/chrony_key" ];
        path = "/run/credentials/chronyd.service/chrony_key";
        failures = [ ];
      };
    };

  testStaticIdentityKeepsTheBackendPath = {
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
      path = "/run/agenix/chrony_key";
      loaded = false;
    };
  };

  testDeliveryNeedsABackendPath = {
    expr =
      (evaluate [
        adapter
        alloy
      ]).systemd.services.alloy.serviceConfig.LoadCredential;
    expectedError.msg = "nixos-contracts: secret `alloy\\.password` has no path: import a secret backend adapter";
  };

  testDeliveryPathNamesTheCredentialByServiceAndId = {
    expr =
      (evaluate [
        adapter
        backend
      ]).contracts.kinds.secrets.delivery.path
        {
          unit = "alloy.service";
          service = "alloy";
          id = "loki-password";
        };
    expected = "/run/credentials/alloy.service/alloy_loki-password";
  };

  testMistypedUnitIsRejected = {
    expr = failures [
      adapter
      backend
      alloy
      { contracts.services.alloy.identity.dynamic.unit = lib.mkForce "alloy-typo.service"; }
    ];
    expected = [
      "nixos-contracts: secrets are delivered to unit `alloy-typo.service`, which is not a service defined in `systemd.services`."
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
    expected = [ "alloy_password:/run/agenix/alloy_password" ];
  };
}
