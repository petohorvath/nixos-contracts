{
  nixos,
  adapter,
  backends,
}:
let
  inherit (nixos) evaluate;

  services = {
    contracts.services = {
      kea = {
        enable = true;
        identity.static = {
          user = "kea";
          group = "dhcp";
        };
        secrets = {
          ddns.generator = "base64";
          token = { };
        };
      };
      alloy = {
        enable = true;
        identity.dynamic.unit = "alloy.service";
        secrets.password = { };
      };
    };
  };
  settings.contracts.adapters.agenixRekey = {
    secretsDir = ./.;
    rekeyFiles.alloy-password = ./agenix-rekey.nix;
  };
  configuration = modules: evaluate (backends ++ [ adapter ] ++ modules);
  failures = modules: nixos.failures (backends ++ [ adapter ] ++ modules);
  secretOf = name: config: {
    inherit (config.age.secrets.${name}) group mode owner;
    rekeyFile = config.age.secrets.${name}.rekeyFile or null;
    generator = config.age.secrets.${name}.generator.script or null;
  };
in
{
  testGeneratedSecretNamesItsGenerator = {
    expr = secretOf "kea-ddns" (configuration [
      services
      settings
    ]);
    expected = {
      owner = "root";
      group = "dhcp";
      mode = "0440";
      rekeyFile = null;
      generator = "base64";
    };
  };

  testProvidedSecretFollowsTheSecretsDir = {
    expr =
      (configuration [
        services
        settings
      ]).age.secrets.kea-token.rekeyFile;
    expected = ./kea-token.age;
  };

  testProvidedSecretTakesItsRekeyFileOverride = {
    expr = secretOf "alloy-password" (configuration [
      services
      settings
    ]);
    expected = {
      owner = "root";
      group = "root";
      mode = "0440";
      rekeyFile = ./agenix-rekey.nix;
      generator = null;
    };
  };

  testProvidedSecretTakesAgenixRekeysOwnSecretsDir =
    let
      modules = [
        { age.rekey.secretsDir = ./.; }
        {
          contracts.services.kea = {
            enable = true;
            identity.static.user = "kea";
            secrets.token = { };
          };
        }
      ];
    in
    {
      expr = {
        failures = failures modules;
        rekeyFile = (configuration modules).age.secrets.kea-token.rekeyFile;
      };
      expected = {
        failures = [ ];
        rekeyFile = ./kea-token.age;
      };
    };

  testProvidedSecretWithoutAFileFailsItsCheck =
    let
      kea.contracts.services.kea = {
        enable = true;
        identity.static.user = "kea";
        secrets.token = { };
      };
    in
    {
      expr = {
        failures = failures [ kea ];
        rekeyFile = (configuration [ kea ]).age.secrets.kea-token.rekeyFile;
      };
      expected = {
        failures = [
          "nixos-contracts: provided secret `kea-token` needs an encrypted file: set `contracts.adapters.agenixRekey.secretsDir`, an entry in its `rekeyFiles`, or agenix-rekey's `age.rekey.secretsDir`."
        ];
        rekeyFile = null;
      };
    };

  testDynamicIdentityWithoutDeliveryCannotReadItsSecret = {
    expr = failures [
      services
      settings
    ];
    expected = [
      "nixos-contracts: secrets claim `alloy-password`: its dynamic identity cannot read it; import a delivery adapter such as `nixosModules.systemd-credentials`, or give the identity a `sharedGroup` and the secret that group."
    ];
  };

  testClaimReadsTheInstalledPath = {
    expr =
      (configuration [
        services
        settings
      ]).contracts.services.kea.secrets.token.path;
    expected = "/run/agenix/kea-token";
  };
}
