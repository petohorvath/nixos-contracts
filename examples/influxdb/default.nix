/*
  A static-identity service with a bind, a persisted mount, and a generated
  and a provided secret, installed by the preservation and agenix-rekey
  adapters. The encrypted files under `secrets/` are not part of the example;
  the configuration is evaluated, not built.
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
      backends.preservation
      backends.agenix
      backends.agenix-rekey
      exports.nixosModules.preservation
      exports.nixosModules.agenix-rekey
      ./service.nix
      ./node.nix
      {
        contracts.node = "influxdb";
        nixpkgs.hostPlatform = system;
        system.stateVersion = "26.05";
      }
    ];
  };
  inherit (node) config;

  secretOf = secret: {
    inherit (secret) owner group mode;
    rekeyFile = if secret.rekeyFile != null then baseNameOf (toString secret.rekeyFile) else null;
    generator = secret.generator.script or null;
  };
in
{
  inherit node;

  result = {
    bindAddress = config.services.influxdb2.settings.http-bind-address;
    initialSetup = {
      inherit (config.services.influxdb2.provision.initialSetup) passwordFile tokenFile;
    };
    preserved = map (entry: {
      inherit (entry)
        directory
        user
        group
        mode
        ;
    }) config.preservation.preserveAt."/persist/state".directories;
    secrets = lib.mapAttrs (_: secretOf) (
      lib.getAttrs [ "influxdb_admin-password" "influxdb_admin-token" ] config.age.secrets
    );
    inherit (config.contracts) failures;
  };
}
