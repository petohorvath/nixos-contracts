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
          ddns.provenance.generated = "base64";
          token.provenance.provided = { };
        };
      };
      alloy = {
        enable = true;
        identity.dynamic.unit = "alloy.service";
        secrets.password.provenance.provided = { };
      };
    };
  };
  settings.contracts.adapters.agenixRekey = {
    secretsDir = ./.;
    rekeyFiles.alloy-password = ./agenix-rekey.nix;
  };
  configuration = modules: evaluate (backends ++ [ adapter ] ++ modules);
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

  testProvidedSecretWithoutAFileFailsItsCheck =
    let
      modules = backends ++ [
        adapter
        {
          contracts.services.kea = {
            enable = true;
            identity.static.user = "kea";
            secrets.token.provenance.provided = { };
          };
        }
      ];
    in
    {
      expr = {
        failures = nixos.failures modules;
        rekeyFile = (evaluate modules).age.secrets.kea-token.rekeyFile;
      };
      expected = {
        failures = [
          "nixos-contracts: provided secret `kea-token` needs `contracts.adapters.agenixRekey.secretsDir` or an entry in its `rekeyFiles`."
        ];
        rekeyFile = null;
      };
    };

  testDynamicIdentityWithoutDeliveryCannotReadItsSecret = {
    expr = nixos.failures (
      backends
      ++ [
        adapter
        services
        settings
      ]
    );
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
