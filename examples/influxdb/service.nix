# A service module for nixpkgs' influxdb2: it states the contract once, at
# default priority, and wires the daemon from it.
{ config, contractsLib, ... }:
let
  contract = config.contracts.services.influxdb;
in
{
  contracts.services.influxdb = contractsLib.mkDefaultContract {
    inherit (config.services.influxdb2) enable;
    identity.static.user = "influxdb2";
    binds.http.port = 8086;
    mounts.data = {
      path = "/var/lib/influxdb2";
      class = "state";
    };
    secrets = {
      admin-password.generator = "alnum";
      admin-token = { };
    };
  };

  services.influxdb2 = {
    settings.http-bind-address = builtins.head contract.binds.http.bindpoints;
    provision = {
      enable = true;
      initialSetup = {
        organization = "main";
        bucket = "metrics";
        passwordFile = contract.secrets.admin-password.path;
        tokenFile = contract.secrets.admin-token.path;
      };
    };
  };
}
