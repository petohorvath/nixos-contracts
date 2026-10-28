{
  fixtures,
  helpers,
  lib,
  ...
}:
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

  # A caller applies the module to `{ libnet }` with a plain `import`, so
  # the module names its own file in diagnostics.
  testModuleIsNamedByItsFile = {
    expr = (builtins.head (helpers.contracts.graphOf [ ])).file;
    expected = toString fixtures.sourceFiles.generic;
  };
}
