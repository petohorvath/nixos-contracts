/*
  A service module for nixpkgs' influxdb2 that provisions one write
  authorization per writer. Each writer's token is a secret on any node,
  its own included, and influxdb holds a copy of each, so it reads every
  token at its own path, with its own owner and mode, and never names the
  backend.
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

  # A copy's id joins the reference's own fields with `_`, which gives the
  # writer token's claim name. Resolving the reference to choose the id
  # would make this claim set read the writer's node.
  copyIdOf = writer: "${writer.node}_${writer.service}_${writer.id}";
in
{
  options.example.influxdb.writers = lib.mkOption {
    type = lib.types.listOf (contractsLib.types.referenceTo "secrets");
    default = [ ];
    description = ''
      The tokens of the writers of the `metrics` bucket, each a reference
      to a secret on any node, as a fleet's shared data carries them.
    '';
  };

  config = {
    contracts.services.influxdb = contractsLib.mkDefaultContract {
      inherit (config.services.influxdb2) enable;
      identity.static.user = "influxdb2";
      secrets = {
        admin-password.value.generated = "alnum";
        admin-token.value.generated = "alnum";
      }
      # A copy of each writer's token, which influxdb alone reads.
      // lib.listToAttrs (
        map (
          writer:
          lib.nameValuePair (copyIdOf writer) {
            value.copied = writer;
            owner = "influxdb2";
            mode = "0400";
          }
        ) cfg.writers
      );
    };

    services.influxdb2.provision = {
      enable = true;
      initialSetup = {
        organization = "main";
        bucket = "metrics";
        passwordFile = contract.secrets.admin-password.path;
        tokenFile = contract.secrets.admin-token.path;
      };
      # One authorization per writer, named by its token's claim name, such
      # as `metrics_telegraf_token`.
      organizations.main.auths = lib.listToAttrs (
        map (
          writer:
          lib.nameValuePair (copyIdOf writer) {
            writeBuckets = [ "metrics" ];
            tokenFile = contract.secrets.${copyIdOf writer}.path;
          }
        ) cfg.writers
      );
    };
  };
}
