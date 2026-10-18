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

  testProvidedSecretWithoutAFileFails = {
    expr = (configuration [ services ]).age.secrets.kea-token.rekeyFile;
    expectedError.msg = "provided secret `kea-token` needs `contracts\\.adapters\\.agenixRekey\\.secretsDir`";
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
