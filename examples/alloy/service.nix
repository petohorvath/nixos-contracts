# A service module for nixpkgs' alloy, which runs as a dynamic user. It holds
# no secret itself: the Loki module adds the secrets that shipping logs needs.
{ config, contractsLib, ... }:
let
  contract = config.contracts.services.alloy;
in
{
  contracts.services.alloy = contractsLib.mkDefaultContract {
    inherit (config.services.alloy) enable;
    identity.dynamic.unit = "alloy.service";
    binds.http = {
      port = 12345;
      addresses = [ "127.0.0.1" ];
    };
  };

  services.alloy.extraFlags = [
    "--server.http.listen-addr=${builtins.head contract.binds.http.bindpoints}"
  ];
}
