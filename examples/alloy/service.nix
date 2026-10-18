# A service module for nixpkgs' alloy, which runs as a dynamic user: its
# secret reaches the daemon as a systemd credential.
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
    secrets.loki-password.provenance.generated = "alnum";
  };

  services.alloy.extraFlags = [
    "--server.http.listen-addr=${builtins.head contract.binds.http.bindpoints}"
  ];

  environment.etc."alloy/config.alloy".text = ''
    loki.write "default" {
      endpoint {
        url = "https://loki.example.test/loki/api/v1/push"
        basic_auth {
          username = "alloy"
          password_file = "${contract.secrets.loki-password.path}"
        }
      }
    }
  '';
}
