{ lib, module }:
let
  inherit ((lib.evalModules { modules = [ module ]; }).options) contracts;
  inherit (contracts) claimSets;
in
{
  # Copies are read where they arrived, in an inbox's `received`.
  testNoRootOptionHoldsCopies = {
    expr = builtins.filter (name: builtins.elem name (builtins.attrNames contracts)) [
      "copies"
      "copySets"
    ];
    expected = [ ];
  };

  testShippedKindsDeclareTheirOptionsInTheirFiles = {
    expr = lib.mapAttrs (_: option: map baseNameOf option.declarations) {
      inherit (claimSets)
        binds
        inboxes
        mounts
        secrets
        ;
    };
    expected = {
      binds = [ "binds.nix" ];
      inboxes = [ "inboxes.nix" ];
      mounts = [ "mounts.nix" ];
      secrets = [ "secrets.nix" ];
    };
  };
}
