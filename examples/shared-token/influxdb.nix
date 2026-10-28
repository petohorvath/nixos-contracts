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
  inherit (contractsLib) claimNameOf copiesOf;
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
      secrets = lib.mkMerge [
        {
          admin-password.value.generated.generator = "alnum";
          admin-token.value.generated.generator = "alnum";
        }
        # A copy of each writer's token, keyed by the token's claim name,
        # which influxdb alone reads. The keys come from the references
        # alone, so this claim set never reads the writer's node.
        (copiesOf cfg.writers)
        (lib.genAttrs (map claimNameOf cfg.writers) (_: {
          owner = "influxdb2";
          mode = "0400";
        }))
      ];
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
      # as `metrics_secrets_telegraf_token`.
      organizations.main.auths = lib.listToAttrs (
        map (
          writer:
          lib.nameValuePair (claimNameOf writer) {
            writeBuckets = [ "metrics" ];
            tokenFile = contract.secrets.${claimNameOf writer}.path;
          }
        ) cfg.writers
      );
    };
  };
}
