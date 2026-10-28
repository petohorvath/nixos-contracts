{ fixtures, ... }:
let
  inherit (fixtures) examples;
in
{
  testCustomKindExampleFoldsAndClashes = {
    expr = examples.custom-kind.result;
    expected = {
      claimSet = {
        grafana.main = {
          database = "grafana";
          owner = "grafana";
        };
        vaultwarden = {
          main = {
            database = "vaultwarden";
            owner = "vaultwarden";
          };
          attachments = {
            database = "vaultwarden_attachments";
            owner = "vaultwarden";
          };
        };
      };
      validFailures = [ ];
      clashingFailures = [
        "nixos-contracts: databases claims `grafana.main` and `vaultwarden.attachments` clash: both own `grafana`."
      ];
    };
  };
}
