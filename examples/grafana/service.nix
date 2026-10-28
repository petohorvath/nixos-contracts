# A service module for nixpkgs' grafana, which runs as the static user
# `grafana`. Grafana's own process reads both secrets through its file
# provider, so the module delivers each into `grafana.service`.
{ config, contractsLib, ... }:
let
  contract = config.contracts.services.grafana;
  fromFile = id: "$__file{${contract.secrets.${id}.path}}";
in
{
  contracts.services.grafana = contractsLib.mkDefaultContract {
    inherit (config.services.grafana) enable;
    identity.static.user = "grafana";
    secrets = {
      admin-password = {
        value.generated.generator = "alnum";
        unit = "grafana.service";
      };
      secret-key = {
        value.generated.generator = "alnum";
        unit = "grafana.service";
      };
    };
  };

  services.grafana.settings.security = {
    admin_password = fromFile "admin-password";
    secret_key = fromFile "secret-key";
  };
}
