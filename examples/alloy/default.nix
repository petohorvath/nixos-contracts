/*
  A dynamic-identity service whose secret comes from a feature module:
  agenix-rekey installs it root-owned, the systemd-credentials adapter
  delivers it into the unit, and the daemon's configuration reads the
  delivered path from the claim.
*/
{
  nixpkgs,
  exports,
  backends,
  system ? "x86_64-linux",
}:
let
  inherit (nixpkgs) lib;

  node = lib.nixosSystem {
    specialArgs.contractsLib = exports.lib;
    modules = [
      backends.agenix
      backends.agenix-rekey
      exports.nixosModules.agenix-rekey
      exports.nixosModules.systemd-credentials
      ./service.nix
      ./loki.nix
      {
        services.alloy.enable = true;
        example.alloy.loki.instances.main = "https://loki.example.test/loki/api/v1/push";
        age.rekey.generatedSecretsDir = ./secrets/generated;
        nixpkgs.hostPlatform = system;
        system.stateVersion = "26.05";
      }
    ];
  };
  inherit (node) config;
  secret = config.age.secrets.alloy-loki-main-password;
in
{
  inherit node;

  result = {
    listenFlags = config.services.alloy.extraFlags;
    passwordFile = config.contracts.services.alloy.secrets.loki-main-password.path;
    loadCredential = config.systemd.services.alloy.serviceConfig.LoadCredential;
    installed = {
      inherit (secret)
        owner
        group
        mode
        path
        ;
      generator = secret.generator.script;
    };
    inherit (config.contracts) failures;
  };
}
