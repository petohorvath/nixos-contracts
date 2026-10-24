/*
  A service module for nixpkgs' influxdb2 that provisions one write
  authorization per writer. Each writer's token is a copy of a secret that
  the writer's own node holds, so influxdb reads it at its own path, with its
  own group, and never names the backend.
*/
{
  config,
  contractsLib,
  lib,
  ...
}:
let
  cfg = config.example.influxdb;
  contract = config.contracts.services.influxdb;
in
{
  options.example.influxdb.writers = lib.mkOption {
    type = lib.types.attrsOf contractsLib.types.reference;
    default = { };
    description = ''
      The writers of the `metrics` bucket, by authorization name, each a
      reference to its token. In a fleet, nixos-cross-config carries them
      from the writers' nodes.
    '';
  };

  config = {
    contracts.services.influxdb = contractsLib.mkDefaultContract {
      inherit (config.services.influxdb2) enable;
      identity.static.user = "influxdb2";
      secrets = {
        admin-password.generate = "alnum";
        admin-token.generate = "alnum";
      }
      // lib.mapAttrs' (
        writer: reference: lib.nameValuePair "writer-${writer}" { from = [ reference ]; }
      ) cfg.writers;
    };

    services.influxdb2.provision = {
      enable = true;
      initialSetup = {
        organization = "main";
        bucket = "metrics";
        passwordFile = contract.secrets.admin-password.path;
        tokenFile = contract.secrets.admin-token.path;
      };
      organizations.main.auths = lib.mapAttrs (writer: _: {
        writeBuckets = [ "metrics" ];
        tokenFile = contract.secrets."writer-${writer}".path;
      }) cfg.writers;
    };
  };
}
