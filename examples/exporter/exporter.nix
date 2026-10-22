/*
  A service module for nixpkgs' chrony exporter, a helper with a process of
  its own. Its contract takes the identity from the exporter's own `user`,
  which nixpkgs sets to `chrony` so the exporter can read chronyd's socket,
  and the exporter listens where the contract's bind says.
*/
{
  config,
  contractsLib,
  lib,
  ...
}:
let
  cfg = config.services.prometheus.exporters.chrony;
  contract = config.contracts.services.chrony-exporter;
in
{
  contracts.services.chrony-exporter = contractsLib.mkDefaultContract {
    inherit (cfg) enable;
    identity.static.user = cfg.user;
    binds.metrics = {
      port = 9123;
      addresses = [ "127.0.0.1" ];
    };
  };

  services.prometheus.exporters.chrony = {
    listenAddress = lib.mkDefault (builtins.head contract.binds.metrics.addresses);
    port = lib.mkDefault contract.binds.metrics.port;
  };
}
