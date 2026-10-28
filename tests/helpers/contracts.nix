/*
  Evaluate contract modules outside NixOS. `evaluate` returns the top-level
  `config` of a node named `local`, unless a module names another, and
  `evaluateWithoutNode` that of a configuration with no node identity.
  `failures` returns the messages of the failed checks, so tests check
  clashes without a NixOS evaluation, and `nodesOf` configurations by node
  name sharing one node collection. `optionsOf` returns the declared options,
  and `graphOf` the import graph, with the file each module is named by.
*/
{ lib, module }:
let
  evaluation = modules: lib.evalModules { modules = [ module ] ++ modules; };
in
rec {
  evaluateWithoutNode = modules: (evaluation modules).config;
  evaluate =
    modules: evaluateWithoutNode ([ { contracts.node = lib.mkDefault "local"; } ] ++ modules);
  failures = modules: (evaluate modules).contracts.failures;
  optionsOf = modules: (evaluation modules).options;
  graphOf = modules: (evaluation modules).graph;
  nodesOf = import ./nodes.nix { inherit evaluate; };
}
