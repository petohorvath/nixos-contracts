# A dynamic-identity service: agenix-rekey installs its generated secret
# root-owned, the systemd-credentials adapter delivers it into the unit, and
# the daemon's configuration reads the delivered path from the claim.
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
      {
        services.alloy.enable = true;
        age.rekey.generatedSecretsDir = ./secrets/generated;
        nixpkgs.hostPlatform = system;
        system.stateVersion = "26.05";
      }
    ];
  };
  inherit (node) config;
  secret = config.age.secrets.alloy-loki-password;
in
{
  inherit node;

  result = {
    listenFlags = config.services.alloy.extraFlags;
    passwordFile = config.contracts.services.alloy.secrets.loki-password.path;
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
