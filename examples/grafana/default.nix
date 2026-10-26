/*
  A static-identity service whose secrets are delivered into the unit that
  reads them: agenix-rekey installs each root-only, the systemd-credentials
  adapter loads it into `grafana.service`, and Grafana reads the delivered
  path from the claim. Other units of the `grafana` account cannot read the
  installed files.
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
      {
        services.grafana.enable = true;
        age.rekey.generatedSecretsDir = ./secrets/generated;
        nixpkgs.hostPlatform = system;
        system.stateVersion = "26.05";
      }
    ];
  };
  inherit (node) config;
in
{
  inherit node;

  result = {
    security = {
      inherit (config.services.grafana.settings.security) admin_password secret_key;
    };
    loadCredential = config.systemd.services.grafana.serviceConfig.LoadCredential;
    installed = lib.mapAttrs (_: secret: { inherit (secret) owner group mode; }) (
      lib.getAttrs [ "grafana_admin-password" "grafana_secret-key" ] config.age.secrets
    );
    inherit (config.contracts) failures;
  };
}
