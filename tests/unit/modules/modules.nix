{ helpers, lib, ... }:
let
  inherit ((helpers.contracts.optionsOf [ ]).contracts) claimSets;
in
{
  testShippedKindsDeclareTheirOptionsInTheirFiles = {
    expr = lib.mapAttrs (_: option: map baseNameOf option.declarations) claimSets;
    expected = {
      binds = [ "binds.nix" ];
      mounts = [ "mounts.nix" ];
      secrets = [ "secrets.nix" ];
    };
  };
}
