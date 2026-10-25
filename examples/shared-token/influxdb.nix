/*
  A service module for nixpkgs' influxdb2 that provisions one write
  authorization per writer. Writers send their tokens to its `writers`
  inbox from any node, its own included, and influxdb holds a copy of each,
  so it reads every token at its own path, with its own group, and never
  names the backend.
*/
{
  config,
  contractsLib,
  lib,
  ...
}:
let
  contract = config.contracts.services.influxdb;

  # What the writers inbox received, by node, service and then id, in a
  # list.
  writers = lib.concatMap (byService: lib.concatMap lib.attrValues (lib.attrValues byService)) (
    lib.attrValues contract.inboxes.writers.received
  );
in
{
  contracts.services.influxdb = contractsLib.mkDefaultContract {
    inherit (config.services.influxdb2) enable;
    identity.static.user = "influxdb2";
    secrets = {
      admin-password.value.generated = "alnum";
      admin-token.value.generated = "alnum";
    };
    # A copy of each writer's token, which influxdb alone reads.
    inboxes.writers.copy = {
      owner = "influxdb2";
      mode = "0400";
    };
  };

  services.influxdb2.provision = {
    enable = true;
    initialSetup = {
      organization = "main";
      bucket = "metrics";
      passwordFile = contract.secrets.admin-password.path;
      tokenFile = contract.secrets.admin-token.path;
    };
    # One authorization per sent token, named by the token's claim name,
    # such as `metrics_telegraf_token`.
    organizations.main.auths = lib.listToAttrs (
      map (
        writer:
        lib.nameValuePair writer.claim.name {
          writeBuckets = [ "metrics" ];
          tokenFile = writer.copy.path;
        }
      ) writers
    );
  };
}
