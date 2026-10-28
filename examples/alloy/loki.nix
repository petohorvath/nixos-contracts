/*
  A feature module that ships alloy's logs to Loki instances. alloy's own
  process reads each instance's password, so the module adds one secret per
  instance to alloy's contract, derived from its own settings, and each
  secret reaches the daemon as a systemd credential.
*/
{
  config,
  contractsLib,
  lib,
  ...
}:
let
  cfg = config.example.alloy.loki;
  contract = config.contracts.services.alloy;

  passwordId = instance: "loki-${instance}-password";

  writeBlock = instance: url: ''
    loki.write "${instance}" {
      endpoint {
        url = "${url}"
        basic_auth {
          username = "alloy"
          password_file = "${contract.secrets.${passwordId instance}.path}"
        }
      }
    }
  '';
in
{
  options.example.alloy.loki.instances = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "The push URLs of the Loki instances alloy ships logs to.";
  };

  config = {
    contracts.services.alloy = contractsLib.mkDefaultContract {
      secrets = lib.mapAttrs' (
        instance: _: lib.nameValuePair (passwordId instance) { value.generated.generator = "alnum"; }
      ) cfg.instances;
    };

    environment.etc."alloy/loki.alloy" = lib.mkIf (cfg.instances != { }) {
      text = lib.concatStrings (lib.mapAttrsToList writeBlock cfg.instances);
    };
  };
}
