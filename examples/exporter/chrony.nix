# A service module for nixpkgs' chrony. It never mentions the exporter, which
# has a contract of its own.
{ config, contractsLib, ... }:
{
  contracts.services.chrony = contractsLib.mkDefaultContract {
    inherit (config.services.chrony) enable;
    # chronyd starts as root and drops to `chrony` itself.
    identity.static.user = "chrony";
    binds.ntp = {
      protocols = "udp";
      port = 123;
    };
  };
}
