# Evaluate configurations by node name, each given the whole collection as
# its node collection, as nixos-cross-config's would be. `modulesOf` returns
# further modules of one node by its name.
{
  evaluate,
  modulesOf ? _: [ ],
}:
modulesByNode:
let
  nodes = builtins.mapAttrs (node: modules: {
    config = evaluate ([ { contracts = { inherit nodes; }; } ] ++ modulesOf node ++ modules);
  }) modulesByNode;
in
nodes
