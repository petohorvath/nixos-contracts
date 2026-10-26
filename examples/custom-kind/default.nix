# A project-defined claim kind evaluated without NixOS: its claims fold into
# `contracts.claimSets.databases` with resolved owners, and a clash becomes a
# failed check.
{ lib, exports }:
let
  databases = import ./databases.nix { inherit (exports.lib) mkClaimKind; };

  evaluate =
    modules:
    (lib.evalModules {
      modules = [
        exports.modules.generic.default
        databases
        { contracts.node = "apps"; }
      ]
      ++ modules;
    }).config;

  services = {
    contracts.services = {
      grafana = {
        enable = true;
        identity.static.user = "grafana";
        databases.main = { };
      };
      vaultwarden = {
        enable = true;
        identity.dynamic.unit = "vaultwarden.service";
        databases = {
          main = { };
          attachments = { };
        };
      };
    };
  };

  valid = evaluate [ services ];
  clashing = evaluate [
    services
    { contracts.services.vaultwarden.databases.attachments.database = "grafana"; }
  ];
in
{
  result = {
    claimSet = lib.mapAttrs (
      _:
      lib.mapAttrs (
        _: entry: {
          inherit (entry) database owner;
        }
      )
    ) valid.contracts.claimSets.databases;
    validFailures = valid.contracts.failures;
    clashingFailures = clashing.contracts.failures;
  };
}
