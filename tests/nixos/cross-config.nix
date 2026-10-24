{
  lib,
  nixos,
  module,
}:
let
  # Stands in for nixos-cross-config's NixOS module, which declares the two
  # options the module reads.
  crossConfig = {
    options.crossConfig = {
      name = lib.mkOption { type = lib.types.str; };
      nodeConfigurations = lib.mkOption { type = lib.types.lazyAttrsOf lib.types.raw; };
    };
  };

  evaluate =
    modules:
    nixos.evaluate (
      [
        crossConfig
        module
        {
          crossConfig = {
            name = "metrics";
            nodeConfigurations.metrics.config = { };
          };
        }
      ]
      ++ modules
    );
in
{
  testNodeIdentityAndCollectionComeFromCrossConfig = {
    expr = {
      inherit ((evaluate [ ]).contracts) node;
      nodes = builtins.attrNames (evaluate [ ]).contracts.nodes;
    };
    expected = {
      node = "metrics";
      nodes = [ "metrics" ];
    };
  };

  testANodeOverridesTheNodeIdentity = {
    expr = (evaluate [ { contracts.node = "elsewhere"; } ]).contracts.node;
    expected = "elsewhere";
  };
}
