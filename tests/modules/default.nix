{ lib, module }:
let
  inherit ((lib.evalModules { modules = [ module ]; }).options.contracts) claimSets;
in
{
  testShippedKindsDeclareTheirOptionsInTheirFiles = {
    expr = lib.mapAttrs (_: option: map baseNameOf option.declarations) {
      inherit (claimSets) binds mounts secrets;
    };
    expected = {
      binds = [ "binds.nix" ];
      mounts = [ "mounts.nix" ];
      secrets = [ "secrets.nix" ];
    };
  };
}
