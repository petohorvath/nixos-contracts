# Evaluate configurations by node identity, each given the whole collection
# as its node collection and its own identity as `contracts.node`, as a
# fleet sets them. `modulesOf` returns further modules of one node by its
# identity.
{
  evaluate,
  modulesOf ? _: [ ],
}:
modulesByNode:
let
  nodes = builtins.mapAttrs (node: modules: {
    config = evaluate ([ { contracts = { inherit node nodes; }; } ] ++ modulesOf node ++ modules);
  }) modulesByNode;
in
nodes
